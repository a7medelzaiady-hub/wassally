import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_cache_policy.dart';
import 'read_meter.dart';

class CatalogService {
  const CatalogService._();

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('app_info').doc('catalog');

  static Future<Source>? _source;

  static Future<Source> source() {
    return _source ??= _decide();
  }

  /// أقل فترة بين تحميلين كاملين للكتالوج عند العميل (ربع ساعة).
  /// لو الكتالوج اتغيّر قبل كده بأقل من كده، العميل يكمّل على نسخته المخزّنة.
  static const _minRefresh = Duration(minutes: 15);
  static const _verKey = 'catalog_loaded_version';
  static const _tsKey = 'catalog_loaded_at';

  /// بصمات نتايج الخادم بالإصدار الحالي (محفوظة على الجهاز) — شوف [CatalogCachePolicy].
  static const _keysKey = 'catalog_fetched_keys';

  /// مفتاح → بصمة نتيجة الخادم (عدد + hash المعرفات). الكاش يتقبل بس لو بصمته مطابقة.
  static Map<String, String> _persistedKeys = {};

  static Future<Source> _decide() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    try {
      final server = await _ref.get(const GetOptions(source: Source.server));
      ReadMeter.document('catalog:version', server);
      final serverVersion = (server.data()?['version'])?.toString();
      final loadedVersion = prefs?.getString(_verKey);
      final loadedAt = prefs?.getInt(_tsKey) ?? 0;

      // لو إصدار الخادم اتغيّر، لازم نسحب البيانات الجديدة فورًا.
      // مهلة الـ 15 دقيقة تُستخدم فقط كاحتياط عند غياب رقم إصدار الخادم،
      // ولا يجوز أن تحجب تحديثًا معروفًا (مثل عرض أضافه صاحب المحل).
      if (serverVersion != null) {
        if (loadedVersion == serverVersion) {
          _persistedKeys =
              CatalogCachePolicy.decode(prefs?.getStringList(_keysKey));
          return Source.cache;
        }
        await prefs?.setString(_verKey, serverVersion);
        await prefs?.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
        await prefs?.setStringList(_keysKey, const []);
        _persistedKeys = {};
        return Source.server;
      }

      final age = DateTime.now().millisecondsSinceEpoch - loadedAt;
      if (loadedVersion != null && age < _minRefresh.inMilliseconds) {
        // بصمات آخر إصدار اتحمّل: المطابقة التامة بس هي اللي بتتقبل، فده آمن.
        _persistedKeys =
            CatalogCachePolicy.decode(prefs?.getStringList(_keysKey));
        return Source.cache;
      }

      await prefs?.setString(_verKey, '');
      await prefs?.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
      await prefs?.setStringList(_keysKey, const []);
      _persistedKeys = {};
      return Source.server;
    } catch (e) {
      debugPrint('Catalog version error: $e');
      // من غير نت: نستخدم بصمات آخر إصدار اتحمّل عشان الكاش يتقري الأول (وكمان النتايج الفاضية).
      _persistedKeys =
          CatalogCachePolicy.decode(prefs?.getStringList(_keysKey));
      return Source.cache;
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> get(
    Query<Map<String, dynamic>> query,
    String key, {
    // ملحوظة: مبقاش بيأثر على قرار الكاش (البصمة أدق)؛ متساب عشان المستدعين.
    int? pageSize,
    bool cacheable = true,
  }) async {
    final src = await source();

    final canUseCache =
        cacheable && (src == Source.cache || _persistedKeys.containsKey(key));

    if (canUseCache) {
      try {
        final snap = await query.get(const GetOptions(source: Source.cache));
        // الكاش يتقبل بس لو مطابق بالظبط لآخر نتيجة خادم بنفس الإصدار
        // (داخل الجلسة أو من جلسة قبلها). [pageSize] مبقاش يكفي لوحده.
        if (CatalogCachePolicy.cacheIsComplete(
          recorded: _persistedKeys[key],
          cachedIds: snap.docs.map((d) => d.id),
        )) {
          return snap;
        }
      } catch (e) {
        debugPrint('Catalog cache error: $e');
      }
    }

    final QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      // من غير نت بس: نعرض اللي في الكاش (لو فيه) بدل شاشة خطأ.
      // أي خطأ تاني (زي permission-denied لمحل اتقفل) بيترمي عادي.
      if (e.code != 'unavailable' && e.code != 'deadline-exceeded') rethrow;
      try {
        final cached =
            await query.get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty) return cached;
      } catch (_) {}
      rethrow;
    }
    ReadMeter.query('catalog:${key.split('/').first}', snap);

    if (cacheable) {
      final mark = CatalogCachePolicy.fingerprint(snap.docs.map((d) => d.id));
      if (_persistedKeys[key] != mark) {
        _persistedKeys[key] = mark;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(
            _keysKey,
            CatalogCachePolicy.encode(_persistedKeys),
          );
        } catch (_) {}
      }
    }

    return snap;
  }

  /// تحديث إصدار الكتالوج بعد أي إضافة أو تعديل أو حذف.
  static Future<void> bump() async {
    try {
      await _ref.set({
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Catalog bump failed: $e');
    }

    // صاحب التعديل يشوف تعديله فورًا: نصفّر وقت آخر تحميل.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_tsKey, 0);
    } catch (_) {}

    _source = null;
    _persistedKeys = {};
  }

  /// إعادة ضبط الكاش المحلي للجلسة.
  static void invalidate() {
    _source = null;
    _persistedKeys = {};
  }
}
