import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/order.dart';

/// طرق الدفع المدعومة. القيم لازم تطابق firestore.rules و Worker.
enum PaymentMethod {
  cash('cash', 'الدفع عند الاستلام'),
  vodafoneCash('vodafone_cash', 'فودافون كاش'),
  instapay('instapay', 'InstaPay');

  const PaymentMethod(this.key, this.label);

  final String key;
  final String label;

  static PaymentMethod parse(String? key) => PaymentMethod.values.firstWhere(
        (m) => m.key == key,
        orElse: () => PaymentMethod.cash,
      );

  static String labelOf(String key) => parse(key).label;
}

/// إعدادات الدفع اللي الإدارة بتحددها (app_info/payment).
class PaymentSettings {
  const PaymentSettings({
    this.enabled = false,
    this.vodafoneCashNumber = '',
    this.instapayAddress = '',
    this.note = '',
  });

  final bool enabled;
  final String vodafoneCashNumber;
  final String instapayAddress;
  final String note;

  factory PaymentSettings.fromMap(Map<String, dynamic>? m) => PaymentSettings(
        enabled: m?['enabled'] == true,
        vodafoneCashNumber: (m?['vodafoneCashNumber'] ?? '').toString().trim(),
        instapayAddress: (m?['instapayAddress'] ?? '').toString().trim(),
        note: (m?['note'] ?? '').toString().trim(),
      );

  /// الرقم/العنوان اللي العميل يحوّل عليه للطريقة دي (فاضي = الطريقة مش متاحة).
  String destinationFor(PaymentMethod method) => switch (method) {
        PaymentMethod.vodafoneCash => vodafoneCashNumber,
        PaymentMethod.instapay => instapayAddress,
        PaymentMethod.cash => '',
      };

  /// الطرق المتاحة للعميل دلوقتي. الكاش متاح دايمًا.
  List<PaymentMethod> get available => [
        PaymentMethod.cash,
        if (enabled && vodafoneCashNumber.isNotEmpty) PaymentMethod.vodafoneCash,
        if (enabled && instapayAddress.isNotEmpty) PaymentMethod.instapay,
      ];
}

class PaymentService {
  const PaymentService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _db.collection('app_info').doc('payment');

  /// رقم العملية بعد التوحيد: حروف إنجليزي كبيرة وأرقام بس (نفس تحقق القواعد).
  static String normalizeRef(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  static bool isValidRef(String normalized) =>
      RegExp(r'^[A-Z0-9]{4,40}$').hasMatch(normalized);

  static Future<PaymentSettings>? _cached;

  /// قراءة واحدة للإعدادات في الجلسة (صفحة الدفع بتفتحها).
  static Future<PaymentSettings> settings({bool refresh = false}) {
    if (refresh) _cached = null;
    return _cached ??= _load();
  }

  static Future<PaymentSettings> _load() async {
    try {
      final snap = await _settingsRef.get();
      return PaymentSettings.fromMap(snap.data());
    } catch (e) {
      debugPrint('Payment settings unavailable: $e');
      _cached = null;
      // لو مقدرناش نقرأ الإعدادات: كاش بس، وده الآمن.
      return const PaymentSettings();
    }
  }

  /// المدير: حفظ إعدادات المحافظ.
  static Future<void> saveSettings(PaymentSettings s) async {
    await _settingsRef.set({
      'enabled': s.enabled,
      'vodafoneCashNumber': s.vodafoneCashNumber.trim(),
      'instapayAddress': s.instapayAddress.trim(),
      'note': s.note.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _cached = null;
  }

  /// المدير: الطلبات اللي تحويلها مستني تأكيد (استعلام واحد بحد 50).
  static Stream<List<AppOrder>> watchPending() => _db
      .collection('orders')
      .where('paymentStatus', isEqualTo: 'pending')
      .limit(50)
      .snapshots()
      .map((snap) {
        final list = [
          for (final d in snap.docs) AppOrder.fromMap(d.id, d.data()),
        ]..removeWhere((o) => o.status != OrderStatus.newOrder);
        list.sort((a, b) {
          final aMs = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bMs = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return aMs.compareTo(bMs);
        });
        return list;
      });

  /// المدير: تأكيد التحويل. بعده المحل يقدر يبدأ يجهّز الطلب.
  static Future<void> confirm(AppOrder order) async {
    final admin = FirebaseAuth.instance.currentUser?.uid;
    if (admin == null) throw StateError('سجّل دخول الأول.');
    final batch = _db.batch()
      ..update(_db.collection('orders').doc(order.id), {
        'paymentStatus': 'confirmed',
        'paymentDecidedAt': FieldValue.serverTimestamp(),
        'paymentDecidedBy': admin,
      })
      ..set(_db.collection('notifications').doc(), {
        'userId': order.userId,
        'title': 'تم تأكيد الدفع',
        'body': 'استلمنا تحويلك (${PaymentMethod.labelOf(order.paymentMethod)}) وطلبك هيبدأ يتجهز.',
        'orderId': order.id,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await _commit(batch);
  }

  /// المدير: رفض التحويل بسبب واضح (5–200 حرف). الطلب بيفضل جديد والعميل يقدر يلغيه.
  static Future<void> reject(AppOrder order, String reason) async {
    final admin = FirebaseAuth.instance.currentUser?.uid;
    if (admin == null) throw StateError('سجّل دخول الأول.');
    final clean = reason.trim();
    if (clean.length < 5 || clean.length > 200) {
      throw StateError('اكتب سبب الرفض (من 5 لـ 200 حرف).');
    }
    final batch = _db.batch()
      ..update(_db.collection('orders').doc(order.id), {
        'paymentStatus': 'rejected',
        'paymentDecidedAt': FieldValue.serverTimestamp(),
        'paymentDecidedBy': admin,
        'paymentRejectReason': clean,
      })
      ..set(_db.collection('notifications').doc(), {
        'userId': order.userId,
        'title': 'مشكلة في التحويل',
        'body': clean.length > 200 ? clean.substring(0, 200) : clean,
        'orderId': order.id,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    await _commit(batch);
  }

  static Future<void> _commit(WriteBatch batch) async {
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('القرار اتاخد قبل كده أو الطلب اتغيرت حالته.');
      }
      throw StateError('تعذر الحفظ (${e.code}).');
    }
  }
}
