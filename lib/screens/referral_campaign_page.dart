import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/order_gateway.dart';
import '../models/referral_admin_choices.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_ui.dart';
import '../widgets/referral_code_card.dart';
import '../widgets/referral_balance_tile.dart';
import '../widgets/referral_marketer_picker.dart';

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
      appBar: AppBar(title: const Text('الدعوات')),
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
              ReferralCodeCard(
                serverIssuedCode: data['code'] as String?,
                rewardsEnabled: data['rewardsEnabled'] == true,
              ),
              if (data['marketerCode'] is String) ...[
                const ListTile(title: Text('كود المسوّق')),
                ReferralCodeCard(serverIssuedCode: data['marketerCode'] as String),
              ],
              ReferralBalanceTile(
                icon: Icons.stars_rounded,
                title: 'رصيد النقاط',
                value: '${amount('points')} نقطة',
                explanation: 'نقاط خصم أثناء التسوق وفق شروط البرنامج.',
              ),
              if (widget.storeOwner || data['marketerCode'] is String)
                ReferralBalanceTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'رصيد المكافآت النقدية',
                  value: '${(amount('cashMinor') / 100).toStringAsFixed(2)} ج.م',
                  explanation: 'مكافآت نقدية تقدر تطلب صرفها من الإدارة.',
                ),
              if (amount('cashMinor') > 0)
                OutlinedButton(
                  onPressed: _requestingPayout ? null : _requestPayout,
                  child: const Text('طلب صرف الرصيد النقدي'),
                ),
              if (widget.storeOwner)
                ReferralBalanceTile(
                  icon: Icons.percent_rounded,
                  title: 'رصيد خصم العمولة',
                  value: '${(amount('commissionDiscountMinor') / 100).toStringAsFixed(2)} ج.م',
                  explanation: 'خصم عمولة وصّلي وليس رصيدًا للسحب.',
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
  String? _selectedMarketer;
  bool _loading = false;
  String? _code;
  String? _error;

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<List<ReferralMarketerChoice>> _loadMarketers() async {
    // Explicit admin action only. One bounded fetch; never a live listener.
    // Firestore rules permit /users listing only for administrators.
    final snap = await FirebaseFirestore.instance.collection('users')
        .limit(80).get();
    return referralMarketerChoices([
      // The Firestore document ID is authoritative. A writable `uid` field
      // inside profile data must never override the selected marketer UID.
      for (final doc in snap.docs) {...doc.data(), 'uid': doc.id},
    ]);
  }

  Future<void> _pickMarketer() async {
    if (_loading) return;
    // Capture one Future before building the sheet so keyboard/view rebuilds
    // do not repeat the bounded Firestore read.
    final accounts = _loadMarketers();
    final picked = await showModalBottomSheet<ReferralMarketerChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: ReferralMarketerPicker(accounts: accounts),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _uid.text = picked.uid;
      _selectedMarketer = picked.label;
      _error = null;
      _code = null;
    });
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
      appBar: AppBar(title: const Text('إدارة الدعوات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'إنشاء كود للمسوّق',
                  icon: Icons.qr_code_2_rounded,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'اختار حساب مسجّل من القائمة أو أدخل UID يدويًا. الخادم بيتحقق من هوية وصلاحية الحساب قبل إصدار الكود.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  key: const Key('admin-marketer-select'),
                  onPressed: _loading ? null : _pickMarketer,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('اختار مسوّق من الحسابات'),
                ),
                if (_selectedMarketer != null) Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('الحساب المحدد: $_selectedMarketer',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700)),
                ),
                _referralField(
                  label: 'معرّف حساب المسوّق',
                  child: TextField(
                    controller: _uid,
                    enabled: !_loading,
                    onChanged: (_) {
                      if (_selectedMarketer != null) setState(() => _selectedMarketer = null);
                    },
                    textDirection: TextDirection.ltr,
                    decoration: _referralInput(hint: 'UID'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _loading ? null : _issue,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                  label: const Text('إصدار الكود'),
                ),
                if (_loading) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          if (_error != null) AppNotice(_error!, type: AppNoticeType.error),
          if (_code != null) ReferralCodeCard(serverIssuedCode: _code),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune),
                title: const Text('إعدادات المكافآت'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _ReferralSettingsPage(),
                )),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.payments_outlined),
                title: const Text('طلبات الصرف'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _ReferralPayoutsPage(),
                )),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.store_outlined),
                title: const Text('تسوية عمولة محل'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const _ReferralCommissionPage(),
                )),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('تسديد خصم النقاط للمحل'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ReferralReimbursementPage(),
                )),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

