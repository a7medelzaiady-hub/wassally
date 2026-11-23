import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quick_price_guide.dart';
import '../services/user_service.dart';
import 'quick_order_customer_detail_page.dart';
import '../services/quick_order_api.dart';
import '../widgets/quick_price_picker.dart';

/// Separate quick-order entry point; never adds items to the regular store cart.
class QuickOrderCreatePage extends StatefulWidget {
  const QuickOrderCreatePage({super.key});

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلباتك على السريع')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('اطلب من أي محل، حتى لو مش موجود على وصّلي.'),
        const SizedBox(height: 12),
        Text('بيانات التوصيل', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(controller: _name,
          decoration: const InputDecoration(labelText: 'اسمك')),
        TextField(controller: _area,
          decoration: const InputDecoration(
            labelText: 'المنطقة العامة (تظهر للمندوب قبل القبول)',
            hintText: 'مثال: مدينة كفر الشيخ - حي الزهور',
            helperText: 'اكتب المدينة والحي فقط، بدون شارع أو رقم منزل.',
            helperMaxLines: 2,
          )),
        TextField(controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقم التليفون')),
        TextField(controller: _address,
          decoration: const InputDecoration(labelText: 'عنوان التوصيل')),
        for (final store in _stores)
          _storeFields(store),
        if (_stores.length < 10)
          OutlinedButton.icon(
            onPressed: _submitting ? null : () => setState(() => _stores.add(_QuickStoreDraft())),
            icon: const Icon(Icons.add),
            label: const Text('أضف محل تاني'),
          ),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 2,
          decoration: const InputDecoration(labelText: 'ملاحظات للمندوب')),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF087B58),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
          ),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب السريع'),
        ),
      ],
    ),
  );

  Widget _storeFields(_QuickStoreDraft store) => Column(
    key: ObjectKey(store),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      TextFormField(
        initialValue: store.name,
        enabled: !_submitting,
        maxLength: 60,
        onChanged: (value) => store.name = value,
        decoration: const InputDecoration(labelText: 'اسم المحل (اختياري)'),
      ),
      QuickPricePicker(
        onChanged: (items) => store.items = items,
        onUnlistedChanged: (text) => store.unlisted = text,
      ),
      if (_stores.length > 1)
        TextButton(
          onPressed: _submitting ? null : () => setState(() => _stores.remove(store)),
          child: const Text('احذف المحل ده'),
        ),
    ],
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
