import 'package:flutter_test/flutter_test.dart';
import 'package:wassally/services/quick_delivery_quote.dart';

void main() {
  test('customer counteroffer invalidates courier previous offer', () {
    final first = const QuickDeliveryQuote().offer(
      actor: 'courier', deliveryPiastres: 5000,
    );
    final second = first.offer(actor: 'customer', deliveryPiastres: 3500);
    expect(second.revision, 2);
    expect(() => second.accept(actor: 'customer', expectedRevision: 1),
        throwsStateError);
    expect(() => second.accept(actor: 'customer', expectedRevision: 2),
        throwsStateError);
    final agreed = second.accept(actor: 'courier', expectedRevision: 2);
    expect(agreed.agreedDeliveryPiastres, 3500);
    expect(agreed.canPurchase, isTrue);
    expect(() => agreed.offer(actor: 'courier', deliveryPiastres: 4000),
        throwsStateError);
  });

  test('purchase prohibited before agreement', () {
    expect(const QuickDeliveryQuote().canPurchase, isFalse);
    expect(() => const QuickDeliveryQuote().totalPiastres([10000]),
        throwsStateError);
  });

  test('multiple receipts incur service fee once', () {
    final agreed = const QuickDeliveryQuote()
        .offer(actor: 'courier', deliveryPiastres: 4000)
        .accept(actor: 'customer', expectedRevision: 1);
    // 200 + 400 EGP purchases; 2% = 12 EGP; delivery = 40 EGP.
    expect(agreed.totalPiastres([20000, 40000]), 65200);
    // 1000 EGP purchases; service fee capped at 15 EGP.
    expect(agreed.totalPiastres([100000]), 105500);
    expect(() => agreed.totalPiastres([-1]), throwsArgumentError);
  });
}
