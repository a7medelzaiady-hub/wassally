import 'package:city_store/services/store_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('favorites and last visited persist on device for one account', () async {
    final state = StoreShortcuts();
    await state.load('customer-1');
    await state.toggleFavorite('customer-1', 'store-3');
    await state.recordVisit('customer-1', 'store-2');
    await state.recordVisit('customer-1', 'store-3');
    await state.recordVisit('customer-1', 'store-2');

    expect(state.isFavorite('store-3'), isTrue);
    expect(state.recent, ['store-2', 'store-3']);
    final restored = StoreShortcuts();
    await restored.load('customer-1');
    expect(restored.isFavorite('store-3'), isTrue);
    expect(restored.recent, ['store-2', 'store-3']);
  });

  test('each account sees only their own shortcuts', () async {
    final state = StoreShortcuts();
    await state.load('customer-a');
    await state.toggleFavorite('customer-a', 'shop-a');
    await state.recordVisit('customer-a', 'shop-a');
    await state.load('customer-b');
    expect(state.favorites, isEmpty);
    expect(state.recent, isEmpty);
    await state.recordVisit('customer-b', 'shop-b');
    await state.load('customer-a');
    expect(state.isFavorite('shop-a'), isTrue);
    expect(state.recent, ['shop-a']);
    expect(state.isFavorite('shop-b'), isFalse);
  });

  test('recent stores are capped and deduplicated', () async {
    final state = StoreShortcuts();
    await state.load('customer');
    for (var i = 0; i < 18; i++) {
      await state.recordVisit('customer', 'shop-$i');
    }
    expect(state.recent.length, StoreShortcuts.maxRecent);
    expect(state.recent.first, 'shop-17');
    expect(state.recent, isNot(contains('shop-0')));
  });

  test('toggling favorite twice removes it', () async {
    final state = StoreShortcuts();
    await state.load('customer');
    await state.toggleFavorite('customer', 'shop');
    await state.toggleFavorite('customer', 'shop');
    expect(state.isFavorite('shop'), isFalse);
  });
}
