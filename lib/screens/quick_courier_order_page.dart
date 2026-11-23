import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/quick_courier_order.dart';
import '../services/quick_courier_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/dialog_controllers.dart';
import '../utils/maps.dart';
import 'quick_courier_orders_page.dart' show quickStepLabel;

/// رحلة المندوب في طلب سريع: زرار واحد كبير لكل خطوة، وأقل كتابة ممكنة (أرقام وصور بس).
/// كل الكتابة عن طريق الـWorker، والطلب بيتحدث من رده. مفيش مستمعات؛ زرار «تحديث» بقراءة واحدة.
class QuickCourierOrderPage extends StatefulWidget {
  final String orderId;
  final QuickCourierOrder? initial;
  final QuickCourierBackend backend;
  const QuickCourierOrderPage({
    super.key,
    required this.orderId,
    this.initial,
    this.backend = const FirebaseQuickCourierBackend(),
  });

  @override
  State<QuickCourierOrderPage> createState() => _QuickCourierOrderPageState();
}

class _QuickCourierOrderPageState extends State<QuickCourierOrderPage> {
  QuickCourierOrder? _order;
  QuickContact? _contact;
  bool _busy = false;
  String? _error;
  final _estimateCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    _deliveryCtrl.addListener(() => setState(() {}));
    _pinCtrl.addListener(() => setState(() {}));
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _estimateCtrl.dispose();
    _deliveryCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _contact = null;
    });
    try {
      final order = await widget.backend.loadOrder(widget.orderId);
      final contact = order?.canSeeContact == true
          ? await widget.backend.loadContact(widget.orderId).catchError((_) => null)
          : null;
      if (!mounted) return;
      setState(() {
        _order = order;
        _contact = contact;
        _error = order == null ? 'الطلب مش موجود أو مش متاح ليك.' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _order = null;
          _error = 'تعذر تحميل الطلب. اسحب للتحديث.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ينفّذ عملية على الـWorker ويحدّث الشاشة من رده.
  Future<void> _act(String action, [Map<String, dynamic> body = const {}, String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.backend.act(widget.orderId, action, body);
      QuickContact? contact = updated.canSeeContact ? _contact : null;
      if (updated.canSeeContact && contact == null) {
        contact = await widget.backend.loadContact(widget.orderId).catchError((_) => null);
      }
      if (!mounted) return;
      setState(() {
        _order = updated;
        _contact = contact;
        _error = null;
      });
      if (done != null) _toast(done);
    } catch (e) {
      if (!mounted) return;
      _toast(e is StateError ? e.message : 'تعذر تنفيذ العملية. حاول تاني.');
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _call() async {
    final phone = _contact?.phone ?? '';
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri)) {
      if (mounted) _toast('تعذر فتح الاتصال.');
    }
  }

  /// نافذة رقم بالجنيه (لمبلغ الفاتورة أو التحويل). بترجع القروش أو null.
  Future<int?> _askAmount(String title, {int? initial}) async {
    final ctrl = TextEditingController(
      text: initial == null ? '' : (initial % 100 == 0 ? '${initial ~/ 100}' : (initial / 100).toStringAsFixed(2)),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final value = parsePoundsToPiastres(ctrl.text);
            return AlertDialog(
              title: Text(title),
              content: _MoneyField(controller: ctrl, autofocus: true, onChanged: () => setLocal(() {})),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: value == null || value <= 0 ? null : () => Navigator.of(ctx).pop(value),
                  child: const Text('تمام'),
                ),
              ],
            );
          },
        ),
      ),
    );
    disposeAfterDialogCloses(ctrl);
    return result;
  }

  Future<void> _addReceipt() async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    String? url;
    try {
      url = await widget.backend.captureReceipt(order.id);
    } catch (e) {
      if (mounted) _toast(e is StateError ? e.message : 'تعذر رفع صورة الفاتورة. حاول تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (url == null || !mounted) return;
    final amount = await _askAmount('مبلغ الفاتورة كام جنيه؟');
    if (amount == null || !mounted) return;
    await _act('receipt', {'imageUrl': url, 'amountPiastres': amount}, 'اتضافت الفاتورة');
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Text(message, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('لا')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('أيوه')),
          ],
        ),
      ),
    );
    return ok == true;
  }

  // ───────────── واجهة ─────────────

  Widget _bigButton(String label, IconData icon, VoidCallback? onPressed, {Color? color, Key? key}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: color ?? Brand.green,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 17 : 15))),
            Text(value, style: TextStyle(fontSize: bold ? 18 : 15, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      );

  Widget _totalsCard(QuickTotalsView t, {String title = 'الكشف'}) {
    return _card(children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      _row('الفواتير', formatPiastres(t.purchases)),
      _row('أجرة التوصيل', formatPiastres(t.delivery)),
      _row('رسوم وصّلي', formatPiastres(t.serviceFee)),
      if (t.prepaid > 0) _row('المقدم المحوّل', '- ${formatPiastres(t.prepaid)}'),
      const Divider(),
      t.due >= 0
          ? _row('تحصّل من العميل', formatPiastres(t.due), bold: true)
          : _row('ترجّع للعميل', formatPiastres(-t.due), bold: true),
    ]);
  }

  Widget _requestCard(QuickCourierOrder o) {
    return _card(children: [
      Text('طلب ${o.customerFirstName.isEmpty ? 'العميل' : o.customerFirstName}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      if (o.area.isNotEmpty)
        Text('📍 منطقة العميل: ${o.area}', style: TextStyle(color: kMuted)),
      if (!o.canSeeContact)
        Text('العنوان التفصيلي ورقم الهاتف يظهران بعد قبول الطلب فقط.',
            style: TextStyle(color: kMuted, fontSize: 12)),
      for (final s in o.stores) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.storefront, color: Brand.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(s.name.isEmpty ? 'أي محل قريب' : s.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
        for (final p in s.pricedItems)
          _row('• ${p.name} × ${p.qty}', 'تقريبًا ${formatPiastres(p.subtotalPiastres)}'),
        if (s.items.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(s.items, style: const TextStyle(fontSize: 15, height: 1.5)),
        ),
      ],
      if (o.notes.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('ملاحظات: ${o.notes}', style: TextStyle(color: kMuted)),
      ],
      if ((o.approxTotalPiastres ?? 0) > 0) ...[
        const Divider(height: 24),
        _row('الإجمالي التقريبي', formatPiastres(o.approxTotalPiastres!), bold: true),
        Text('الأسعار تقريبية وقد تزيد أو تقل حسب المحل. الحساب النهائي من الفواتير.',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
      ],
    ]);
  }

  Widget _contactCard(QuickCourierOrder o) {
    final c = _contact;
    if (!o.canSeeContact) return const SizedBox.shrink();
    if (c == null) {
      return _card(children: [
        const Text('بيانات التواصل غير متاحة حاليًا.'),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: const Text('إعادة المحاولة'),
        ),
      ]);
    }
    return _card(children: [
      if (c.name.isNotEmpty) Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      if (c.address.isNotEmpty) Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(c.address, style: const TextStyle(height: 1.5)),
      ),
      if (c.address.isEmpty) const Text('العنوان التفصيلي غير متاح'),
      if (c.address.isNotEmpty)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final opened = await openInMaps(c.address);
                  if (!opened && mounted) _toast('تعذر فتح الخريطة.');
                },
          icon: const Icon(Icons.map_outlined),
          label: const Text('افتح الخريطة'),
        ),
      if (c.notes.isNotEmpty) Text(c.notes, style: TextStyle(color: kMuted)),
      const SizedBox(height: 10),
      _bigButton('اتصل بالعميل', Icons.call, c.phone.isEmpty ? null : _call,
          color: const Color(0xFF2563EB), key: const Key('quick-call')),
    ]);
  }

  List<Widget> _stepWidgets(QuickCourierOrder o) {
    switch (o.step) {
      case QuickCourierStep.available:
        return [
          _bigButton('اقبل الطلب', Icons.check_circle, () => _act('accept', const {}, 'الطلب بقى معاك. اتصل بالعميل.'),
              key: const Key('quick-accept')),
        ];

      case QuickCourierStep.estimate:
        final estimate = parsePoundsToPiastres(_estimateCtrl.text);
        return [
          _card(children: [
            const Text('بعد المكالمة: المشتريات تقريبًا كام جنيه؟',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _MoneyField(controller: _estimateCtrl, onChanged: () => setState(() {}), key: const Key('quick-estimate')),
            const SizedBox(height: 8),
            Text(
              'انت بتدفع المشتريات، والعميل يدفع الباقي عند الاستلام. لو العميل حوّل لك مقدم، هتأكد استلامه وانت بتشتري.',
              style: TextStyle(color: kMuted, height: 1.4),
            ),
            if (o.advanceSentAt != null) ...[
              const SizedBox(height: 8),
              Text('العميل حوّل مقدم ${formatPiastres(o.advanceAmountPiastres ?? 0)}، هتأكده بعد ما تبدأ.',
                  style: TextStyle(color: Brand.green, fontWeight: FontWeight.w700)),
            ],
          ]),
          _bigButton(
            'ابدأ الشراء',
            Icons.shopping_cart,
            estimate == null || estimate <= 0
                ? null
                : () => _act('start-purchase', {'estimatedPurchasesPiastres': estimate}),
            key: const Key('quick-start'),
          ),
        ];

      case QuickCourierStep.purchasing:
        final delivery = parsePoundsToPiastres(_deliveryCtrl.text);
        final preview = delivery == null ? null : o.previewTotals(delivery);
        final deliveryTooHigh = delivery != null && delivery > o.maximumDeliveryPiastres;
        return [
          if (o.hasPendingAdvance)
            _card(children: [
              const Text('العميل بيقول إنه حوّل مقدم:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              _row('المبلغ', formatPiastres(o.advanceAmountPiastres ?? 0), bold: true),
              if (o.advanceReference.isNotEmpty) _row('رقم العملية', o.advanceReference),
              Text('اتأكد من محفظتك. المقدم بيتخصم من الكشف بعد تأكيدك بس.', style: TextStyle(color: kMuted)),
              const SizedBox(height: 8),
              _bigButton('وصلني التحويل', Icons.verified, () async {
                final amount = await _askAmount('المبلغ اللي وصلك فعلًا كام جنيه؟', initial: o.advanceAmountPiastres);
                if (amount == null) return;
                await _act('advance-received', {'amountPiastres': amount}, 'اتسجل المقدم');
              }, color: const Color(0xFF2563EB), key: const Key('quick-advance-received')),
            ]),
          if (o.advanceConfirmedAt != null)
            _card(children: [
              _row('مقدم مؤكد من العميل', formatPiastres(o.advanceAmountPiastres ?? 0), bold: true),
            ]),
          if (o.summaryRejectedAt != null)
            _card(children: [
              Text('العميل رفض الكشف${o.summaryRejectReason.isEmpty ? '' : ': ${o.summaryRejectReason}'}',
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w800)),
              const Text('اتصل بيه، وعدّل الفواتير أو الأجرة، وابعت كشف جديد.'),
            ]),
          _card(children: [
            Text('الفواتير (${o.receipts.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            for (var i = 0; i < o.receipts.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(o.receipts[i].imageUrl, width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.receipt_long, size: 40)),
                ),
                title: Text(formatPiastres(o.receipts[i].amountPiastres),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  tooltip: 'شيل الفاتورة',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm('تشيل الفاتورة دي؟')) {
                            await _act('receipt-remove', {'index': i});
                          }
                        },
                ),
              ),
            if (o.receipts.isNotEmpty) _row('مجموع الفواتير', formatPiastres(o.receiptsTotalPiastres), bold: true),
            const SizedBox(height: 8),
            _bigButton('صوّر فاتورة', Icons.photo_camera, _addReceipt, key: const Key('quick-receipt')),
          ]),
          _card(children: [
            const Text('أجرة التوصيل كام جنيه؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _MoneyField(controller: _deliveryCtrl, key: const Key('quick-delivery')),
            if (deliveryTooHigh)
              Text('أقصى أجرة ${formatPiastres(o.maximumDeliveryPiastres)}',
                  style: TextStyle(color: Colors.red.shade700)),
          ]),
          if (preview != null && o.receipts.isNotEmpty && !deliveryTooHigh) _totalsCard(preview, title: 'الكشف اللي هيوصل للعميل'),
          _bigButton(
            'ابعت الكشف للعميل',
            Icons.send,
            o.receipts.isEmpty || delivery == null || deliveryTooHigh
                ? null
                : () => _act('submit-summary', {'deliveryPiastres': delivery}, 'الكشف وصل للعميل'),
            key: const Key('quick-submit-summary'),
          ),
        ];

      case QuickCourierStep.waitCustomer:
        return [
          if (o.totals != null) _totalsCard(o.totals!),
          _card(children: const [
            Icon(Icons.hourglass_top, size: 40),
            SizedBox(height: 8),
            Text('مستني العميل يوافق على الكشف. ممنوع التسليم قبل موافقته.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.5)),
          ]),
          _bigButton('تحديث', Icons.refresh, _refresh, key: const Key('quick-refresh')),
        ];

      case QuickCourierStep.deliver:
        final pin = _pinCtrl.text.trim();
        return [
          if (o.totals != null) _totalsCard(o.totals!, title: 'العميل وافق على الكشف ✅'),
          _card(children: [
            const Text('اطلب من العميل رمز التسليم (4 أرقام):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('quick-pin'),
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.w900),
              decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
            ),
          ]),
          _bigButton(
            'تم التسليم',
            Icons.done_all,
            o.canEnterPin && RegExp(r'^\d{4}$').hasMatch(pin)
                ? () => _act('deliver', {'pin': pin}, 'تم التسليم. شكرًا!')
                : null,
            key: const Key('quick-deliver'),
          ),
        ];

      case QuickCourierStep.delivered:
        return [
          if (o.totals != null) _totalsCard(o.totals!),
          _card(children: const [
            Icon(Icons.check_circle, size: 48, color: Colors.green),
            Text('الطلب اتسلّم', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ];

      case QuickCourierStep.cancelled:
        return [
          _card(children: const [
            Icon(Icons.cancel, size: 48, color: Colors.red),
            Text('الطلب ده اتلغى', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(o == null ? 'طلب سريع' : quickStepLabel(o.step)),
          actions: [
            if (o != null && o.canRelease)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('تسيب الطلب ده لمندوب تاني؟')) {
                          await _act('release', const {}, 'سبت الطلب');
                          if (mounted) Navigator.of(context).pop();
                        }
                      },
                child: const Text('سيب الطلب'),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              if (o != null) ...[
                _requestCard(o),
                _contactCard(o),
                ..._stepWidgets(o),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// خانة مبلغ بالجنيه: كيبورد أرقام وخط كبير.
class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback? onChanged;
  const _MoneyField({super.key, required this.controller, this.autofocus = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      decoration: const InputDecoration(
        suffixText: 'جنيه',
        border: OutlineInputBorder(),
      ),
    );
  }
}
