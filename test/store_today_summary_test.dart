import 'package:city_store/models/order.dart';
import 'package:city_store/utils/store_today_summary.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _o(String id, OrderStatus s, DateTime? created, {double sub = 100}) => AppOrder(
      id: id, storeName: 'S', items: const [], subtotal: sub, deliveryFee: 20, total: sub + 20,
      status: s, createdAt: created, address: 'a', phone: '010', notes: '',
    );

void main() {
  final now = DateTime(2026, 11, 26, 18, 0);
  final today = DateTime(2026, 11, 26, 10, 0);
  final yesterday = DateTime(2026, 11, 25, 23, 30);

  test('ملخص النهارده بس، والملغي لوحده', () {
    final s = StoreTodaySummary.of([
      _o('a', OrderStatus.delivered, today, sub: 150),
      _o('b', OrderStatus.delivered, today, sub: 50),
      _o('c', OrderStatus.preparing, today, sub: 80),
      _o('d', OrderStatus.cancelled, today, sub: 999),
      _o('old', OrderStatus.delivered, yesterday, sub: 500),
      _o('nodate', OrderStatus.delivered, null, sub: 500),
    ], now);
    expect(s.orders, 3);
    expect(s.delivered, 2);
    expect(s.cancelled, 1);
    expect(s.deliveredGoods, 200);
    expect(s.expectedGoods, 280);
    expect(s.isEmpty, isFalse);
  });

  test('مفيش طلبات النهارده = فاضي', () {
    expect(StoreTodaySummary.of([_o('old', OrderStatus.delivered, yesterday)], now).isEmpty, isTrue);
  });
}
