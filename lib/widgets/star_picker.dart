import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// اختيار تقييم من 1 لـ5 نجوم.
/// النجمة الفاضية رمادي فاتح (واضح إنها فاضية)، والمليانة بلون التطبيق.
/// بيصغر لوحده لو المساحة ضيقة بدل ما يطلع خارج الحوار (overflow).
class StarPicker extends StatelessWidget {
  final num value;
  final ValueChanged<int> onChanged;
  final double size;
  final Color? filledColor;

  const StarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 32,
    this.filledColor,
  });

  static const Color emptyColor = Color(0xFFD9D9D9);

  @override
  Widget build(BuildContext context) {
    final filled = filledColor ?? kAccent;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Semantics(
              button: true,
              selected: star <= value,
              label: '$star من 5',
              child: InkResponse(
                key: ValueKey('star_$star'),
                radius: size * 0.75,
                onTap: () => onChanged(star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Icon(
                    Icons.star_rounded,
                    size: size,
                    color: star <= value ? filled : emptyColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
