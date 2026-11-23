import 'package:city_store/models/order.dart';
import 'package:city_store/screens/courier_orders_page.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order(OrderStatus status, {bool ready = true, DateTime? confirmed}) => AppOrder(
      id: 'o1',
      storeName: 'S',
      items: const [],
      subtotal: 10,
      deliveryFee: 20,
      total: 30,
      status: status,
      createdAt: DateTime(2026, 11, 20),
      address: 'a',
      phone: '01000000000',
      notes: '',
      ready: ready,
      customerConfirmedAt: confirmed,
      deliveryMode: 'external',
    );

void main() {
  test('زرار «استلمت من المحل» يظهر بس قبل بدء التوصيل', () {
    expect(showsPickupButton(_order(OrderStatus.preparing)), isTrue);
    // في الطريق والعميل أكد ومستني تسوية النقدية: مفيش زرار استلام من المحل
    expect(showsPickupButton(_order(OrderStatus.onTheWay, confirmed: DateTime(2026, 11, 20))), isFalse);
    expect(showsPickupButton(_order(OrderStatus.onTheWay)), isFalse);
    expect(showsPickupButton(_order(OrderStatus.delivered)), isFalse);
    expect(showsPickupButton(_order(OrderStatus.cancelled)), isFalse);
  });
}
