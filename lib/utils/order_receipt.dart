import '../models/order.dart';
import 'format.dart';
import 'share_links.dart';

/// سطر في إيصال الطلب.
class ReceiptLine {
  final String label;
  final String value;
  final bool strong;

  /// بيانات أعمدة الفاتورة، من غير ما نكسر استهلاك label/value القديم.
  /// السعر للوحدة شامل الخيارات، والقيمة value هي إجمالي السطر.
  final String? itemName;
  final int? quantity;
  final double? unitPrice;
  bool get hasItemColumns => itemName != null && quantity != null && unitPrice != null;

  const ReceiptLine(
    this.label,
    this.value, {
    this.strong = false,
    this.itemName,
    this.quantity,
    this.unitPrice,
  });
}

/// بيانات الإيصال محسوبة من الطلب اللي قدام العميل أصلًا: صفر قراءات.
/// نفس الأرقام اللي في صفحة «تفاصيل الطلب» بالظبط.
class OrderReceipt {
  /// عنوان الإيصال تحت اسم وصّلي («إيصال طلب» أو «سلتي»).
  final String title;
  final String orderNumber;
  final String date;
  final String storeName;
  final List<ReceiptLine> items;
  final List<ReceiptLine> totals;

  /// سطر صغير تحت الإجمالي (مثلًا: الأسعار بتتأكد في التطبيق).
  final String note;

  /// رابط يترسم QR في آخر الإيصال (رابط التطبيق على Play). فاضي = من غير QR.
  final String qrLink;

  /// اسم ملف الصورة ونص المشاركة اللي معاها.
  final String fileName;
  final String shareText;

  const OrderReceipt({
    this.title = 'إيصال طلب',
    required this.orderNumber,
    required this.date,
    required this.storeName,
    required this.items,
    required this.totals,
    this.note = '',
    this.qrLink = '',
    String? fileName,
    String? shareText,
  })  : fileName = fileName ?? 'wasally-receipt-$orderNumber.png',
        shareText = shareText ?? 'إيصال طلب $orderNumber من وصّلي';

  /// الإيصال بيظهر للطلبات اللي اتسلّمت بس.
  static bool available(AppOrder order) =>
      order.status == OrderStatus.delivered && order.items.isNotEmpty;

  factory OrderReceipt.of(AppOrder order) {
    final when = order.deliveredAt ?? order.createdAt;
    return OrderReceipt(
      qrLink: ShareLinks.playLink(),
      orderNumber: simpleOrderNumber(order.id),
      date: when == null ? '' : formatDateTime(when.toLocal()),
      storeName: order.storeName,
      items: [
        for (final item in order.items)
          ReceiptLine(
            '${item.qty} × ${item.name}'
            '${item.options.isEmpty ? '' : ' (${item.options.join('، ')})'}',
            formatPrice(item.total),
            itemName: '${item.name}'
                '${item.options.isEmpty ? '' : ' (${item.options.join('، ')})'}',
            quantity: item.qty,
            unitPrice: item.price,
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
}
