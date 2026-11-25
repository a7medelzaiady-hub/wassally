import 'package:flutter/material.dart';

import '../models/order.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';

/// فاتورة مقروءة للمندوب بعد التعيين، بلا قراءات Firestore جديدة.
/// تعرض محتوى الطلب مباشرة بدل إخفائه أسفل كارت الإجراءات.
class CourierOrderReceipt extends StatelessWidget {
  final List<OrderLine> items;
  final Map<String, dynamic>? specialRequest;
  final String notes;

  const CourierOrderReceipt({
    super.key,
    required this.items,
    this.specialRequest,
    this.notes = '',
  });

  @override
  Widget build(BuildContext context) {
    final specialDescription =
        (specialRequest?['description'] ?? '').toString().trim();
    final hasSpecialImage =
        (specialRequest?['imageUrl'] ?? '').toString().trim().isNotEmpty;
    final hasSpecialVoice =
        (specialRequest?['voiceUrl'] ?? '').toString().trim().isNotEmpty;
    final specialQuantity =
        (specialRequest?['quantity'] ?? '').toString().trim();
    final customerNotes = notes.trim();

    return Container(
      key: const Key('courier-order-receipt'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF8),
        border: Border.all(color: kLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 26, color: Brand.green),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'فاتورة طلب العميل',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${items.length} صنف',
            style: TextStyle(fontSize: 12.5, color: kMuted),
          ),
          const Divider(height: 20),
          if (items.isEmpty && specialDescription.isEmpty)
            const Text('لا توجد أصناف مسجلة في الطلب.'),
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Brand.green.withValues(alpha: 0.10),
                    ),
                    child: Text(
                      '${item.qty} ×',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Brand.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (item.options.isNotEmpty)
                          Text(
                            item.options.join('، '),
                            softWrap: true,
                            style: TextStyle(fontSize: 12.5, color: kMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPrice(item.total),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (specialDescription.isNotEmpty) ...[
            const Divider(height: 20),
            const Text(
              'طلب خاص',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            Text(
              specialQuantity.isEmpty
                  ? specialDescription
                  : '$specialDescription • الكمية: $specialQuantity',
              softWrap: true,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            if (hasSpecialImage)
              const Text('📎 صورة مرفقة بالطلب'),
            if (hasSpecialVoice)
              const Text('🎙️ ملف صوتي مرفق بالطلب'),
          ],
          if (customerNotes.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              'ملاحظات الطلب: $customerNotes',
              softWrap: true,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
