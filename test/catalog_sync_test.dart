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
    test('keeps only display fields (matching the rules) and trims highlights', () {
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
          (i) => {'name': 'o$i', 'price': 5, 'image': 'x', 'junk': true},
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
      expect(entry.containsKey('approvedBy'), isFalse);
      expect(entry['ratingSum'], 9);
      final offers = entry['offerItems'] as List;
      expect(offers.length, CatalogSync.indexHighlightsCap);
      expect((offers.first as Map).containsKey('junk'), isFalse);
      expect((entry['bestItems'] as List).length, 1);
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
      expect(entry.containsKey('offerItems'), isFalse);
      expect(entry.containsKey('rating'), isFalse);
    });
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
}
