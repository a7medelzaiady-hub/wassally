import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// نوع طلب الانضمام. القيم لازم تطابق firestore.rules (validRoleRequest).
enum JoinType {
  storeOwner('store_owner', 'صاحب محل'),
  courier('courier', 'مندوب توصيل');

  final String key;
  final String label;
  const JoinType(this.key, this.label);

  static JoinType? parse(String? k) {
    for (final t in JoinType.values) {
      if (t.key == k) return t;
    }
    return null;
  }
}

/// طلبات الانضمام في role_requests/{uid}_{type}. المستخدم عنده طلب واحد لكل نوع.
class RoleRequestService {
  const RoleRequestService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('role_requests');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// طلباتي (للعرض في صفحة الحساب).
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchMine() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _col.where('userId', isEqualTo: uid).snapshots().map((s) => s.docs);
  }

  /// بيبعت الطلب (أو يعيد التقديم بعد الرفض: set بيستبدل المستند، والقواعد بتسمح بده للمرفوض بس).
  static Future<void> submit({
    required JoinType type,
    required String name,
    required String phone,
    String storeName = '',
    String storeCategory = '',
    String address = '',
    String vehicle = '',
    String notes = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    await _col.doc('${user.uid}_${type.key}').set({
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'type': type.key,
      'name': name.trim(),
      'phone': phone,
      if (type == JoinType.storeOwner) 'storeName': storeName.trim(),
      if (type == JoinType.storeOwner) 'storeCategory': storeCategory.trim(),
      if (type == JoinType.storeOwner) 'address': address.trim(),
      if (type == JoinType.courier) 'vehicle': vehicle.trim(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// طلبات الانضمام المعلقة للأدمن.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPending() =>
      _col.where('status', isEqualTo: 'pending').snapshots();

  /// للمدير: قبول طلب. بيكتب الدور (couriers أو storeOwners) وبيقفل الطلب في نفس الـ batch.
  /// لصاحب المحل: إما [storeId] لمحل موجود، أو [newStoreName] لمحل جديد (بيتعمل له مستند في stores).
  static Future<void> approve(
    QueryDocumentSnapshot<Map<String, dynamic>> req, {
    String? storeId,
    String? newStoreName,
  }) async {
    final admin = FirebaseAuth.instance.currentUser?.uid;
    if (admin == null) throw StateError('سجّل دخول الأول.');
    final m = req.data();
    final uid = (m['userId'] ?? '').toString();
    final type = JoinType.parse(m['type']?.toString());
    if (uid.isEmpty || type == null) throw StateError('طلب غير صالح.');
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    if (type == JoinType.courier) {
      batch.set(db.collection('couriers').doc(uid), {
        'name': (m['name'] ?? '').toString(),
        'phone': (m['phone'] ?? '').toString(),
        'active': true,
      }, SetOptions(merge: true));
    } else {
      final newName = (newStoreName ?? '').trim();
      if ((storeId == null || storeId.isEmpty) && newName.isEmpty) {
        throw StateError('اكتب اسم المحل أو اختار محل موجود.');
      }
      if (storeId == null || storeId.isEmpty) {
        final storeRef = db.collection('stores').doc();
        batch.set(storeRef, {
          'name': newName,
          'category': (m['storeCategory'] ?? 'أخرى').toString(),
          'active': true,
          'time': '',
          'image': '',
          'imageUrl': '',
          'productCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        storeId = storeRef.id;
      }
      batch.set(db.collection('storeOwners').doc(uid), {
        'name': (m['name'] ?? '').toString(),
        'phone': (m['phone'] ?? '').toString(),
        'storeId': storeId,
        'active': true,
      });
    }
    batch.update(req.reference, {
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': admin,
    });
    await batch.commit();
  }

  static Future<void> reject(
    QueryDocumentSnapshot<Map<String, dynamic>> req, {
    String note = '',
  }) {
    final admin = FirebaseAuth.instance.currentUser?.uid ?? '';
    return req.reference.update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': admin,
      'adminNote': cleanNote,
    });
  }
}
