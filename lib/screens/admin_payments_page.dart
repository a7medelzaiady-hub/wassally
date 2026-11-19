import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/order.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _why(Object e) => e is StateError ? e.message : e.toString();

// ───────────────────────── إعدادات المحافظ ─────────────────────────

/// المدير: تفعيل الدفع بفودافون كاش / InstaPay والأرقام اللي العميل يحوّل عليها.
class AdminPaymentSettingsPage extends StatefulWidget {
  const AdminPaymentSettingsPage({super.key});

  @override
  State<AdminPaymentSettingsPage> createState() =>
      _AdminPaymentSettingsPageState();
}

class _AdminPaymentSettingsPageState extends State<AdminPaymentSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _vodafone = TextEditingController();
  final _instapay = TextEditingController();
  final _note = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    PaymentService.settings(refresh: true).then((s) {
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _vodafone.text = s.vodafoneCashNumber;
        _instapay.text = s.instapayAddress;
        _note.text = s.note;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _vodafone.dispose();
    _instapay.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    if (_enabled &&
        _vodafone.text.trim().isEmpty &&
        _instapay.text.trim().isEmpty) {
      _toast(context, 'اكتب رقم فودافون كاش أو عنوان InstaPay قبل التفعيل.');
      return;
    }
    setState(() => _saving = true);
    try {
      await PaymentService.saveSettings(PaymentSettings(
        enabled: _enabled,
        vodafoneCashNumber: _vodafone.text,
        instapayAddress: _instapay.text,
        note: _note.text,
      ));
      if (mounted) _toast(context, 'تم حفظ إعدادات الدفع.');
    } catch (e) {
      if (mounted) _toast(context, 'تعذر الحفظ: ${_why(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'الدفع بالمحفظة'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        SwitchListTile(
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                          title: const Text(
                            'تفعيل الدفع بالمحفظة',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text(
                            'العميل يحوّل ويكتب رقم العملية، وإنت تأكد التحويل قبل ما المحل يجهّز.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _vodafone,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'رقم فودافون كاش (سيبه فاضي لو مش متاح)',
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null;
                            return RegExp(r'^01[0125][0-9]{8}$').hasMatch(t)
                                ? null
                                : 'رقم موبايل مصري صحيح (11 رقم)';
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _instapay,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'عنوان InstaPay (مثال: name@instapay)',
                          ),
                          validator: (v) => (v ?? '').trim().length > 80
                              ? 'العنوان طويل'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _note,
                          maxLines: 2,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة للعميل (اختياري)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('حفظ'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تحويلات بانتظار التأكيد ─────────────────────────

/// المدير: مراجعة التحويلات (رقم العملية والمبلغ) وتأكيدها أو رفضها بسبب.
class AdminPendingPaymentsPage extends StatefulWidget {
  const AdminPendingPaymentsPage({super.key});

  @override
  State<AdminPendingPaymentsPage> createState() =>
      _AdminPendingPaymentsPageState();
}

class _AdminPendingPaymentsPageState extends State<AdminPendingPaymentsPage> {
  late final Stream<List<AppOrder>> _stream = PaymentService.watchPending();
  final Set<String> _busy = {};

  Future<void> _confirm(AppOrder o) async {
    final ok = await confirmDialog(
      context,
      title: 'تأكيد التحويل',
      message:
          'اتأكدت إن ${formatPrice(o.total)} وصلت على ${PaymentMethod.labelOf(o.paymentMethod)} '
          'برقم العملية ${o.paymentRef}؟',
      confirmLabel: 'أيوه، وصل',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(o.id));
    try {
      await PaymentService.confirm(o);
      if (mounted) _toast(context, 'تم تأكيد التحويل، والمحل يقدر يجهّز الطلب.');
    } catch (e) {
      if (mounted) _toast(context, _why(e));
    } finally {
      if (mounted) setState(() => _busy.remove(o.id));
    }
  }

  Future<void> _reject(AppOrder o) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض التحويل'),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'السبب (هيوصل للعميل)',
            hintText: 'مثال: رقم العملية مش موجود أو المبلغ ناقص',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !mounted) return;
    setState(() => _busy.add(o.id));
    try {
      await PaymentService.reject(o, reason);
      if (mounted) _toast(context, 'تم رفض التحويل وإبلاغ العميل.');
    } catch (e) {
      if (mounted) _toast(context, _why(e));
    } finally {
      if (mounted) setState(() => _busy.remove(o.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'تحويلات بانتظار التأكيد'),
          Expanded(
            child: StreamBuilder<List<AppOrder>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(child: Text('تعذر تحميل التحويلات.'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return const Center(child: Text('مفيش تحويلات مستنية تأكيد.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final busy = _busy.contains(o.id);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${o.storeName} — ${o.displayCustomer}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${PaymentMethod.labelOf(o.paymentMethod)} • ${formatPrice(o.total)}',
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              'رقم العملية: ${o.paymentRef}',
                              style: TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: busy ? null : () => _confirm(o),
                                    child: const Text('تأكيد'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: busy ? null : () => _reject(o),
                                    child: const Text('رفض'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
