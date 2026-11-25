import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/quick_courier_order.dart';
import '../services/delivery_pin_service.dart';
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
  int _loadGeneration = 0;
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
    if (!mounted || _busy) return;
    final generation = ++_loadGeneration;
    setState(() {
      _busy = true;
      _contact = null;
    });
    try {
      final order = await widget.backend.loadOrder(widget.orderId);
      final contact = order?.canSeeContact == true
          ? await widget.backend.loadContact(widget.orderId).catchError((_) => null)
          : null;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _order = order;
        _contact = contact;
        _error = order == null ? 'الطلب مش موجود أو مش متاح ليك.' : null;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          // Never display an old order or contact details after a failed reload.
          _order = null;
          _contact = null;
          _error = 'تعذر تحميل الطلب. اسحب للتحديث.';
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _busy = false);
    }
  }

  /// ينفّذ عملية على الـWorker ويحدّث الشاشة من رده.
  Future<void> _act(String action, [Map<String, dynamic> body = const {}, String? done]) async {
    if (_busy) return;
    ++_loadGeneration;
    setState(() => _busy = true);
    try {
      final updated = await widget.backend.act(widget.orderId, action, body);
      QuickContact? contact = updated.canSeeContact ? _contact : null;
      if (updated.canSeeContact && contact == null) {
        contact = await widget.backend.loadContact(widget.orderId).catchError((_) => null);
      }
      if (!mounted) return;
      if (action == 'deliver' && updated.step == QuickCourierStep.delivered) {
        // Do not retain the customer's delivery PIN after successful verification.
        _pinCtrl.clear();
      }
      setState(() {
        _order = updated;
        _contact = contact;
        _error = null;
      });
      if (done != null) _toast(done);
    } catch (e) {
      if (!mounted) return;
      _toast(e is StateError ? e.message : 'تعذر تنفيذ العملية. حاول تاني.');
      setState(() => _busy = false);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _call() async {
    // Never dial a cached phone after the server revoked the assignment.
    if (_order?.canSeeContact != true) return;
    final phone = _contact?.phone.trim() ?? '';
    if (phone.isEmpty) return;
    // Build a tel URI without interpreting # or ? in a phone number as URL delimiters.
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (!await launchUrl(uri) && mounted) _toast('تعذر فتح الاتصال.');
    } catch (_) {
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
    // Ask for the amount first: cancelling must not upload an orphaned image.
    final amount = await _askAmount('مبلغ الفاتورة كام جنيه؟');
    if (amount == null || !mounted || _busy) return;
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

  Widget _bigButton(String label, IconData icon, VoidCallback? onPressed, {Key? key}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: Brand.green,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label),
      ),
    );
  }

  Widget _card({required List<Widget> children, bool receipt = false}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: receipt ? const Color(0xFFFFFEF8) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kLine),
          boxShadow: [
            BoxShadow(
              color: Brand.ink.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 17 : 15))),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                softWrap: true,
                style: TextStyle(
                  fontSize: bold ? 18 : 15,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _totalsCard(
    QuickTotalsView t, {
    String title = 'الحساب النهائي',
    bool delivered = false,
  }) {
    return _card(children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      _row('الفواتير', formatPiastres(t.purchases)),
      _row('أجرة التوصيل', formatPiastres(t.delivery)),
      _row('رسوم وصّلي', formatPiastres(t.serviceFee)),
      if (t.prepaid > 0) _row('المقدم المحوّل', '- ${formatPiastres(t.prepaid)}'),
      const Divider(),
      t.due >= 0
          ? _row(delivered ? 'المبلغ عند التسليم' : 'تحصّل من العميل',
              formatPiastres(t.due), bold: true)
          : _row(delivered ? 'الرد عند التسليم' : 'ترجّع للعميل',
              formatPiastres(-t.due), bold: true),
    ]);
  }

  Widget _requestDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < (constraints.maxWidth / 8).floor(); i++)
            SizedBox(width: 4, height: 1, child: ColoredBox(color: kMuted)),
        ],
      ),
    ),
  );

  Widget _requestCard(QuickCourierOrder o) {
    return _card(receipt: true, children: [
      Row(
        children: [
          Icon(Icons.receipt_long_rounded, color: Brand.green, size: 30),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'فاتورة مشتريات العميل',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(quickStepLabel(o.step), style: TextStyle(color: kMuted)),
      if (o.step == QuickCourierStep.available)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'الطلب متاح للقبول. العنوان التفصيلي ورقم العميل يظهروا بعد تعيينك عليه بس.',
            key: Key('quick-before-assignment-note'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        )
      else if (o.isActive)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'الطلب مُسند ليك. راجع المشتريات وكمّل الخطوة الموضحة تحت الفاتورة.',
            key: Key('quick-after-assignment-note'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      if (!o.hasCustomerRequest)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'مفيش أصناف أو تفاصيل مشتريات ظاهرة في الطلب ده. اسحب لتحديث التفاصيل، ولو فضلت فاضية تواصل مع الدعم قبل الشراء.',
            key: Key('quick-request-empty-warning'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      if (o.area.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('الحي: ${o.area}', style: TextStyle(color: kMuted)),
      ],
      if (!o.canSeeContact)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'العنوان ورقم التليفون بيظهروا بعد قبول الطلب فقط.',
            style: TextStyle(fontSize: 12, color: kMuted),
          ),
        ),
      for (final (index, store) in o.stores.indexed) ...[
        _requestDivider(),
        Text(
          store.name.isEmpty
              ? (o.stores.length > 1 ? 'محل ${index + 1} · أي محل قريب' : 'أي محل قريب')
              : store.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        if (store.pricedItems.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('الصنف', style: TextStyle(color: kMuted))),
              Text('الكمية', style: TextStyle(color: kMuted)),
            ],
          ),
          for (final item in store.pricedItems)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontSize: 17, height: 1.4)),
                        Text('تقريبًا ${formatPiastres(item.subtotalPiastres)}',
                            style: TextStyle(color: kMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${item.qty}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
        if (store.items.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              store.items.trim(),
              style: const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ),
      ],
      if (o.notes.isNotEmpty) ...[
        _requestDivider(),
        const Text('ملاحظات العميل', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(o.notes),
      ],
      if ((o.approxTotalPiastres ?? 0) > 0) ...[
        _requestDivider(),
        _row('الإجمالي التقريبي', formatPiastres(o.approxTotalPiastres!), bold: true),
        Text('الحساب النهائي من الفواتير.', style: TextStyle(color: kMuted)),
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
      if (c.notes.isNotEmpty) Text(c.notes, style: TextStyle(color: kMuted)),
      if (c.address.isNotEmpty || c.phone.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (c.phone.isNotEmpty)
              FilledButton.icon(
                key: const Key('quick-call'),
                onPressed: _busy ? null : _call,
                icon: const Icon(Icons.call_rounded, size: 22),
                label: const Text('اتصل بالعميل'),
              ),
            if (c.address.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final opened = await openInMaps(c.address);
                          if (!opened && mounted) _toast('تعذر فتح الخريطة.');
                        } catch (_) {
                          if (mounted) _toast('تعذر فتح الخريطة.');
                        }
                      },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('افتح الخريطة'),
              ),
          ],
        ),
      ],
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
              }, key: const Key('quick-advance-received')),
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
        final pin = DeliveryPinService.normalize(_pinCtrl.text);
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
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
              style: const TextStyle(fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.w900),
              decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
            ),
          ]),
          _bigButton(
            'تم التسليم',
            Icons.done_all,
            o.canEnterPin && pin != null
                ? () => _act('deliver', {'pin': pin}, 'تم التسليم. شكرًا!')
                : null,
            key: const Key('quick-deliver'),
          ),
        ];

      case QuickCourierStep.delivered:
        return [
          _card(children: const [
            Icon(Icons.check_circle_outline, size: 36, color: Colors.green),
            SizedBox(height: 8),
            Text('الطلب اتسلّم', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          if (o.totals != null) _totalsCard(o.totals!, delivered: true),
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
          title: const Text('تفاصيل الطلب السريع'),
          actions: [
            if (o != null && o.canRelease)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('تسيب الطلب ده لمندوب تاني؟')) {
                          await _act('release', const {}, 'سبت الطلب');
                          // Only leave the screen if the Worker confirmed release.
                          if (mounted && _order?.step == QuickCourierStep.available) {
                            Navigator.of(context).pop();
                          }
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
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      if (o == null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ],
                  ),
                ),
              if (o == null && _busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('جاري تحميل تفاصيل الطلب...')),
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
