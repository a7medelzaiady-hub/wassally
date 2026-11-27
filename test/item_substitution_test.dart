import 'package:city_store/models/order.dart';
import 'package:city_store/screens/edit_order_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/substitute_picker.dart';
import 'package:city_store/widgets/substitution_offers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order({
  List<OrderLine>? items,
  List<String> unavailable = const ['بيبسي 2 لتر'],
  Map<String, OrderSubstitute> subs = const {},
}) =>
    AppOrder(
      id: 'o1',
      storeId: 'shop1',
      storeName: 'سوبر النور',
      items: items ??
          const [
            OrderLine('بيبسي 2 لتر', 30, 2, 'pepsi2'),
            OrderLine('شيبسي', 10, 1, 'chips'),
          ],
      subtotal: 70,
      deliveryFee: 15,
      total: 85,
      status: OrderStatus.newOrder,
      createdAt: DateTime(2026, 11, 27),
      address: '',
      phone: '',
      notes: '',
      unavailableItems: unavailable,
      substitutions: subs,
    );

const _pepsi15 = OrderSubstitute(productId: 'pepsi15', name: 'بيبسي 1.5 لتر', price: 25);

void main() {
  group('قراية البدائل من مستند الطلب', () {
    test('بديل سليم بيتقري، والغلط بيتجاهل', () {
      final parsed = OrderSubstitute.parseAll({
        'بيبسي 2 لتر': {'productId': 'pepsi15', 'name': 'بيبسي 1.5 لتر', 'price': 25},
        'ناقص سعر': {'productId': 'x', 'name': 'x'},
        'سعر صفر': {'productId': 'x', 'name': 'x', 'price': 0},
        'مش map': 'x',
      });
      expect(parsed.keys, ['بيبسي 2 لتر']);
      expect(parsed['بيبسي 2 لتر']!.price, 25);
      expect(OrderSubstitute.parseAll(null), isEmpty);
    });

    test('toMap بنفس الشكل اللي بيتقري', () {
      expect(OrderSubstitute.parse(_pepsi15.toMap())!.productId, 'pepsi15');
    });
  });

  group('أصناف الطلب بعد الموافقة على البديل', () {
    test('من غير موافقة: الصنف الناقص بصفر بس', () {
      final lines = linesWithSubstitutes(_order(subs: {'بيبسي 2 لتر': _pepsi15}), const {});
      expect(lines.map((l) => '${l.name}:${l.qty}'), ['بيبسي 2 لتر:0', 'شيبسي:1']);
    });

    test('موافقة: البديل بيتضاف بنفس الكمية وبمعرّف الكتالوج', () {
      final lines = linesWithSubstitutes(_order(), {'بيبسي 2 لتر': _pepsi15});
      expect(lines.length, 3);
      final sub = lines.last;
      expect(sub.name, 'بيبسي 1.5 لتر');
      expect(sub.productId, 'pepsi15');
      expect(sub.qty, 2);
      expect(sub.price, 25);
    });

    test('البديل موجود أصلًا في الطلب: الكمية بتزيد على نفس السطر (من غير تكرار)', () {
      final order = _order(items: const [
        OrderLine('بيبسي 2 لتر', 30, 2, 'pepsi2'),
        OrderLine('بيبسي 1.5 لتر', 25, 1, 'pepsi15'),
      ]);
      final lines = linesWithSubstitutes(order, {'بيبسي 2 لتر': _pepsi15});
      expect(lines.length, 2);
      expect(lines[1].qty, 3);
    });

    test('بديل لصنف مش ناقص بيتجاهل', () {
      final lines = linesWithSubstitutes(_order(), {'شيبسي': _pepsi15});
      expect(lines.length, 2);
    });
  });

  group('أصناف الكتالوج اللي تنفع بديل', () {
    test('متاح ومن غير اختيارات', () {
      expect(substituteFromCatalog('a', {'name': 'لبن', 'price': 20})!.price, 20);
      expect(substituteFromCatalog('a', {'name': 'لبن', 'price': 20, 'available': false}), isNull);
      expect(substituteFromCatalog('a', {'name': 'قهوة', 'price': 20, 'optionGroups': [{'title': 'سكر'}]}), isNull);
      expect(substituteFromCatalog('a', {'name': '', 'price': 20}), isNull);
      expect(substituteFromCatalog('a', {'name': 'لبن', 'price': 0}), isNull);
    });

    test('العرض المنتهي بيتجاهل (نفس السعر اللي العميل والـWorker بيحسبوه)', () {
      final now = DateTime(2026, 11, 27);
      final expired = substituteFromCatalog('a', {
        'name': 'لبن', 'price': 15, 'oldPrice': 20, 'offerEndsAt': DateTime(2026, 11, 1),
      }, now: now);
      expect(expired!.price, 20);
      final active = substituteFromCatalog('a', {
        'name': 'لبن', 'price': 15, 'oldPrice': 20, 'offerEndsAt': DateTime(2026, 12, 1),
      }, now: now);
      expect(active!.price, 15);
    });
  });

  group('العميل بيوافق على البديل', () {
    Future<Map<String, OrderSubstitute>?> run(WidgetTester tester, {bool accept = true}) async {
      Map<String, OrderSubstitute>? got;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SubstitutionOffers(
              order: _order(subs: {'بيبسي 2 لتر': _pepsi15}),
              onContinue: (a) => got = a,
            ),
          ),
        ),
      ));
      expect(find.textContaining('بيبسي 1.5 لتر'), findsOneWidget);
      if (accept) await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byKey(const Key('substitute-continue')));
      return got;
    }

    testWidgets('وافق: البديل بيتبعت للتعديل', (tester) async {
      final got = await run(tester);
      expect(got!.keys, ['بيبسي 2 لتر']);
      expect(find.text('كمّل بالبديل وراجع الحساب'), findsOneWidget);
    });

    testWidgets('ما وافقش: يكمّل من غير الصنف', (tester) async {
      final got = await run(tester, accept: false);
      expect(got, isEmpty);
      expect(find.text('كمّل من غير الأصناف دي'), findsOneWidget);
    });
  });
}
