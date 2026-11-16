import 'package:flutter/material.dart';

import '../services/image_service.dart';
import '../services/role_request_service.dart';
import '../services/navigation.dart' show roleInfoOverride;
import '../services/role_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// نموذج الانضمام كصاحب محل أو مندوب.
class JoinRequestPage extends StatefulWidget {
  final JoinType type;
  final String initialName;
  final String initialPhone;

  const JoinRequestPage({
    super.key,
    required this.type,
    this.initialName = '',
    this.initialPhone = '',
  });

  @override
  State<JoinRequestPage> createState() => _JoinRequestPageState();
}

class _JoinRequestPageState extends State<JoinRequestPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _store = TextEditingController();
  final _address = TextEditingController();
  final _storePhone = TextEditingController();
  String _storeImageUrl = '';
  bool _uploadingStoreImage = false;
  final _registrationNumber = TextEditingController();
  final _proofUrl = TextEditingController();
  final _vehicle = TextEditingController();
  final _notes = TextEditingController();

  String? _storeCategory;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _store,
      _address,
      _storePhone,
      _registrationNumber,
      _proofUrl,
      _vehicle,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _digits(String value) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var result = value.replaceAll(RegExp(r'[\s\-]'), '');
    for (var i = 0; i < arabicDigits.length; i++) {
      result = result.replaceAll(arabicDigits[i], '$i');
    }
    return result;
  }


  Future<void> _pickStoreImage() async {
    setState(() => _uploadingStoreImage = true);
    try {
      final url = await ImageService.pickAndUpload('stores');
      if (url != null && mounted) {
        setState(() => _storeImageUrl = url);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع الصورة. حاول بصورة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingStoreImage = false);
    }
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final isStore = widget.type == JoinType.storeOwner;
    if (isStore && _storeImageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختار صورة للمحل أولاً.')),
      );
      return;
    }

    if (isStore &&
        _registrationNumber.text.trim().isEmpty &&
        _proofUrl.text.trim().isEmpty &&
        _digits(_storePhone.text).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'أدخل رقم السجل التجاري أو رابط إثبات النشاط أو تليفون المحل.',
          ),
        ),
      );
      return;
    }

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);

    try {
      await RoleRequestService.submit(
        type: widget.type,
        name: _name.text,
        phone: _digits(_phone.text),
        storePhone: _digits(_storePhone.text),
        storeName: _store.text,
        storeCategory: _storeCategory ?? '',
        address: _address.text,
        storeImageUrl: _storeImageUrl,
        registrationNumber: _registrationNumber.text,
        proofUrl: _proofUrl.text,
        vehicle: _vehicle.text,
        notes: _notes.text,
      );
      final refreshedRole = await RoleService.load();
      roleInfoOverride.value = refreshedRole;
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('اتبعت طلبك. هنراجعه ونرد عليك.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر إرسال الطلب. ممكن يكون عندك طلب قيد المراجعة.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStore = widget.type == JoinType.storeOwner;

    return Scaffold(
      appBar: AppBar(title: Text('انضم كـ ${widget.type.label}')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              isStore
                  ? 'سجّل بيانات محلك وهنراجعها. لما نوافق هتدير طلباتك وأصنافك من التطبيق.'
                  : 'سجّل بياناتك وهنراجعها. لما نوافق هتقدر تتقدّم على طلبات التوصيل.',
              style: TextStyle(color: kMuted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'الاسم',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) =>
                  (value ?? '').trim().length < 2 ? 'اكتب اسمك' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: isStore
                    ? 'رقم موبايل صاحب المحل (اختياري)'
                    : 'رقم الموبايل',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                final phone = _digits(value ?? '');
                if (isStore && phone.isEmpty) return null;
                return isValidEgyptianMobile(phone)
                    ? null
                    : 'اكتب رقم موبايل مصري صحيح (11 رقم)';
              },
            ),
            if (isStore) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _store,
                decoration: const InputDecoration(
                  labelText: 'اسم المحل',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (value) =>
                    (value ?? '').trim().length < 2 ? 'اكتب اسم المحل' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _storeCategory,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'نوع نشاط المحل',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'مطاعم', child: Text('مطاعم')),
                  DropdownMenuItem(
                    value: 'سوبرماركت',
                    child: Text('سوبر ماركت'),
                  ),
                  DropdownMenuItem(value: 'بقالة', child: Text('بقالة')),
                  DropdownMenuItem(
                    value: 'خضار وفاكهة',
                    child: Text('خضار وفاكهة'),
                  ),
                  DropdownMenuItem(
                    value: 'لحوم ودواجن',
                    child: Text('لحوم ودواجن'),
                  ),
                  DropdownMenuItem(
                    value: 'مخبوزات وحلويات',
                    child: Text('مخبوزات وحلويات'),
                  ),
                  DropdownMenuItem(
                    value: 'محمصات وعطارة',
                    child: Text('محمصات وعطارة'),
                  ),
                  DropdownMenuItem(
                    value: 'كافيه ومشروبات',
                    child: Text('كافيه ومشروبات'),
                  ),
                  DropdownMenuItem(
                    value: 'ورد وهدايا',
                    child: Text('ورد وهدايا'),
                  ),
                  DropdownMenuItem(value: 'أخرى', child: Text('نشاط آخر')),
                ],
                onChanged: (value) => setState(() => _storeCategory = value),
                validator: (value) =>
                    value == null || value.isEmpty ? 'اختار نوع نشاط المحل' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'عنوان المحل',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: (value) => (value ?? '').trim().length < 5
                    ? 'اكتب العنوان بالتفصيل'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storePhone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم تليفون المحل (اختياري - بديل إثبات النشاط)',
                  prefixIcon: Icon(Icons.store_mall_directory_outlined),
                ),
                validator: (value) {
                  final phone = _digits(value ?? '');
                  return phone.isEmpty ||
                          RegExp(r'^[0-9]{8,11}$').hasMatch(phone)
                      ? null
                      : 'اكتب رقم تليفون صحيح من 8 إلى 11 رقمًا';
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_storeImageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _storeImageUrl,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 80,
                            child: Center(child: Text('تعذر عرض الصورة')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: _busy || _uploadingStoreImage
                          ? null
                          : _pickStoreImage,
                      icon: _uploadingStoreImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(_uploadingStoreImage
                          ? 'جاري رفع الصورة...'
                          : _storeImageUrl.isEmpty
                              ? 'اختار صورة المحل (مطلوب)'
                              : 'تغيير صورة المحل'),
                    ),
                    Text(
                      'اختار صورة من معرض الموبايل، والتطبيق هيرفعها تلقائيًا.',
                      style: TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _registrationNumber,
                decoration: const InputDecoration(
                  labelText: 'رقم السجل التجاري (اختياري)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  final number = _digits((value ?? '').trim());
                  return number.isEmpty ||
                      RegExp(r'^[A-Za-z0-9/-]{6,30}$').hasMatch(number)
                      ? null
                      : 'رقم السجل من 6 إلى 30 حرفًا أو رقمًا';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _proofUrl,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط إثبات النشاط (اختياري)',
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
                validator: (value) {
                  final proof = (value ?? '').trim();
                  final uri = Uri.tryParse(proof);
                  return proof.isEmpty ||
                          (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty)
                      ? null
                      : 'أدخل رابط إثبات صحيح يبدأ بـ https://';
                },
              ),
              const SizedBox(height: 6),
              Text(
                'يكفي واحد من: رقم السجل التجاري أو رابط إثبات النشاط أو رقم تليفون المحل. رقمك الشخصي للتواصل اختياري.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _vehicle,
                decoration: const InputDecoration(
                  labelText: 'وسيلة التوصيل (موتوسيكل، عجلة...)',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                validator: (value) =>
                    (value ?? '').trim().length < 2
                    ? 'اكتب وسيلة التوصيل'
                    : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('إرسال الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}