import 'package:city_store/models/order.dart';
import 'package:city_store/utils/order_pages.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = DateTime(2026, 11, 27, 12);

AppOrder _o(String id, int minute, {OrderStatus status = OrderStatus.newOrder, bool timed = true}) =>
    AppOrder(
      id: id,
      storeName: 'محل',
      items: const [OrderLine('صنف', 10, 1)],
      subtotal: 10,
      deliveryFee: 5,
      total: 15,
      status: status,
      createdAt: timed ? _base.add(Duration(minutes: minute)) : null,
      address: '',
      phone: '',
      notes: '',
    );

List<String> _ids(List<AppOrder> l) => [for (final o in l) o.id];

void main() {
  group('صفحات طلبات الإدارة بمؤشر', () {
    test('الدمج: من غير تكرار، والأحدث الأول', () {
      final live = [_o('c', 30), _o('b', 20)];
      final older = [_o('b', 20), _o('a', 10)];
      expect(_ids(mergeOrderPages(live, older)), ['c', 'b', 'a']);
    });

    test('النسخة اللحظية بتكسب لو الطلب موجود في صفحة أقدم', () {
      final live = [_o('x', 5, status: OrderStatus.preparing)];
      final older = [_o('x', 5)];
      final merged = mergeOrderPages(live, older);
      expect(merged.single.status, OrderStatus.preparing);
    });

    test('الطلب اللي لسه بيتحفظ (من غير وقت) بيظهر الأول', () {
      final merged = mergeOrderPages([_o('a', 10), _o('new', 0, timed: false)], const []);
      expect(_ids(merged), ['new', 'a']);
    });

    test('طلب خرج من الصفحة اللحظية بيتحفظ وما يختفيش', () {
      final spill = <String, AppOrder>{};
      final prev = [_o('c', 30), _o('b', 20)];
      final next = [_o('d', 40), _o('c', 30)]; // b خرج لما d وصل
      spillDroppedOrders(previousLive: prev, nextLive: next, spill: spill);
      expect(spill.keys, ['b']);
      expect(_ids(mergeOrderPages(next, spill.values)), ['d', 'c', 'b']);
    });

    test('طلب رجع للصفحة اللحظية بيتشال من المحفوظ', () {
      final spill = <String, AppOrder>{'b': _o('b', 20)};
      spillDroppedOrders(
        previousLive: [_o('c', 30)],
        nextLive: [_o('c', 30), _o('b', 20, status: OrderStatus.cancelled)],
        spill: spill,
      );
      expect(spill, isEmpty);
    });

    test('المؤشر = آخر طلب ليه وقت', () {
      final list = [_o('c', 30), _o('b', 20), _o('z', 0, timed: false)];
      expect(oldestTimedOrder(list)?.id, 'b');
      expect(oldestTimedOrder(const []), isNull);
    });
  });
}
