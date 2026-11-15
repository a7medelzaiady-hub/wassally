import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/order.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';

/// تعديل الطلب قبل استلام المندوب: في حالتي new وpreparing طالما courierId فارغ.
/// القواعد (firestore.rules) هي اللي بتمنع التعديل لو الحالة اتغيّرت.
class EditOrderPage extends StatefulWidget {
  final AppOrder order;
  const EditOrderPage({super.key, required this.order});

  @override
  State<EditOrderPage> createState() => _EditOrderPageState();
}

class _EditOrderPageState extends State<EditOrderPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.order.userName.isNotEmpty
        ? widget.order.userName
        : widget.order.customerName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.order.phone,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.order.address,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.order.notes,
  );
  late final TextEditingController _courierNotes = TextEditingController(
    text: widget.order.courierNotes,
  );
  // الأصناف اللي المحل علّمها «غير متاحة» بتبدأ بكمية صفر (العميل يقدر يرجّعها لو حب).
  late final List<OrderLine> _lines = [
    for (final l in widget.order.items)
      widget.order.unavailableItems.contains(l.name) ? l.withQty(0) : l,
  ];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    _courierNotes.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold(0.0, (a, l) => a + l.price * l.qty);

  double get _discount {
    final o = widget.order;
    if (o.discount <= 0 || o.subtotal <= 0) return 0;
    final d = (_subtotal * (o.discount / o.subtotal) * 100).floor() / 100;
    return d >= _subtotal ? 0 : d;
  }

  double get _total => _subtotal + widget.order.deliveryFee - _discount;

  void _setQty(int index, int qty) {
    if (qty < 0 || qty > kMaxLineQty) return;
    setState(() => _lines[index] = _lines[index].withQty(qty));
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await OrderService.updateOrder(
        order: widget.order,
        items: _lines,
        name: _name.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'[\s\-]'), ''),
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        courierNotes: _courierNotes.text.trim(),
      );
      messenger.showSnackBar(const SnackBar(content: Text('تم تعديل الطلب.')));
      navigator.pop();
    } on OrderLimitException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تعديل الطلب (${e.runtimeType}).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final remaining = _lines.where((l) => l.qty > 0).length;

    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'تعديل الطلب'),
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'المنتجات',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _lines.length; i++) _lineRow(i),
                  const SizedBox(height: 4),
                  Text(
                    'المجموع: ${formatPrice(_subtotal)}'
                    '${_discount > 0 ? '  •  خصم: ${formatPrice(_discount)}' : ''}'
                    '  •  توصيل: ${formatPrice(widget.order.deliveryFee)}',
                    style: TextStyle(color: kMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الإجمالي: ${formatPrice(_total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'بيانات التوصيل',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    inputFormatters: [LengthLimitingTextInputFormatter(80)],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'اكتب اسمك' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الموبايل',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => isValidEgyptianMobile(v ?? '')
                        ? null
                        : 'اكتب رقم موبايل مصري صحيح (11 رقم)',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'العنوان بالتفصيل',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'اكتب العنوان بالتفصيل عشان المندوب يوصلك'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات للمحل (اختياري)',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _courierNotes,
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات للمندوب (اختياري)',
                      prefixIcon: Icon(Icons.two_wheeler_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: (_saving || remaining == 0) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ التعديلات'),
                  ),
                  if (remaining == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'شلت كل الأصناف. ارجع واستخدم "حذف الطلب" لو عايز تلغيه.',
                        style: TextStyle(color: kDanger),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(int i) {
    final l = _lines[i];
    final removed = l.qty == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: removed ? TextDecoration.lineThrough : null,
                    color: removed ? kMuted : null,
                  ),
                ),
                Text(
                  formatPrice(l.price),
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: removed ? null : () => _setQty(i, l.qty - 1),
            icon: Icon(
              l.qty == 1 ? Icons.delete_outline : Icons.remove_circle_outline,
              color: l.qty == 1 ? kDanger : null,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${l.qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: l.qty >= kMaxLineQty ? null : () => _setQty(i, l.qty + 1),
            icon: Icon(Icons.add_circle_outline, color: kPrimary),
          ),
        ],
      ),
    );
  }
}
