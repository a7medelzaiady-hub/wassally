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

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  Widget _amount(String label, Object? value, {bool emphasis = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _money(value),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                  fontSize: emphasis ? 18 : null,
                ),
              ),
            ),
          ],
        ),
      );

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
    final delivered = status == 'delivered';
    final hasFinalBill =
        delivered || status == 'summary_pending' || status == 'summary_approved';
    final due = (totals['due'] as num?) ?? 0;
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
          _section(quickOrderStatusLabel(status), [
            if (area.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(area),
              ),
          ]),
          if (hasFinalBill) ...[
            _section('الحساب النهائي', [
              _amount('الفواتير', totals['purchases']),
              _amount('أجرة التوصيل', totals['delivery']),
              _amount('رسوم وصّلي', totals['serviceFee']),
              if (((totals['prepaid'] as num?) ?? 0) > 0)
                _amount('المقدم', totals['prepaid']),
              const Divider(height: 20),
              _amount(
                delivered
                    ? (due < 0 ? 'الرد عند التسليم' : 'المبلغ عند التسليم')
                    : (due < 0 ? 'يُردّ لك' : 'المتبقي عند التسليم'),
                due.abs(),
                emphasis: true,
              ),
            ]),
            if (receipts.isNotEmpty)
              _section('الفواتير', [
                for (final raw in receipts)
                  if (raw is Map && raw['imageUrl'] is String) ...[
                    _amount('فاتورة', raw['amountPiastres']),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        raw['imageUrl'] as String,
                        height: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('تعذر تحميل صورة الفاتورة'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ]),
          ],
          _section('محتويات الطلب', [
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
            if (!hasFinalBill) ...[
              const SizedBox(height: 8),
              if (((order['approxTotalPiastres'] as num?) ?? 0) > 0)
                _amount('التقدير', order['approxTotalPiastres']),
              const Text('الأسعار تقريبية لحد صدور الحساب النهائي.'),
            ],
          ]),
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
