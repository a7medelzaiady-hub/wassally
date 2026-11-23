import 'dart:math';

import 'package:flutter/material.dart';

import '../services/order_gateway.dart';
import '../widgets/referral_code_card.dart';

const _campaignTitle = 'شير بكودك واكسب هدايا';

class ReferralCampaignLink extends StatelessWidget {
  const ReferralCampaignLink({super.key, this.storeOwner = false});

  final bool storeOwner;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.card_giftcard),
      title: const Text(_campaignTitle),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReferralCampaignPage(storeOwner: storeOwner),
      )),
    );
  }
}

class ReferralCampaignPage extends StatefulWidget {
  const ReferralCampaignPage({super.key, required this.storeOwner});

  final bool storeOwner;

  @override
  State<ReferralCampaignPage> createState() => _ReferralCampaignPageState();
}

class _ReferralCampaignPageState extends State<ReferralCampaignPage> {
  late Future<Map<String, dynamic>> _campaign = _load();

  String? _payoutKey;
  bool _requestingPayout = false;

  Future<void> _requestPayout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب صرف الرصيد النقدي'),
        content: const Text('هيتسجل طلب للإدارة لصرف كامل رصيد المكافآت النقدية المتاح.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اطلب الصرف')),
        ],
      ),
    );
    if (!mounted || confirmed != true || _requestingPayout) return;
    setState(() => _requestingPayout = true);
    final random = Random.secure();
    _payoutKey ??= List.generate(12, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    try {
      await OrderGateway.referralPayout(action: 'request', requestId: _payoutKey);
      _payoutKey = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل طلب الصرف للإدارة.')),
      );
      setState(() => _campaign = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_failureMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingPayout = false);
    }
  }

  Future<Map<String, dynamic>> _load() => OrderGateway.referralCampaign(
        channel: widget.storeOwner ? 'store_owner' : 'customer',
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإحالات')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _campaign,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_failureMessage(snapshot.error)),
                  TextButton(
                    onPressed: () => setState(() => _campaign = _load()),
                    child: const Text('حاول تاني'),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final balance = data['balance'];
          num amount(String field) {
            if (balance is Map<String, dynamic> && balance[field] is num) {
              return balance[field] as num;
            }
            return 0;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ReferralCodeCard(serverIssuedCode: data['code'] as String?),
              if (data['marketerCode'] is String) ...[
                const ListTile(title: Text('كود المسوّق')),
                ReferralCodeCard(serverIssuedCode: data['marketerCode'] as String),
              ],
              ListTile(title: const Text('النقاط'), trailing: Text('${amount('points')}')),
              if (widget.storeOwner || data['marketerCode'] is String)
                ListTile(
                  title: const Text('رصيد المكافآت النقدية'),
                  trailing: Text('${(amount('cashMinor') / 100).toStringAsFixed(2)} ج.م'),
                ),
              if (amount('cashMinor') > 0)
                OutlinedButton(
                  onPressed: _requestingPayout ? null : _requestPayout,
                  child: const Text('طلب صرف الرصيد النقدي'),
                ),
              if (widget.storeOwner)
                ListTile(
                  title: const Text('رصيد خصم العمولة'),
                  trailing: Text('${(amount('commissionDiscountMinor') / 100).toStringAsFixed(2)} ج.م'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AdminReferralCampaignPage extends StatefulWidget {
  const AdminReferralCampaignPage({super.key});

  @override
  State<AdminReferralCampaignPage> createState() => _AdminReferralCampaignPageState();
}

class _AdminReferralCampaignPageState extends State<AdminReferralCampaignPage> {
  final _uid = TextEditingController();
  bool _loading = false;
  String? _code;
  String? _error;

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _issue() async {
    final uid = _uid.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid)) {
      setState(() => _error = 'اكتب معرّف حساب المسوّق.');
      return;
    }
    setState(() {
      _loading = true;
      _code = null;
      _error = null;
    });
    try {
      final result = await OrderGateway.referralCampaign(
        channel: 'marketer',
        marketerUid: uid,
      );
      if (mounted) setState(() => _code = result['code'] as String?);
    } catch (error) {
      if (mounted) setState(() => _error = _failureMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الإحالات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _uid,
            enabled: !_loading,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'معرّف حساب المسوّق'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _issue,
            child: const Text('إصدار كود للمسوّق'),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_code != null) ReferralCodeCard(serverIssuedCode: _code),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const _ReferralSettingsPage(),
            )),
            child: const Text('إعدادات المكافآت'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const _ReferralPayoutsPage(),
            )),
            child: const Text('طلبات الصرف'),
          ),
        ],
      ),
    );
  }
}

String _failureMessage(Object? error) =>
    error is StateError ? error.message : 'تعذر تحميل الإحالات.';

class _ReferralSettingsPage extends StatefulWidget {
  const _ReferralSettingsPage();

  @override
  State<_ReferralSettingsPage> createState() => _ReferralSettingsPageState();
}

