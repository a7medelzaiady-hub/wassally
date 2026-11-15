import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<Source> _decide() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    try {
      final server = await _ref.get(const GetOptions(source: Source.server));
      final serverVersion = (server.data()?['version'])?.toString();
      final loadedVersion = prefs?.getString(_verKey);
      final loadedAt = prefs?.getInt(_tsKey) ?? 0;

      if (serverVersion != null && loadedVersion == serverVersion) {
        return Source.cache;
      }

      final age = DateTime.now().millisecondsSinceEpoch - loadedAt;
      if (loadedVersion != null && age < _minRefresh.inMilliseconds) {
        // اتغيّر الكتالوج بس لسه ما عدّتش الفترة: نكمّل على الكاش.
        return Source.cache;
      }

      await prefs?.setString(_verKey, serverVersion ?? '');
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

        final complete =
            snap.docs.isNotEmpty &&
            (pageSize == null ||
                snap.docs.length >= pageSize ||
                _fetched.contains(key));

        if (complete) {
          return snap;
        }
      } catch (e) {
        debugPrint('Catalog cache error: $e');
      }
    }

    final snap = await query.get(const GetOptions(source: Source.server));

    _fetched.add(key);

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
  }

  /// إعادة ضبط الكاش المحلي للجلسة.
  static void invalidate() {
    _source = null;
    _fetched.clear();
  }
}
