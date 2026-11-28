import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// #339: مسودات النماذج على الموبايل بس (SharedPreferences). مفيش Firestore.
/// - المفتاح مرتبط بالحساب (uid) واسم النموذج، والقيم في JSON مش في اسم المفتاح.
/// - المسودة بتنتهي بعد [maxAge] وبتتمسح بعد الإرسال أو تسجيل الخروج أو تبديل الحساب.
class DraftStore {
  DraftStore._();

  static const maxAge = Duration(hours: 24);
  static const _prefix = 'draft_v1:';
  static const _maxFieldLength = 2000;
  static const _maxFields = 20;

  static final _namePattern = RegExp(r'^[a-z0-9-]{1,40}$');

  static String? _keyFor(String uid, String form) {
    if (uid.isEmpty || !_namePattern.hasMatch(form) || uid.contains(':')) return null;
    return '$_prefix$uid:$form';
  }

  /// حقول المسودة، أو null لو مفيش/انتهت/مش لنفس الحساب.
  static Future<Map<String, String>?> load(String uid, String form, {DateTime? now}) async {
    final key = _keyFor(uid, form);
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt = decoded['t'];
      final fields = decoded['f'];
      if (savedAt is! int || fields is! Map) return null;
      final age = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
      if (age.isNegative || age >= maxAge) {
        await prefs.remove(key);
        return null;
      }
      final out = <String, String>{};
      for (final entry in fields.entries) {
        if (entry.key is String && entry.value is String) {
          out[entry.key as String] = entry.value as String;
        }
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// حفظ المسودة. لو كل الحقول فاضية بنمسحها بدل ما نحفظ مسودة فاضية.
  static Future<void> save(
    String uid,
    String form,
    Map<String, String> fields, {
    DateTime? now,
  }) async {
    final key = _keyFor(uid, form);
    if (key == null) return;
    final clean = <String, String>{};
    for (final entry in fields.entries) {
      final value = entry.value.trim().isEmpty
          ? ''
          : (entry.value.length > _maxFieldLength
              ? entry.value.substring(0, _maxFieldLength)
              : entry.value);
      if (value.isNotEmpty && clean.length < _maxFields) clean[entry.key] = value;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (clean.isEmpty) {
        await prefs.remove(key);
        return;
      }
      await prefs.setString(
        key,
        jsonEncode({'t': (now ?? DateTime.now()).millisecondsSinceEpoch, 'f': clean}),
      );
    } catch (_) {}
  }

  static Future<void> clear(String uid, String form) async {
    final key = _keyFor(uid, form);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// تسجيل الخروج/حذف الحساب/تبديل الحساب: كل المسودات تتمسح.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
