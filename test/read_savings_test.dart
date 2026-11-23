import 'package:city_store/services/driver_service.dart';
import 'package:city_store/services/read_meter.dart';
import 'package:city_store/services/store_highlights.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoreHighlights.compute (home offers come from this summary)', () {
    final now = DateTime(2026, 11, 19, 12);
    final past = Timestamp.fromDate(now.subtract(const Duration(days: 1)));
    final future = Timestamp.fromDate(now.add(const Duration(days: 1)));

    test('keeps discounted/text offers and best sellers, skips unavailable and expired', () {
      final h = StoreHighlights.compute([
        {'name': 'a-text', 'price': 5, 'offerText': '1+1', 'offerEndsAt': future},
        {'name': 'b-discount', 'price': 8, 'oldPrice': 10, 'image': 'x'},
        {'name': 'c-expired', 'price': 5, 'oldPrice': 9, 'offerEndsAt': past},
        {'name': 'd-off', 'price': 5, 'oldPrice': 9, 'available': false},
        {'name': 'e-plain', 'price': 5},
        {'name': 'f-best', 'price': 7, 'bestSeller': true},
        {'name': 'g-best-off', 'price': 7, 'bestSeller': true, 'isAvailable': false},
      ], now: now);
      expect(h.offers.map((m) => m['name']), ['a-text', 'b-discount']);
      expect(h.best.map((m) => m['name']), ['f-best']);
      expect(h.offers.last.keys.toSet(), {'name', 'price', 'oldPrice', 'image'});
    });

    test('caps both lists at the store-document rule limit', () {
      final many = [
        for (var i = 0; i < 30; i++)
          {'name': 'p$i', 'price': 5, 'oldPrice': 9, 'bestSeller': true},
      ];
      final h = StoreHighlights.compute(many, now: now);
      expect(h.offers.length, StoreHighlights.maxItems);
      expect(h.best.length, StoreHighlights.maxItems);
    });
  });

  group('RatingSummary.fromStore (owner rating without reading reviews)', () {
    test('averages ratingSum / ratingCount', () {
      final r = RatingSummary.fromStore({'ratingSum': 9, 'ratingCount': 2});
      expect(r.avg, 4.5);
      expect(r.count, 2);
    });

    test('no ratings or missing doc means zero', () {
      expect(RatingSummary.fromStore(null).count, 0);
      expect(RatingSummary.fromStore({'ratingSum': 0, 'ratingCount': 0}).avg, 0);
      expect(RatingSummary.fromStore({}).text, 'لسه مفيش تقييمات');
    });
  });

  test('ReadMeter aggregate/reset bookkeeping', () {
    ReadMeter.enabled = true;
    ReadMeter.reset();
    ReadMeter.aggregate('x');
    ReadMeter.aggregate('x');
    ReadMeter.aggregate('y');
    expect(ReadMeter.total(), 3);
    expect(ReadMeter.snapshot().first.key, 'x');
    ReadMeter.reset();
    expect(ReadMeter.total(), 0);
  });
}
