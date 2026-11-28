import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_key.dart';

/// #326/#339: موبايلات زي شاومي/بوكو بتقفل عملية التطبيق كلها وهو في الخلفية،
/// فالرجوع بيشغّل التطبيق من الأول. هنا بنفتكر (على الموبايل بس، من غير Firestore):
/// - إمتى التطبيق راح الخلفية آخر مرة،
/// - الشاشة الرئيسية اللي كان عليها المستخدم (تبويب أو لوحة دور أو محل أو خدمة)،
/// - مكدّس الصفحات المفتوحة فوقها (طلب، إشعارات، ...) كأسماء [RouteKey] بس،
/// - مواضع التمرير ورقم التبويب الداخلي (أرقام صحيحة فقط).
/// لو رجع خلال [window]، ده «رجوع» مش فتح جديد: من غير إعلانات ما بعد الدخول،
/// وبيرجع لنفس الشاشة. مفيش بيانات حساسة: كله مرتبط بالحساب (uid) وبيتمسح
/// عند الخروج أو تبديل الحساب.
class ResumeSession {
  ResumeSession._();

  static const window = Duration(minutes: 30);
  static const _pausedKey = 'resume_paused_at';
  static const _locationKey = 'resume_location';
  static const _stackKey = 'resume_stack';
  static const _stateKey = 'resume_state';
  static const _maxStack = 12;
  static const _maxState = 64;

  static bool _recent = false;
  static bool _suppressed = false;
  static String? _pending;
  static String? _pendingStackRaw;
  static Map<String, int> _restoreState = {};
  static String _restoreOwner = '';
  static String? _current;
  static String _uid = '';
  static List<String> _stack = [];
  static String _stackUid = '';
  static Map<String, int> _state = {};
  static String _stateUid = '';
  static Future<void> _pendingWrite = Future<void>.value();

  /// التشغيل ده رجوع لاستخدام قريب (التطبيق اتقفل في الخلفية من أقل من [window]).
  static bool get resumedRecently => _recent;

  /// الشاشة الحالية (للاختبارات والتشخيص).
  static String? get current => _current;

  /// مكدّس الصفحات المتتبَّعة حاليًا (نسخة للقراءة فقط).
  static List<String> get stack => List.unmodifiable(_stack);

