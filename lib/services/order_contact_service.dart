import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// ترجع null فقط لو المستند غير موجود.
  /// أخطاء الصلاحيات/الشبكة تخرج للواجهة كي تعرض السبب وتتيح إعادة المحاولة.
  static Future<OrderContact?> load(
    String orderId, {
    GetOptions? options,
  }) async {
    final snap = await ref(orderId).get(options);
    final data = snap.data();
    return data == null ? null : OrderContact.fromMap(data);
  }
}
