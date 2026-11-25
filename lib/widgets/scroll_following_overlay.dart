import 'package:flutter/widgets.dart';

/// يرسم زرًا فوق قائمة قابلة للتمرير لكن **خارجها**، ويحركه مع التمرير
/// كأنه جزء من المحتوى.
///
/// السبب: Flutter بيتجاهل اللمس داخل أي Scrollable طول ما التمرير أو
/// الارتداد (bounce) شغال. فزر الإشعارات اللي جوه الهيدر كان محتاج ضغطتين:
/// الأولى بتوقف الارتداد والتانية بتفتح الصفحة. الزر هنا بيستقبل أول ضغطة.
class ScrollFollowingOverlay extends StatelessWidget {
  const ScrollFollowingOverlay({
    super.key,
    required this.controller,
    required this.top,
    required this.child,
    this.start,
    this.end,
    this.hideAfter,
  });

  final ScrollController controller;

  /// موضع الزر من أعلى المحتوى عندما يكون التمرير عند الصفر.
  final double top;
  final double? start;
  final double? end;

  /// يختفي الزر بعد تمرير المسافة دي (لما الهيدر يطلع برا الشاشة).
  final double? hideAfter;
  final Widget child;

  double get _offset =>
      controller.hasClients && controller.positions.length == 1
          ? controller.offset
          : 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final offset = _offset;
        if (hideAfter != null && offset > hideAfter!) {
          return const SizedBox.shrink();
        }
        return PositionedDirectional(
          top: top - offset,
          start: start,
          end: end,
          child: child!,
        );
      },
    );
  }
}
