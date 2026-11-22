import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/quick_price_guide.dart';
import '../services/quick_price_guide_service.dart';

/// Admin-only editor. Firestore rules remain the authorization boundary.
/// Call from an existing admin-only navigation route.
class QuickPriceAdminPage extends StatefulWidget {
  const QuickPriceAdminPage({super.key});

  @override
  State<QuickPriceAdminPage> createState() => _QuickPriceAdminPageState();
}

class _QuickPriceAdminPageState extends State<QuickPriceAdminPage> {
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();
  final _items = <QuickPriceItem>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final guide = await QuickPriceGuideService.refresh();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(guide?.items ?? const []);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _add() {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final value = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty || unit.isEmpty || value == null || !value.isFinite ||
        value < 0 || value > 100000 || _items.length >= 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('راجع الاسم والوحدة والسعر (بحد أقصى 200 صنف)')),
      );
      return;
    }
    final pricePiastres = (value * 100).round();
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _items.add(QuickPriceItem(
        id: id, name: name, unit: unit, pricePiastres: pricePiastres,
      ));
      _name.clear();
      _unit.clear();
      _price.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance.collection('app_info').doc('quick_price_guide');
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final current = await transaction.get(ref);
        final version = (current.data()?['version'] as num?)?.toInt() ?? 0;
        transaction.set(ref, {
          'version': version + 1,
          'items': [
            for (final item in _items)
              {'id': item.id, 'name': item.name, 'unit': item.unit,
                'pricePiastres': item.pricePiastres},
          ],
        });
      });
      await QuickPriceGuideService.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ قائمة الأسعار')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ. تأكد من صلاحية الإدارة والاتصال')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة الأسعار التقريبية')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _name,
                decoration: const InputDecoration(labelText: 'اسم الصنف')),
              TextField(controller: _unit,
                decoration: const InputDecoration(labelText: 'الوحدة (كيلو / قطعة / لتر)')),
              TextField(controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'السعر التقريبي بالجنيه')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _add,
                icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
              for (var i = 0; i < _items.length; i++)
                ListTile(
                  title: Text(_items[i].name),
                  subtitle: Text('${_items[i].unit} — ${(_items[i].pricePiastres / 100).toStringAsFixed(2)} ج'),
                  trailing: IconButton(
                    tooltip: 'حذف الصنف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الأسعار'),
              ),
            ],
          ),
  );
}
