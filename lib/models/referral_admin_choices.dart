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


/// Read-only account suggestions for administrators. These are not eligibility
/// decisions: the trusted Worker must verify Firebase Auth and issue the code.
class ReferralMarketerChoice {
  const ReferralMarketerChoice({
    required this.uid,
    required this.name,
    required this.email,
  });

  final String uid;
  final String name;
  final String email;

  String get label => email.isEmpty ? name : '$name — $email';

  bool matches(String query) {
    final search = query.trim().toLowerCase();
    return search.isEmpty ||
        name.toLowerCase().contains(search) ||
        email.toLowerCase().contains(search) ||
        uid.toLowerCase().contains(search);
  }
}

/// Normalizes a bounded /users admin fetch into unique selection rows.
/// Keep this independent of Firestore so its filtering can be unit tested.
List<ReferralMarketerChoice> referralMarketerChoices(
  List<Map<String, dynamic>> users,
) {
  final result = <ReferralMarketerChoice>[];
  final seen = <String>{};
  for (final user in users) {
    final uid = (user['uid'] ?? '').toString().trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid) ||
        !seen.add(uid) ||
        user['active'] == false ||
        user['deleted'] == true) {
      continue;
    }
    final primaryName = (user['name'] ?? '').toString().trim();
    final alternateName = (user['displayName'] ?? '').toString().trim();
    result.add(ReferralMarketerChoice(
      uid: uid,
      name: primaryName.isNotEmpty
          ? primaryName
          : alternateName.isNotEmpty
              ? alternateName
              : 'حساب ($uid)',
      email: (user['email'] ?? '').toString().trim(),
    ));
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}
