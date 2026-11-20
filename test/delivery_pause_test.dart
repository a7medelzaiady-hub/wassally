import 'package:city_store/services/delivery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مفتاح إيقاف الطلبات: true صريحة بس هي اللي بتوقف', () {
    expect(DeliveryService.parseOrdersPaused({'ordersPaused': true}), isTrue);
    expect(DeliveryService.parseOrdersPaused({'ordersPaused': false}), isFalse);
    expect(DeliveryService.parseOrdersPaused({'ordersPaused': 'true'}), isFalse);
    expect(DeliveryService.parseOrdersPaused({'areas': []}), isFalse);
    expect(DeliveryService.parseOrdersPaused(null), isFalse);
  });
}
