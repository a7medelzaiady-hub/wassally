import '../models/order.dart';
import 'format.dart';

/// سطر في إيصال الطلب.
class ReceiptLine {
  final String label;
  final String value;
  final bool strong;
  const ReceiptLine(this.label, this.value, {this.strong = false});
}

/// بيانات الإيصال محسوبة من الطلب اللي قدام العميل أصلًا: صفر قراءات.
/// نفس الأرقام اللي في صفحة «تفاصيل الطلب» بالظبط.
class OrderReceipt {
  final String orderNumber;
  final String date;
  final String storeName;
  final List<ReceiptLine> items;
  final List<ReceiptLine> totals;

  const OrderReceipt({
    required this.orderNumber,
    required this.date,
    required this.storeName,
    required this.items,
    required this.totals,
  });

  /// الإيصال بيظهر للطلبات اللي اتسلّمت بس.
  static bool available(AppOrder order) =>
      order.status == OrderStatus.delivered && order.items.isNotEmpty;

  factory OrderReceipt.of(AppOrder order) {
    final when = order.deliveredAt ?? order.createdAt;
    return OrderReceipt(
      orderNumber: shortOrderId(order.id),
      date: when == null ? '' : formatDateTime(when.toLocal()),
      storeName: order.storeName,
      items: [
        for (final item in order.items)
          ReceiptLine(
            '${item.qty} × ${item.name}'
            '${item.options.isEmpty ? '' : ' (${item.options.join('، ')})'}',
            formatPrice(item.total),
          ),
      ],
      totals: [
        ReceiptLine('المجموع', formatPrice(order.subtotal)),
        ReceiptLine('رسوم التوصيل', formatPrice(order.courierFee)),
        if ((order.serviceFee ?? 0) > 0)
          ReceiptLine('رسوم الخدمة', formatPrice(order.serviceFee!)),
        if (order.referralDiscountMinor > 0)
          ReceiptLine(
            'خصم نقاط الدعوات',
            '- ${formatPrice(order.referralDiscountMinor / 100)}',
          ),
        ReceiptLine('الإجمالي', formatPrice(order.payable), strong: true),
      ],
    );
  }

  /// اسم ملف الصورة عند المشاركة.
  String get fileName =>
      'wasally-receipt-${orderNumber.replaceAll('#', '')}.png';
}
