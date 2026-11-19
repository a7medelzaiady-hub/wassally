import 'package:city_store/services/catalog_menu_sync.dart';
import 'package:city_store/services/catalog_sync.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogSync.highlightsFrom', () {
    test('picks discounted and text offers, skips unavailable and expired ones', () {
      final past = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)));
      final future = Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));
      final h = CatalogSync.highlightsFrom([
        {'name': 'b-discount', 'price': 8, 'oldPrice': 10, 'image': 'x'},
        {'name': 'a-text', 'price': 5, 'offerText': '1+1', 'offerEndsAt': future},
        {'name': 'c-expired', 'price': 5, 'oldPrice': 9, 'offerEndsAt': past},
        {'name': 'd-off', 'price': 5, 'oldPrice': 9, 'available': false},
        {'name': 'e-plain', 'price': 5},
        {'name': 'f-best', 'price': 7, 'bestSeller': true},
        {'name': 'g-best-off', 'price': 7, 'bestSeller': true, 'isAvailable': false},
      ]);
      expect(h.offers.map((m) => m['name']), ['a-text', 'b-discount']);
      expect(h.best.map((m) => m['name']), ['f-best']);
      expect(h.offers.last['oldPrice'], 10);
      expect(h.offers.first['offerText'], '1+1');
    });

    test('caps offers and best sellers at 12 each', () {
      final many = [
        for (var i = 0; i < 30; i++)
          {'name': 'p${i.toString().padLeft(2, '0')}', 'price': 5, 'oldPrice': 9, 'bestSeller': true},
      ];
      final h = CatalogSync.highlightsFrom(many);
      expect(h.offers.length, 12);
      expect(h.best.length, 12);
    });
  });

  group('CatalogSync.indexEntry', () {
    test('keeps only display fields (matching the rules) and packs a few highlights into "hl"', () {
      final ends = Timestamp.fromMillisecondsSinceEpoch(1763550000123);
      final store = <String, dynamic>{
        'name': 'S',
        'category': 'مطاعم',
        'active': true,
        'image': 'https://img',
        'ownerUid': 'u1',
        'approvedBy': 'admin',
        'lastReviewId': 'r1',
        'ratingSum': 9,
        'ratingCount': 2,
        'offerItems': List.generate(
          10,
          (i) => {
            'name': 'o$i',
            'price': 5,
            'oldPrice': 7,
            'offerText': 'خصم',
            'offerEndsAt': ends,
            'image': 'x',
            'junk': true,
          },
        ),
        'bestItems': [
          {'name': 'b', 'price': 3},
        ],
      };
      final entry = CatalogSync.indexEntry(store);
      expect(entry.keys.toSet().difference(CatalogSync.indexKeys.toSet()), isEmpty);
      expect(entry['name'], 'S');
      expect(entry['imageUrl'], 'https://img');
      expect(entry.containsKey('image'), isFalse);
      expect(entry.containsKey('ownerUid'), isFalse);
      expect(entry.containsKey('offerItems'), isFalse);
      expect(entry['ratingSum'], 9);
      expect((entry['hl'] as String).length, lessThanOrEqualTo(CatalogSync.maxHighlightsChars));

      // القراءة عند العميل بترجّع نفس شكل مستند المحل.
      final decoded = CatalogSync.decodeIndexEntry(entry);
      expect(decoded.containsKey('hl'), isFalse);
      final offers = decoded['offerItems'] as List;
      expect(offers.length, CatalogSync.indexOffersCap);
      final first = offers.first as Map;
      expect(first['name'], 'o0');
      expect(first['oldPrice'], 7);
      expect(first['offerText'], 'خصم');
      expect(first['offerEndsAt'], ends);
      expect(first.containsKey('junk'), isFalse);
      expect((decoded['bestItems'] as List).single['name'], 'b');
      // الأصل ما يتغيرش.
      expect((store['offerItems'] as List).length, 10);
    });

    test('prefers imageUrl over image and omits absent fields', () {
      final entry = CatalogSync.indexEntry({
        'name': 'S',
        'active': true,
        'imageUrl': 'https://new',
        'image': 'https://old',
      });
      expect(entry['imageUrl'], 'https://new');
      expect(entry.containsKey('hl'), isFalse);
      expect(entry.containsKey('rating'), isFalse);
      expect(CatalogSync.decodeIndexEntry(entry).containsKey('offerItems'), isFalse);
    });
  });

  group('CatalogSync.canonical (هل الملخص اتغير فعلًا؟)', () {
    test('ترتيب المفاتيح وصيغة الأرقام ما بيفرقوش', () {
      final a = [
        {'name': 'x', 'price': 5, 'image': 'i'},
      ];
      final b = [
        {'image': 'i', 'price': 5.0, 'name': 'x'},
      ];
      expect(CatalogSync.canonical(a), CatalogSync.canonical(b));
      expect(
        CatalogSync.canonical([{'name': 'x', 'price': 6}]),
        isNot(CatalogSync.canonical(a)),
      );
      expect(CatalogSync.canonical(null), isNot(CatalogSync.canonical(const [])));
    });
  });

  test('indexRoomFor: محل موجود دايمًا ليه مكان، والجديد بس لو العدد أقل من الحد', () {
    final full = {
      for (var i = 0; i < CatalogSync.maxIndexStores; i++) 's_x$i': <String, dynamic>{},
      'updatedAt': 1,
    };
    expect(CatalogSync.indexRoomFor(null, 'new'), isTrue);
    expect(CatalogSync.indexRoomFor(full, 'x3'), isTrue);
    expect(CatalogSync.indexRoomFor(full, 'new'), isFalse);
    full.remove('s_x0');
    expect(CatalogSync.indexRoomFor(full, 'new'), isTrue);
  });

  test('nextVersion never repeats a number after a disable (must match the rules)', () {
    expect(MenuSync.nextVersion(null), 1);
    expect(MenuSync.nextVersion(0), 1);
    expect(MenuSync.nextVersion(-2), 3);
    expect(MenuSync.nextVersion(-7), 8);
    expect(MenuSync.nextVersion(4), 5);
  });

  test('estimateBytes grows with content', () {
    final small = CatalogSync.estimateBytes({'p1': {'name': 'a'}});
    final big = CatalogSync.estimateBytes({'p1': {'name': 'ب' * 1000}});
    expect(big, greaterThan(small + 1000));
  });

  test('CatalogDoc mirrors id and data()', () {
    const doc = CatalogDoc('shop1', {'name': 'S'});
    expect(doc.id, 'shop1');
    expect(doc.data()['name'], 'S');
  });

  group('حدود الحجم (200 محل × 200 صنف ببيانات حقيقية)', () {
    final ts = Timestamp.fromMillisecondsSinceEpoch(1763550000123);
    const img =
        'https://res.cloudinary.com/wasally/image/upload/v1763550000/products/shop_000/abcdefghij1234567890.jpg';

    Map<String, dynamic> product(int i, {int desc = 150, int groups = 3, int options = 4}) => {
          'name': 'ساندوتش فراخ كريسبي سبايسي ${i.toString().padLeft(3, '0')}',
          'price': 85.5,
          'oldPrice': 95.0,
          'image': img,
          'description': 'و' * desc,
          'optionGroups': [
            for (var g = 0; g < groups; g++)
              {
                'title': 'الإضافات المتاحة',
                'min': 0,
                'max': 3,
                'options': [
                  for (var o = 0; o < options; o++) {'name': 'جبنة شيدر زيادة', 'price': 10.0},
                ],
              },
          ],
          'bestSeller': false,
          'isAvailable': true,
          'available': true,
          'createdAt': ts,
          'updatedAt': ts,
        };

    Map<String, Map<String, dynamic>> menu({int desc = 150, int groups = 3, int options = 4}) => {
          for (var i = 0; i < 200; i++)
            'p${i.toString().padLeft(17, '0')}xyz':
                product(i, desc: desc, groups: groups, options: options),
        };

    test('قائمة 200 صنف عادية (وصف 150 حرف + 3 مجموعات خيارات) تحت حد المستند بهامش كبير', () {
      final bytes = MenuSync.estimateBytes(menu());
      // ignore: avoid_print
      print('menu 200 typical: ${bytes ~/ 1024}KB');
      expect(bytes, lessThan(450 * 1024));
    });

    test('قائمة 200 صنف تقيلة (وصف 300 + 4 مجموعات × 6 خيارات) لسه تحت الحد الآمن', () {
      final bytes = MenuSync.estimateBytes(menu(desc: 300, groups: 4, options: 6));
      // ignore: avoid_print
      print('menu 200 heavy: ${bytes ~/ 1024}KB');
      expect(bytes, lessThan(MenuSync.maxMenuBytes));
    });

    test('قائمة أكبر من الحد (وصف 500 + 10 مجموعات × 8): بتتعدّى الحد فالمحل يروح للمسار القديم', () {
      final bytes = MenuSync.estimateBytes(menu(desc: 500, groups: 10, options: 8));
      expect(bytes, greaterThan(MenuSync.maxMenuBytes));
    });

    Map<String, dynamic> store(int i, {int offers = 12, int best = 12, String? name}) {
      final offer = {
        'name': 'ساندوتش فراخ كريسبي سبايسي',
        'price': 85.5,
        'oldPrice': 95.0,
        'offerText': 'خصم لفترة محدودة',
        'offerEndsAt': ts,
        'image': img,
      };
      return {
        'name': name ?? 'مطعم الشيف أبو محمد للمأكولات $i',
        'category': 'مطاعم',
        'icon': 'restaurant',
        'color': 4294198070,
        'imageUrl': img,
        'storePhone': '01000197222',
        'rating': 4.5,
        'ratingSum': 450,
        'ratingCount': 100,
        'time': '20-30',
        'active': true,
        'order': i,
        'minOrder': 50,
        'ownerUid': 'uid-$i',
        'offerItems': List.filled(offers, offer),
        'bestItems': List.filled(best, {'name': 'ساندوتش', 'price': 85.5, 'image': img}),
      };
    }

    test('فهرس 200 محل بعروض كاملة: كل خانة تحت 3.5KB والإجمالي تحت الحد', () {
      final entries = {
        for (var i = 0; i < 200; i++) 's_shop$i': CatalogSync.indexEntry(store(i)),
      };
      for (final e in entries.values) {
        expect(CatalogSync.indexEntryTooBig(e), isFalse);
      }
      final bytes = CatalogSync.estimateBytes(entries);
      // ignore: avoid_print
      print('index 200 stores: ${bytes ~/ 1024}KB');
      expect(bytes, lessThan(CatalogSync.maxIndexBytes));
      expect(CatalogSync.indexProblem(entries), isNull);
    });

    test('أقصى عدد (250 محل) بأكبر خانة مسموحة لسه تحت الحد؛ 251 محل بيترفض', () {
      final entries = {
        for (var i = 0; i < 250; i++)
          's_shop$i': CatalogSync.indexEntry(store(i, name: 'م' * 120)),
      };
      for (final e in entries.values) {
        expect(CatalogSync.estimateBytes(e), lessThanOrEqualTo(CatalogSync.maxIndexEntryBytes));
      }
      expect(CatalogSync.indexProblem(entries), isNull);
      entries['s_extra'] = CatalogSync.indexEntry(store(999));
      expect(CatalogSync.indexProblem(entries), contains('أكبر من حد الفهرس'));
    });

    test('خانة كبيرة: العروض بتتقص (الأكثر مبيعًا الأول) لحد ما تدخل تحت الحدود', () {
      final longItem = {
        'name': 'ع' * 120,
        'price': 10,
        'offerText': 'ع' * 120,
        'image': img,
      };
      final big = store(1)
        ..['offerItems'] = List.filled(6, longItem)
        ..['bestItems'] = List.filled(6, longItem);
      final entry = CatalogSync.indexEntry(big);
      expect(CatalogSync.estimateBytes(entry), lessThanOrEqualTo(CatalogSync.maxIndexEntryBytes));
      expect((entry['hl'] as String).length, lessThanOrEqualTo(CatalogSync.maxHighlightsChars));
      expect(CatalogSync.indexEntryTooBig(entry), isFalse);
      final decoded = CatalogSync.decodeIndexEntry(entry);
      // الأكثر مبيعًا اتشالوا الأول، والعروض فضلت.
      expect((decoded['bestItems'] as List).length, 0);
      expect((decoded['offerItems'] as List), isNotEmpty);
      // الأصل ما اتغيرش.
      expect((big['bestItems'] as List).length, 6);
    });

    test('محل عليه قائمة أصناف قديمة كبيرة على مستنده: الخانة بتترفض وبيطلب ترحيل', () {
      final legacy = store(1)
        ..['products'] = [
          for (var i = 0; i < 100; i++) {'name': 'صنف قديم $i', 'price': 10, 'image': img},
        ];
      final entry = CatalogSync.indexEntry(legacy);
      expect(CatalogSync.indexEntryTooBig(entry), isTrue);
      expect(CatalogSync.indexProblem({'s_1': entry}), contains('رحّل'));
    });
  });
}
