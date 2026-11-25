import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quick_price_guide.dart';
import '../theme/app_tokens.dart';
import '../services/user_service.dart';
import 'quick_order_customer_detail_page.dart';
import '../services/quick_order_api.dart';
import '../widgets/quick_price_picker.dart';
import '../widgets/app_ui.dart';
import '../widgets/quick_order_promo.dart' show kQuickPhotoOrdersEnabled;
import '../services/image_service.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

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

  /// «صوّر طلبك»: روابط الصور المرفوعة (لحد 3).
  final List<String> _photos = [];
  bool _uploadingPhoto = false;
  static const _maxPhotos = 3;
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
    // البيانات المحفوظة بتظهر كملخص، و«تعديل» يفتح الحقول.
    setState(() => _contactCollapsed = _contactComplete);
  }

  @override
  void dispose() {
    for (final c in [_name, _area, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_uploadingPhoto || _photos.length >= _maxPhotos) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ImageService.pickAndUploadQuickRequest(source: source);
      if (url != null && mounted) setState(() => _photos.add(url));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is StateError ? error.message : 'تعذر رفع الصورة، جرّب تاني.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_uploadingPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('استنى لحد ما الصورة تترفع'),
      ));
      return;
    }
    if (_name.text.trim().isEmpty || _area.text.trim().isEmpty ||
        _phone.text.trim().isEmpty || _address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب الحي والعنوان والاسم ورقم الموبايل'),
      ));
      return;
    }
    // الصورة لوحدها طلب كامل؛ من غيرها لازم صنف مكتوب لكل محل.
    if (_photos.isEmpty && _stores.any((store) => !store.hasItems)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(kQuickPhotoOrdersEnabled
            ? 'اكتب طلبك أو صوّره'
            : 'اكتب صنف واحد على الأقل لكل محل'),
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
        if (_photos.isNotEmpty) 'customerImages': List<String>.of(_photos),
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

  bool _contactCollapsed = false;
  bool _showNotes = false;

  bool get _contactComplete =>
      _name.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty &&
      _address.text.trim().isNotEmpty;

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
        _heading(
          'إيه اللي محتاجه؟',
          kQuickPhotoOrdersEnabled
              ? 'اكتبها أو صوّرها… وإحنا نجيبها'
              : 'من محل واحد أو أكتر، أو سيب المندوب يختار.',
        ),
        if (kQuickPhotoOrdersEnabled) ...[
          _photoSection(),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (final store in _stores) _storeFields(store),
        if (_stores.length < 10)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('quick-add-store'),
              onPressed: _submitting
                  ? null
                  : () => setState(() => _stores.add(_QuickStoreDraft())),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('أضف محل تاني'),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _heading('التوصيل إلى', null),
        _deliveryCard(),
        if (!_showNotes)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('quick-add-note'),
              onPressed: () => setState(() => _showNotes = true),
              icon: const Icon(Icons.sticky_note_2_outlined),
              label: const Text('أضف ملاحظة للمندوب'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'ملاحظات للمندوب (اختياري)',
              hintText: 'مثال: لو الصنف مش موجود كلمني الأول',
              prefixIcon: Icon(Icons.sticky_note_2_outlined),
            ),
          ),
          ),
        const SizedBox(height: AppSpacing.sm),
        const _FeesNote(),
      ],
    ),
    // الزر ثابت تحت ويستخبى ورا الكيبورد بدل ما ياكل مساحة الكتابة.
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.md),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x141E1638), blurRadius: 12, offset: Offset(0, -3))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                'مفيش دفع دلوقتي • الدفع عند الاستلام',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton.icon(
              key: const Key('quick-submit'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'جارٍ الإرسال...' : 'اطلب دلوقتي'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _photoTile({required Widget child, VoidCallback? onTap, Key? key}) => Material(
        key: key,
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 76, height: 76, child: child),
        ),
      );

  /// «صوّر طلبك»: الكاميرا أو المعرض، لحد 3 صور مع معاينة وتكبير وحذف.
  Widget _photoSection() => AppCard(
        key: const Key('quick-photo-section'),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [
              Icon(Icons.photo_camera_outlined, color: AppColors.purple),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('صوّر طلبك', style: AppTypography.sectionTitle),
              ),
            ]),
            const SizedBox(height: 2),
            const Text(
              'صوّر الورقة بوضوح والإضاءة كويسة. المندوب بيقرا الصورة ويكلمك.',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (i, url) in _photos.indexed)
                  Stack(clipBehavior: Clip.none, children: [
                    _photoTile(
                      key: ValueKey('quick-photo-$i'),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (dialog) => Dialog(
                          clipBehavior: Clip.antiAlias,
                          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                        ),
                      ),
                      child: Image.network(url, fit: BoxFit.cover, cacheWidth: 240,
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                    ),
                    PositionedDirectional(
                      top: -6,
                      end: -6,
                      child: Material(
                        color: AppColors.danger,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _submitting ? null : () => setState(() => _photos.removeAt(i)),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ]),
                if (_uploadingPhoto)
                  _photoTile(child: const Center(
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ))
                else if (_photos.length < _maxPhotos) ...[
                  _photoTile(
                    key: const Key('quick-photo-camera'),
                    onTap: _submitting ? null : () => _addPhoto(ImageSource.camera),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.photo_camera_rounded, color: AppColors.purple),
                      SizedBox(height: 2),
                      Text('الكاميرا', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.purple)),
                    ]),
                  ),
                  _photoTile(
                    key: const Key('quick-photo-gallery'),
                    onTap: _submitting ? null : () => _addPhoto(ImageSource.gallery),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.photo_library_outlined, color: AppColors.purple),
                      SizedBox(height: 2),
                      Text('المعرض', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.purple)),
                    ]),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${_photos.length} من $_maxPhotos صور • بتتمسح بعد ما تستلم طلبك',
                style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption),
              ),
            ),
          ],
        ),
      );

  Widget _heading(String title, String? subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.sectionTitle.copyWith(fontSize: AppTypography.title)),
            if (subtitle != null) Text(subtitle, style: AppTypography.secondary),
          ],
        ),
      );

  /// العنوان وبيانات التواصل: ملخص سطرين لو البيانات محفوظة، و«تعديل» يفتح الحقول.
  Widget _deliveryCard() {
    final showFields = !_contactCollapsed;
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _area,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'المدينة والحي',
              hintText: 'مثال: بيلا، حي المحطة',
              prefixIcon: Icon(Icons.location_on_outlined),
              helperText: 'الحي بس بيظهر للمندوب قبل ما يقبل الطلب.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!showFields)
            Row(
              key: const Key('quick-contact-summary'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.purpleSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline_rounded, color: AppColors.purple),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppTypography.bodySmall,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        _phone.text.trim(),
                        textDirection: TextDirection.ltr,
                        style: AppTypography.secondary.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(_address.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: AppTypography.secondary),
                      const SizedBox(height: AppSpacing.xxs),
                      const _PrivacyBadge(),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _contactCollapsed = false),
                  child: const Text('تعديل'),
                ),
              ],
            )
          else ...[
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
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                    labelText: 'اسمك',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الموبايل',
                hintText: '01xxxxxxxxx',
                prefixIcon: Icon(Icons.phone_iphone_rounded),
                suffixIcon: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: _PrivacyBadge(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _storeFields(_QuickStoreDraft store) {
    final index = _stores.indexOf(store);
    return AppCard(
      key: ObjectKey(store),
      elevated: true,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: store.name,
                enabled: !_submitting,
                maxLength: 60,
                onChanged: (value) => store.name = value,
                decoration: InputDecoration(
                  labelText: _stores.length == 1
                      ? 'اسم المحل (اختياري)'
                      : 'المحل ${index + 1} (اختياري)',
                  hintText: 'سيبه فاضي لو المندوب هيختار',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  counterText: '',
                ),
              ),
            ),
            if (_stores.length > 1)
              IconButton(
                tooltip: 'احذف المحل ده',
                color: AppColors.danger,
                onPressed:
                    _submitting ? null : () => setState(() => _stores.remove(store)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ]),
          const SizedBox(height: AppSpacing.md),
          QuickPricePicker(
            onChanged: (items) => store.items = items,
            onUnlistedChanged: (text) => store.unlisted = text,
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.orangeDeep, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'أجرة التوصيل بالاتفاق مع المندوب قبل الشراء، وبتوافق على الفواتير والحساب قبل الاستلام.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: AppTypography.label,
                  height: 1.45,
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
