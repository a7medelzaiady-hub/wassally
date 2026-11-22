import 'wasally_service_fee.dart';

/// Quick-order pricing state. This is a UI model only; the Worker must
/// authenticate both parties and enforce every revision and transition.
class QuickDeliveryQuote {
  final String courierId;
  final int revision;
  final int? proposedDeliveryPiastres;
  final int? agreedDeliveryPiastres;

  const QuickDeliveryQuote({
    this.courierId = '',
    this.revision = 0,
    this.proposedDeliveryPiastres,
    this.agreedDeliveryPiastres,
  });

  bool get isAgreed => courierId.isNotEmpty && agreedDeliveryPiastres != null;
  bool get canPurchase => isAgreed;

  /// The assigned courier sets the fee before shopping; customer accepts.
  QuickDeliveryQuote propose({
    required String assignedCourierId,
    required int deliveryPiastres,
    required int maximumDeliveryPiastres,
  }) {
    if (assignedCourierId.isEmpty ||
        deliveryPiastres < 0 ||
        maximumDeliveryPiastres < 0 ||
        deliveryPiastres > maximumDeliveryPiastres) {
      throw ArgumentError('Invalid courier or delivery fee');
    }
    if (isAgreed) throw StateError('Fee already agreed');
    if (courierId.isNotEmpty && courierId != assignedCourierId) {
      throw StateError('Courier changed: reset pricing first');
    }
    return QuickDeliveryQuote(
      courierId: assignedCourierId,
      revision: revision + 1,
      proposedDeliveryPiastres: deliveryPiastres,
    );
  }

  QuickDeliveryQuote accept({
    required String assignedCourierId,
    required int expectedRevision,
  }) {
    if (assignedCourierId.isEmpty ||
        courierId != assignedCourierId ||
        proposedDeliveryPiastres == null ||
        expectedRevision != revision ||
        isAgreed) {
      throw StateError('Invalid or stale fee approval');
    }
    return QuickDeliveryQuote(
      courierId: courierId,
      revision: revision + 1,
      proposedDeliveryPiastres: proposedDeliveryPiastres,
      agreedDeliveryPiastres: proposedDeliveryPiastres,
    );
  }

  /// Changing the courier or approved shopping list requires a fresh quote.
  QuickDeliveryQuote reset() => QuickDeliveryQuote(revision: revision + 1);

  /// Gross customer bill, with one service fee for all shops.
  int totalPiastres(Iterable<int> receiptTotalsPiastres) {
    if (!isAgreed) throw StateError('Delivery fee not agreed');
    var purchases = 0;
    for (final amount in receiptTotalsPiastres) {
      if (amount < 0) throw ArgumentError.value(amount, 'receipt amount');
      purchases += amount;
    }
    return purchases +
        WasallyServiceFee.calculate(itemsAfterDiscountPiastres: purchases) +
        agreedDeliveryPiastres!;
  }

  /// Positive = customer owes courier; negative = courier refunds customer.
  int settlementPiastres({
    required Iterable<int> receiptTotalsPiastres,
    required int prepaidPiastres,
  }) {
    if (prepaidPiastres < 0) throw ArgumentError.value(prepaidPiastres);
    return totalPiastres(receiptTotalsPiastres) - prepaidPiastres;
  }
}

/// The server must snapshot these admin settings on creation.
class QuickOrderPaymentPolicy {
  final int prepaidThresholdPiastres;
  final int maximumAdvancePiastres;
  const QuickOrderPaymentPolicy({
    this.prepaidThresholdPiastres = 20000,
    required this.maximumAdvancePiastres,
  });

  bool requiresAdvance(int estimatedPurchasesPiastres) {
    if (estimatedPurchasesPiastres < 0) {
      throw ArgumentError.value(estimatedPurchasesPiastres);
    }
    return estimatedPurchasesPiastres > prepaidThresholdPiastres;
  }

  bool validAdvance(int amountPiastres) =>
      amountPiastres > 0 && amountPiastres <= maximumAdvancePiastres;
}
