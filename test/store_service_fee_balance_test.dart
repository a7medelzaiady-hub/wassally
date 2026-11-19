import 'package:flutter_test/flutter_test.dart';
import 'package:wassally/services/store_service_fee_balance.dart';

void main() {
  test('delivered orders minus confirmed payments', () {
    final due = StoreServiceFeeBalance.outstandingPiastres(
      charges: const [
        StoreFeeCharge(orderId: 'a', amountPiastres: 500, delivered: true),
        StoreFeeCharge(orderId: 'b', amountPiastres: 1000, delivered: true),
        StoreFeeCharge(orderId: 'c', amountPiastres: 1500, delivered: false),
        StoreFeeCharge(orderId: 'd', amountPiastres: 500, delivered: true, cancelled: true),
        StoreFeeCharge(orderId: 'a', amountPiastres: 500, delivered: true),
      ],
      payments: const [
        StoreFeePayment(id: 'pay1', amountPiastres: 1000, confirmed: true),
        StoreFeePayment(id: 'pay1', amountPiastres: 1000, confirmed: true),
        StoreFeePayment(id: 'pending', amountPiastres: 500, confirmed: false),
      ],
    );
    expect(due, 500);
  });

  test('full payment zeros balance', () {
    expect(StoreServiceFeeBalance.outstandingPiastres(
      charges: const [StoreFeeCharge(orderId: 'a', amountPiastres: 500, delivered: true)],
      payments: const [StoreFeePayment(id: 'p', amountPiastres: 500, confirmed: true)],
    ), 0);
  });
}