  /// بيتنده مرة واحدة قبل runApp.
  static Future<void> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paused = prefs.getInt(_pausedKey);
      final t = now ?? DateTime.now();
      final age = paused == null ? null : t.difference(DateTime.fromMillisecondsSinceEpoch(paused));
      _recent = age != null && !age.isNegative && age < window;
      _suppressed = false;
      _restoreOwner = '';
      if (_recent) {
        _pending = prefs.getString(_locationKey);
        _pendingStackRaw = prefs.getString(_stackKey);
        _restoreState = _decodeState(prefs.getString(_stateKey));
      } else {
        _pending = null;
        _pendingStackRaw = null;
        _restoreState = {};
        await prefs.remove(_locationKey);
        await prefs.remove(_stackKey);
        await prefs.remove(_stateKey);
      }
    } catch (_) {
      _recent = false;
      _pending = null;
      _pendingStackRaw = null;
      _restoreState = {};
    }
  }

  /// الرابط (deep link) أو الإشعار اللي فتح التطبيق له الأولوية: مفيش استعادة فوقه.
  static void suppressRestore() {
    _suppressed = true;
    _pending = null;
    _pendingStackRaw = null;
    _restoreState = {};
  }

  /// آخر شاشة محفوظة للحساب ده (مرة واحدة بس)، لو التشغيل ده رجوع قريب.
  /// القيمة: `shell:<tab>` أو `store:<id>` أو `dashboard` أو `service:<name>`.
  static String? takeLocation(String uid) {
    final saved = _pending;
    _pending = null;
    if (saved == null || _suppressed) return null;
    final sep = saved.indexOf('|');
    if (sep <= 0 || saved.substring(0, sep) != uid) return null;
    return saved.substring(sep + 1);
  }

  /// مكدّس الصفحات المحفوظ للحساب ده (مرة واحدة بس). أسماء صالحة فقط، بالترتيب.
  static List<String> takeStack(String uid) {
    final raw = _pendingStackRaw;
    _pendingStackRaw = null;
    if (raw == null || _suppressed) return const [];
    final sep = raw.indexOf('|');
    if (sep <= 0 || raw.substring(0, sep) != uid) return const [];
    final keys = <String>[];
    for (final part in raw.substring(sep + 1).split(',')) {
      if (RouteKey.parse(part) == null || keys.contains(part)) continue;
      keys.add(part);
    }
    return keys.length > _maxStack ? keys.sublist(keys.length - _maxStack) : keys;
  }

  /// بتتسجل الشاشة الرئيسية الحالية (null = صفحة الخدمات).
  static void setLocation(String uid, String? location) {
    _uid = uid;
    _current = location;
    // Serialize writes: a rapid push/pop must not leave an older route saved.
    final value = location == null || uid.isEmpty ? null : '$uid|$location';
    _enqueue(() => _write(_locationKey, value));
  }

  // ───────────────────────── مكدّس الصفحات ─────────────────────────

  /// صفحة قابلة للاستعادة اتفتحت. الحساب الجديد بيبدأ مكدّس نضيف.
  static void trackPush(String uid, String key) {
    if (uid.isEmpty || RouteKey.parse(key) == null) return;
    if (_stackUid != uid) {
      _stack = [];
      _stackUid = uid;
    }
    if (_stack.isNotEmpty && _stack.last == key) return;
    _stack.remove(key);
    _stack.add(key);
    if (_stack.length > _maxStack) _stack.removeAt(0);
    _persistStack();
  }

  /// الصفحة اتقفلت (زرار رجوع أو إزالة): ما تتستعادش تاني.
  static void trackPop(String key) => closeRoute(key);

  /// صفحة لسه ظاهرة بس محتواها خلص (طلب اتسلّم/اتلغى): ما تتستعادش بعد كده.
  static void closeRoute(String key) {
    final removed = _stack.remove(key);
    final prefix = '$key/';
    final hadState = _state.keys.any((k) => k.startsWith(prefix));
    _state.removeWhere((k, _) => k.startsWith(prefix));
    if (removed || hadState) _persistStack();
  }

  /// بتتنده من build صفحة الطلب: لو الطلب خلص أو اختفى، الصفحة ما تتستعادش.
  static void closeIfFinished(String? key, bool finished) {
    if (key != null && finished) closeRoute(key);
  }

  static void _persistStack() {
    final uid = _stackUid;
    final value = uid.isEmpty || _stack.isEmpty ? null : '$uid|${_stack.join(',')}';
    _enqueue(() => _write(_stackKey, value));
  }

  // ───────────────────────── التمرير والتبويبات ─────────────────────────

  /// موضع تمرير/تبويب (رقم صحيح) في الذاكرة؛ بيتكتب على الموبايل عند الذهاب للخلفية.
  /// المفتاح: `<شاشة>/<اسم>`، حروف وأرقام و`:` `-` `_` `/` بس.
  static void remember(String uid, String key, int value) {
    if (uid.isEmpty || !_stateKeyPattern.hasMatch(key) || value < 0) return;
    if (_stateUid != uid) {
      _state = {};
      _stateUid = uid;
    }
    if (_state.length >= _maxState && !_state.containsKey(key)) return;
    _state[key] = value;
  }

  /// الصفحة اتقفلت بشكل عادي: موضعها ما يتستعادش في مرة جاية.
  static void forget(String uid, String key) {
    if (_stateUid == uid) _state.remove(key);
  }

  /// القيمة المحفوظة من التشغيل السابق لنفس الحساب (مرة واحدة)، أو null.
  static int? takeRemembered(String uid, String key) {
    if (_suppressed || uid.isEmpty || _restoreOwner != uid) return null;
    return _restoreState.remove(key);
  }

  static final _stateKeyPattern = RegExp(r'^[A-Za-z0-9:_/-]{1,160}$');

  static Map<String, int> _decodeState(String? raw) {
    if (raw == null) return {};
    final sep = raw.indexOf('|');
    if (sep <= 0) return {};
    _restoreOwner = raw.substring(0, sep);
    final out = <String, int>{};
    for (final part in raw.substring(sep + 1).split(';')) {
      final eq = part.lastIndexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq);
      final value = int.tryParse(part.substring(eq + 1));
      if (value == null || value < 0 || !_stateKeyPattern.hasMatch(key)) continue;
      out[key] = value;
    }
    return out;
  }

  static String? _encodeState() {
    if (_state.isEmpty || _stateUid.isEmpty) return null;
    return '$_stateUid|${_state.entries.map((e) => '${e.key}=${e.value}').join(';')}';
  }

  // ───────────────────────── الكتابة والدورة ─────────────────────────

  static void _enqueue(Future<void> Function() job) {
    _pendingWrite = _pendingWrite.then((_) => job());
    unawaited(_pendingWrite);
  }

  static Future<void> _write(String key, String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (_) {}
  }

  /// Wait for queued route changes before persisting the background timestamp.
  static Future<void> markBackground({DateTime? now}) async {
    final state = _encodeState();
    _enqueue(() => _write(_stateKey, state));
    await _pendingWrite;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pausedKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// تسجيل الخروج/حذف الحساب/تبديل الحساب: مفيش أي أثر لمسار حساب سابق.
  static Future<void> clearAll() async {
    _recent = false;
    _pending = null;
    _pendingStackRaw = null;
    _restoreState = {};
    _restoreOwner = '';
    _current = null;
    _uid = '';
    _stack = [];
    _stackUid = '';
    _state = {};
    _stateUid = '';
    _enqueue(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_locationKey);
        await prefs.remove(_stackKey);
        await prefs.remove(_stateKey);
        await prefs.remove(_pausedKey);
      } catch (_) {}
    });
    await _pendingWrite;
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
    _suppressed = false;
    _pending = null;
    _pendingStackRaw = null;
    _restoreState = {};
    _restoreOwner = '';
    _current = null;
    _uid = '';
    _stack = [];
    _stackUid = '';
    _state = {};
    _stateUid = '';
    _pendingWrite = Future<void>.value();
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
