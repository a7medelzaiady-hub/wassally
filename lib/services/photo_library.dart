import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/product_photo.dart';

/// «مكتبة صور وصّلي»: صور حقيقية بترفعها الإدارة مرة واحدة لأسماء أصناف
/// (طماطم، بطاطس، زيت موبيل...) وبتستخدمها كل المحلات للأصناف اللي من غير صورة،
/// قبل الصور التوضيحية العامة.
///
/// المستند: app_info/photo_library = { photos: { <اسم مطبّع>: {name, url} }, updatedAt }.
/// القراءة: مرة كل 6 ساعات بالكتير (متخزنة على الموبايل). الكتابة: الإدارة بس (القواعد).
class PhotoLibrary {
  PhotoLibrary._();

  static const _prefsKey = 'photo_library_v1';
  static const _prefsAtKey = 'photo_library_at_v1';
  static const _refreshEvery = Duration(hours: 6);

  static DocumentReference<Map<String, dynamic>> get doc =>
      FirebaseFirestore.instance.collection('app_info').doc('photo_library');

  /// بيحمّل من الموبايل فورًا، وبيحدّث من Firestore لو آخر تحديث أقدم من 6 ساعات.
  static Future<void>? _inflight;

  static Future<void> load({bool force = false}) {
    if (!force && _inflight != null) return _inflight!;
    final f = _load(force: force);
    _inflight = f;
    return f.whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    });
  }

  static Future<void> _load({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) _apply(_decode(cached));
      final at = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_prefsAtKey) ?? 0);
      if (!force && DateTime.now().difference(at) < _refreshEvery) return;
      final snap = await doc.get();
      final map = entriesFrom(snap.data());
      _apply(map);
      await prefs.setString(_prefsKey, jsonEncode(map));
      await prefs.setInt(_prefsAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('PhotoLibrary load failed: $e');
    }
  }

  /// {اسم مطبّع: رابط} من بيانات المستند.
  static Map<String, String> entriesFrom(Map<String, dynamic>? data) {
    final photos = data?['photos'];
    final out = <String, String>{};
    if (photos is Map) {
      photos.forEach((key, value) {
        final url = value is Map ? (value['url'] ?? '').toString() : '';
        if (key is String && key.trim().isNotEmpty && url.startsWith('https://')) {
          out[key] = url;
        }
      });
    }
    return out;
  }

  static Map<String, String> _decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map) return m.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    return const {};
  }

  static void _apply(Map<String, String> map) => setProductPhotoLibrary(map);

  /// إضافة/تحديث صورة في المكتبة (الإدارة).
  static Future<void> put(
    String name,
    String url, {
    String? sourcePageUrl,
    String? creator,
  }) async {
    final key = normalizeProductPhotoKey(name);
    if (key.isEmpty) throw ArgumentError('اكتب اسم الصنف');
    final photo = <String, String>{'name': name.trim(), 'url': url};
    // نخزن المصدر للمراجعة؛ صور Openverse المعتمدة CC0 فقط بعد اختيار الإدارة.
    if (sourcePageUrl != null && sourcePageUrl.startsWith('https://')) {
      photo['source'] = sourcePageUrl;
      photo['license'] = 'cc0';
      if (creator != null && creator.trim().isNotEmpty) {
        photo['creator'] = creator.trim().substring(
          0, creator.trim().length > 120 ? 120 : creator.trim().length);
      }
    }
    await doc.set({
      'photos': {key: photo},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await load(force: true);
  }

  /// حذف صورة من المكتبة (الإدارة).
  static Future<void> remove(String key) async {
    await doc.update({
      FieldPath(['photos', key]): FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await load(force: true);
  }
}
