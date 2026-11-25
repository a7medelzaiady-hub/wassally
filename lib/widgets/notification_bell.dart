import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// زر الإشعارات الموحد.
///
/// سبب مشكلة «لازم أضغط أكتر من مرة»: شارة العدد الحمراء كانت مرسومة فوق
/// ركن الزر وبتستقبل اللمسة بدل الزر نفسه، والزر كان أصغر من مساحة الضغط
/// المريحة (38 بدل 48). هنا الشارة لا تستقبل اللمس، والمنطقة كلها 48×48،
/// فأي ضغطة على الجرس أو الشارة بتفتح الإشعارات من أول مرة.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.onTap,
    this.count = 0,
    this.shake,
    this.size = kMinTapTarget,
    this.color = Colors.white,
    this.iconColor = AppColors.orange,
  });

  final VoidCallback onTap;
  final int count;

  /// أنيميشن هزة الجرس (اختياري).
  final Animation<double>? shake;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    Widget icon = Icon(Icons.notifications_none_rounded, color: iconColor, size: 26);
    final shake = this.shake;
    if (shake != null) {
      icon = AnimatedBuilder(
        animation: shake,
        child: icon,
        builder: (context, child) {
          // هزة يمين وشمال وتخفت تدريجيًا
          final t = shake.value;
          final angle = math.sin(t * math.pi * 6) * 0.35 * (1 - t);
          return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
        },
      );
    }
    return Semantics(
      button: true,
      label: count > 0 ? 'الإشعارات، $count غير مقروءة' : 'الإشعارات',
      excludeSemantics: true,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('notification-bell'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                icon,
                if (count > 0)
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    // The badge is decoration only: taps go to the button.
                    child: IgnorePointer(
                      child: Container(
                        key: const Key('notification-bell-badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
