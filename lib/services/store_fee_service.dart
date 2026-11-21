import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';

/// رصيد رسوم خدمة وصّلي على محل.
class StoreFeeSummary {
  /// مجموع رسوم الخدمة على الطلبات المسلّمة (بالقروش).
  final int dueMinor;

  /// اللي المحل دفعه لوصّلي وسجّلته الإدارة (بالقروش).
  final int paidMinor;

  /// وقت آخر «تقفيل حساب» من الإدارة (null = لسه ما اتقفلش). الطلبات اللي قبله بتختفي من صفحة المحل.
  final DateTime? settledAt;

  const StoreFeeSummary({
    required this.dueMinor,
    required this.paidMinor,
    this.settledAt,
  });

  int get outstandingMinor => dueMinor - paidMinor;
  double get due => dueMinor / 100;
  double get paid => paidMinor / 100;
  double get outstanding => outstandingMinor / 100;
}

/// رسوم الخدمة: العميل بيدفعها كاش ضمن الإجمالي، فالمحل بيبقى ماسكها ومستحقة عليه.
/// المستحق بيتحسب بـ aggregate واحد (قراءة لكل 1000 طلب)، والمدفوع من مستند رصيد واحد.
class StoreFeeService {
  const StoreFeeService._();

  static final _db = FirebaseFirestore.instance;

  static Future<StoreFeeSummary> load(String storeId) async {
    final results = await Future.wait<Object>([
      _db
          .collection('orders')
          .where('storeId', isEqualTo: storeId)
          .where('status', isEqualTo: OrderStatus.delivered.key)
          .aggregate(sum('serviceFee'))
          .get(),
      _db.collection('store_fee_balances').doc(storeId).get(),
    ]);
    final agg = results[0] as AggregateQuerySnapshot;
    final bal = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final due = (agg.getSum('serviceFee') as num?)?.toDouble() ?? 0;
    return StoreFeeSummary(
      dueMinor: (due * 100).round(),
      paidMinor: (bal.data()?['paidAmountMinor'] as num?)?.toInt() ?? 0,
      settledAt: bal.data()?['settledAt'] is Timestamp
          ? (bal.data()!['settledAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// بيرجع رسالة خطأ لو المبلغ مش مقبول، أو null.
  static String? validatePayment(double amount, StoreFeeSummary s) {
    if (!amount.isFinite || amount <= 0 || amount > 1000000) return 'اكتب مبلغ صحيح.';
    if ((amount * 100 - (amount * 100).round()).abs() > 0.000001) return 'المبلغ لحد قرشين بس.';
    if ((amount * 100).round() > s.outstandingMinor) {
      return 'المبلغ أكبر من المتبقي (${s.outstanding.toStringAsFixed(2)} جنيه).';
    }
    return null;
  }

  /// للأدمن: تسجيل دفعة من المحل. مستند الدفعة + تحديث الرصيد في معاملة واحدة.
  static Future<void> recordPayment({
    required String storeId,
    required double amount,
    String note = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final summary = await load(storeId);
    final err = validatePayment(amount, summary);
    if (err != null) throw StateError(err);
    final cleanNote = note.trim();
    if (cleanNote.length > 200) throw StateError('الملاحظة أطول من المسموح.');
    final amountMinor = (amount * 100).round();
    final balanceRef = _db.collection('store_fee_balances').doc(storeId);
    final paymentRef = _db.collection('store_fee_payments').doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(balanceRef);
      final paid = (snap.data()?['paidAmountMinor'] as num?)?.toInt() ?? 0;
      if (paid + amountMinor > summary.dueMinor) {
        throw StateError('الرصيد اتغير. حدّث البيانات وحاول تاني.');
      }
      tx.set(paymentRef, {
        'storeId': storeId,
        'amount': amount,
        'amountMinor': amountMinor,
        'note': cleanNote,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(balanceRef, {
        'storeId': storeId,
        'paidAmountMinor': paid + amountMinor,
        'lastPaymentId': paymentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
