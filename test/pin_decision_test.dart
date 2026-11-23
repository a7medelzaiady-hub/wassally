import 'package:city_store/models/order.dart';
import 'package:city_store/screens/admin_orders_page.dart';
import 'package:city_store/screens/courier_orders_page.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _o(OrderStatus s, {DateTime? locked, DateTime? confirmed}) => AppOrder(
      id: 'o1', storeName: 'S', items: const [], subtotal: 10, deliveryFee: 20, total: 30,
      status: s, createdAt: DateTime(2026, 11, 21), address: 'a', phone: '010', notes: '',
      deliveryPinLockedAt: locked, customerConfirmedAt: confirmed,
    );

void main() {
  test('قرار الإدارة بيظهر بس لطلب في الطريق رمزه اتقفل ولسه ما اتأكدش', () {
    final t = DateTime(2026, 11, 21);
    expect(needsPinDecision(_o(OrderStatus.onTheWay, locked: t)), isTrue);
    expect(needsPinDecision(_o(OrderStatus.onTheWay)), isFalse);
    expect(needsPinDecision(_o(OrderStatus.onTheWay, locked: t, confirmed: t)), isFalse);
    expect(needsPinDecision(_o(OrderStatus.delivered, locked: t)), isFalse);
  });

  test('المندوب: بعد قفل الرمز الزرار يتقفل، وبيرجع طبيعي لو الإدارة أكدت أو الرمز مش مقفول', () {
    final t = DateTime(2026, 11, 21);
    expect(courierPinLocked(_o(OrderStatus.onTheWay, locked: t)), isTrue);
    expect(courierPinLocked(_o(OrderStatus.onTheWay)), isFalse);
    expect(courierPinLocked(_o(OrderStatus.onTheWay, locked: t, confirmed: t)), isFalse);
  });

  test('الإدارة: الانتقالات المسموحة تطابق القواعد (بعد تأكيد العميل مفيش تغيير)', () {
    final t = DateTime(2026, 11, 21);
    final confirmed = _o(OrderStatus.onTheWay, locked: t, confirmed: t);
    for (final s in OrderStatus.values) {
      expect(adminCanSetStatus(confirmed, s), isFalse, reason: s.key);
    }
    // مندوب المحل + رمز مقفول: الإغلاق «تم التوصيل» مسموح، الرجوع ممنوع، الإلغاء بيتحقق منه الـservice.
    final storeLocked = AppOrder(
      id: 'o1', storeName: 'S', items: const [], subtotal: 10, deliveryFee: 20, total: 30,
      status: OrderStatus.onTheWay, createdAt: t, address: 'a', phone: '010', notes: '',
      deliveryPinLockedAt: t, deliveryMode: 'store', courierId: 'c1',
    );
    expect(adminCanSetStatus(storeLocked, OrderStatus.delivered), isTrue);
    expect(adminCanSetStatus(storeLocked, OrderStatus.preparing), isFalse);
    expect(adminCanSetStatus(storeLocked, OrderStatus.newOrder), isFalse);
    // مندوب خارجي رمزه مقفول (لسه ما اتأكدش): مفيش إغلاق من الإدارة، بس قرار تأكيد الاستلام.
    expect(adminCanSetStatus(_o(OrderStatus.onTheWay, locked: t), OrderStatus.delivered), isFalse);
    // الدورة العادية.
    expect(adminCanSetStatus(_o(OrderStatus.newOrder), OrderStatus.preparing), isTrue);
    expect(adminCanSetStatus(_o(OrderStatus.newOrder), OrderStatus.onTheWay), isFalse);
    expect(adminCanSetStatus(_o(OrderStatus.preparing), OrderStatus.cancelled), isTrue);
    expect(adminCanSetStatus(_o(OrderStatus.preparing), OrderStatus.onTheWay), isFalse);
    // مسلّم أو ملغي: مقفول بالكامل.
    expect(adminCanSetStatus(_o(OrderStatus.delivered), OrderStatus.cancelled), isFalse);
    expect(adminCanSetStatus(_o(OrderStatus.cancelled), OrderStatus.delivered), isFalse);
  });

  test('اعتماد السعر مقفول بعد خروج الطلب للتوصيل أو تأكيد العميل (مطابق pricingApprovalWindow)', () {
    final t = DateTime(2026, 11, 21);
    expect(adminCanApprovePrice(_o(OrderStatus.newOrder)), isTrue);
    expect(adminCanApprovePrice(_o(OrderStatus.preparing)), isTrue);
    expect(adminCanApprovePrice(_o(OrderStatus.onTheWay)), isFalse);
    expect(adminCanApprovePrice(_o(OrderStatus.delivered)), isFalse);
    expect(adminCanApprovePrice(_o(OrderStatus.cancelled)), isFalse);
    expect(adminCanApprovePrice(_o(OrderStatus.preparing, confirmed: t)), isFalse);
    expect(adminPrepStepsApply(_o(OrderStatus.preparing)), isTrue);
    expect(adminPrepStepsApply(_o(OrderStatus.onTheWay)), isFalse);
  });
}
