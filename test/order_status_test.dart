import 'package:city_store/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderStatus.courierNext', () {
    test('طلب جديد أو بيتحضّر: الخطوة الجاية هي في الطريق', () {
      expect(OrderStatus.newOrder.courierNext, OrderStatus.onTheWay);
      expect(OrderStatus.preparing.courierNext, OrderStatus.onTheWay);
    });

    test('في الطريق: الخطوة الجاية هي تم التسليم', () {
      expect(OrderStatus.onTheWay.courierNext, OrderStatus.delivered);
    });

    test('المسلّم والملغي مفيهمش إجراء للمندوب', () {
      expect(OrderStatus.delivered.courierNext, isNull);
      expect(OrderStatus.cancelled.courierNext, isNull);
    });
  });

  test('المندوب يستنى التجهيز: بس في الطلب الجديد', () {
    expect(OrderStatus.newOrder.courierMustWait, isTrue);
    expect(OrderStatus.preparing.courierMustWait, isFalse);
    expect(OrderStatus.onTheWay.courierMustWait, isFalse);
  });

  test('الحالة المجهولة بتتحول لطلب جديد', () {
    expect(OrderStatus.parse('???'), OrderStatus.newOrder);
    expect(OrderStatus.parse('delivered'), OrderStatus.delivered);
  });
}
