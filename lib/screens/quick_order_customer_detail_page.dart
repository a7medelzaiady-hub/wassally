import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/quick_order_api.dart';
import '../theme/brand.dart';
import '../utils/quick_order_status.dart';
import '../utils/dialog_controllers.dart';

/// Customer-facing final bill. Uses explicit refresh, not a permanent listener.
class QuickOrderCustomerDetailPage extends StatefulWidget {
  final String orderId;
  const QuickOrderCustomerDetailPage({super.key, required this.orderId});

  @override
  State<QuickOrderCustomerDetailPage> createState() => _QuickOrderCustomerDetailPageState();
}

class _QuickOrderCustomerDetailPageState extends State<QuickOrderCustomerDetailPage> {
  Map<String, dynamic>? _order;
  String? _pin;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('سجل دخولك أولًا');
      final doc = await FirebaseFirestore.instance.collection('quick_orders')
          .doc(widget.orderId).get();
      if (!doc.exists || doc.data()?['userId'] != user.uid) {
        throw StateError('الطلب غير متاح');
      }
      if (!mounted) return;
      setState(() { _order = doc.data(); _pin = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    if (_order == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await QuickOrderApi.action(widget.orderId, action, body);
      if (!mounted) return;
      final updated = result['order'];
      if (updated is Map) {
        setState(() { _order = Map<String, dynamic>.from(updated); _error = null; });
      } else {
        setState(() { _busy = false; });
        await _refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final order = _order;
    if (order == null || _busy || order['status'] != 'open') return;
    final rawStores = order['stores'];
    if (rawStores is! List || rawStores.isEmpty) return;
    final stores = rawStores.whereType<Map>().map(Map<String, dynamic>.from).toList();
    if (stores.isEmpty) return;
    final names = [
      for (final store in stores)
        TextEditingController(text: (store['name'] ?? '').toString()),
    ];
    final items = [
      for (final store in stores)
        TextEditingController(text: (store['items'] ?? '').toString()),
    ];
    final notes = TextEditingController(text: (order['notes'] ?? '').toString());
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('تعديل الطلب السريع'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < stores.length; i++) ...[
              TextField(
                controller: names[i],
                decoration: const InputDecoration(labelText: 'اسم المحل (اختياري)'),
              ),
              TextField(
                controller: items[i],
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'الأصناف المكتوبة'),
              ),
            ],
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات للمندوب'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, {
              'stores': [
                for (var i = 0; i < stores.length; i++)
                  {...stores[i], 'name': names[i].text.trim(), 'items': items[i].text.trim()},
              ],
              'notes': notes.text.trim(),
            }),
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
    for (final controller in [...names, ...items, notes]) {
      disposeAfterDialogCloses(controller);
    }
    if (mounted && updated != null) await _act('edit', updated);
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('تلغي الطلب السريع؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _act('cancel');
  }

  Future<void> _showPin() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await QuickOrderApi.deliveryPin(widget.orderId);
      if (!mounted) return;
      final pin = (result['pin'] ?? result['deliveryPin'] ?? '').toString();
      if (pin.length != 4 || !RegExp(r'^[0-9]{4}').hasMatch(pin)) {
        throw StateError('تعذر عرض رمز التسليم. حاول التحديث مرة أخرى.');
      }
      setState(() { _pin = pin; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  String _money(Object? piastres) =>
      '${(((piastres as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)} جنيه';

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final status = (order?['status'] ?? '').toString();
    final totals = order?['totals'] is Map
        ? Map<String, dynamic>.from(order!['totals'] as Map)
        : <String, dynamic>{};
    final receipts = order?['receipts'] is List ? order!['receipts'] as List : const [];
    final stores = order?['stores'] is List ? order!['stores'] as List : const [];
    final notes = (order?['notes'] ?? '').toString().trim();
    final area = (order?['area'] ?? '').toString().trim();
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب السريع'),
        actions: [IconButton(onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh), tooltip: 'تحديث')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (order == null)
          Text(_error != null ? 'تعذر تحميل الطلب. اضغط تحديث لإعادة المحاولة.' : 'جارٍ تحميل الطلب...')
        else ...[
          Text('الحالة: ${quickOrderStatusLabel(status)}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (area.isNotEmpty) Text('المنطقة: $area'),
          const Text('محتويات الطلب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          if (stores.isEmpty) const Text('لم تُحدد محلات أو أصناف في الطلب.'),
          for (final raw in stores)
            if (raw is Map) ...[
              const SizedBox(height: 8),
              Text((raw['name'] ?? '').toString().trim().isEmpty
                  ? 'محل يختاره المندوب' : (raw['name'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
              if ((raw['items'] ?? '').toString().trim().isNotEmpty)
                Text((raw['items'] ?? '').toString()),
              if (raw['pricedItems'] is List)
                for (final line in raw['pricedItems'] as List)
                  if (line is Map)
                    Text('• ${line['name'] ?? 'صنف'} × ${line['qty'] ?? 1}'),
            ],
          if (notes.isNotEmpty) Text('ملاحظات: $notes'),
          const SizedBox(height: 12),
          if ((order['approxTotalPiastres'] as num? ?? 0) > 0)
            Text('التقدير الاسترشادي: ${_money(order['approxTotalPiastres'])}'),
          const Text('الأسعار تقريبية وقد تزيد أو تقل حسب المحل'),
          if (status == 'summary_pending' || status == 'summary_approved' || status == 'delivered') ...[
            const Divider(),
            Text('إجمالي الفواتير: ${_money(totals['purchases'])}'),
            Text('أجرة التوصيل: ${_money(totals['delivery'])}'),
            Text('رسوم وصّلي: ${_money(totals['serviceFee'])}'),
            Text('المقدم: ${_money(totals['prepaid'])}'),
            Text('المتبقي: ${_money(totals['due'])}',
              style: Theme.of(context).textTheme.titleLarge),
            for (final raw in receipts)
              if (raw is Map && raw['imageUrl'] is String)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('فاتورة: ${_money(raw['amountPiastres'])}'),
                    Image.network(raw['imageUrl'] as String, height: 180,
                      errorBuilder: (_, _, _) => const Text('تعذر تحميل صورة الفاتورة')),
                  ])),
          ],
          if (status == 'open')
            OutlinedButton(
              onPressed: _busy ? null : _edit,
              child: const Text('تعديل الطلب'),
            ),
          if (status == 'open' || status == 'accepted')
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: const Text('إلغاء الطلب'),
            ),
          if (status == 'summary_pending') ...[
            const SizedBox(height: 12),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.green), onPressed: _busy ? null : () => _act('approve-summary', {
                'expectedSummaryRevision': (order['summaryRevision'] as num?)?.toInt() ?? -1,
              }),
              child: const Text('موافق على الحساب النهائي')),
            OutlinedButton(onPressed: _busy ? null : () => _act('reject-summary'),
              child: const Text('مش موافق — راجع الحساب مع المندوب')),
          ],
          if (status == 'summary_approved') ...[
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.green), onPressed: _busy ? null : _showPin,
              child: const Text('إظهار رمز التسليم')),
            if (_pin != null && _pin!.isNotEmpty)
              SelectableText(_pin!, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ],
      ]),
    );
  }
}
