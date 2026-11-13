import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// بيانات العميل الشخصية في الطلب (الاسم الكامل، الموبايل، العنوان).
///
/// متخزّنة في مستند منفصل `orders/{id}/private/contact` عشان قواعد الأمان تتحكم فيه:
///   • العميل صاحب الطلب والمدير: دايمًا.
///   • المندوب: بس لو الطلب متكلّف بيه وحالته لسه جاري (preparing / on_the_way).
///   • صاحب المحل والمناديب التانيين: مفيش وصول خالص.
class OrderContact {
  final String name;
  final String phone;
  final String address;

  /// ملاحظات للمندوب فقط (الدور، علامة مميزة...). المحل مش بيشوفها.
  final String courierNotes;
  const OrderContact({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.courierNotes = '',
  });

  factory OrderContact.fromMap(Map<String, dynamic> m) => OrderContact(
    name: (m['userName'] ?? '').toString(),
    phone: (m['phone'] ?? '').toString(),
    address: (m['address'] ?? '').toString(),
    courierNotes: (m['courierNotes'] ?? '').toString(),
  );

  bool get isEmpty =>
      name.isEmpty && phone.isEmpty && address.isEmpty && courierNotes.isEmpty;
}

class OrderContactService {
  const OrderContactService._();

  static DocumentReference<Map<String, dynamic>> ref(String orderId) =>
      FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('private')
          .doc('contact');

  /// بترجع null لو مفيش مستند أو الصلاحية مش متاحة (مثلًا الطلب اتسلّم).
  static Future<OrderContact?> load(String orderId) async {
    try {
      final snap = await ref(orderId).get();
      final data = snap.data();
      return data == null ? null : OrderContact.fromMap(data);
    } catch (e) {
      debugPrint('Order contact unavailable: $e');
      return null;
    }
  }
}
