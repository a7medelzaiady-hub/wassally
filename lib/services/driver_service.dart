import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// تقييم محل: متوسط آخر 300 تقييم من reviews. مسموح لصاحب المحل وللمدير.
  static Future<RatingSummary?> store(String storeId) async {
    try {
      final snap = await _db
          .collection('reviews')
          .where('storeId', isEqualTo: storeId)
          .limit(300)
          .get();
      var sum = 0.0;
      for (final d in snap.docs) {
        sum += (d.data()['rating'] as num?)?.toDouble() ?? 0;
      }
      final n = snap.docs.length;
      return RatingSummary(n == 0 ? 0 : sum / n, n);
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
  }
}
