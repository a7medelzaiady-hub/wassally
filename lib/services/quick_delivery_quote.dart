import 'wasally_service_fee.dart';

/// Pure state for negotiating delivery price in «طلباتك على السريع».
/// This model does not grant write permissions: Worker and Firestore rules
/// must independently validate every transition and its revision.
class QuickDeliveryQuote {
  final int revision;
  final int? proposedDeliveryPiastres;
  final String? proposedBy;
  final int? agreedDeliveryPiastres;

  const QuickDeliveryQuote({
    this.revision = 0,
    this.proposedDeliveryPiastres,
    this.proposedBy,
    this.agreedDeliveryPiastres,
  });

  bool get isAgreed => agreedDeliveryPiastres != null;
  bool get canPurchase => isAgreed;

  /// Each new offer invalidates the previous offer and any stale acceptance.
  QuickDeliveryQuote offer({
    required String actor,
    required int deliveryPiastres,
  }) {
    if (actor != 'customer' && actor != 'courier') {
      throw ArgumentError.value(actor, 'actor');
    }
    if (deliveryPiastres < 0) {
      throw ArgumentError.value(deliveryPiastres, 'deliveryPiastres');
    }
    if (isAgreed) {
      throw StateError('Agreed delivery fee cannot be changed unilaterally');
    }
    return QuickDeliveryQuote(
      revision: revision + 1,
      proposedDeliveryPiastres: deliveryPiastres,
      proposedBy: actor,
    );
  }

  /// Accept only the current revision, and only by the opposite party.
  QuickDeliveryQuote accept({
    required String actor,
    required int expectedRevision,
  }) {
    if (isAgreed || proposedDeliveryPiastres == null ||
        expectedRevision != revision || actor == proposedBy ||
        (actor != 'customer' && actor != 'courier')) {
      throw StateError('Invalid or outdated delivery quote acceptance');
    }
    return QuickDeliveryQuote(
      revision: revision + 1,
      proposedDeliveryPiastres: proposedDeliveryPiastres,
      proposedBy: proposedBy,
      agreedDeliveryPiastres: proposedDeliveryPiastres,
    );
  }

  /// One Wasally service fee per task, even when there are many receipts.
  int totalPiastres(Iterable<int> receiptTotalsPiastres) {
    if (!isAgreed) throw StateError('Delivery price is not agreed');
    var purchases = 0;
    for (final amount in receiptTotalsPiastres) {
      if (amount < 0) throw ArgumentError.value(amount, 'receipt amount');
      purchases += amount;
    }
    return purchases +
        WasallyServiceFee.calculate(itemsAfterDiscountPiastres: purchases) +
        agreedDeliveryPiastres!;
  }
}
