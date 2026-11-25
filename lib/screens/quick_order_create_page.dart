import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quick_price_guide.dart';
import '../theme/app_tokens.dart';
import '../services/user_service.dart';
import 'quick_order_customer_detail_page.dart';
import '../services/quick_order_api.dart';
import '../widgets/quick_price_picker.dart';
import '../widgets/app_ui.dart';

/// Separate quick-order entry point; never adds items to the regular store cart.
class QuickOrderCreatePage extends StatefulWidget {
  const QuickOrderCreatePage({super.key, this.prefillFromAccount = true});

  /// للاختبارات فقط: تعطيل ملء بيانات الحساب (يحتاج Firebase).
  final bool prefillFromAccount;

  @override
  State<QuickOrderCreatePage> createState() => _QuickOrderCreatePageState();
}

class _QuickOrderCreatePageState extends State<QuickOrderCreatePage> {
  final _name = TextEditingController();
  final _area = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _stores = [_QuickStoreDraft()];
  bool _submitting = false;
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    if (!widget.prefillFromAccount) return;
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
    _prefillContact();
  }

  Future<void> _prefillContact() async {
    final profile = await UserService.load();
    if (!mounted) return;
    // Never overwrite values the customer has already typed.
    if (profile.name.trim().isNotEmpty &&
        (_name.text.trim().isEmpty ||
         _name.text.trim() == (FirebaseAuth.instance.currentUser?.displayName ?? '').trim())) {
      _name.text = profile.name;
    }
    if (_phone.text.trim().isEmpty) _phone.text = profile.phone;
    if (_address.text.trim().isEmpty) _address.text = profile.address;
  }

  @override
  void dispose() {
    for (final c in [_name, _area, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_name.text.trim().isEmpty || _area.text.trim().isEmpty ||
        _phone.text.trim().isEmpty || _address.text.trim().isEmpty ||
        _stores.any((store) => !store.hasItems)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب بيانات التواصل وصنف واحد على الأقل لكل محل'),
      ));
      return;
    }
    final phone = _phone.text.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب رقم موبايل مصري صحيح من 11 رقم، مثل 01012345678'),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      // The ID is created once per submission, so the same request can be
      // retried without creating duplicate orders.
      final user = await _currentUserId();
      final id = _pendingOrderId ??= '${user}_${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0')}';
      await QuickOrderApi.create({
        'orderId': id,
        'customerName': _name.text.trim(),
        'area': _area.text.trim(),
        'notes': _notes.text.trim(),
        'stores': [for (final store in _stores) store.toWorkerMap()],
        'contact': {
          'userName': _name.text.trim(),
          'phone': phone,
          'address': _address.text.trim(),
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلبك السريع')),
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => QuickOrderCustomerDetailPage(orderId: id),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String> _currentUserId() async {
    // The authenticated token is obtained by QuickOrderApi.
    // Read the uid only to create a stable, user-prefixed order ID.
    final uid = await _uid();
    if (uid == null || uid.isEmpty) throw StateError('سجل دخولك أولًا');
    return uid;
  }

  Future<String?> _uid() async {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('طلباتك على السريع')),
    body: ListView(
      key: const Key('quick-create-list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xxl),
      children: [
        const _QuickIntro(),
        const SizedBox(height: AppSpacing.lg),
        for (final store in _stores) _storeFields(store),
        if (_stores.length < 10)
          OutlinedButton.icon(
            key: const Key('quick-add-store'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.purple, width: 1.2),
              backgroundColor: AppColors.purpleSoft.withValues(alpha: 0.5),
            ),
            onPressed: _submitting
                ? null
                : () => setState(() => _stores.add(_QuickStoreDraft())),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('أضف محل تاني'),
          ),
        const SizedBox(height: AppSpacing.lg),
        _section(
          step: _stores.length > 1 ? null : 2,
          title: 'عنوان التوصيل',
          icon: Icons.location_on_outlined,
          children: [
            TextField(
              controller: _area,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'المدينة والحي',
                hintText: 'مثال: بيلا، حي المحطة',
                prefixIcon: Icon(Icons.map_outlined),
                helperText: 'الحي بس بيظهر للمندوب قبل ما يقبل الطلب.',
                helperMaxLines: 2,
              ),
            ),
            TextField(
              controller: _address,
              textInputAction: TextInputAction.next,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'العنوان بالتفصيل',
                hintText: 'الشارع، رقم العمارة، الدور، علامة مميزة',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
          ],
        ),
        _section(
          step: _stores.length > 1 ? null : 3,
          title: 'بيانات التواصل',
          icon: Icons.call_outlined,
          trailing: const _PrivacyBadge(),
          children: [
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسمك',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الموبايل',
                hintText: '01xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_iphone_rounded),
              ),
            ),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ملاحظات للمندوب (اختياري)',
                hintText: 'مثال: لو الصنف مش موجود كلمني الأول',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
          ],
        ),
        const _FeesNote(),
      ],
    ),
    // الزر ثابت تحت ويستخبى ورا الكيبورد بدل ما ياكل مساحة الكتابة.
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: FilledButton.icon(
          key: const Key('quick-submit'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب السريع'),
        ),
      ),
    ),
  );

  Widget _section({
    Key? key,
    int? step,
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) => AppCard(
    key: key,
    elevated: true,
    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(title: title, icon: icon, step: step, trailing: trailing),
        for (final child in children) ...[
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ],
    ),
  );

  Widget _storeFields(_QuickStoreDraft store) => _section(
    key: ObjectKey(store),
    step: _stores.length == 1 ? 1 : null,
    title: _stores.length == 1
        ? 'اكتب طلباتك'
        : 'مشتريات المحل ${_stores.indexOf(store) + 1}',
    icon: Icons.shopping_basket_outlined,
    trailing: _stores.length > 1
        ? IconButton(
            tooltip: 'احذف المحل ده',
            color: AppColors.danger,
            onPressed:
                _submitting ? null : () => setState(() => _stores.remove(store)),
            icon: const Icon(Icons.delete_outline_rounded),
          )
        : null,
    children: [
      TextFormField(
        initialValue: store.name,
        enabled: !_submitting,
        maxLength: 60,
        onChanged: (value) => store.name = value,
        decoration: const InputDecoration(
          labelText: 'اسم المحل (اختياري)',
          hintText: 'سيبه فاضي لو المندوب هيختار',
          prefixIcon: Icon(Icons.storefront_outlined),
          counterText: '',
        ),
      ),
      QuickPricePicker(
        onChanged: (items) => store.items = items,
        onUnlistedChanged: (text) => store.unlisted = text,
      ),
    ],
  );
}

