import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/order_gateway.dart';
import '../widgets/referral_code_card.dart';
import '../widgets/referral_registration_card.dart';

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

  bool get _canEnterInviteCode {
    final metadata = FirebaseAuth.instance.currentUser?.metadata;
    return isWithinReferralRegistrationWindow(
      accountCreatedAt: metadata?.creationTime,
      lastSignInAt: metadata?.lastSignInTime,
    );
  }

  Future<void> _saveInviteCode(String code) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('سجّل الدخول من جديد.');
    }
    await OrderGateway.claimRegistrationReferral(idToken: token, code: code);
  }

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
      body: Column(
        children: [
          if (!widget.storeOwner && _canEnterInviteCode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: ReferralRegistrationCard(onSubmit: _saveInviteCode),
            ),
          if (!widget.storeOwner && !_canEnterInviteCode)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'إدخال كود الدعوة متاح للحساب الجديد خلال أول ٢٤ ساعة من التسجيل فقط، ومرة واحدة. تقدر تشارك كودك مع أصحابك في أي وقت.',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
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
          ),
        ],
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
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const _ReferralCommissionPage(),
            )),
            child: const Text('تسوية عمولة محل'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ReferralReimbursementPage(),
            )),
            child: const Text('تسديد خصم النقاط للمحل'),
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
  int _pointValueMinor = 0;
  int _maxDiscountMinor = 0;
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
        settings: {
          'version': version + 1,
          'policies': policies,
          if (_pointValueMinor > 0)
            'redemption': {
              'pointValueMinor': _pointValueMinor,
              'maxDiscountMinor': _maxDiscountMinor,
            },
        },
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
          final redemption = settings?['redemption'] as Map<String, dynamic>?;
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
                TextFormField(
                  initialValue: redemption?['pointValueMinor']?.toString() ?? '0',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'قيمة النقطة بالقروش (صفر لإيقاف استخدام النقاط)',
                  ),
                  validator: (value) {
                    final amount = int.tryParse(value?.trim() ?? '');
                    _pointValueMinor = amount ?? 0;
                    return amount == null || amount < 0 || amount > 10000000
                        ? 'اكتب قيمة صحيحة للنقطة.'
                        : null;
                  },
                  onSaved: (value) => _pointValueMinor = int.parse(value!.trim()),
                ),
                TextFormField(
                  initialValue: redemption?['maxDiscountMinor']?.toString() ?? '0',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'أقصى خصم للطلب بالقروش',
                  ),
                  validator: (value) {
                    final amount = int.tryParse(value?.trim() ?? '');
                    final minimum = _pointValueMinor;
                    return amount == null || amount < minimum || amount > 10000000
                        ? 'اكتب حدًا صحيحًا لا يقل عن قيمة النقطة.'
                        : null;
                  },
                  onSaved: (value) => _maxDiscountMinor = int.parse(value!.trim()),
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

class ReferralReimbursementPage extends StatefulWidget {
  const ReferralReimbursementPage({super.key, this.initialOrderId = ''});

  final String initialOrderId;

  @override
  State<ReferralReimbursementPage> createState() =>
      _ReferralReimbursementPageState();
}

class _ReferralReimbursementPageState extends State<ReferralReimbursementPage> {
  late final _order = TextEditingController(text: widget.initialOrderId);
  final _reference = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _claim;
  String? _message;

  @override
  void dispose() {
    _order.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    if (_busy) return;
    final orderId = _order.text.trim();
    final reference = _reference.text.trim();
    if (orderId.isEmpty || (action == 'paid' && reference.length < 5)) {
      setState(() => _message = 'اكتب رقم الطلب، ومرجع التحويل عند تسجيل السداد.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await OrderGateway.referralRedemption(
        orderId,
        action,
        reference: action == 'paid' ? reference : null,
      );
      if (!mounted) return;
      setState(() {
        if (action == 'claim') {
          _claim = result;
        } else {
          _claim = null;
          _reference.clear();
          _message = action == 'paid'
              ? 'تم تسجيل سداد فرق الخصم للمحل.'
              : 'تمت مراجعة استرجاع نقاط الطلب الملغي.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = _failureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = _claim;
    return Scaffold(
      appBar: AppBar(title: const Text('تسديد خصم النقاط للمحل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _order,
            enabled: !_busy && claim == null,
            decoration: const InputDecoration(labelText: 'رقم الطلب'),
          ),
          if (claim == null) ...[
            FilledButton(
              onPressed: _busy ? null : () => _act('claim'),
              child: const Text('استلام تسوية الطلب')),
            TextButton(
              onPressed: _busy ? null : () => _act('refund'),
              child: const Text('استرجاع نقاط طلب ملغي')),
          ] else ...[
            Text('المحل: ${claim['storeId']}'),
            Text('المستحق: ${((claim['discountMinor'] as num) / 100).toStringAsFixed(2)} ج.م.'),
            TextField(
              controller: _reference,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'مرجع التحويل اليدوي'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _act('paid'),
              child: const Text('تسجيل السداد')),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) Text(_message!),
        ],
      ),
    );
  }
}

class _ReferralCommissionPage extends StatefulWidget {
  const _ReferralCommissionPage();

  @override
  State<_ReferralCommissionPage> createState() => _ReferralCommissionPageState();
}

class _ReferralCommissionPageState extends State<_ReferralCommissionPage> {
  final _form = GlobalKey<FormState>();
  String _ownerUid = '';
  String _storeId = '';
  String _reference = '';
  int _dueMinor = 0;
  bool _saving = false;
  String? _result;
  String? _error;

  Future<void> _settle() async {
    if (_saving || !_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _saving = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await OrderGateway.settleReferralCommission(
        ownerUid: _ownerUid,
        storeId: _storeId,
        reference: _reference,
        dueMinor: _dueMinor,
      );
      final discount = ((result['discountMinor'] as num) / 100).toStringAsFixed(2);
      final payable = ((result['payableMinor'] as num) / 100).toStringAsFixed(2);
      if (mounted) {
        setState(() => _result = 'الخصم: $discount ج.م. والمتبقي: $payable ج.م.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _failureMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _identifier(
    String label,
    RegExp pattern,
    ValueChanged<String> save,
  ) => TextFormField(
    enabled: !_saving,
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(labelText: label),
    validator: (value) => pattern.hasMatch(value?.trim() ?? '')
        ? null
        : 'راجع $label.',
    onSaved: (value) => save(value!.trim()),
  );

  @override
  Widget build(BuildContext context) {
    final identifier = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
    return Scaffold(
      appBar: AppBar(title: const Text('تسوية عمولة محل')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _identifier('معرّف المحل', identifier, (value) => _storeId = value),
            _identifier('معرّف صاحب المحل', identifier, (value) => _ownerUid = value),
            _identifier(
              'مرجع العمولة المسجّلة',
              RegExp(r'^[A-Za-z0-9_-]{4,64}$'),
              (value) => _reference = value,
            ),
            TextFormField(
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'العمولة المستحقة بالقروش'),
              validator: (value) {
                final amount = int.tryParse(value?.trim() ?? '');
                return amount == null || amount < 1 || amount > 10000000
                    ? 'اكتب قيمة صحيحة للعمولة.'
                    : null;
              },
              onSaved: (value) => _dueMinor = int.parse(value!.trim()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _settle,
              child: const Text('سجّل العمولة وطبّق الخصم'),
            ),
            if (_saving) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_result != null) Text(_result!),
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
