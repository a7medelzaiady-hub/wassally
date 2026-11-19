import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/product_offer.dart';
import 'read_meter.dart';

/// ملخص العروض والأكثر مبيعًا المحفوظ على مستند المحل (offerItems / bestItems).
/// الرئيسية بتعرض العروض منه من غير ما تقرا أصناف المحلات، فلازم يتحدث بعد أي تعديل صنف.
class StoreHighlights {
  const StoreHighlights._();

  /// أقصى عدد عناصر في كل قائمة (لازم يطابق حد القواعد على مستند المحل: 12).
  static const int maxItems = 12;

  static Map<String, dynamic> _item(Map<String, dynamic> m) => {
        'name': (m['name'] ?? '').toString(),
        'price': (m['price'] as num?) ?? 0,
        if (m['oldPrice'] is num) 'oldPrice': m['oldPrice'],
        if ((m['offerText'] ?? '').toString().trim().isNotEmpty)
          'offerText': (m['offerText'] ?? '').toString().trim(),
        if (m['offerEndsAt'] is Timestamp) 'offerEndsAt': m['offerEndsAt'],
        'image': (m['image'] ?? '').toString(),
      };

  /// العروض (خصم أو نص عرض، غير منتهية) والأكثر مبيعًا من أصناف المحل المتاحة.
  /// [products] مرتبة بالاسم (الأول بالاسم بياخد الأولوية لو العروض أكتر من 12).
  static ({List<Map<String, dynamic>> offers, List<Map<String, dynamic>> best})
      compute(Iterable<Map<String, dynamic>> products, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final offers = <Map<String, dynamic>>[];
    final best = <Map<String, dynamic>>[];
    for (final m in products) {
      if (m['available'] == false || m['isAvailable'] == false) continue;
      final p = (m['price'] as num?) ?? 0;
      final o = m['oldPrice'];
      final e = m['offerEndsAt'];
      final expired = isOfferExpired(e is Timestamp ? e.toDate() : null, at);
      final offerText = (m['offerText'] ?? '').toString().trim();
      final hasPriceDiscount = o is num && o > p;
      if ((hasPriceDiscount || offerText.isNotEmpty) &&
          !expired &&
          offers.length < maxItems) {
        offers.add(_item(m));
      }
      if (m['bestSeller'] == true && best.length < maxItems) {
        best.add(_item(m));
      }
    }
    return (offers: offers, best: best);
  }

  /// المدير: تحديث ملخص العروض لدفعة من المحلات (بالترتيب حسب المعرّف) بعد [startAfterId].
  /// كل محل بيكلف عدد أصنافه المرشحة (عروض/الأكثر مبيعًا) بس، والدفعة 50 محل بالكتير عشان ما نخلصش حصة اليوم مرة واحدة.
  /// بيرجع آخر معرّف اتعالج (للدفعة الجاية) أو null لو خلصوا.
  static Future<({int done, int failed, String? lastId})> refreshBatch({
    String? startAfterId,
    int batchSize = 50,
  }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('stores')
        .orderBy(FieldPath.documentId)
        .limit(batchSize);
    if (startAfterId != null && startAfterId.isNotEmpty) {
      q = q.startAfter([startAfterId]);
    }
    final page = await q.get(const GetOptions(source: Source.server));
    ReadMeter.query('highlights:batch-stores', page);
    var failed = 0;
    for (final d in page.docs) {
      if (!await refresh(d.id)) failed++;
    }
    final lastId = page.docs.length < batchSize || page.docs.isEmpty
        ? null
        : page.docs.last.id;
    return (done: page.docs.length, failed: failed, lastId: lastId);
  }

  /// تنبيه موحّد لما تعديل الصنف يتحفظ لكن الملخص يفشل.
  static const String failedNote =
      'لكن ملخص العروض في الرئيسية ما اتحدثش (مشكلة اتصال)؛ '
      'احفظ أي صنف تاني لما الاتصال يرجع عشان يتحدث.';

  /// بيضيف التنبيه للرسالة لو الملخص فشل.
  static String withNote(String message, bool highlightsOk) =>
      highlightsOk ? message : '$message، $failedNote';

  /// حجم الصفحة لكل استعلام مرشحين، والسقف الكلي لكل استعلام.
  /// الاستعلام بشرط (oldPrice > 0) Firestore بيرتّبه بالحقل ده، فلو وقفنا عند أول صفحة
  /// ممكن عروض شغالة تتقطع لصالح عروض منتهية أو أصناف متوقفة؛ فبنكمّل صفحات لحد السقف.
  static const int candidatePage = 100;
  static const int candidateCap = 500;

  /// بيدمج نتايج الاستعلامات المستهدفة (من غير تكرار) ومرتبة بالاسم زي ترتيب المحل.
  static List<Map<String, dynamic>> mergeCandidates(
    Iterable<Iterable<MapEntry<String, Map<String, dynamic>>>> groups,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final g in groups) {
      for (final e in g) {
        byId.putIfAbsent(e.key, () => e.value);
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .compareTo((b['name'] ?? '').toString()));
    return list;
  }

  /// إعادة حساب الملخص من الخادم بعد أي تعديل صنف (مدير / صفحة المحل / صاحب المحل).
  ///
  /// بدل قراءة أول 200 صنف، بنقرا الأصناف المرشحة بس: اللي عليها خصم، أو نص عرض،
  /// أو الأكثر مبيعًا. فالنتيجة صحيحة مهما كان عدد أصناف المحل، والتكلفة = عدد
  /// المرشحين (أقل حاجة 3 قراءات) بدل 200.
  ///
  /// بيرجع true لو الملخص اتكتب فعلًا. عند الفشل بيعيد المحاولة مرة، وبعدها
  /// بيرجع false من غير ما يرمي استثناء (عشان تعديل الصنف نفسه اتحفظ خلاص)،
  /// والمستدعي لازم يبلغ إن ملخص العروض ما اتحدثش.
  static Future<bool> refresh(String storeId) async {
    if (storeId.isEmpty) return false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _refreshOnce(storeId);
        return true;
      } catch (e) {
        debugPrint('Store highlights refresh failed for $storeId: $e');
      }
    }
    return false;
  }

  static Future<void> _refreshOnce(String storeId) async {
    final storeRef =
        FirebaseFirestore.instance.collection('stores').doc(storeId);
    final col = storeRef.collection('products');
    final groups = await Future.wait([
      _allCandidates(col.where('oldPrice', isGreaterThan: 0)),
      _allCandidates(col.where('offerText', isGreaterThan: '')),
      _allCandidates(col.where('bestSeller', isEqualTo: true)),
    ]);
    final candidates = mergeCandidates(groups);
    final h = compute(candidates);
    await storeRef.update({
      'offerItems': h.offers,
      'bestItems': h.best,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// صفحات من الخادم لحد ما الصفحة تيجي ناقصة أو نوصل [candidateCap].
  static Future<List<MapEntry<String, Map<String, dynamic>>>> _allCandidates(
    Query<Map<String, dynamic>> query,
  ) async {
    const server = GetOptions(source: Source.server);
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    while (out.length < candidateCap) {
      var q = query.limit(candidatePage);
      if (last != null) q = q.startAfterDocument(last);
      final page = await q.get(server);
      ReadMeter.query('highlights:refresh', page);
      out.addAll(page.docs.map((d) => MapEntry(d.id, d.data())));
      if (page.docs.length < candidatePage) break;
      last = page.docs.last;
    }
    return out;
  }
}