String _failureMessage(Object? error) =>
    error is StateError ? error.message : 'تعذر تحميل الدعوات.';

InputDecoration _referralInput({String? hint}) => InputDecoration(
  isDense: true,
  hintText: hint,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
);

Widget _referralField({required String label, required Widget child}) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, maxLines: 3,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    const SizedBox(height: 5),
    child,
  ]),
);

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
                  ('customer', 'دعوات العملاء', 'points'),
                  ('marketer', 'دعوات المسوّقين', 'cash_minor'),
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
                _referralField(
                  label: 'قيمة النقطة بالقروش (صفر لإيقاف استخدامها)',
                  child: TextFormField(
                    initialValue: redemption?['pointValueMinor']?.toString() ?? '0',
                    keyboardType: TextInputType.number,
                    decoration: _referralInput(hint: '0'),
                    validator: (value) {
                      final amount = int.tryParse(value?.trim() ?? '');
                      _pointValueMinor = amount ?? 0;
                      return amount == null || amount < 0 || amount > 10000000
                          ? 'اكتب قيمة صحيحة للنقطة.' : null;
                    },
                    onSaved: (value) => _pointValueMinor = int.parse(value!.trim()),
                  ),
                ),
                _referralField(
                  label: 'أقصى خصم للطلب بالقروش',
                  child: TextFormField(
                    initialValue: redemption?['maxDiscountMinor']?.toString() ?? '0',
                    keyboardType: TextInputType.number,
                    decoration: _referralInput(hint: '0'),
                    validator: (value) {
                      final amount = int.tryParse(value?.trim() ?? '');
                      return amount == null || amount < _pointValueMinor || amount > 10000000
                          ? 'اكتب حدًا صحيحًا لا يقل عن قيمة النقطة.' : null;
                    },
                    onSaved: (value) => _maxDiscountMinor = int.parse(value!.trim()),
                  ),
                ),
                const SizedBox(height: 14),
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
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(widget.label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Switch(value: _enabled,
                onChanged: (value) => setState(() => _enabled = value)),
            ]),
            if (widget.channel == 'store_owner' || widget.channel == 'store_customer')
              _referralField(
                label: 'نوع المكافأة',
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  isExpanded: true,
                  decoration: _referralInput(),
                  items: const [
                    DropdownMenuItem(value: 'cash_minor', child: Text('فلوس قابلة للسحب')),
                    DropdownMenuItem(value: 'commission_discount_minor', child: Text('خصم عمولة وصّلي')),
                  ],
                  onChanged: (value) => setState(() => _unit = value ?? widget.unit),
                ),
              ),
            _referralField(
              label: _unit == 'points' ? 'عدد النقاط' : 'المبلغ بالقروش',
              child: TextFormField(
                initialValue: '$_amount',
                keyboardType: TextInputType.number,
                decoration: _referralInput(hint: '0'),
                validator: (value) {
                  final amount = int.tryParse(value?.trim() ?? '');
                  return amount == null || amount < (_enabled ? 1 : 0)
                      ? 'اكتب قيمة صحيحة للمكافأة.' : null;
                },
                onSaved: (value) => _amount = int.parse(value!.trim()),
              ),
            ),
            _referralField(
              label: 'حد المكافآت لكل داعٍ (اختياري)',
              child: TextFormField(
                initialValue: widget.initial?['maxPerInviter']?.toString(),
                keyboardType: TextInputType.number,
                decoration: _referralInput(hint: 'بدون حد'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return text.isNotEmpty && (int.tryParse(text) ?? -1) < 0
                      ? 'اكتب حدًا صحيحًا.' : null;
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
  final _reference = TextEditingController();
  late Future<List<ReferralOrderChoice>> _eligible = _loadEligible();
  String? _selectedOrderId;
  bool _busy = false;
  Map<String, dynamic>? _claim;
  String? _message;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.initialOrderId.isEmpty ? null : widget.initialOrderId;
  }

  Future<List<ReferralOrderChoice>> _loadEligible() async {
    // قراءة واحدة محدودة بدل استماع دائم؛ تحقّق الأهلية النهائي في Worker.
    final docs = await FirebaseFirestore.instance.collection('orders')
        .orderBy('createdAt', descending: true).limit(100).get();
    final rows = <Map<String, dynamic>>[
      for (final doc in docs.docs) {'id': doc.id, ...doc.data()},
    ];
    // إذا فُتحت الشاشة من طلب قديم، تأكد من أهليته بقراءة مستند واحد.
    final initialId = widget.initialOrderId.trim();
    if (initialId.isNotEmpty && !rows.any((row) => row['id'] == initialId)) {
      final doc = await FirebaseFirestore.instance.collection('orders').doc(initialId).get();
      if (doc.exists && doc.data() != null) {
        rows.insert(0, {'id': doc.id, ...doc.data()!});
      }
    }
    return referralEligibleOrders(rows);
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    if (_busy) return;
    final orderId = _selectedOrderId;
    final reference = _reference.text.trim();
    if (orderId == null || (action == 'paid' && reference.length < 5)) {
      setState(() => _message = 'اختار الطلب، واكتب مرجع التحويل عند تسجيل السداد.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final result = await OrderGateway.referralRedemption(
        orderId, action, reference: action == 'paid' ? reference : null,
      );
      if (!mounted) return;
      setState(() {
        if (action == 'claim') {
          _claim = result;
        } else {
          _claim = null;
          _selectedOrderId = null;
          _reference.clear();
          _eligible = _loadEligible();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسديد خصم النقاط للمحل'),
        actions: [
          IconButton(
            tooltip: 'تحديث الطلبات المؤهلة',
            onPressed: _busy ? null : () => setState(() => _eligible = _loadEligible()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<ReferralOrderChoice>>(
        future: _eligible,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('تعذر تحميل الطلبات. تحقق من الاتصال والصلاحيات.'));
          }
          final choices = snapshot.data ?? const <ReferralOrderChoice>[];
          ReferralOrderChoice? selected;
          for (final choice in choices) {
            if (choice.id == _selectedOrderId) selected = choice;
          }
          final claim = _claim;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('آخر 100 طلب — تظهر الطلبات المسلّمة أو الملغاة ذات خصم النقاط فقط.',
                style: Theme.of(context).textTheme.bodySmall),
              if (choices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا توجد طلبات مؤهلة حاليًا ضمن آخر 100 طلب.'),
                )
              else
                _referralField(
                  label: 'اختار الطلب',
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('redemption-$_selectedOrderId'),
                    isExpanded: true,
                    initialValue: selected?.id,
                    decoration: _referralInput(hint: 'الطلبات المؤهلة'),
                    items: [
                      for (final choice in choices)
                        DropdownMenuItem(
                          value: choice.id,
                          child: Text(choice.label,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy || claim != null ? null : (id) {
                      setState(() { _selectedOrderId = id; _message = null; });
                    },
                  ),
                ),
              const SizedBox(height: 12),
              if (claim == null) ...[
                if (selected?.isDelivered == true)
                  FilledButton(
                    onPressed: _busy ? null : () => _act('claim'),
                    child: const Text('استلام تسوية الطلب')),
                if (selected?.isCancelled == true)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _act('refund'),
                    child: const Text('استرجاع نقاط الطلب الملغي')),
              ] else ...[
                Text('المحل: ${claim['storeId']}'),
                Text('المستحق: ${((claim['discountMinor'] as num) / 100).toStringAsFixed(2)} ج.م.'),
                _referralField(
                  label: 'مرجع التحويل اليدوي',
                  child: TextField(
                    controller: _reference,
                    enabled: !_busy,
                    decoration: _referralInput(hint: 'مرجع السداد الفعلي'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : () => _act('paid'),
                  child: const Text('تسجيل السداد')),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_message != null) Text(_message!),
            ],
          );
        },
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
  late Future<List<ReferralStoreOwnerChoice>> _owners = _loadOwners();
  String _ownerUid = '';
  String _storeId = '';
  String _reference = '';
  int _dueMinor = 0;
  bool _saving = false;
  String? _result;
  String? _error;
  String? _selection;

  Future<List<ReferralStoreOwnerChoice>> _loadOwners() async {
    // الإدارة فقط: قراءتان محدودتان عند فتح النافذة، من غير listeners جديدة.
    final ownerDocs = await FirebaseFirestore.instance.collection('storeOwners')
        .limit(200).get();
    final storeDocs = await FirebaseFirestore.instance.collection('stores')
        .limit(200).get();
    return referralStoreOwnerChoices(
      owners: [
        for (final doc in ownerDocs.docs) {'uid': doc.id, ...doc.data()},
      ],
      storeNames: {
        for (final doc in storeDocs.docs) doc.id: (doc.data()['name'] ?? '').toString(),
      },
    );
  }

  Future<void> _settle() async {
    if (_saving || !_form.currentState!.validate()) return;
    _form.currentState!.save();
    if (_ownerUid.isEmpty || _storeId.isEmpty) {
      setState(() => _error = 'اختار المحل وصاحب الحساب المرتبط به.');
      return;
    }
    setState(() { _saving = true; _result = null; _error = null; });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسوية عمولة محل'),
        actions: [
          IconButton(
            tooltip: 'تحديث المحلات',
            onPressed: _saving ? null : () => setState(() => _owners = _loadOwners()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<ReferralStoreOwnerChoice>>(
        future: _owners,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل المحلات وأصحابها. تحقق من الصلاحيات والإنترنت.'));
          }
          final choices = snapshot.data ?? const <ReferralStoreOwnerChoice>[];
          final keys = choices.map((choice) => choice.key).toSet();
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (choices.isEmpty)
                  const Text('لا توجد محلات مرتبطة بأصحاب نشطين ضمن أول 200 سجل.')
                else
                  _referralField(
                    label: 'اختار المحل (صاحب الحساب يظهر تلقائيًا)',
                    child: DropdownButtonFormField<String>(
                      key: const Key('commission-store-choice'),
                      initialValue: keys.contains(_selection) ? _selection : null,
                      isExpanded: true,
                      decoration: _referralInput(hint: 'المحل وصاحبه'),
                      items: [
                        for (final choice in choices)
                          DropdownMenuItem(
                            value: choice.key,
                            child: Text(choice.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving ? null : (value) {
                        setState(() {
                          _selection = value;
                          _ownerUid = '';
                          _storeId = '';
                          for (final choice in choices) {
                            if (choice.key == value) {
                              _ownerUid = choice.ownerUid;
                              _storeId = choice.storeId;
                            }
                          }
                        });
                      },
                      validator: (value) =>
                          value == null || !keys.contains(value) ? 'اختار المحل.' : null,
                    ),
                  ),
                _referralField(
                  label: 'مرجع العمولة المسجّلة',
                  child: TextFormField(
                    enabled: !_saving,
                    textDirection: TextDirection.ltr,
                    decoration: _referralInput(hint: 'مرجع العمولة الفعلي'),
                    validator: (value) =>
                        RegExp(r'^[A-Za-z0-9_-]{4,64}$').hasMatch(value?.trim() ?? '')
                            ? null : 'راجع مرجع العمولة.',
                    onSaved: (value) => _reference = value!.trim(),
                  ),
                ),
                _referralField(
                  label: 'العمولة المستحقة بالقروش',
                  child: TextFormField(
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: _referralInput(hint: 'المبلغ الفعلي'),
                    validator: (value) {
                      final amount = int.tryParse(value?.trim() ?? '');
                      return amount == null || amount < 1 || amount > 10000000
                          ? 'اكتب قيمة صحيحة للعمولة.' : null;
                    },
                    onSaved: (value) => _dueMinor = int.parse(value!.trim()),
                  ),
                ),
                const SizedBox(height: 6),
                Text('يتم تطبيق الخصم على عمولة مسجّلة فعلًا، وليس احتساب عمولة جديدة.',
                  style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving || choices.isEmpty ? null : _settle,
                  child: const Text('سجّل العمولة وطبّق الخصم'),
                ),
                if (_saving) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                if (_result != null) Text(_result!),
              ],
            ),
          );
        },
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
