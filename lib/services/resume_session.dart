import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #326: موبايلات زي شاومي/بوكو بتقفل عملية التطبيق كلها وهو في الخلفية،
/// فالرجوع بيشغّل التطبيق من الأول. هنا بنفتكر (على الموبايل بس، من غير Firestore):
/// - إمتى التطبيق راح الخلفية آخر مرة،
/// - وآخر شاشة رئيسية كان عليها العميل (تبويب من الشريط أو محل).
/// لو رجع خلال [window]، ده «رجوع» مش فتح جديد: من غير إعلانات ما بعد الدخول،
/// وبيرجع لنفس الشاشة. مفيش بيانات حساسة: رقم تبويب أو رقم محل بس.
class ResumeSession {
  ResumeSession._();

  static const window = Duration(minutes: 30);
  static const _pausedKey = 'resume_paused_at';
  static const _locationKey = 'resume_location';

  static bool _recent = false;
  static String? _pending;
  static String? _current;
  static String _uid = '';

  /// التشغيل ده رجوع لاستخدام قريب (التطبيق اتقفل في الخلفية من أقل من [window]).
  static bool get resumedRecently => _recent;

  /// الشاشة الحالية (للاختبارات والتشخيص).
  static String? get current => _current;

  /// بيتنده مرة واحدة قبل runApp.
  static Future<void> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paused = prefs.getInt(_pausedKey);
      final t = now ?? DateTime.now();
      final age = paused == null ? null : t.difference(DateTime.fromMillisecondsSinceEpoch(paused));
      _recent = age != null && !age.isNegative && age < window;
      _pending = _recent ? prefs.getString(_locationKey) : null;
      if (!_recent) await prefs.remove(_locationKey);
    } catch (_) {
      _recent = false;
      _pending = null;
    }
  }

  /// آخر شاشة محفوظة للحساب ده (مرة واحدة بس)، لو التشغيل ده رجوع قريب.
  /// القيمة: `shell:<tab>` أو `store:<id>`.
  static String? takeLocation(String uid) {
    final saved = _pending;
    _pending = null;
    if (saved == null) return null;
    final sep = saved.indexOf('|');
    if (sep <= 0 || saved.substring(0, sep) != uid) return null;
    return saved.substring(sep + 1);
  }

  /// بتتسجل الشاشة الرئيسية الحالية (null = صفحة الخدمات).
  static void setLocation(String uid, String? location) {
    _uid = uid;
    _current = location;
    unawaited(_write(location == null || uid.isEmpty ? null : '$uid|$location'));
  }

  static Future<void> _write(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_locationKey);
      } else {
        await prefs.setString(_locationKey, value);
      }
    } catch (_) {}
  }

  static Future<void> markBackground({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pausedKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }

  static _Observer? _observer;

  /// بيسجّل وقت الخروج للخلفية (من غير خدمات خلفية).
  static void startObserving() {
    if (_observer != null) return;
    _observer = _Observer();
    WidgetsBinding.instance.addObserver(_observer!);
  }

  /// للاختبارات بس.
  @visibleForTesting
  static void reset() {
    _recent = false;
    _pending = null;
    _current = null;
    _uid = '';
  }

  static String get uid => _uid;
}

class _Observer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      unawaited(ResumeSession.markBackground());
    }
  }
}