/// شرح مختصر للخدمة وخطواتها، من غير إطالة.
class _QuickIntro extends StatelessWidget {
  const _QuickIntro();

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        );
    return Container(
      key: const Key('quick-intro'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppColors.actionGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.bolt_rounded, size: 32, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'وصّلي ع السريع',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.headline,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xxs),
                    Text(
                      'اكتب اللي محتاجه من أي محل، ومندوب معتمد يشتريه ويوصّله لحد بابك.',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: AppTypography.bodySmall,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              step(Icons.edit_note_rounded, 'اكتب طلبك'),
              step(Icons.phone_in_talk_rounded, 'المندوب يكلمك ويتفق معاك'),
              step(Icons.receipt_long_rounded, 'توافق على الحساب'),
              step(Icons.verified_rounded, 'تستلم برمز التسليم'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'رقمك وعنوانك بيظهروا للمندوب بعد ما يقبل الطلب بس',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.success),
              SizedBox(width: 3),
              Text(
                'محمية',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
}

/// توضيح الرسوم والاتفاق على السعر (نفس قواعد الخدمة الحالية).
class _FeesNote extends StatelessWidget {
  const _FeesNote();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('quick-fees-note'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.orangeDeep),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'أجرة التوصيل بتتفق عليها مع المندوب في التليفون قبل الشراء. '
                'بعد الشراء بتشوف الفواتير والحساب النهائي وتوافق عليه قبل الاستلام.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: AppTypography.bodySmall,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _QuickStoreDraft {
  String name = '';
  String unlisted = '';
  List<QuickPriceSelection> items = const [];

  bool get hasItems => items.isNotEmpty || unlisted.trim().isNotEmpty;

  Map<String, dynamic> toWorkerMap() => {
    'name': name.trim(),
    'items': unlisted.trim(),
    if (items.isNotEmpty) 'pricedItems': [for (final item in items) item.toWorkerMap()],
  };
}
