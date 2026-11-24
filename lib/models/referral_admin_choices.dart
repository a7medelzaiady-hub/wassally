/// بيانات عرض محدودة لمهام إدارة الدعوات. التحقق والصرف على Worker فقط.
class ReferralStoreOwnerChoice {
  const ReferralStoreOwnerChoice({
    required this.storeId,
    required this.storeName,
    required this.ownerUid,
    required this.ownerName,
  });

  final String storeId;
  final String storeName;
  final String ownerUid;
  final String ownerName;

  String get key => '$storeId|$ownerUid';

  String get label => '$storeName — $ownerName';
}

/// ربط المحل بصاحبه من سجلات storeOwners المعتمدة، وليس من إدخال يدوي.
/// كل صاحب محل نشط يظهر كسطر منفصل عند وجود عدة ملاك للمحل نفسه.
List<ReferralStoreOwnerChoice> referralStoreOwnerChoices({
  required List<Map<String, dynamic>> owners,
  required Map<String, String> storeNames,
}) {
  final result = <ReferralStoreOwnerChoice>[];
  final seen = <String>{};
  for (final owner in owners) {
    final uid = (owner['uid'] ?? '').toString().trim();
    final storeId = (owner['storeId'] ?? '').toString().trim();
    if (uid.isEmpty || storeId.isEmpty || owner['active'] == false) continue;
    final storeName = storeNames[storeId];
    if (storeName == null || storeName.trim().isEmpty) continue;
    final entry = ReferralStoreOwnerChoice(
      storeId: storeId,
      storeName: storeName,
      ownerUid: uid,
      ownerName: (owner['name'] ?? '').toString().trim().isEmpty
          ? 'صاحب المحل ($uid)'
          : owner['name'].toString().trim(),
    );
    if (seen.add(entry.key)) result.add(entry);
  }
  result.sort((a, b) {
    final byStore = a.storeName.compareTo(b.storeName);
    return byStore != 0 ? byStore : a.ownerName.compareTo(b.ownerName);
  });
  return result;
}

class ReferralOrderChoice {
  const ReferralOrderChoice({
    required this.id,
    required this.storeName,
    required this.discountMinor,
    required this.status,
  });

  final String id;
  final String storeName;
  final int discountMinor;
  final String status;

  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';

  String get label =>
      '$storeName • $id • خصم ${(discountMinor / 100).toStringAsFixed(2)} ج.م'
      '${isCancelled ? ' • ملغي' : ''}';
}

/// لا تعرض طلبات دون خصم نقاط فعلي، أو قيد التجهيز.
/// Worker يتحقق كذلك من حالة سجل التسوية وأنه لم يُصرف سابقًا.
List<ReferralOrderChoice> referralEligibleOrders(
  List<Map<String, dynamic>> orders,
) {
  final result = <ReferralOrderChoice>[];
  final seen = <String>{};
  for (final row in orders) {
    final id = (row['id'] ?? '').toString().trim();
    final status = (row['status'] ?? '').toString();
    final discount = row['referralDiscountMinor'];
    if (id.isEmpty ||
        !seen.add(id) ||
        (status != 'delivered' && status != 'cancelled') ||
        discount is! num ||
        discount <= 0 ||
        discount != discount.roundToDouble()) {
      continue;
    }
    result.add(ReferralOrderChoice(
      id: id,
      storeName: (row['storeName'] ?? '').toString().trim().isEmpty
          ? 'محل غير معروف'
          : row['storeName'].toString().trim(),
      discountMinor: discount.toInt(),
      status: status,
    ));
  }
  return result;
}
