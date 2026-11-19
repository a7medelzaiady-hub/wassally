/// حساب مستحقات وصّلي على المحل، بدون خلطها بثمن البضاعة أو أجر المندوب.
///
/// تُستخرج الرسوم من الطلبات المكتملة فقط، ويُخصم منها السداد المؤكد.
/// عند ربطها بـ Firestore يجب أن يقتصر تسجيل السداد على المدير، وأن تُمنع
/// إعادة احتساب الطلب أو عملية السداد نفسها مرتين.
class StoreServiceFeeBalance {
  const StoreServiceFeeBalance._();

  static int outstandingPiastres({
    required Iterable<StoreFeeCharge> charges,
    required Iterable<StoreFeePayment> payments,
  }) {
    final seenOrders = <String>{};
    var due = 0;
    for (final charge in charges) {
      if (charge.orderId.isEmpty ||
          charge.amountPiastres < 0 ||
          !seenOrders.add(charge.orderId)) {
        continue;
      }
      if (charge.delivered && !charge.cancelled) {
        due += charge.amountPiastres;
      }
    }
    final seenPayments = <String>{};
    var paid = 0;
    for (final payment in payments) {
      if (payment.id.isEmpty ||
          payment.amountPiastres <= 0 ||
          !payment.confirmed ||
          !seenPayments.add(payment.id)) {
        continue;
      }
      paid += payment.amountPiastres;
    }
    return due - paid;
  }
}

class StoreFeeCharge {
  const StoreFeeCharge({
    required this.orderId,
    required this.amountPiastres,
    required this.delivered,
    this.cancelled = false,
  });

  final String orderId;
  final int amountPiastres;
  final bool delivered;
  final bool cancelled;
}

class StoreFeePayment {
  const StoreFeePayment({
    required this.id,
    required this.amountPiastres,
    required this.confirmed,
  });

  final String id;
  final int amountPiastres;
  final bool confirmed;
}
