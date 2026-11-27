import 'package:flutter/material.dart';

/// شاشة التحميل الأولى بنفس لون ولوجو شاشة البداية بتاعة أندرويد
/// (android/app/src/main/res/values/colors.xml → wasally_splash)، فالانتقال من
/// شاشة النظام لـFlutter ما يبانش فيه وميض أبيض (#326).
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  /// لازم يفضل نفس قيمة `wasally_splash` في الأندرويد.
  static const color = Color(0xFF452080);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/wasally_logo_light.png',
              width: 117,
              errorBuilder: (_, _, _) => const SizedBox(height: 50),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
