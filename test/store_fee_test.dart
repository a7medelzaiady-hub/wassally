import 'package:city_store/services/store_fee_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = StoreFeeSummary(dueMinor: 2350, paidMinor: 500);

  test('المتبقي = المستحق - المدفوع', () {
    expect(s.outstandingMinor, 1850);
    expect(s.outstanding, 18.5);
  });

  test('تسجيل الدفعة: موجب، لحد قرشين، وما يزيدش عن المتبقي', () {
    expect(StoreFeeService.validatePayment(10, s), isNull);
    expect(StoreFeeService.validatePayment(18.5, s), isNull);
    expect(StoreFeeService.validatePayment(18.51, s), isNotNull);
    expect(StoreFeeService.validatePayment(0, s), isNotNull);
    expect(StoreFeeService.validatePayment(-3, s), isNotNull);
    expect(StoreFeeService.validatePayment(1.234, s), isNotNull);
  });
}
