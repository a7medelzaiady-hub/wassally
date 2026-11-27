import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/order_contact_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import 'courier_order_receipt.dart';

/// Full courier order summary, using the order and private contact already loaded
/// by the parent card: no additional Firestore reads or listeners.
///
/// Private fields are rebuilt when the parent revokes access (status change,
/// reassignment or customer confirmation), including while this sheet is open.
class CourierOrderDetailsSheet extends StatelessWidget {
  final AppOrder order;
  final String orderNumber;
  final OrderContact? contact;
  /// Reads the parent's cached contact on notifier changes; never fetches data.
  final OrderContact? Function()? contactProvider;
  final ValueListenable<bool> canSeePrivateContact;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCall;

  const CourierOrderDetailsSheet({
    super.key,
    required this.order,
    required this.orderNumber,
    required this.contact,
    this.contactProvider,
    required this.canSeePrivateContact,
    this.onOpenMap,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            key: const Key('courier-order-details-sheet'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kLine,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'تفاصيل الطلب رقم $orderNumber',
                style: TextStyle(
                  color: Brand.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text('المحل: ${order.storeName.isEmpty ? 'المحل' : order.storeName}'),
              Text('الحالة: ${order.status.label}'),
              Text('منطقة التوصيل: ${order.area.isEmpty ? 'غير محددة' : order.area}'),
              const SizedBox(height: 5),
              // Show the receipt first, like a clear thermal invoice.
              CourierOrderReceipt(
                items: order.items,
                specialRequest: order.specialRequest,
                notes: order.notes,
              ),
              const SizedBox(height: 8),
              Text(
                'المطلوب تحصيله: ${formatPrice(order.payable)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'عمولتك: ${formatPrice(order.courierFee)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: Brand.green),
              ),
              const Divider(height: 26),
              ValueListenableBuilder<bool>(
                valueListenable: canSeePrivateContact,
                builder: (context, allowed, _) {
                  if (!allowed) {
                    final beforePickup = order.status == OrderStatus.preparing;
                    return Text(
                      beforePickup
                          ? 'العنوان بالتفصيل وتليفون العميل بيظهروا بعد ما تستلم الطلب من المحل. '
                              'لو محتاج حاجة قبل كده كلّم المحل أو الإدارة.'
                          : 'بيانات العميل الخاصة غير متاحة بعد انتهاء التعيين أو التسليم.',
                      key: const Key('courier-private-hidden'),
                      style: const TextStyle(color: Colors.black54),
                    );
                  }
                  final c = contactProvider != null
                      ? contactProvider!()
                      : contact;
                  if (c == null) {
                    return const Text('جارٍ تحميل بيانات العميل أو تعذر الوصول إليها.');
                  }
                  return Column(
                    key: const Key('courier-private-details'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('بيانات التواصل بعد التعيين',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      if (c.name.trim().isNotEmpty)
                        Text('العميل: ${c.name}'),
                      Text(c.address.trim().isEmpty
                          ? 'العنوان التفصيلي غير متاح'
                          : 'العنوان: ${c.address}'),
                      if (c.phone.trim().isNotEmpty)
                        Text('الهاتف: ${c.phone}'),
                      if (c.courierNotes.trim().isNotEmpty)
                        Text('ملاحظات للمندوب: ${c.courierNotes}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (c.address.trim().isNotEmpty)
                            OutlinedButton.icon(
                              key: const Key('courier-details-map'),
                              onPressed: onOpenMap,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('افتح الخريطة'),
                            ),
                          if (c.phone.trim().isNotEmpty)
                            OutlinedButton.icon(
                              key: const Key('courier-details-call'),
                              onPressed: onCall,
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('اتصل بالعميل'),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}
