import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/format.dart';
import 'order_receipt_sheet.dart' show ReceiptDashes, ReceiptTornEdges;

/// سطر صنف في الفاتورة.
class InvoiceItem {
  final String name;
  final int qty;
  final double unitPrice;
  const InvoiceItem(this.name, this.qty, this.unitPrice);
  double get total => unitPrice * qty;
}

/// سطر من سطور الحساب تحت الأصناف (المجموع، التوصيل، خصم...).
class InvoiceTotal {
  final String label;
  final String value;
  const InvoiceTotal(this.label, this.value);
}

/// ملخص الطلب في شاشة الإتمام بشكل فاتورة كاشير: جدول (الصنف/الكمية/السعر/
/// الإجمالي) بسطور مضغوطة، حواف مقصوصة، وخطوط متقطعة. بيوفّر مساحة عن
/// الكارت القديم وبيطابق شكل الإيصال اللي العميل بيشاركه بعدين.
class CheckoutInvoice extends StatelessWidget {
  final String storeName;
  final Widget? eta;
  final List<InvoiceItem> items;
  final List<InvoiceTotal> totals;
  final String grandTotal;

  /// زرار اختياري قبل الإجمالي (مثلاً «استخدم نقاط الدعوات»).
  final Widget? beforeTotal;
  final String? note;

  const CheckoutInvoice({
    super.key,
    required this.storeName,
    required this.items,
    required this.totals,
    required this.grandTotal,
    this.eta,
    this.beforeTotal,
    this.note,
  });

  static const _ink = Color(0xFF1B1B1B);
  static const _faded = Color(0xFF6A6A6A);
  static const _paper = Color(0xFFFFFEFA);
  static const _band = Color(0xFFF3F2ED);
  static const _rule = Color(0xFFE6E4DD);

  static String _amount(num v) => formatPrice(v).replaceAll(' ج.م', '');

  @override
  Widget build(BuildContext context) {
    const numbers = [FontFeature.tabularFigures()];
    TextStyle st(double size, {FontWeight w = FontWeight.w600, Color c = _ink}) =>
        TextStyle(fontSize: size, fontWeight: w, color: c, height: 1.3, fontFeatures: numbers);

    Widget cell(String v, int flex, {bool head = false, bool name = false}) => Expanded(
          flex: flex,
          child: Text(
            v,
            textAlign: name ? TextAlign.start : TextAlign.center,
            style: st(head ? 11.5 : 12.5, w: head ? FontWeight.w800 : (name ? FontWeight.w600 : FontWeight.w700),
                c: head ? _faded : _ink),
          ),
        );

    Widget tableRow(String name, String qty, String unit, String total, {bool head = false, Key? key}) =>
        Container(
          key: key,
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: head ? 5 : 5.5),
          decoration: BoxDecoration(
            color: head ? _band : null,
            borderRadius: head ? BorderRadius.circular(6) : null,
            border: head ? null : const Border(bottom: BorderSide(color: _rule, width: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cell(name, 9, head: head, name: true),
              cell(qty, 3, head: head),
              cell(unit, 4, head: head),
              cell(total, 4, head: head),
            ],
          ),
        );

    Widget totalRow(InvoiceTotal t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          child: Row(
            children: [
              Expanded(child: Text(t.label, style: st(13, w: FontWeight.w600, c: _faded))),
              Text(t.value, style: st(13, w: FontWeight.w700)),
            ],
          ),
        );

    return PhysicalShape(
      key: const Key('checkout-invoice'),
      clipper: const ReceiptTornEdges(),
      color: _paper,
      elevation: 2.5,
      shadowColor: const Color(0x55000000),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(storeName, style: st(15, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('فاتورة الطلب', style: st(11.5, w: FontWeight.w700, c: _faded)),
              ],
            ),
            if (eta != null) ...[const SizedBox(height: 4), eta!],
            const ReceiptDashes(),
            tableRow('الصنف', 'الكمية', 'السعر', 'الإجمالي', head: true, key: const Key('invoice-head')),
            for (var i = 0; i < items.length; i++)
              tableRow(
                items[i].name,
                '${items[i].qty}',
                _amount(items[i].unitPrice),
                _amount(items[i].total),
                key: Key('invoice-line-$i'),
              ),
            const SizedBox(height: 4),
            for (final t in totals) totalRow(t),
            if (beforeTotal != null) Align(alignment: AlignmentDirectional.centerStart, child: beforeTotal!),
            const ReceiptDashes(),
            Container(
              key: const Key('invoice-grand-total'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('الإجمالي', style: st(15.5, w: FontWeight.w900))),
                  Text(
                    grandTotal,
                    style: st(17, w: FontWeight.w900, c: AppColors.orangeDeep),
                  ),
                ],
              ),
            ),
            if (note != null && note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline_rounded, size: 15, color: _faded),
                  ),
                  const SizedBox(width: 5),
                  Expanded(child: Text(note!, style: st(11.5, w: FontWeight.w500, c: _faded).copyWith(height: 1.45))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
