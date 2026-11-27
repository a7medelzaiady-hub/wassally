import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/navigation.dart' show rootNavigatorKey;
import '../theme/app_tokens.dart';

/// نوع الرسالة: بيحدد الرسمة اللي فوق البرواز ولونها.
enum AppNoticeKind { success, info, error }

/// الرسالة المعروضة حاليًا (رسالة واحدة بس في المرة).
Route<void>? _current;

/// رسالة مهمة في نص الشاشة: برواز ثلاثي الأبعاد ورسمة على الزاوية اللي فوق.
/// للإشعارات زي «تم إرسال طلبك» و«طلبك جاهز». الرسائل الصغيرة السريعة
/// (اتحفظ، تعذر...) بتفضل `appSnack` تحت عشان ما تقاطعش الشغل.
///
/// بتشتغل من غير context (بتستخدم الـ navigator الرئيسي)، فينفع تتنادى
/// حتى بعد ما الصفحة اللي طلبتها اتقفلت.
Future<void> showAppNotice({
  required String title,
  required String message,
  AppNoticeKind kind = AppNoticeKind.success,
  String buttonLabel = 'تمام',
  Duration? autoClose,
}) async {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  final old = _current;
  if (old != null && old.isActive) nav.removeRoute(old);

  final route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: 'قفل',
    barrierColor: const Color(0x8C140A26),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, a1, a2) => AppNoticeCard(
      title: title,
      message: message,
      kind: kind,
      buttonLabel: buttonLabel,
      onClose: () => Navigator.of(ctx).maybePop(),
    ),
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 0.82, end: 1.0).animate(curved), child: child),
      );
    },
  );
  _current = route;
  Timer? timer;
  if (autoClose != null) {
    timer = Timer(autoClose, () {
      if (route.isCurrent) {
        nav.pop();
      } else if (route.isActive) {
        nav.removeRoute(route);
      }
    });
  }
  await nav.push(route);
  timer?.cancel();
  if (identical(_current, route)) _current = null;
}

/// الكارت نفسه (منفصل عشان الاختبارات ومعاينة التصميم).
class AppNoticeCard extends StatelessWidget {
  final String title;
  final String message;
  final AppNoticeKind kind;
  final String buttonLabel;
  final VoidCallback onClose;

  const AppNoticeCard({
    super.key,
    required this.title,
    required this.message,
    required this.onClose,
    this.kind = AppNoticeKind.success,
    this.buttonLabel = 'تمام',
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // البرواز: إطار متدرّج بنفسجي/برتقالي + طبقة غامقة تحت
                  // (ظل صلب) بتدّي إحساس إن الكارت بارز ثلاثي الأبعاد.
                  Container(
                    key: const Key('app-notice-frame'),
                    margin: const EdgeInsets.only(top: 34),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [AppColors.purpleDeep, AppColors.purple, AppColors.orangeLight],
                        stops: [0, 0.55, 1],
                      ),
                      boxShadow: const [
                        BoxShadow(color: AppColors.purpleDarker, offset: Offset(0, 7)),
                        BoxShadow(color: Color(0x55000000), offset: Offset(0, 18), blurRadius: 30),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 48, 18, 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Color(0xFFF7F3FF)],
                        ),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: AppTypography.title,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            message,
                            style: const TextStyle(
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w500,
                              color: AppColors.inkSoft,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _PressableButton(label: buttonLabel, onTap: onClose),
                        ],
                      ),
                    ),
                  ),
                  // الرسمة على الزاوية اللي فوق (يمين، أول السطر العربي).
                  Positioned(
                    top: 0,
                    right: 16,
                    child: _NoticeIllustration(kind: kind),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زرار برتقالي بارز (له حافة غامقة تحت زي البرواز).
class _PressableButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PressableButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: AppColors.orangeDeep, offset: Offset(0, 4))],
        gradient: AppColors.actionGradient,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('app-notice-ok'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypography.titleSmall,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// كرة مجسّمة (تدرّج دائري بلمعة) وجواها أيقونة، وحواليها نجوم وكونفيتي.
class _NoticeIllustration extends StatelessWidget {
  final AppNoticeKind kind;
  const _NoticeIllustration({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (light, deep, icon, badge) = switch (kind) {
      AppNoticeKind.success => (
          const Color(0xFFB57BFF),
          AppColors.purpleDarker,
          Icons.shopping_bag_rounded,
          Icons.check_rounded,
        ),
      AppNoticeKind.info => (
          const Color(0xFFFFB46B),
          AppColors.orangeDeep,
          Icons.notifications_active_rounded,
          null,
        ),
      AppNoticeKind.error => (
          const Color(0xFFFF8A80),
          const Color(0xFFB3261E),
          Icons.priority_high_rounded,
          null,
        ),
    };
    return SizedBox(
      key: const Key('app-notice-illustration'),
      width: 104,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // كونفيتي ونجوم حوالين الكرة.
          const Positioned.fill(child: CustomPaint(painter: _ConfettiPainter())),
          Positioned(
            right: 12,
            top: 0,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 0.95,
                  colors: [light, deep],
                ),
                boxShadow: [
                  BoxShadow(color: deep.withValues(alpha: 0.45), offset: const Offset(0, 8), blurRadius: 14),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // لمعة صغيرة فوق الشمال بتكمّل الإحساس بالتجسيم.
                  Positioned(
                    top: 9,
                    left: 13,
                    child: Container(
                      width: 16,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Icon(icon, color: Colors.white, size: 36, shadows: const [
                    Shadow(color: Color(0x40000000), offset: Offset(0, 2), blurRadius: 4),
                  ]),
                ],
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: 4,
              bottom: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 3), blurRadius: 5)],
                ),
                child: Icon(badge, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..style = PaintingStyle.fill;
    void star(Offset c, double r, Color color) {
      final p = Path();
      for (var i = 0; i < 8; i++) {
        final rad = i.isEven ? r : r * 0.38;
        final a = -math.pi / 2 + i * math.pi / 4;
        final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(p..close(), dot..color = color);
    }

    star(Offset(size.width * 0.12, size.height * 0.30), 7, AppColors.orangeLight);
    star(Offset(size.width * 0.20, size.height * 0.78), 4.5, AppColors.purple);
    star(Offset(size.width * 0.96, size.height * 0.12), 5, AppColors.orangeLight);
    canvas.drawCircle(Offset(size.width * 0.04, size.height * 0.58), 2.6, dot..color = AppColors.purpleDeep);
    canvas.drawCircle(Offset(size.width * 0.30, size.height * 0.05), 2.2, dot..color = AppColors.success);
    final bar = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width * 0.06, size.height * 0.04), width: 8, height: 3),
      const Radius.circular(2),
    );
    canvas.save();
    canvas.translate(bar.center.dx, bar.center.dy);
    canvas.rotate(-0.6);
    canvas.translate(-bar.center.dx, -bar.center.dy);
    canvas.drawRRect(bar, dot..color = AppColors.orange);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
