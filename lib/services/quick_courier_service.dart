import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quick_courier_order.dart';
import 'image_service.dart';
import 'quick_order_api.dart';

/// بيانات تواصل العميل (private/contact): بتظهر للمندوب المعيّن بعد القبول بس.
class QuickContact {
  final String name;
  final String phone;
  final String address;
  final String notes;
  const QuickContact({this.name = '', this.phone = '', this.address = '', this.notes = ''});
}

/// كل اللي شاشات المندوب محتاجاه. الكتابة كلها عن طريق الـWorker؛ القراءة get بس (مفيش مستمعات).
abstract class QuickCourierBackend {
  Future<bool> isQuickEnabled();
  Future<List<QuickCourierOrder>> loadOpen();
  Future<List<QuickCourierOrder>> loadMine();
  Future<QuickCourierOrder?> loadOrder(String id);
  Future<QuickContact?> loadContact(String id);

  /// تنفيذ عملية على الطلب؛ بيرجّع الطلب بعد التعديل من رد الـWorker (من غير قراءة إضافية).
  Future<QuickCourierOrder> act(String id, String action, [Map<String, dynamic> body = const {}]);

  /// تصوير فاتورة ورفعها؛ null لو المندوب لغى.
  Future<String?> captureReceipt(String orderId);
}

class FirebaseQuickCourierBackend implements QuickCourierBackend {
  const FirebaseQuickCourierBackend();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Future<bool> isQuickEnabled() async {
    final uid = _uid;
    if (uid.isEmpty) return false;
    final snap = await _db.collection('couriers').doc(uid).get();
    final data = snap.data();
    if (data == null) return false;
    final active = data['active'];
    return data['quickEnabled'] == true && (active == null || active == true);
  }

  @override
  Future<List<QuickCourierOrder>> loadOpen() async {
    // لازم فلتر الحالة: القواعد بترفض أي قايمة من غيره للمندوب.
    final snap = await _db
        .collection('quick_orders')
        .where('status', isEqualTo: 'open')
        .limit(30)
        .get();
    final list = [for (final d in snap.docs) QuickCourierOrder.fromMap(d.id, d.data())];
    list.sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000)));
    return list;
  }

  @override
  Future<List<QuickCourierOrder>> loadMine() async {
    final uid = _uid;
    if (uid.isEmpty) return const [];
    final snap = await _db
        .collection('quick_orders')
        .where('courierId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    return [for (final d in snap.docs) QuickCourierOrder.fromMap(d.id, d.data())];
  }

  @override
  Future<QuickCourierOrder?> loadOrder(String id) async {
    final snap = await _db.collection('quick_orders').doc(id).get();
    final data = snap.data();
    return data == null ? null : QuickCourierOrder.fromMap(snap.id, data);
  }

  @override
  Future<QuickContact?> loadContact(String id) async {
    final snap = await _db.collection('quick_orders').doc(id).collection('private').doc('contact').get();
    final d = snap.data();
    if (d == null) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    return QuickContact(
      name: s(d['userName']),
      phone: s(d['phone']),
      address: s(d['address']),
      notes: s(d['courierNotes']),
    );
  }

  @override
  Future<QuickCourierOrder> act(String id, String action, [Map<String, dynamic> body = const {}]) async {
    final res = await QuickOrderApi.action(id, action, body);
    final order = res['order'];
    if (order is! Map) throw StateError('رد غير متوقع من الخادم. حدّث الصفحة.');
    return QuickCourierOrder.fromMap(id, Map<String, dynamic>.from(order));
  }

  @override
  Future<String?> captureReceipt(String orderId) => ImageService.pickAndUploadQuickReceipt(orderId);
}
