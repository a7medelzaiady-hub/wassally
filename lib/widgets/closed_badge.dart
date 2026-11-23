import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// شارة «مغلق الآن» للمحل المغلق مؤقتًا (ظاهر للعميل بس مايستقبلش طلبات).
class ClosedBadge extends StatelessWidget {
  final double fontSize;
  const ClosedBadge({super.key, this.fontSize = 11.5});

  static const String label = 'مغلق الآن';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDanger.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: kDanger, fontSize: fontSize, fontWeight: FontWeight.w800),
      ),
    );
  }
}
