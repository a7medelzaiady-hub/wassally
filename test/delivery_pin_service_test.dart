import 'package:city_store/services/delivery_pin_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('رمز التسليم: 4 أرقام بس، والأرقام العربي بتتحول', () {
    expect(DeliveryPinService.normalize('0427'), '0427');
    expect(DeliveryPinService.normalize(' ٠٤٢٧ '), '0427');
    expect(DeliveryPinService.normalize('427'), isNull);
    expect(DeliveryPinService.normalize('04270'), isNull);
    expect(DeliveryPinService.normalize('04a7'), isNull);
    expect(DeliveryPinService.normalize(''), isNull);
  });
}
