import 'package:flutter/material.dart';

import '../utils/format.dart';

/// سطر واحد في فاتورة صفحة «إتمام الطلب».
class CheckoutInvoiceItem {
  final String name;
  final int qty;
  final double total;
  const CheckoutInvoiceItem(this.name, this.qty, this.total);
}

/// أصناف الطلب في صفحة «إتمام الطلب» على شكل فاتورة بنفس أسلوب الإيصال الحراري:
/// ثلاثة أعمدة (الصنف، الكمية، الإجمالي)، رأس رمادي فاتح، وخطوط رفيعة بين السطور.
/// من بيانات السلة اللي على الموبايل: صفر قراءات.
class CheckoutInvoiceTable extends StatelessWidget {
  final List<CheckoutInvoiceItem> items;
  const CheckoutInvoiceTable({super.key, required this.items});

  static const ink = Color(0xFF1B1B1B);
  static const _headerFill = Color(0xFFF3F2ED);
  static const _rowLine = Color(0xFFE1DFD8);

  /// الأرقام من غير «ج.م» جوه كل خلية لتوفير العرض (العملة ظاهرة في الإجماليات تحت).
  static String amountOnly(double v) => formatPrice(v).replaceAll(' ج.م', '');

  @override
  Widget build(BuildContext context) {
    const numbers = [FontFeature.tabularFigures()];
    TextStyle style({bool header = false}) => TextStyle(
          fontSize: header ? 12 : 13,
          fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          color: ink,
          height: 1.3,
          fontFeatures: numbers,
        );

    Widget row(String name, String qty, String total, {bool header = false, Key? key}) {
      Widget num(String v) => Expanded(
            flex: 4,
            child: Text(
              v,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: style(header: header),
            ),
          );
      return Container(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: header ? _headerFill : null,
          border: const Border(bottom: BorderSide(color: _rowLine, width: 0.7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 10, child: Text(name, style: style(header: header))),
            num(qty),
            num(total),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        key: const Key('checkout-invoice'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('الصنف', 'الكمية', 'الإجمالي', header: true, key: const Key('checkout-invoice-header')),
          for (var i = 0; i < items.length; i++)
            row(
              items[i].name,
              '${items[i].qty}',
              amountOnly(items[i].total),
              key: Key('checkout-invoice-line-$i'),
            ),
        ],
      ),
    );
  }
}

/// خط متقطع زي ورق الكاشير (نفس شكل الإيصال).
class CheckoutDashes extends StatelessWidget {
  const CheckoutDashes({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, c) {
          final count = (c.maxWidth / 7).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
              (_) => const SizedBox(
                width: 4,
                height: 1.2,
                child: ColoredBox(color: Color(0xFF8A8A8A)),
              ),
            ),
          );
        },
      ),
    );
  }
}
