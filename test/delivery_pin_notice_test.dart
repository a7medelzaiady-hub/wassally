import 'package:city_store/utils/delivery_pin_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تنبيه رمز التسليم بيذكر الـ4 أرقام والاحتفاظ بيه', () {
    expect(kDeliveryPinKeepNotice, contains('4 أرقام'));
    expect(kDeliveryPinKeepNotice, contains('احتفظ'));
  });
}
