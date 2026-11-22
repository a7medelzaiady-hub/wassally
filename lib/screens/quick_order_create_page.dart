import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quick_price_guide.dart';
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
  final _store = TextEditingController();
  final _notes = TextEditingController();
  String _unlisted = '';
  List<QuickPriceSelection> _selected = const [];
  bool _submitting = false;
  String? _pendingOrderId;

  @override
  void dispose() {
    for (final c in [_name, _area, _phone, _address, _store, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_name.text.trim().isEmpty || _area.text.trim().isEmpty ||
        _phone.text.trim().isEmpty || _address.text.trim().isEmpty ||
        (_selected.isEmpty && _unlisted.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('اكتب بيانات التواصل وصنف واحد على الأقل'),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      // The ID is created once per submission, so the same request can be
      // retried without creating duplicate orders.
      final user = await _currentUserId();
      final id = _pendingOrderId ??= '${user}_${DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0')}';
      final pricedItems = [
        for (final s in _selected) s.toWorkerMap(),
      ];
      await QuickOrderApi.create({
        'orderId': id,
        'customerName': _name.text.trim(),
        'area': _area.text.trim(),
        'notes': _notes.text.trim(),
        'stores': [
          {
            'name': _store.text.trim(),
            'items': _unlisted.trim(),
            if (pricedItems.isNotEmpty) 'pricedItems': pricedItems,
          },
        ],
        'contact': {
          'userName': _name.text.trim(),
          'phone': _phone.text.trim(),
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
        TextField(controller: _name,
          decoration: const InputDecoration(labelText: 'اسمك')),
        TextField(controller: _area,
          decoration: const InputDecoration(labelText: 'المنطقة')),
        TextField(controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقم التليفون')),
        TextField(controller: _address,
          decoration: const InputDecoration(labelText: 'عنوان التوصيل')),
        TextField(controller: _store,
          decoration: const InputDecoration(labelText: 'اسم المحل (اختياري)')),
        const SizedBox(height: 16),
        QuickPricePicker(
          onChanged: (items) => _selected = items,
          onUnlistedChanged: (text) => _unlisted = text,
        ),
        TextField(controller: _notes, maxLines: 2,
          decoration: const InputDecoration(labelText: 'ملاحظات للمندوب')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال الطلب السريع'),
        ),
      ],
    ),
  );
}
