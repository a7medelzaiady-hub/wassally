import 'package:city_store/models/order.dart';
import 'package:city_store/services/order_issue_service.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/order_issue_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order({OrderStatus status = OrderStatus.delivered, String store = 'سوبر ماركت النور'}) => AppOrder(
      id: 'order123',
      storeId: 'shop1',
      storeName: store,
      items: const [OrderLine('لبن', 30, 1)],
      subtotal: 30,
      deliveryFee: 15,
      total: 45,
      status: status,
      createdAt: DateTime(2026, 11, 27, 18),
      address: '',
      phone: '',
      notes: '',
    );

void main() {
  group('بيانات بلاغ «عندي مشكلة» (نفس شروط القواعد)', () {
    test('الحقول المسموحة بس، ورقم البلاغ = رقم الطلب', () {
      final p = OrderIssueService.payload(
        order: _order(), uid: 'cust1', type: OrderIssueType.missingItem, note: '  ناقص لبن  ',
      );
      expect(p.keys.toSet(), {
        'orderId', 'customerId', 'storeId', 'storeName', 'type', 'note', 'status', 'createdBy',
      });
      expect(p['orderId'], 'order123');
      expect(p['customerId'], 'cust1');
      expect(p['createdBy'], 'cust1');
      expect(p['storeId'], 'shop1');
      expect(p['type'], 'missing_item');
      expect(p['note'], 'ناقص لبن');
      expect(p['status'], 'open');
    });

    test('الملاحظة واسم المحل ما يعدّوش حدود القواعد', () {
      final p = OrderIssueService.payload(
        order: _order(store: 'م' * 200), uid: 'u', type: OrderIssueType.other, note: 'x' * 500,
      );
      expect((p['note'] as String).length, 300);
      expect((p['storeName'] as String).length, 120);
    });

    test('الأنواع زي قايمة القواعد بالظبط', () {
      expect(OrderIssueType.values.map((t) => t.key).toList(),
          ['missing_item', 'wrong_item', 'late', 'courier', 'price', 'other']);
      expect(OrderIssueType.parse('late'), OrderIssueType.late);
      expect(OrderIssueType.parse('x'), isNull);
    });

    test('الزرار ما يظهرش قبل ما المحل يأكد', () {
      expect(OrderIssueButton.visibleFor(_order(status: OrderStatus.newOrder)), isFalse);
      expect(OrderIssueButton.visibleFor(_order(status: OrderStatus.preparing)), isTrue);
      expect(OrderIssueButton.visibleFor(_order()), isTrue);
    });
  });

  group('شاشة البلاغ', () {
    Future<void> pump(WidgetTester tester, Future<bool> Function(OrderIssueType, String) submit) =>
        tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: OrderIssueSheet(order: _order(), submit: submit)),
          ),
        ));

    testWidgets('لازم يختار نوع المشكلة قبل الإرسال', (tester) async {
      var called = false;
      await pump(tester, (_, _) async => called = true);
      await tester.tap(find.byKey(const Key('order-issue-send')));
      await tester.pump();
      expect(called, isFalse);
      expect(find.text('اختار نوع المشكلة الأول.'), findsOneWidget);
    });

    testWidgets('بيبعت النوع والملاحظة', (tester) async {
      OrderIssueType? sentType;
      String? sentNote;
      await pump(tester, (t, n) async {
        sentType = t;
        sentNote = n;
        return false; // من غير ما يقفل الشاشة في الاختبار
      });
      await tester.tap(find.byKey(const Key('order-issue-wrong_item')));
      await tester.enterText(find.byKey(const Key('order-issue-note')), 'جالي بيبسي بدل كوكاكولا');
      await tester.tap(find.byKey(const Key('order-issue-send')));
      await tester.pump();
      expect(sentType, OrderIssueType.wrongItem);
      expect(sentNote, 'جالي بيبسي بدل كوكاكولا');
    });

    testWidgets('فشل الإرسال: رسالة واضحة', (tester) async {
      await pump(tester, (_, _) async => throw Exception('offline'));
      await tester.tap(find.byKey(const Key('order-issue-late')));
      await tester.tap(find.byKey(const Key('order-issue-send')));
      await tester.pump();
      expect(find.textContaining('تعذر إرسال البلاغ'), findsOneWidget);
    });
  });
}
