import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'resume_session.dart';
import 'route_key.dart';

/// uid الحساب الحالي، أو '' (من غير تسجيل دخول أو في اختبارات من غير Firebase).
String resumeAccountUid() {
  try {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  } catch (_) {
    return '';
  }
}

/// #339: تتبع مركزي لكل مسارات الـ Navigator (push / pushOnce / pushReplacement /
/// pop / popUntil / removeRoute). أي مسار اسمه [RouteKey] صالح بيتسجل في مكدّس
/// [ResumeSession] وبيتشال أول ما يتقفل، فالصفحة المقفولة عمرها ما بتتستعاد.
/// مفيش أي قراءة Firestore أو listener: كله في ذاكرة التطبيق وSharedPreferences.
class ResumeRouteObserver extends NavigatorObserver {
  ResumeRouteObserver({String Function()? uidOf}) : _uidOf = uidOf ?? resumeAccountUid;

  final String Function() _uidOf;

  String? _keyOf(Route<dynamic>? route) {
    final name = route?.settings.name;
    return RouteKey.parse(name) == null ? null : name;
  }

  void _track(Route<dynamic>? route) {
    final key = _keyOf(route);
    if (key != null) ResumeSession.trackPush(_uidOf(), key);
  }

  void _untrack(Route<dynamic>? route) {
    final key = _keyOf(route);
    if (key != null) ResumeSession.trackPop(key);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _untrack(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _untrack(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _untrack(oldRoute);
    _track(newRoute);
  }
}
