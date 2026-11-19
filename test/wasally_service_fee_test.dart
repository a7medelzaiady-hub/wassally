import 'package:flutter_test/flutter_test.dart';
import 'package:wassally/services/wasally_service_fee.dart';

void main() {
  test('2% with 5 EGP minimum and 15 EGP maximum', () {
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 10000), 500);
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 30000), 600);
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 75000), 1500);
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 100000), 1500);
  });
  test('waiver and empty cart yield zero', () {
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 20000, waived: true), 0);
    expect(WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 0), 0);
  });
  test('invalid settings are rejected', () {
    expect(() => WasallyServiceFee.calculate(itemsAfterDiscountPiastres: -1), throwsArgumentError);
    expect(() => WasallyServiceFee.calculate(itemsAfterDiscountPiastres: 1000, minimumPiastres: 1500, maximumPiastres: 500), throwsArgumentError);
  });
}
