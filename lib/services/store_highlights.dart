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
  /// [products] مرتبة بالاسم زي ما صفحة صاحب المحل بتحمّلها.
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

  /// إعادة حساب الملخص من أصناف المحل (بعد تعديلات المدير أو صفحة المحل).
  /// بيقرا أصناف المحل مرة (لحد 200) — للتعديلات بس، مش للعملاء.
  static Future<void> refresh(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      final storeRef =
          FirebaseFirestore.instance.collection('stores').doc(storeId);
      final snap = await storeRef
          .collection('products')
          .orderBy('name')
          .limit(200)
          .get(const GetOptions(source: Source.server));
      ReadMeter.query('highlights:refresh', snap);
      final h = compute(snap.docs.map((d) => d.data()));
      await storeRef.update({
        'offerItems': h.offers,
        'bestItems': h.best,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Store highlights refresh failed for $storeId: $e');
    }
  }
}
