import 'package:city_store/utils/format.dart';
import 'package:city_store/widgets/checkout_invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ملخص الطلب بيظهر كفاتورة بجدول أعمدة وإجمالي', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: CheckoutInvoice(
              storeName: 'فواكه وخضروات',
              items: const [
                InvoiceItem('بصل اصفر', 8, 13.12),
                InvoiceItem('بطاطس', 2, 33),
              ],
              totals: const [
                InvoiceTotal('المجموع', '171 ج.م'),
                InvoiceTotal('رسوم التوصيل', '20 ج.م'),
              ],
              grandTotal: '191 ج.م',
              note: 'تقدر تعدّل من «طلباتي»',
            ),
          ),
        ),
      ),
    ));

    expect(find.byKey(const Key('checkout-invoice')), findsOneWidget);
    expect(find.byKey(const Key('invoice-head')), findsOneWidget);
    for (final h in ['الصنف', 'الكمية', 'السعر', 'الإجمالي']) {
      expect(find.text(h), findsWidgets);
    }
    expect(find.byKey(const Key('invoice-line-0')), findsOneWidget);
    expect(find.byKey(const Key('invoice-line-1')), findsOneWidget);
    // 8 × 13.12 = 104.96 تتقرّب «105» مش «105.0».
    expect(find.text('105'), findsOneWidget);
    expect(find.text('66'), findsOneWidget);
    expect(find.text('191 ج.م'), findsOneWidget);
    expect(find.textContaining('طلباتي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('السعر بيتقرّب لرقم عشري واحد من غير «.0»', () {
    expect(formatPrice(104.96), '105 ج.م');
    expect(formatPrice(26.3), '26.3 ج.م');
    expect(formatPrice(35), '35 ج.م');
  });
}
