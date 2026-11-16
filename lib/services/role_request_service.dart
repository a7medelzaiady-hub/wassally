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
    return _col.where('userId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(50).snapshots().map((s) => s.docs);
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
    String storeImageUrl = '',
    String registrationNumber = '',
    String proofUrl = '',
    String storePhone = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    final db = FirebaseFirestore.instance;
    final requestRef = _col.doc('${user.uid}_${type.key}');
    final requestSnapshot = await requestRef.get();
    final previous = requestSnapshot.data();
    final previousStatus = (previous?['status'] ?? '').toString();
    if (previousStatus == 'pending' || previousStatus == 'approved') {
      throw StateError('عندك طلب انضمام قائم بالفعل.');
    }

    final requestData = <String, dynamic>{
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'type': type.key,
      'name': name.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (type == JoinType.storeOwner && storePhone.trim().isNotEmpty)
        'storePhone': storePhone.trim(),
      if (type == JoinType.storeOwner) 'storeName': storeName.trim(),
      if (type == JoinType.storeOwner) 'storeCategory': storeCategory.trim(),
      if (type == JoinType.storeOwner) 'address': address.trim(),
      if (type == JoinType.storeOwner) 'storeImageUrl': storeImageUrl.trim(),
      if (type == JoinType.storeOwner && registrationNumber.trim().isNotEmpty)
        'registrationNumber': registrationNumber.trim(),
      if (type == JoinType.storeOwner && proofUrl.trim().isNotEmpty)
        'proofUrl': proofUrl.trim(),
      if (type == JoinType.courier) 'vehicle': vehicle.trim(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (type == JoinType.storeOwner) {
      var storeId = (previous?['storeId'] ?? '').toString();
      DocumentReference<Map<String, dynamic>> storeRef = storeId.isEmpty
          ? db.collection('stores').doc()
          : db.collection('stores').doc(storeId);
      DocumentSnapshot<Map<String, dynamic>>? previousStore;
      if (storeId.isNotEmpty) {
        previousStore = await storeRef.get();
        if (!previousStore.exists ||
            previousStore.data()?['ownerUid'] != user.uid) {
          storeRef = db.collection('stores').doc();
          previousStore = null;
        }
      }
      storeId = storeRef.id;
      requestData['storeId'] = storeId;

      final batch = db.batch();
      final previousCount = previousStore?.data()?['productCount'];
      final storeData = <String, dynamic>{
        'name': storeName.trim(),
        'category': storeCategory.trim(),
        'address': address.trim(),
        'ownerUid': user.uid,
        'active': false,
        'approved': false,
        'time': '',
        'image': storeImageUrl.trim(),
        'imageUrl': storeImageUrl.trim(),
        'storePhone': storePhone.trim(),
        'productCount': previousCount is num ? previousCount.toInt() : 0,
        if (previousStore == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (previousStore?.exists == true) {
        batch.update(storeRef, storeData);
      } else {
        batch.set(storeRef, storeData);
      }
      batch.set(requestRef, requestData);
      await batch.commit();
      return;
    }

    await requestRef.set(requestData);
  }

  /// طلبات الانضمام المعلقة للأدمن.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPending() =>
      _col.where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).limit(100).snapshots();

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
      final draftId = (m['storeId'] ?? '').toString();
      if (draftId.isNotEmpty) {
        final storeRef = db.collection('stores').doc(draftId);
        final storeSnapshot = await storeRef.get();
        if (!storeSnapshot.exists ||
            storeSnapshot.data()?['ownerUid'] != uid) {
          throw StateError('مسودة المحل غير موجودة أو لا تخص صاحب الطلب.');
        }
        final products = await storeRef.collection('products').count().get();
        final storeData = storeSnapshot.data() ?? {};
        final imageUrl = (storeData['imageUrl'] ?? storeData['image'] ?? '').toString();
        final readyToPublish = (products.count ?? 0) >= 5 &&
            imageUrl.startsWith('https://');
        batch.update(storeRef, {
          'approved': true,
          'active': readyToPublish,
          'ownerUid': FieldValue.delete(),
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': admin,
        });
        storeId = draftId;
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
            'active': false,
            'approved': true,
            'time': '',
            'image': (m['storeImageUrl'] ?? '').toString(),
            'imageUrl': (m['storeImageUrl'] ?? '').toString(),
            'storePhone': (m['storePhone'] ?? '').toString(),
            'productCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'approvedAt': FieldValue.serverTimestamp(),
            'approvedBy': admin,
          });
          storeId = storeRef.id;
        } else if ((m['storePhone'] ?? '').toString().isNotEmpty) {
          batch.update(db.collection('stores').doc(storeId), {
            'storePhone': (m['storePhone'] ?? '').toString(),
            'approved': true,
          });
        }
      }
      batch.set(db.collection('storeOwners').doc(uid), {
        'name': (m['name'] ?? '').toString(),
        if ((m['phone'] ?? '').toString().isNotEmpty)
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
    required String note,
  }) {
    final cleanNote = note.trim();
    if (cleanNote.length < 5 || cleanNote.length > 300) {
      throw ArgumentError('سبب الرفض يجب أن يكون من 5 إلى 300 حرف.');
    }
    final admin = FirebaseAuth.instance.currentUser?.uid;
    if (admin == null) throw StateError('سجّل دخول الأول.');
    return req.reference.update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': admin,
      'adminNote': cleanNote,
    });
  }
}
