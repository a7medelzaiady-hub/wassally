import 'dart:async';

import 'package:flutter/material.dart';

import '../services/resume_route_observer.dart' show resumeAccountUid;
import '../services/resume_session.dart';

/// #339: بيحفظ موضع التمرير (رقم صحيح في ذاكرة التطبيق، ويتكتب على الموبايل
/// عند الذهاب للخلفية) وبيرجّعه بعد ما أندرويد يقفل العملية ويرجع المستخدم.
/// القوائم بتتحمّل من الشبكة بعد أول فريم، فبنحاول لحد ما المحتوى يطول كفاية
/// (حد أقصى [maxAttempts] محاولة)، ونوقف فورًا لو المستخدم لمس الشاشة.
/// مفيش قراءات Firestore ولا listeners.
class ScrollMemory {
  ScrollMemory(
    this.key, {
    ScrollController? controller,
    String Function()? uidOf,
    this.interval = const Duration(milliseconds: 100),
    this.maxAttempts = 80,
  })  : controller = controller ?? ScrollController(),
        _ownsController = controller == null,
        _uidOf = uidOf ?? resumeAccountUid;

  /// `<شاشة>/<اسم>` — يفضّل يبدأ باسم المسار (`order:<id>/items`) عشان يتمسح لما الصفحة تتقفل.
  final String key;
  final ScrollController controller;
  final Duration interval;
  final int maxAttempts;
  final bool _ownsController;
  final String Function() _uidOf;

  Timer? _timer;
  int _attempts = 0;
  double _lastApplied = 0;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    controller.addListener(_save);
    final target = ResumeSession.takeRemembered(_uidOf(), key);
    if (target != null && target > 0) _restore(target.toDouble());
  }

  void _save() {
    // أثناء الاستعادة ما نكتبش فوق الموضع المحفوظ بموضع مؤقت.
    if (!controller.hasClients || (_timer?.isActive ?? false)) return;
    ResumeSession.remember(_uidOf(), key, controller.offset.round());
  }

  void _restore(double target) {
    _timer = Timer.periodic(interval, (timer) {
      _attempts++;
      if (_attempts > maxAttempts) {
        timer.cancel();
        return;
      }
      if (!controller.hasClients) return;
      final position = controller.position;
      // المستخدم بدأ يتمرر بنفسه: ما نقاطعوش.
      if ((position.pixels - _lastApplied).abs() > 4) {
        timer.cancel();
        return;
      }
      final max = position.maxScrollExtent;
      if (max >= target) {
        controller.jumpTo(target);
        _lastApplied = target;
        timer.cancel();
      } else if (max > _lastApplied) {
        controller.jumpTo(max);
        _lastApplied = max;
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    if (_attached) {
      controller.removeListener(_save);
      // قفل عادي للصفحة: موضعها ما يتستعادش بعد كده.
      ResumeSession.forget(_uidOf(), key);
    }
    if (_ownsController) controller.dispose();
  }
}

/// #339: بيلف أي قائمة بتتمرر بـ [ScrollMemory] من غير ما الصفحة تبقى StatefulWidget.
class RememberScroll extends StatefulWidget {
  const RememberScroll({super.key, required this.name, required this.builder});

  /// `<شاشة>/<اسم>`؛ يفضّل يبدأ باسم المسار (`notifications/list`).
  final String name;
  final Widget Function(BuildContext context, ScrollController controller) builder;

  @override
  State<RememberScroll> createState() => _RememberScrollState();
}

class _RememberScrollState extends State<RememberScroll> {
  late final ScrollMemory _memory = ScrollMemory(widget.name)..attach();

  @override
  void dispose() {
    _memory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _memory.controller);
}

/// #339: رقم التبويب الداخلي (لوحة المحل مثلًا). بيتحط جوه [DefaultTabController].
class TabIndexMemory extends StatefulWidget {
  const TabIndexMemory({super.key, required this.name, required this.child, this.uidOf});

  final String name;
  final Widget child;
  final String Function()? uidOf;

  /// التبويب المحفوظ (مرة واحدة)، للـ `initialIndex` بتاع [DefaultTabController].
  static int initialIndex(String name, int length, {String Function()? uidOf}) {
    final saved = ResumeSession.takeRemembered((uidOf ?? resumeAccountUid)(), name);
    if (saved == null || saved < 0 || saved >= length) return 0;
    return saved;
  }

  @override
  State<TabIndexMemory> createState() => _TabIndexMemoryState();
}

class _TabIndexMemoryState extends State<TabIndexMemory> {
  TabController? _controller;

  void _save() {
    final c = _controller;
    if (c == null || c.indexIsChanging) return;
    ResumeSession.remember((widget.uidOf ?? resumeAccountUid)(), widget.name, c.index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.removeListener(_save);
    _controller = next?..addListener(_save);
  }

  @override
  void dispose() {
    _controller?.removeListener(_save);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
