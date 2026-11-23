import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/models/quick_price_guide.dart';

void main() {
  test('parse guide and calculate approximate prices', () {
    final guide = QuickPriceGuide.fromMap({
      'version': 2,
      'items': [
        {'id': 'milk', 'name': 'لبن', 'unit': 'لتر', 'pricePiastres': 3500},
        {'id': 'bread', 'name': 'عيش', 'unit': 'رغيف', 'pricePiastres': 200},
      ],
    });
    expect(guide.version, 2);
    final selected = [
      QuickPriceSelection(item: guide.items[0], quantity: 2),
      QuickPriceSelection(item: guide.items[1], quantity: 3),
    ];
    expect(QuickPriceEstimate.totalPiastres(selected), 7600);
    expect(selected[0].toWorkerMap(), {
      'name': 'لبن', 'qty': 2, 'unitPricePiastres': 3500,
    });
  });

  test('search price guide by name or unit without fetching', () {
    const item = QuickPriceItem(
      id: 'milk', name: 'لبن', unit: 'لتر', pricePiastres: 3500,
    );
    expect(item.matchesSearch('لبن'), isTrue);
    expect(item.matchesSearch('لتر'), isTrue);
    expect(item.matchesSearch('  لتر  '), isTrue);
    expect(item.matchesSearch('كيلو'), isFalse);
  });

  test('reject malformed guide entries and duplicate ids', () {
    expect(() => QuickPriceGuide.fromMap({
      'version': 1,
      'items': [
        {'id': 'a', 'name': 'أ', 'unit': 'قطعة', 'pricePiastres': -1},
      ],
    }), throwsFormatException);
    expect(() => QuickPriceGuide.fromMap({
      'version': 1,
      'items': [
        {'id': 'a', 'name': 'أ', 'unit': 'قطعة', 'pricePiastres': 100},
        {'id': 'a', 'name': 'ب', 'unit': 'قطعة', 'pricePiastres': 200},
      ],
    }), throwsFormatException);
  });
}
