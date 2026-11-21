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

  test('الإدارة: بعد تأكيد العميل الاستلام مفيش رجوع ولا إلغاء، الإغلاق «تم التوصيل» بس', () {
    final t = DateTime(2026, 11, 21);
    final confirmed = _o(OrderStatus.onTheWay, locked: t, confirmed: t);
    expect(adminCanSetStatus(confirmed, OrderStatus.delivered), isTrue);
    expect(adminCanSetStatus(confirmed, OrderStatus.cancelled), isFalse);
    expect(adminCanSetStatus(confirmed, OrderStatus.preparing), isFalse);
    expect(adminCanSetStatus(confirmed, OrderStatus.newOrder), isFalse);
    // طلب عادي لسه ما اتأكدش: الإدارة تقدر تغيّر زي الأول.
    expect(adminCanSetStatus(_o(OrderStatus.onTheWay), OrderStatus.cancelled), isTrue);
    // مسلّم أو ملغي: مقفول بالكامل.
    expect(adminCanSetStatus(_o(OrderStatus.delivered), OrderStatus.cancelled), isFalse);
    expect(adminCanSetStatus(_o(OrderStatus.cancelled), OrderStatus.delivered), isFalse);
  });
}
