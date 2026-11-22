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

  group('صفحة «سلّاتي»', () {
    tearDown(carts.clearAll);

    testWidgets('بتعرض كل السلال، والمسح بيحتاج تأكيد', (tester) async {
      carts.rememberStore(_grocery);
      cart.add(_rice, storeId: 'g', storeName: 'بقالة الخير', qty: 2);
      carts.switchTo('p');
      cart.add(_chicken, storeId: 'p', storeName: 'دواجن النور');

      await tester.pumpWidget(const MaterialApp(home: MyCartsPage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cart-card-g')), findsOneWidget);
      expect(find.byKey(const Key('cart-card-p')), findsOneWidget);
      expect(find.text('السلة الحالية'), findsOneWidget);
      // المحل المعروف بس عليه «إضافة منتجات من نفس المحل».
      expect(find.byKey(const Key('cart-add-more-g')), findsOneWidget);
      expect(find.byKey(const Key('cart-add-more-p')), findsNothing);
      expect(find.byKey(const Key('carts-shop-other')), findsOneWidget);

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
}
