import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/quick_delivery_quote.dart';

void main() {
  test('only the assigned courier quote can be approved', () {
    final quote = const QuickDeliveryQuote().propose(
      assignedCourierId: 'courier-a',
      deliveryPiastres: 4000,
      maximumDeliveryPiastres: 10000,
    );
    expect(() => quote.accept(
      assignedCourierId: 'courier-b', expectedRevision: 1,
    ), throwsStateError);
    expect(() => quote.accept(
      assignedCourierId: 'courier-a', expectedRevision: 0,
    ), throwsStateError);
    final agreed = quote.accept(
      assignedCourierId: 'courier-a', expectedRevision: 1,
    );
    expect(agreed.canPurchase, isTrue);
    expect(() => agreed.propose(
      assignedCourierId: 'courier-a',
      deliveryPiastres: 5000,
      maximumDeliveryPiastres: 10000,
    ), throwsStateError);
    expect(agreed.reset().canPurchase, isFalse);
  });

  test('reject negative, oversized and switched courier offers', () {
    expect(() => const QuickDeliveryQuote().propose(
      assignedCourierId: 'a', deliveryPiastres: 11000,
      maximumDeliveryPiastres: 10000,
    ), throwsArgumentError);
    final q = const QuickDeliveryQuote().propose(
      assignedCourierId: 'a', deliveryPiastres: 3000,
      maximumDeliveryPiastres: 10000,
    );
    expect(() => q.propose(
      assignedCourierId: 'b', deliveryPiastres: 3000,
      maximumDeliveryPiastres: 10000,
    ), throwsStateError);
  });

  test('one service fee across receipts and advance reconciliation', () {
    final q = const QuickDeliveryQuote().propose(
      assignedCourierId: 'a', deliveryPiastres: 4000,
      maximumDeliveryPiastres: 10000,
    ).accept(assignedCourierId: 'a', expectedRevision: 1);
    expect(q.totalPiastres([20000, 40000]), 65200);
    expect(q.settlementPiastres(
      receiptTotalsPiastres: [20000, 40000],
      prepaidPiastres: 60000,
    ), 5200);
    expect(q.settlementPiastres(
      receiptTotalsPiastres: [10000],
      prepaidPiastres: 20000,
    ), lessThan(0));
  });

  test('200 EGP threshold is inclusive for cash-on-delivery', () {
    const policy = QuickOrderPaymentPolicy(maximumAdvancePiastres: 50000);
    expect(policy.requiresAdvance(20000), isFalse);
    expect(policy.requiresAdvance(20001), isTrue);
    expect(policy.validAdvance(50000), isTrue);
    expect(policy.validAdvance(50001), isFalse);
  });
}
