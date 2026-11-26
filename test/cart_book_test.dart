import 'dart:convert';

import 'package:city_store/models/product.dart';
import 'package:city_store/models/store.dart';
import 'package:city_store/screens/my_carts_page.dart';
import 'package:city_store/services/cart_book.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _rice = Product('رز', 30);
const _oil = Product('زيت', 80);
const _chicken = Product('فراخ', 120);

const _grocery = Store(
  id: 'g', name: 'بقالة الخير', category: 'بقالة', iconKey: 'store',
  colorHex: 0xFF00AA00, rating: 4.5, time: '30', products: [],
);

class _MemoryStorage implements CartStorage {
  String? value;
  int writes = 0;
  _MemoryStorage([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async {
    writes++;
    value = v;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('CartBook («سلّاتي»)', () {
    late CartModel active;
    late CartBook book;
    setUp(() {
      active = CartModel();
      book = CartBook(active);
    });

    test('السلة الحالية بتشتغل زي الأول لنفس المحل', () {
      expect(active.add(_rice, storeId: 'g', storeName: 'بقالة الخير'), isTrue);
      book.switchTo('g'); // نفس المحل: مفيش تغيير
      expect(active.count, 1);
      expect(book.hasParked, isFalse);
      expect(book.cartsCount, 1);
    });

    test('التسوق من محل تاني بيحفظ السلة القديمة زي ما هي ويبدأ سلة جديدة', () {
      active.add(_rice, storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      active.add(_oil, storeId: 'g', storeName: 'بقالة الخير');
      active.setPromo('SAVE', 10);
      active.setArea('وسط البلد', 25);

      book.switchTo('p');
      expect(active.isEmpty, isTrue);
      expect(active.add(_chicken, storeId: 'p', storeName: 'دواجن النور'), isTrue);

      expect(book.cartsCount, 2);
      final saved = book.parkedFor('g')!;
      expect(saved.storeName, 'بقالة الخير');
      expect(saved.count, 3);
      expect(saved.subtotal, 140);
      expect(saved.promoCode, 'SAVE');
    });

    test('الرجوع لمحل محفوظ بيرجّع سلته بكل تفاصيلها ويحفظ الحالية', () {
      active.add(_rice, storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      active.setPromo('SAVE', 10);
      active.setArea('وسط البلد', 25);
      book.switchTo('p');
      active.add(_chicken, storeId: 'p', storeName: 'دواجن النور');

      book.switchTo('g');
      expect(active.storeId, 'g');
      expect(active.qtyOf(_rice), 2);
      expect(active.promoCode, 'SAVE');
      expect(active.area, 'وسط البلد');
      expect(active.fee, 25);
      expect(book.parkedFor('g'), isNull);
      expect(book.parkedFor('p')!.count, 1);
      expect(book.cartsCount, 2);
    });

    test('الطلب الخاص بيتحفظ مع السلة', () {
      active.setSpecialRequest(storeId: 'g', storeName: 'بقالة الخير', request: {'description': 'عيش سن'});
      book.switchTo('p');
      expect(book.parkedFor('g')!.specialRequest, {'description': 'عيش سن'});
      book.switchTo('g');
      expect(active.specialRequest, {'description': 'عيش سن'});
    });

    test('السلة المحفوظة نسخة مستقلة: التعديل بعدها ما يغيّرهاش', () {
      active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      book.switchTo('p');
      active.add(_rice, storeId: 'p', storeName: 'دواجن النور', qty: 5);
      expect(book.parkedFor('g')!.items[_rice], 1);
    });

    test('سلة فاضية ما بتتحفظش، ومسح سلة محفوظة، ومسح الكل عند الخروج', () {
      book.switchTo('p');
      expect(book.hasParked, isFalse);
      active.add(_chicken, storeId: 'p', storeName: 'دواجن النور');
      book.switchTo('g');
      active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      book.removeParked('p');
      expect(book.hasParked, isFalse);
      book.switchTo('x');
      book.clearAll();
      expect(book.hasParked, isFalse);
      expect(active.isEmpty, isTrue);
      expect(book.cartsCount, 0);
    });

    test('بيفتكر المحل عشان «إضافة منتجات من نفس المحل»', () {
      book.rememberStore(_grocery);
      expect(book.storeFor('g')?.name, 'بقالة الخير');
      expect(book.storeFor('nope'), isNull);
      expect(book.storeFor(null), isNull);
    });
  });

  group('علامة السلة', () {
    tearDown(carts.clearAll);

    test('بتعدّ الأصناف المختلفة ومش بتعدّ السلة اللي اتبعت', () {
      cart.add(_rice, storeId: 'g', storeName: 'بقالة الخير', qty: 6);
      cart.add(_oil, storeId: 'g', storeName: 'بقالة الخير', qty: 4);
      expect(carts.totalItems, 2);
      carts.switchTo('p');
      cart.add(_chicken, storeId: 'p', storeName: 'دواجن النور', qty: 3);
      expect(carts.totalItems, 3);
      cart.markSubmitted('order_1');
      expect(carts.totalItems, 2);
    });
  });

  group('صفحة «سلّاتي»', () {
    tearDown(carts.clearAll);

    testWidgets('بتعرض كل السلات، والمسح بيحتاج تأكيد', (tester) async {
      carts.rememberStore(_grocery);
      cart.add(_rice, storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      carts.switchTo('p');
      cart.add(_chicken, storeId: 'p', storeName: 'دواجن النور');

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: MyCartsPage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cart-card-g')), findsOneWidget);
      expect(find.byKey(const Key('cart-card-p')), findsOneWidget);
      expect(find.text('السلة الحالية'), findsOneWidget);
      expect(find.textContaining('لحد ما تفرّغها بنفسك'), findsOneWidget);
      expect(find.textContaining('3 أيام'), findsNothing);
      // المحل المعروف بس عليه «إضافة منتجات من نفس المحل».
      expect(find.byKey(const Key('cart-add-more-g')), findsOneWidget);
      expect(find.byKey(const Key('cart-add-more-p')), findsNothing);
      // The shop-another-store button is below two full cart cards on a
      // phone-sized viewport. Scroll before asserting: ListView lazily builds
      // children and a missing offscreen widget is not a missing feature.
      await tester.scrollUntilVisible(
        find.byKey(const Key('carts-shop-other')),
        180,
      );
      expect(find.byKey(const Key('carts-shop-other')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('cart-delete-g')),
        -180,
      );
      await tester.ensureVisible(find.byKey(const Key('cart-delete-g')));
      await tester.tap(find.byKey(const Key('cart-delete-g')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('امسح').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cart-card-g')), findsNothing);
      expect(carts.hasParked, isFalse);
      expect(cart.storeId, 'p');
    });
  });


  group('حفظ «سلّاتي» على الموبايل', () {
    test('السلات بتتحفظ وترجع بعد فتح التطبيق تاني بكل تفاصيلها', () async {
      final storage = _MemoryStorage();
      final first = CartBook(CartModel(), storage: storage);
      await first.load();
      first.active.add(const Product('زيت', 80, '', 'oil1', true, 0, '', null, '', [], [ProductOption('لتر', 5)]),
          storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      first.active.setPromo('SAVE', 10);
      first.switchTo('p');
      first.active.add(_chicken, storeId: 'p', storeName: 'دواجن النور');
      await _settle();
      expect(storage.value, isNotNull);

      // فتح التطبيق تاني.
      final second = CartBook(CartModel(), storage: storage);
      await second.load();
      expect(second.restoredCount, 2);
      expect(second.active.storeId, 'p');
      expect(second.active.qtyOf(_chicken), 1);
      final g = second.parkedFor('g')!;
      expect(g.storeName, 'بقالة الخير');
      expect(g.count, 2);
      expect(g.promoCode, 'SAVE');
      final line = g.items.keys.single;
      expect(line.id, 'oil1');
      expect(line.chosen.single.name, 'لتر');
      second.markRestoredSeen();
      expect(second.restoredCount, 0);
    });

    test('السلات القديمة بتفضل محفوظة حتى يفرغها العميل', () async {
      final now = DateTime(2026, 11, 22, 12);
      final data = {
        'v': 1,
        'active': 'old',
        'carts': [
          {
            'storeId': 'old', 'storeName': 'قديم',
            'touchedAt': now.subtract(const Duration(days: 4)).toIso8601String(),
            'items': [{'id': 'a', 'name': 'رز', 'price': 30, 'qty': 1}],
          },
          {
            'storeId': 'new', 'storeName': 'جديد',
            'touchedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
            'items': [{'id': 'b', 'name': 'زيت', 'price': 80, 'qty': 2}],
          },
        ],
      };
      final book = CartBook(CartModel(), storage: _MemoryStorage(jsonEncode(data)));
      await book.load(now: now);
      expect(book.restoredCount, 2);
      expect(book.parkedFor('new')!.count, 2);
      expect(book.active.storeId, 'old');
      expect(book.active.count, 1);
    });

    test('سلة اتبعت طلبها ما بترجعش بعد فتح التطبيق (مكانها «طلباتي»)', () async {
      final storage = _MemoryStorage();
      final first = CartBook(CartModel(), storage: storage);
      await first.load();
      first.active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      first.active.markSubmitted('order_123');
      await first.flush();
      expect(storage.value, contains('submittedOrderId'));

      await first.detachForSignOut();
      expect(first.active.isEmpty, isTrue);
      expect(storage.value, isNotNull);

      await first.attachAfterSignIn();
      expect(first.active.isEmpty, isTrue);
      expect(first.cartsCount, 0);
    });

    test('بعد تأكيد الطلب سلة المحل بتتمسح والسلات التانية بتفضل', () async {
      final book = CartBook(CartModel(), storage: _MemoryStorage());
      await book.load();
      book.active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      book.switchTo('p');
      book.active.add(_chicken, storeId: 'p', storeName: 'دواجن النور');
      book.active.markSubmitted('order_9');
      book.finishSubmitted('p');
      expect(book.active.isEmpty, isTrue);
      expect(book.parkedFor('g')!.count, 1);
      expect(book.cartsCount, 1);
    });

    test('تخزين تالف ما يوقعش التطبيق', () async {
      final book = CartBook(CartModel(), storage: _MemoryStorage('{not json'));
      await book.load();
      expect(book.cartsCount, 0);
      expect(book.restoredCount, 0);
    });

    test('اللي العميل ضافه قبل ما التحميل يخلص ما يتلمسش', () async {
      final storage = _MemoryStorage(jsonEncode({
        'v': 1,
        'active': 'g',
        'carts': [
          {
            'storeId': 'g', 'storeName': 'بقالة الخير',
            'touchedAt': DateTime.now().toIso8601String(),
            'items': [{'id': 'r', 'name': 'رز', 'price': 30, 'qty': 5}],
          },
        ],
      }));
      final book = CartBook(CartModel(), storage: storage);
      book.active.add(_chicken, storeId: 'g', storeName: 'بقالة الخير');
      await book.load();
      expect(book.active.qtyOf(_chicken), 1);
      expect(book.active.count, 1);
    });

    test('تسجيل الخروج بيمسح السلات من الموبايل', () async {
      final storage = _MemoryStorage();
      final book = CartBook(CartModel(), storage: storage);
      await book.load();
      book.active.add(_rice, storeId: 'g', storeName: 'بقالة الخير');
      await _settle();
      expect(storage.value, isNotNull);
      book.clearAll();
      await _settle();
      expect(storage.value, isNull);
    });
  });

  group('مراجعة الأسعار على قائمة المحل', () {
    test('السعر المتغير بيتحدث، والصنف اللي اتشال بيتشال من السلة', () {
      final c = CartModel();
      c.add(const Product('رز', 30, '', 'r'), storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      c.add(const Product('زيت', 80, '', 'o'), storeId: 'g', storeName: 'بقالة الخير');
      c.add(const Product('سكر', 25, '', 's'), storeId: 'g', storeName: 'بقالة الخير');
      final changes = c.syncWithMenu('g', const [
        Product('رز', 35, '', 'r'),
        Product('سكر', 25, '', 's'),
      ]);
      expect(changes.length, 2);
      expect(c.count, 3);
      expect(c.subtotal, 35 * 2 + 25);
    });

    test('من غير تغيير مفيش رسائل، ومحل تاني ما يتراجعش', () {
      final c = CartModel();
      c.add(const Product('رز', 30, '', 'r'), storeId: 'g', storeName: 'بقالة الخير');
      expect(c.syncWithMenu('g', const [Product('رز', 30, '', 'r')]), isEmpty);
      expect(c.syncWithMenu('other', const [Product('رز', 99, '', 'r')]), isEmpty);
      expect(c.subtotal, 30);
    });

    test('الخيارات المدفوعة بتتحسب فوق السعر الجديد', () {
      final c = CartModel();
      const base = Product('قهوة', 20, '', 'c');
      c.add(base.withChoices(const [ProductOption('سكر زيادة', 3)]), storeId: 'k', storeName: 'كافيه');
      c.syncWithMenu('k', const [Product('قهوة', 25, '', 'c')]);
      expect(c.subtotal, 28);
    });
  });
}
