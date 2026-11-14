import 'package:material_ui/material_ui.dart';

import '../models/order.dart';

/// كبسولة ملوّنة بحالة الطلب.
class OrderStatusPill extends StatelessWidget {
  final OrderStatus status;
  const OrderStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, status.color, 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: status.color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
