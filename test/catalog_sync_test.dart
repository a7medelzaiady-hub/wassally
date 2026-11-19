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
    test('keeps every store field and trims highlight lists to the index cap', () {
      final store = <String, dynamic>{
        'name': 'S',
        'category': 'مطاعم',
        'active': true,
        'offerItems': List.generate(10, (i) => {'name': 'o$i'}),
        'bestItems': [{'name': 'b'}],
      };
      final entry = CatalogSync.indexEntry(store);
      expect(entry['name'], 'S');
      expect(entry['category'], 'مطاعم');
      expect(entry['active'], true);
      expect((entry['offerItems'] as List).length, CatalogSync.indexHighlightsCap);
      expect((entry['bestItems'] as List).length, 1);
      // الأصل ما يتغيرش.
      expect((store['offerItems'] as List).length, 10);
    });
  });

  test('CatalogDoc mirrors id and data()', () {
    const doc = CatalogDoc('shop1', {'name': 'S'});
    expect(doc.id, 'shop1');
    expect(doc.data()['name'], 'S');
  });
}
