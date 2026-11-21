import 'package:city_store/models/order.dart';
import 'package:city_store/utils/store_orders_split.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _o(String id, OrderStatus s, {DateTime? created, DateTime? delivered, double sub = 100, double? fee}) =>
    AppOrder(
      id: id, storeName: 'S', items: const [], subtotal: sub, deliveryFee: 20, total: sub + 20,
      status: s, createdAt: created, address: 'a', phone: '010', notes: '',
      deliveredAt: delivered, serviceFee: fee,
    );

void main() {
  final d1 = DateTime(2026, 11, 10);
  final d2 = DateTime(2026, 11, 20);
  final settle = DateTime(2026, 11, 15);

  test('الطلبات الشغالة بس هي المفتوحة', () {
    expect(isOpenOrder(_o('a', OrderStatus.preparing)), isTrue);
    expect(isOpenOrder(_o('b', OrderStatus.delivered)), isFalse);
    expect(isOpenOrder(_o('c', OrderStatus.cancelled)), isFalse);
  });

  test('قبل أي تقفيل: كل المنتهي يظهر، والشغال لا', () {
    final r = closedOrdersAfterSettlement([
      _o('a', OrderStatus.preparing, created: d1),
      _o('b', OrderStatus.delivered, created: d1, delivered: d1),
      _o('c', OrderStatus.cancelled, created: d2),
    ], null);
    expect(r.map((e) => e.id), ['b', 'c']);
  });

  test('بعد التقفيل: القديم يختفي والأحدث يفضل', () {
    final r = closedOrdersAfterSettlement([
      _o('old', OrderStatus.delivered, created: d1, delivered: d1),
      _o('new', OrderStatus.delivered, created: d1, delivered: d2),
      _o('oldCancel', OrderStatus.cancelled, created: d1),
      _o('nodate', OrderStatus.cancelled),
    ], settle);
    expect(r.map((e) => e.id), ['new', 'nodate']);
  });

  test('ملخص الفلوس', () {
    final m = ClosedOrdersMoney.of([
      _o('a', OrderStatus.delivered, sub: 100, fee: 5),
      _o('b', OrderStatus.delivered, sub: 50),
      _o('c', OrderStatus.cancelled, sub: 999, fee: 9),
    ]);
    expect(m.completedCount, 2);
    expect(m.cancelledCount, 1);
    expect(m.goodsTotal, 150);
    expect(m.serviceFeeTotal, 5);
  });

  test('تجميع حسب اليوم: الأحدث أولاً، الرسوم للمسلّم بس، الملغي بيتعدّ من غير فلوس', () {
    final g = groupClosedByDay([
      _o('a', OrderStatus.delivered, created: DateTime(2026, 11, 20, 10), delivered: DateTime(2026, 11, 20, 23, 30), sub: 100, fee: 5),
      _o('b', OrderStatus.delivered, created: DateTime(2026, 11, 21, 9), delivered: DateTime(2026, 11, 21, 9, 30), sub: 50, fee: 2),
      _o('c', OrderStatus.cancelled, created: DateTime(2026, 11, 21, 12), sub: 999, fee: 9),
      _o('d', OrderStatus.delivered, created: DateTime(2026, 11, 21, 8), delivered: DateTime(2026, 11, 21, 14), sub: 10, fee: 1),
    ]);
    expect(g.length, 2);
    expect(g[0].day, DateTime(2026, 11, 21));
    expect(g[0].orders.map((e) => e.id), ['d', 'b', 'c']);
    expect(g[0].money.completedCount, 2);
    expect(g[0].money.cancelledCount, 1);
    expect(g[0].money.goodsTotal, 60);
    expect(g[0].money.serviceFeeTotal, 3);
    expect(g[1].day, DateTime(2026, 11, 20));
    expect(g[1].money.serviceFeeTotal, 5);
  });
}
