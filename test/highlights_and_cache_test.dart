import 'package:city_store/services/catalog_cache_policy.dart';
import 'package:city_store/services/store_highlights.dart';
import 'package:flutter_test/flutter_test.dart';

/// يحاكي المحل كخريطة معرّف → بيانات، ويحسب الملخص بنفس طريق refresh():
/// المرشحين = اللي عليهم خصم أو نص عرض أو الأكثر مبيعًا، مدموجين ومرتبين بالاسم.
List<String> offersOf(Map<String, Map<String, dynamic>> store, DateTime now) {
  Iterable<MapEntry<String, Map<String, dynamic>>> where(
    bool Function(Map<String, dynamic>) f,
  ) =>
      store.entries.where((e) => f(e.value));
  final candidates = StoreHighlights.mergeCandidates([
    where((m) => m['oldPrice'] is num && (m['oldPrice'] as num) > 0),
    where((m) => (m['offerText'] ?? '').toString().isNotEmpty),
    where((m) => m['bestSeller'] == true),
  ]);
  return StoreHighlights.compute(candidates, now: now)
      .offers
      .map((m) => '${m['name']}@${m['price']}')
      .toList();
}

void main() {
  final now = DateTime(2026, 11, 19, 12);

  group('ملخص العروض بعد كل نوع تعديل', () {
    late Map<String, Map<String, dynamic>> store;
    setUp(() {
      store = {
        'a': {'name': 'عصير', 'price': 10},
        'b': {'name': 'بيتزا', 'price': 80},
      };
    });

    test('إضافة صنف عليه عرض يظهر', () {
      store['c'] = {'name': 'كنافة', 'price': 40, 'oldPrice': 50};
      expect(offersOf(store, now), ['كنافة@40']);
    });

    test('تعديل سعر العرض يظهر بالسعر الجديد', () {
      store['a'] = {'name': 'عصير', 'price': 8, 'oldPrice': 10};
      expect(offersOf(store, now), ['عصير@8']);
      store['a'] = {'name': 'عصير', 'price': 7, 'oldPrice': 10};
      expect(offersOf(store, now), ['عصير@7']);
    });

    test('إلغاء العرض أو حذف الصنف أو تعطيله يخفيه', () {
      store['a'] = {'name': 'عصير', 'price': 8, 'oldPrice': 10};
      store['b'] = {'name': 'بيتزا', 'price': 70, 'offerText': '1+1'};
      expect(offersOf(store, now).length, 2);

      store['a'] = {'name': 'عصير', 'price': 10}; // إلغاء
      expect(offersOf(store, now), ['بيتزا@70']);

      store['b'] = {...store['b']!, 'available': false}; // تعطيل
      expect(offersOf(store, now), isEmpty);

      store.remove('b'); // حذف
      expect(offersOf(store, now), isEmpty);
    });

    test('محل فيه أكتر من 200 صنف: عرض على الصنف رقم 500 مايضيعش', () {
      for (var i = 0; i < 600; i++) {
        store['p$i'] = {'name': 'صنف ${i.toString().padLeft(3, '0')}', 'price': 5};
      }
      store['p500'] = {'name': 'صنف 500', 'price': 4, 'oldPrice': 5};
      expect(offersOf(store, now), ['صنف 500@4']);
    });

    test('الدمج بيشيل التكرار (صنف عليه خصم ونص عرض وأكثر مبيعًا)', () {
      final m = {'name': 'x', 'price': 1, 'oldPrice': 2, 'offerText': 't', 'bestSeller': true};
      final merged = StoreHighlights.mergeCandidates([
        [MapEntry('x', m)],
        [MapEntry('x', m)],
        [MapEntry('x', m)],
      ]);
      expect(merged.length, 1);
    });

    test('رسالة الفشل بتوضح إن الصنف اتحفظ والملخص لأ', () {
      expect(StoreHighlights.withNote('تم حفظ الصنف', true), 'تم حفظ الصنف');
      final failed = StoreHighlights.withNote('تم حفظ الصنف', false);
      expect(failed, startsWith('تم حفظ الصنف'));
      expect(failed, contains(StoreHighlights.failedNote));
    });
  });

  group('CatalogCachePolicy (قبول الكاش)', () {
    final server = ['s1', 's2', 's3'];
    final recorded = CatalogCachePolicy.fingerprint(server);

    test('نفس المعرفات (بأي ترتيب) = كاش مقبول', () {
      expect(
        CatalogCachePolicy.cacheIsComplete(
            recorded: recorded, cachedIds: ['s3', 's1', 's2']),
        isTrue,
      );
    });

    test('مستند اتشال من الكاش = نرجع للخادم', () {
      expect(
        CatalogCachePolicy.cacheIsComplete(
            recorded: recorded, cachedIds: ['s1', 's2']),
        isFalse,
      );
    });

    test('نفس العدد بمعرفات مختلفة (حذف + إضافة) = نرجع للخادم', () {
      expect(
        CatalogCachePolicy.cacheIsComplete(
            recorded: recorded, cachedIds: ['s1', 's2', 'old']),
        isFalse,
      );
    });

    test('مستند قديم زيادة في الكاش = نرجع للخادم', () {
      expect(
        CatalogCachePolicy.cacheIsComplete(
            recorded: recorded, cachedIds: [...server, 'stale']),
        isFalse,
      );
    });

    test('نتيجة فاضية متسجلة: الكاش الفاضي مقبول (مفيش قراءة كل مرة)', () {
      final empty = CatalogCachePolicy.fingerprint(const []);
      expect(
        CatalogCachePolicy.cacheIsComplete(recorded: empty, cachedIds: const []),
        isTrue,
      );
    });

    test('مفتاح ما اتجابش بالإصدار ده (أو الإصدار اتغيّر واتمسح) = خادم', () {
      expect(
        CatalogCachePolicy.cacheIsComplete(recorded: null, cachedIds: server),
        isFalse,
      );
      expect(
        CatalogCachePolicy.cacheIsComplete(recorded: '', cachedIds: const []),
        isFalse,
      );
    });

    test('إعادة فتح التطبيق: الحفظ والقراية بيرجعوا نفس البصمة', () {
      final keys = {'stores/active': recorded, 'menu|odd': '0:811c9dc5'};
      final decoded = CatalogCachePolicy.decode(CatalogCachePolicy.encode(keys));
      expect(decoded, keys);
      expect(CatalogCachePolicy.fingerprint(server), recorded); // ثابتة
    });

    test('الصيغة القديمة (مفتاح|عدد) ما بتطابقش أي بصمة', () {
      final old = CatalogCachePolicy.decode(['stores/active|3']);
      expect(
        CatalogCachePolicy.cacheIsComplete(
            recorded: old['stores/active'], cachedIds: server),
        isFalse,
      );
    });

    test('المعرفات المتجاورة ما بتتلخبطش (ab,c ≠ a,bc)', () {
      expect(
        CatalogCachePolicy.fingerprint(['ab', 'c']),
        isNot(CatalogCachePolicy.fingerprint(['a', 'bc'])),
      );
    });
  });
}
