import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// عدّاد تقريبي لقراءات Firestore اللي التطبيق بيجيبها من الخادم، لكل شاشة/خدمة.
/// الغرض: نقيس قبل وبعد كل تحسين (القواعد والـ Worker مش بيتحسبوا هنا).
///
/// القواعد اللي بنعدّ بيها (نفس طريقة فوترة Firestore تقريبًا):
///  • استعلام/مستند جاي من الكاش المحلي = صفر.
///  • استعلام من الخادم = عدد المستندات (وأقل حاجة 1 حتى لو النتيجة فاضية).
///  • مستمع: عدد المستندات اللي اتغيرت في كل لقطة من الخادم (أول لقطة = كلها).
///
/// العدّاد شغال في نسخ التطوير بس (kDebugMode) أو لو اتفعّل يدويًا من الإعدادات.
class ReadMeter {
  ReadMeter._();

  static bool enabled = kDebugMode;

  static final Map<String, int> _counts = {};
  static DateTime _since = DateTime.now();

  static void _add(String label, int reads) {
    if (!enabled || reads <= 0) return;
    _counts[label] = (_counts[label] ?? 0) + reads;
    if (kDebugMode) {
      debugPrint('[ReadMeter] $label +$reads (total ${total()})');
    }
  }

  /// استعلام واحد بـ get().
  static void query(String label, QuerySnapshot<Object?> snap) {
    if (snap.metadata.isFromCache) return;
    _add(label, snap.docs.isEmpty ? 1 : snap.docs.length);
  }

  /// مستند واحد بـ get() أو لقطة مستمع على مستند.
  static void document(String label, DocumentSnapshot<Object?> snap) {
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) return;
    _add(label, 1);
  }

  /// لقطة من مستمع استعلام (snapshots()). أول لقطة من الخادم فيها كل المستندات كـ «added»،
  /// وبعدها التغييرات بس، فعدد docChanges قريب من اللي Firestore بيحاسب عليه.
  /// لقطات تعديلات الجهاز نفسه (hasPendingWrites) مش قراءات من الخادم فما بتتحسبش.
  /// وكل اشتراك في snapshots() بيفتح مستمع منفصل في Firestore، فالعدّ لكل مشترك صح.
  static void listener(String label, QuerySnapshot<Object?> snap) {
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) return;
    _add(label, snap.docChanges.length);
  }

  /// استعلام تجميع (count/sum): أقل حاجة قراءة واحدة.
  static void aggregate(String label) => _add(label, 1);

  static int total() => _counts.values.fold(0, (a, b) => a + b);

  static DateTime get since => _since;

  /// الأكبر استهلاكًا الأول.
  static List<MapEntry<String, int>> snapshot() {
    final list = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  static void reset() {
    _counts.clear();
    _since = DateTime.now();
  }
}

/// بيعدّ لقطات مستمع استعلام من غير ما يغيّر البيانات.
extension ReadMeterQueryStream<T> on Stream<QuerySnapshot<T>> {
  Stream<QuerySnapshot<T>> metered(String label) {
    return map((snap) {
      ReadMeter.listener(label, snap);
      return snap;
    });
  }
}

/// بيعدّ لقطات مستمع مستند.
extension ReadMeterDocStream<T> on Stream<DocumentSnapshot<T>> {
  Stream<DocumentSnapshot<T>> metered(String label) {
    return map((snap) {
      ReadMeter.document(label, snap);
      return snap;
    });
  }
}
