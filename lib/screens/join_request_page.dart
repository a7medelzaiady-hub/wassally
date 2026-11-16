import 'package:flutter/material.dart';

import '../services/image_service.dart';
import '../services/role_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// نموذج الانضمام كصاحب محل أو مندوب. بيتحفظ في role_requests ويظهر للمدير.
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
  String? _storeCategory;
  final _address = TextEditingController();
  final _storePhone = TextEditingController();
  final _storeImageUrl = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _proofUrl = TextEditingController();
  final _vehicle = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _store, _address, _storePhone, _storeImageUrl, _registrationNumber, _proofUrl, _vehicle, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _digits(String v) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var out = v.replaceAll(RegExp(r'[\s\-]'), '');
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(ar[i], '$i');
    }
    return out;
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (widget.type == JoinType.storeOwner &&
        _registrationNumber.text.trim().isEmpty && _proofUrl.text.trim().isEmpty && _digits(_storePhone.text).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم السجل التجاري أو رابط إثبات النشاط أو تليفون المحل.')),
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
        storeImageUrl: _storeImageUrl.text,
        registrationNumber: _registrationNumber.text,
        proofUrl: _proofUrl.text,
        vehicle: _vehicle.text,
        notes: _notes.text,
      );
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
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'اكتب اسمك' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: isStore ? 'رقم موبايل صاحب المحل (اختياري)' : 'رقم الموبايل',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                final value = _digits(v ?? '');
                if (isStore && value.isEmpty) return null;
                return isValidEgyptianMobile(value)
                    ? null
                    : 'اكتب رقم موبايل مصري صحيح (11 رقم)';
              },
            ),
            const SizedBox(height: 12),
            if (isStore) ...[
              TextFormField(
                controller: _store,
                decoration: const InputDecoration(
                  labelText: 'اسم المحل',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب اسم المحل' : null,
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
                  DropdownMenuItem(value: 'سوبرماركت', child: Text('سوبر ماركت')),
                  DropdownMenuItem(value: 'بقالة', child: Text('بقالة')),
                  DropdownMenuItem(value: 'خضار وفاكهة', child: Text('خضار وفاكهة')),
                  DropdownMenuItem(value: 'لحوم ودواجن', child: Text('لحوم ودواجن')),
                  DropdownMenuItem(value: 'مخبوزات وحلويات', child: Text('مخبوزات وحلويات')),
                  DropdownMenuItem(value: 'محمصات وعطارة', child: Text('محمصات وعطارة')),
                  DropdownMenuItem(value: 'كافيه ومشروبات', child: Text('كافيه ومشروبات')),
                  DropdownMenuItem(value: 'ورد وهدايا', child: Text('ورد وهدايا')),
                  DropdownMenuItem(value: 'أخرى', child: Text('نشاط آخر')),
                ],
                onChanged: (value) => setState(() => _storeCategory = value),
                validator: (value) => value == null || value.isEmpty
                    ? 'اختار نوع نشاط المحل'
                    : null,
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
                validator: (v) => (v ?? '').trim().length < 5
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
                validator: (v) {
                  final value = _digits(v ?? '');
                  return value.isEmpty || RegExp(r'^[0-9]{8,11}
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط صورة واجهة/المحل (مطلوب)',
                  prefixIcon: Icon(Icons.photo_outlined),
                ),
                validator: (v) => isValidImageUrl(v ?? '')
                    ? null
                    : 'أدخل رابط صورة صحيح يبدأ بـ https://',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _registrationNumber,
                decoration: const InputDecoration(
                  labelText: 'رقم السجل التجاري (اختياري)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  return value.isEmpty || RegExp(r'^[A-Za-z0-9\\-/]{6,30}
            ] else
              TextFormField(
                controller: _vehicle,
                decoration: const InputDecoration(
                  labelText: 'وسيلة التوصيل (موتوسيكل، عجلة...)',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب وسيلة التوصيل' : null,
              ),
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
).hasMatch(value)
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
                validator: (v) => (v ?? '').trim().isEmpty || isValidImageUrl(v ?? '')
                    ? null
                    : 'أدخل رابط إثبات صحيح يبدأ بـ https://',
              ),
              const SizedBox(height: 6),
              Text('يكفي واحد من: رقم السجل التجاري أو رابط إثبات النشاط أو رقم تليفون المحل. رقمك الشخصي للتواصل اختياري.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ] else
              TextFormField(
                controller: _vehicle,
                decoration: const InputDecoration(
                  labelText: 'وسيلة التوصيل (موتوسيكل، عجلة...)',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب وسيلة التوصيل' : null,
              ),
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
).hasMatch(value)
                      ? null
                      : 'اكتب رقم تليفون صحيح من 8 إلى 11 رقمًا';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storeImageUrl,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط صورة واجهة/المحل (مطلوب)',
                  prefixIcon: Icon(Icons.photo_outlined),
                ),
                validator: (v) => isValidImageUrl(v ?? '')
                    ? null
                    : 'أدخل رابط صورة صحيح يبدأ بـ https://',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _registrationNumber,
                decoration: const InputDecoration(
                  labelText: 'رقم السجل التجاري (اختياري)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  return value.isEmpty || RegExp(r'^[A-Za-z0-9\\-/]{6,30}
            ] else
              TextFormField(
                controller: _vehicle,
                decoration: const InputDecoration(
                  labelText: 'وسيلة التوصيل (موتوسيكل، عجلة...)',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب وسيلة التوصيل' : null,
              ),
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
).hasMatch(value)
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
                validator: (v) => (v ?? '').trim().isEmpty || isValidImageUrl(v ?? '')
                    ? null
                    : 'أدخل رابط إثبات صحيح يبدأ بـ https://',
              ),
              const SizedBox(height: 6),
              Text('لازم رقم سجل تجاري أو رابط إثبات نشاط على الأقل.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ] else
              TextFormField(
                controller: _vehicle,
                decoration: const InputDecoration(
                  labelText: 'وسيلة التوصيل (موتوسيكل، عجلة...)',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب وسيلة التوصيل' : null,
              ),
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
