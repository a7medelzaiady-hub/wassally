import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/quick_order_api.dart';
import '../theme/brand.dart';

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

  Future<void> _act(bool approve) async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = approve
          ? await QuickOrderApi.approveSummary(widget.orderId,
              (order['summaryRevision'] as num?)?.toInt() ?? -1)
          : await QuickOrderApi.rejectSummary(widget.orderId);
      if (!mounted) return;
      final updated = result['order'];
      if (updated is Map) {
        setState(() { _order = Map<String, dynamic>.from(updated); _error = null; });
      } else {
        await _refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPin() async {
    setState(() => _busy = true);
    try {
      final result = await QuickOrderApi.deliveryPin(widget.orderId);
      if (!mounted) return;
      setState(() => _pin = (result['pin'] ?? result['deliveryPin'] ?? '').toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String statusLabel(String status) => switch (status) {
    'open' => 'بانتظار مندوب',
    'accepted' || 'assigned' => 'المندوب استلم الطلب',
    'shopping' || 'purchasing' => 'المندوب بيشتري طلبك',
    'summary_pending' => 'راجع الحساب النهائي',
    'summary_approved' => 'تمت الموافقة على الحساب',
    'delivered' => 'تم التسليم',
    'cancelled' || 'canceled' => 'ملغي',
    _ => 'جارٍ متابعة الطلب',
  };

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
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب السريع'),
        actions: [IconButton(onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh), tooltip: 'تحديث')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (order == null) const Text('جارٍ تحميل الطلب...') else ...[
          Text('الحالة: ${statusLabel(status)}', style: Theme.of(context).textTheme.titleLarge),
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
          if (status == 'summary_pending') ...[
            const SizedBox(height: 12),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.green), onPressed: _busy ? null : () => _act(true),
              child: const Text('موافق على الحساب النهائي')),
            OutlinedButton(onPressed: _busy ? null : () => _act(false),
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
