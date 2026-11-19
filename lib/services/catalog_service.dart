import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'read_meter.dart';

class CatalogService {
  const CatalogService._();

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('app_info').doc('catalog');

  static Future<Source>? _source;

  static final Set<String> _fetched = {};

  static Future<Source> source() {
    return _source ??= _decide();
  }

  /// أقل فترة بين تحميلين كاملين للكتالوج عند العميل (ربع ساعة).
  /// لو الكتالوج اتغيّر قبل كده بأقل من كده، العميل يكمّل على نسخته المخزّنة.
  static const _minRefresh = Duration(minutes: 15);
  static const _verKey = 'catalog_loaded_version';
  static const _tsKey = 'catalog_loaded_at';

  /// المفاتيح اللي اتجابت من الخادم بالإصدار الحالي (محفوظة على الجهاز). بتخلّي نتيجة فاضية
  /// متخزنة تتقبل من الكاش بدل ما تتقري من الخادم في كل مرة.
  static const _keysKey = 'catalog_fetched_keys';

  /// مفتاح → عدد المستندات اللي رجعت من الخادم. الكاش يتقبل بس لو فيه نفس العدد أو أكتر،
  /// فلو Firestore شال مستندات من الكاش (مساحة/مسح) بنرجع للخادم بدل ما نعرض نتيجة ناقصة.
  static Map<String, int> _persistedKeys = {};

  static Map<String, int> _decodeKeys(List<String>? raw) {
    final out = <String, int>{};
    for (final entry in raw ?? const <String>[]) {
      final i = entry.lastIndexOf('|');
      if (i <= 0) continue;
      final n = int.tryParse(entry.substring(i + 1));
      if (n != null) out[entry.substring(0, i)] = n;
    }
    return out;
  }

  static List<String> _encodeKeys(Map<String, int> keys) =>
      [for (final e in keys.entries) '${e.key}|${e.value}'];

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
          _persistedKeys = _decodeKeys(prefs?.getStringList(_keysKey));
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
        return Source.cache;
      }

      await prefs?.setString(_verKey, '');
      await prefs?.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
      return Source.server;
    } catch (e) {
      debugPrint('Catalog version error: $e');
      return Source.cache;
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> get(
    Query<Map<String, dynamic>> query,
    String key, {
    int? pageSize,
    bool cacheable = true,
  }) async {
    final src = await source();

    final canUseCache =
        cacheable && (src == Source.cache || _fetched.contains(key));

    if (canUseCache) {
      try {
        final snap = await query.get(const GetOptions(source: Source.cache));

        // اتجاب من الخادم بنفس الإصدار (في الجلسة دي أو قبلها): الكاش كامل حتى لو فاضي.
        // قبل كده النتيجة الفاضية كانت بتتقري من الخادم في كل مرة.
        final persistedCount = _persistedKeys[key];
        final fetchedBefore = _fetched.contains(key) ||
            (persistedCount != null && snap.docs.length >= persistedCount);
        final complete = fetchedBefore ||
            (snap.docs.isNotEmpty &&
                (pageSize == null || snap.docs.length >= pageSize));

        if (complete) {
          return snap;
        }
      } catch (e) {
        debugPrint('Catalog cache error: $e');
      }
    }

    final snap = await query.get(const GetOptions(source: Source.server));
    ReadMeter.query('catalog:${key.split('/').first}', snap);

    _fetched.add(key);
    if (cacheable && _persistedKeys[key] != snap.docs.length) {
      _persistedKeys[key] = snap.docs.length;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_keysKey, _encodeKeys(_persistedKeys));
      } catch (_) {}
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
    _fetched.clear();
    _persistedKeys = {};
  }

  /// إعادة ضبط الكاش المحلي للجلسة.
  static void invalidate() {
    _source = null;
    _fetched.clear();
    _persistedKeys = {};
  }
}
