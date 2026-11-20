import 'package:city_store/models/order.dart';
import 'package:city_store/screens/admin_orders_page.dart';
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
}