class _ReferralSettingsPageState extends State<_ReferralSettingsPage> {
  late final _initial = OrderGateway.referralSettings();
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  Future<void> _save(int version, Map<String, Map<String, dynamic>> policies) async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await OrderGateway.referralSettings(
        settings: {'version': version + 1, 'policies': policies},
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _failureMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المكافآت')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _initial,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(_failureMessage(snapshot.error)));
          final settings = snapshot.data;
          final raw = settings?['policies'] as Map<String, dynamic>?;
          final policies = <String, Map<String, dynamic>>{};
          return Form(
            key: _form,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                for (final (channel, label, unit) in const [
                  ('customer', 'إحالات العملاء', 'points'),
                  ('marketer', 'إحالات المسوقين', 'cash_minor'),
                  ('store_owner', 'دعوة محل جديد', 'cash_minor'),
                  ('store_customer', 'دعوة عميل بواسطة محل', 'cash_minor'),
                ])
                  _PolicyEditor(
                    channel: channel,
                    label: label,
                    unit: unit,
                    initial: raw?[channel] as Map<String, dynamic>?,
                    onSave: (policy) => policies[channel] = policy,
                  ),
                if (_error != null) Text(_error!),
                FilledButton(
                  onPressed: _saving ? null : () => _save(settings?['version'] as int? ?? 0, policies),
                  child: const Text('حفظ الإعدادات'),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PolicyEditor extends StatefulWidget {
  const _PolicyEditor({
    required this.channel,
    required this.label,
    required this.unit,
    required this.initial,
    required this.onSave,
  });

  final String channel;
  final String label;
  final String unit;
  final Map<String, dynamic>? initial;
  final ValueChanged<Map<String, dynamic>> onSave;

  @override
  State<_PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends State<_PolicyEditor> {
  late bool _enabled = widget.initial?['enabled'] == true;
  late String _unit = widget.initial?['unit'] as String? ?? widget.unit;
  late int _amount = widget.initial?['amount'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.label),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            if (widget.channel == 'store_owner' || widget.channel == 'store_customer')
              DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'نوع المكافأة'),
                items: const [
                  DropdownMenuItem(value: 'cash_minor', child: Text('فلوس')),
                  DropdownMenuItem(value: 'commission_discount_minor', child: Text('خصم عمولة')),
                ],
                onChanged: (value) => setState(() => _unit = value ?? widget.unit),
              ),
            TextFormField(
              initialValue: '$_amount',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _unit == 'points' ? 'عدد النقاط' : 'المبلغ بالقروش',
              ),
              validator: (value) {
                final amount = int.tryParse(value?.trim() ?? '');
                return amount == null || amount < (_enabled ? 1 : 0)
                    ? 'اكتب قيمة صحيحة للمكافأة.'
                    : null;
              },
              onSaved: (value) => _amount = int.parse(value!.trim()),
            ),
            TextFormField(
              initialValue: widget.initial?['maxPerInviter']?.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'حد المكافآت لكل مُحيل (اختياري)'),
              validator: (value) {
                final text = value?.trim() ?? '';
                return text.isNotEmpty && (int.tryParse(text) ?? -1) < 0
                    ? 'اكتب حدًا صحيحًا.'
                    : null;
              },
              onSaved: (value) {
                final limit = int.tryParse(value?.trim() ?? '');
                widget.onSave({
                  'channel': widget.channel,
                  'enabled': _enabled,
                  'unit': _unit,
                  'amount': _amount,
                  if (limit != null) 'maxPerInviter': limit,
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferralPayoutsPage extends StatefulWidget {
  const _ReferralPayoutsPage();

  @override
  State<_ReferralPayoutsPage> createState() => _ReferralPayoutsPageState();
}

class _ReferralPayoutsPageState extends State<_ReferralPayoutsPage> {
  late Future<List<dynamic>> _pending = _load();
  bool _saving = false;

  Future<List<dynamic>> _load() async {
    final result = await OrderGateway.referralPayout(action: 'list');
    return result['pending'] as List<dynamic>;
  }

  Future<void> _claim(String id) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await OrderGateway.referralPayout(action: 'claim', payoutId: id);
      if (mounted) setState(() => _pending = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_failureMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolve(String id, {required bool paid}) async {
    var reference = '';
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paid ? 'تسجيل تحويل تم بالفعل' : 'رفض طلب الصرف'),
        content: Form(
          key: form,
          child: TextFormField(
            maxLength: 120,
            onChanged: (value) => reference = value.trim(),
            validator: (_) => reference.length < 5 ? 'اكتب ٥ حروف أو أرقام على الأقل.' : null,
            decoration: InputDecoration(labelText: paid ? 'مرجع التحويل' : 'سبب الرفض'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _saving) return;
    setState(() => _saving = true);
    try {
      await OrderGateway.referralPayout(
        action: paid ? 'paid' : 'rejected',
        payoutId: id,
        reference: reference,
      );
      if (mounted) setState(() => _pending = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_failureMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الصرف'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _saving ? null : () => setState(() => _pending = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _pending,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || _saving) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(_failureMessage(snapshot.error)));
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات صرف معلّقة.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final row in rows.cast<Map<String, dynamic>>())
                Card(
                  child: ListTile(
                    title: Text('${((row['amountMinor'] as num) / 100).toStringAsFixed(2)} ج.م'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(row['uid'] as String),
                        if (row['status'] == 'pending')
                          TextButton(
                            onPressed: () => _claim(row['id'] as String),
                            child: const Text('استلم الطلب للمعالجة'),
                          )
                        else if (row['canResolve'] == true)
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => _resolve(row['id'] as String, paid: true),
                                child: const Text('سجّل التحويل'),
                              ),
                              TextButton(
                                onPressed: () => _resolve(row['id'] as String, paid: false),
                                child: const Text('ارفض وأرجع الرصيد'),
                              ),
                            ],
                          )
                        else
                          const Text('الطلب مع مسؤول آخر.'),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
