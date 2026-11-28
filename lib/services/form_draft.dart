import 'dart:async';

import 'package:flutter/widgets.dart';

import 'draft_store.dart';
import 'resume_route_observer.dart' show resumeAccountUid;
import 'resume_session.dart';

/// #339: مسودة نموذج على الموبايل بس.
/// - بتتحفظ بعد ما المستخدم يوقف كتابة لحظة (وفورًا لما التطبيق يروح الخلفية).
/// - بتتستعاد بس لو التطبيق رجع بعد ما أندرويد قفله (رجوع قريب)، مش في كل فتح.
/// - بتتمسح بعد الإرسال، وأول ما المستخدم يقفل الصفحة بنفسه.
/// مفيش Firestore ولا أي قراءة.
class FormDraft with WidgetsBindingObserver {
  FormDraft(
    this.form,
    this.fields, {
    String Function()? uidOf,
    this.delay = const Duration(milliseconds: 600),
  }) : _uidOf = uidOf ?? resumeAccountUid;

  final String form;

  /// القيم الحالية للحقول (بتتنده وقت الحفظ).
  final Map<String, String> Function() fields;
  final Duration delay;
  final String Function() _uidOf;

  Timer? _timer;
  bool _attached = false;
  bool _closed = false;

  /// بيبدأ يتابع التغييرات. [listenables] عادةً الـ TextEditingControllers.
  void attach(Iterable<Listenable> listenables) {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    for (final l in listenables) {
      l.addListener(changed);
    }
    _listenables = List.of(listenables);
  }

  List<Listenable> _listenables = const [];

  /// حقل بيتضاف بعد كده (محل جديد في الطلب السريع): صاحبه هو اللي بيعمله dispose.
  void watch(Listenable listenable) => listenable.addListener(changed);

  /// حقول المسودة لو ده رجوع بعد قفل التطبيق، وإلا null.
  Future<Map<String, String>?> loadIfResumed() async {
    if (!ResumeSession.resumedRecently) return null;
    return DraftStore.load(_uidOf(), form);
  }

  /// حقل اتغيّر: احفظ بعد لحظة.
  void changed() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_closed) return;
    await DraftStore.save(_uidOf(), form, fields());
  }

  /// الإرسال نجح: مفيش مسودة تفضل.
  Future<void> clear() async {
    _closed = true;
    _timer?.cancel();
    await DraftStore.clear(_uidOf(), form);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }

  /// قفل عادي للصفحة: المستخدم سابها بنفسه، فالمسودة تتمسح.
  void dispose() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      for (final l in _listenables) {
        l.removeListener(changed);
      }
    }
    final wasClosed = _closed;
    _closed = true;
    _timer?.cancel();
    if (!wasClosed) unawaited(DraftStore.clear(_uidOf(), form));
  }
}
