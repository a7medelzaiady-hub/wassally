import '../services/cart_model.dart';
import 'format.dart';

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
