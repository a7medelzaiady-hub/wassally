/// رسوم خدمة وصّلي: حساب خالص بدون Firestore أو آثار جانبية.
/// لا تُستخدم هذه الدالة وحدها لتوثيق مبلغ الطلب؛ يجب إعادة الحساب في Worker.
class WasallyServiceFee {
  const WasallyServiceFee._();

  /// حساب الرسوم بالقروش لتجنب أخطاء الكسور العشرية.
  /// [itemsAfterDiscountPiastres] قيمة البضاعة بعد خصم الأصناف/الكوبون.
  static int calculate({
    required int itemsAfterDiscountPiastres,
    int rateBasisPoints = 200, // 2%
    int minimumPiastres = 500, // 5 EGP
    int maximumPiastres = 1500, // 15 EGP
    bool waived = false,
  }) {
    if (itemsAfterDiscountPiastres < 0 ||
        rateBasisPoints < 0 ||
        minimumPiastres < 0 ||
        maximumPiastres < minimumPiastres) {
      throw ArgumentError('Invalid service fee settings');
    }
    if (waived || itemsAfterDiscountPiastres == 0) return 0;
    final computed =
        (itemsAfterDiscountPiastres * rateBasisPoints + 5000) ~/ 10000;
    return computed.clamp(minimumPiastres, maximumPiastres).toInt();
  }

  /// رسوم الخدمة بالجنيه على قيمة الأصناف (بعد الخصم): 2%، أقل حاجة 5 وأقصى حاجة 15.
  /// نفس الحساب بالظبط في الـWorker (serviceFeeFor)، والـWorker هو اللي بيعتمد الرقم.
  static double forItems(double itemsAfterDiscount) {
    if (!itemsAfterDiscount.isFinite || itemsAfterDiscount <= 0) return 0;
    final piastres = (itemsAfterDiscount * 100).round();
    return calculate(itemsAfterDiscountPiastres: piastres) / 100;
  }
}
