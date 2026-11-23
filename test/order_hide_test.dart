import 'package:city_store/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('الإخفاء من سجل العميل للطلبات المنتهية بس (نفس شرط القواعد)', () {
    expect(OrderStatus.delivered.canHideFromHistory, isTrue);
    expect(OrderStatus.cancelled.canHideFromHistory, isTrue);
    expect(OrderStatus.newOrder.canHideFromHistory, isFalse);
    expect(OrderStatus.preparing.canHideFromHistory, isFalse);
    expect(OrderStatus.onTheWay.canHideFromHistory, isFalse);
  });
}
