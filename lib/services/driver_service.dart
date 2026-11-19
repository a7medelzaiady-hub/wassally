import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'catalog_sync.dart';
import 'read_meter.dart';

class DriverService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// تقييم المندوب على طلب اتسلّم. بيكتب في batch واحد:
  /// 1) reviews/{orderId}_courier  2) إحصائية المندوب (ratingSum/ratingCount) في couriers.
  /// قواعد Firestore بتربط الاتنين ببعض، والطلب الواحد بيتقيّم مرة واحدة بس.
  static Future<void> rateDriver({
    required String orderId,
    required String driverId,
    required double rating,
    String? comment,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    final stars = rating.round().clamp(1, 5);
    final reviewId = '${orderId}_courier';
    var text = (comment ?? '').trim();
    if (text.length > 300) text = text.substring(0, 300);

    final batch = _db.batch();
    batch.set(_db.collection('reviews').doc(reviewId), {
      'orderId': orderId,
      'courierId': driverId,
      'userId': user.uid,
      'rating': stars,
      'comment': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('couriers').doc(driverId), {
      'ratingSum': FieldValue.increment(stars),
      'ratingCount': FieldValue.increment(1),
      'lastReviewId': reviewId,
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('الطلب ده اتقيّم قبل كده أو لسه ما اتسلّمش.');
      }
      throw StateError('مقدرناش نسجّل التقييم، حاول تاني.');
    }
  }
}

/// ملخص تقييم (متوسط + عدد).
class RatingSummary {
  final double avg;
  final int count;
  const RatingSummary(this.avg, this.count);

  /// من ratingSum/ratingCount المحفوظين على مستند المحل (بيتحدثوا مع كل تقييم).
  factory RatingSummary.fromStore(Map<String, dynamic>? store) {
    final sum = (store?['ratingSum'] as num?)?.toDouble() ?? 0;
    final n = (store?['ratingCount'] as num?)?.toInt() ?? 0;
    return RatingSummary(n <= 0 ? 0 : sum / n, n < 0 ? 0 : n);
  }
  String get text => count == 0
      ? 'لسه مفيش تقييمات'
      : '${avg.toStringAsFixed(1)} من 5 · $count تقييم';
}

class RatingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// تقييم مندوب (من إحصائيته في couriers). مسموح للمندوب نفسه وللمدير.
  static Future<RatingSummary?> courier(String courierId) async {
    try {
      final d = await _db.collection('couriers').doc(courierId).get();
      final m = d.data();
      if (m == null) return null;
      final sum = (m['ratingSum'] as num?)?.toDouble() ?? 0;
      final n = (m['ratingCount'] as num?)?.toInt() ?? 0;
      return RatingSummary(n == 0 ? 0 : sum / n, n);
    } catch (_) {
      return null;
    }
  }

  /// تقييم محل من ratingSum/ratingCount على مستند المحل: قراءة واحدة بدل لحد 300 تقييم.
  static Future<RatingSummary?> store(String storeId) async {
    try {
      final d = await _db.collection('stores').doc(storeId).get();
      ReadMeter.document('rating:store', d);
      return RatingSummary.fromStore(d.data());
    } catch (_) {
      return null;
    }
  }

  /// تقييم العميل للمحل بعد التسليم (مرة واحدة لكل طلب).
  static Future<void> rateStore({
    required String orderId,
    required String storeId,
    required double rating,
    String? comment,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    var text = (comment ?? '').trim();
    if (text.length > 300) text = text.substring(0, 300);
    final stars = rating.round().clamp(1, 5);
    final reviewId = '${orderId}_store';
    final batch = _db.batch();
    batch.set(_db.collection('reviews').doc(reviewId), {
      'orderId': orderId,
      'storeId': storeId,
      'userId': user.uid,
      'rating': stars,
      'comment': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('stores').doc(storeId), {
      'ratingSum': FieldValue.increment(stars),
      'ratingCount': FieldValue.increment(1),
      'lastReviewId': reviewId,
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('المحل ده اتقيّم قبل كده أو الطلب لسه ما اتسلّمش.');
      }
      throw StateError('مقدرناش نسجّل تقييم المحل، حاول تاني.');
    }
    // التقييم اتسجل: نحدّث أرقامه في فهرس المحلات (أفضل محاولة، من غير رفع رقم الإصدار).
    await CatalogSync.syncRating(storeId);
  }
}
