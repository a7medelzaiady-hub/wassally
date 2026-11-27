import '../services/cart_model.dart';
import 'format.dart';
import 'order_receipt.dart';
import 'share_links.dart';

/// نص مشاركة يدوي، من بيانات السلة الموجودة بالفعل.
/// لا نضمّن عنوان العميل أو هاتفه أو روابط المرفقات الخاصة.
String buildCartShareText(CartModel cart) {
  final lines = <String>[
    '🛒 سلتي في وصّلي',
    if ((cart.storeName ?? '').trim().isNotEmpty)
      'المحل: ${cart.storeName!.trim()}',
    '',
    for (final entry in cart.items.entries)
      '${entry.value} × ${entry.key.name} — '
          '${formatPrice(entry.key.price * entry.value)}',
  ];
  final note = (cart.specialRequest?['description'] ?? '').toString().trim();
  if (note.isNotEmpty) lines.add('ملاحظة: $note');
  lines.addAll([
    '',
    'إجمالي الأصناف: ${formatPrice(cart.subtotal)}',
    'الأسعار والتوافر ورسوم التوصيل يتم تأكيدها داخل التطبيق.',
  ]);
  return lines.join('\n');
}

/// السلة كإيصال حراري (صورة) للمشاركة. من بيانات السلة اللي على الموبايل: صفر قراءات.
/// من غير عنوان العميل أو تليفونه.
OrderReceipt buildCartReceipt(CartModel cart, {DateTime? now}) {
  final store = (cart.storeName ?? '').trim();
  final when = now ?? DateTime.now();
  final note = (cart.specialRequest?['description'] ?? '').toString().trim();
  final link = ShareLinks.playLink(storeId: cart.storeId);
  return OrderReceipt(
    title: 'سلتي',
    orderNumber: '',
    date: formatDateTime(when),
    storeName: store,
    items: [
      for (final entry in cart.items.entries)
        ReceiptLine(
          '${entry.value} × ${entry.key.name}',
          formatPrice(entry.key.price * entry.value),
          itemName: entry.key.name,
          quantity: entry.value,
          unitPrice: entry.key.price,
        ),
      if (note.isNotEmpty) ReceiptLine('طلب خاص: $note', ''),
    ],
    totals: [
      ReceiptLine('إجمالي الأصناف', formatPrice(cart.subtotal), strong: true),
    ],
    note: 'الأسعار والتوافر ورسوم التوصيل بتتأكد جوه التطبيق',
    qrLink: link,
    fileName: 'wasally-cart-${when.millisecondsSinceEpoch}.png',
    shareText: store.isEmpty
        ? 'سلتي على وصّلي 👇\n$link'
        : 'سلتي من $store على وصّلي 👇\n$link',
  );
}
