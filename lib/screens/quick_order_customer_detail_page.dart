import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/quick_order_api.dart';
import '../theme/app_tokens.dart';
import '../theme/brand.dart';
import '../utils/quick_order_status.dart';
import '../utils/dialog_controllers.dart';
import '../widgets/app_ui.dart';

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

  Widget _receiptDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: CustomPaint(
      painter: _ReceiptDividerPainter(Brand.palette.line),
      child: const SizedBox(width: double.infinity, height: 1),
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

  Widget _card({Key? key, required String title, IconData? icon, required List<Widget> children}) =>
      AppCard(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(title: title, icon: icon),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      );

  void _openReceipt(String url) => showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.lg),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text('تعذر تحميل صورة الفاتورة'),
                ),
              ),
            ),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: IconButton.filledTonal(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(dialog),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ]),
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
    final receiptImages = [
      for (final raw in receipts)
        if (raw is Map && raw['imageUrl'] is String) raw,
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('تفاصيل الطلب السريع'),
        actions: [IconButton(onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')]),
      body: RefreshIndicator(
        color: AppColors.purple,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.lg),
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(color: AppColors.purple),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_error != null) AppNotice(_error!, type: AppNoticeType.error),
            if (order == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Text(
                  _error != null
                      ? 'تعذر تحميل الطلب. اسحب لأسفل أو اضغط تحديث لإعادة المحاولة.'
                      : 'جارٍ تحميل الطلب...',
                  textAlign: TextAlign.center,
                  style: AppTypography.secondary,
                ),
              )
            else ...[
              _StatusHeader(status: status, area: area),
              const SizedBox(height: AppSpacing.md),
              if (status == 'summary_pending')
                const AppNotice(type: AppNoticeType.action, 'راجع الفواتير والحساب النهائي تحت، ووافق عليه علشان يظهر رمز التسليم.'),
              if (status == 'summary_approved' && (_pin == null || _pin!.isEmpty))
                const AppNotice(type: AppNoticeType.action, 'اضغط «إظهار رمز التسليم» وادّي الرمز للمندوب لما يسلمك الطلب.'),
              _card(
                title: 'محتويات الطلب',
                icon: Icons.shopping_basket_outlined,
                children: [
                  if (stores.isEmpty)
                    const Text('لم تُحدد محلات أو أصناف في الطلب.', style: AppTypography.secondary),
                  for (final raw in stores)
                    if (raw is Map) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        (raw['name'] ?? '').toString().trim().isEmpty
                            ? 'محل يختاره المندوب'
                            : (raw['name'] ?? '').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppTypography.body,
                          color: AppColors.purple,
                        ),
                      ),
                      if ((raw['items'] ?? '').toString().trim().isNotEmpty)
                        Text((raw['items'] ?? '').toString(), style: AppTypography.bodyText),
                      if (raw['pricedItems'] is List)
                        for (final line in raw['pricedItems'] as List)
                          if (line is Map)
                            Text('• ${line['name'] ?? 'صنف'} × ${line['qty'] ?? 1}',
                                style: AppTypography.bodyText),
                    ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text('ملاحظات: $notes', style: AppTypography.secondary),
                  ],
                  if (!hasFinalBill) ...[
                    _receiptDivider(),
                    if (((order['approxTotalPiastres'] as num?) ?? 0) > 0)
                      _amount('التقدير', order['approxTotalPiastres']),
                    const Text('الحساب بيتحدد بعد الشراء، وبيتفق عليه المندوب معاك في التليفون.',
                        style: AppTypography.secondary),
                  ],
                ],
              ),
              if (hasFinalBill)
                _card(
                  key: const Key('quick-final-bill'),
                  title: 'الحساب النهائي',
                  icon: Icons.receipt_long_outlined,
                  children: [
                    _amount('الفواتير', totals['purchases']),
                    _amount('أجرة التوصيل', totals['delivery']),
                    _amount('رسوم وصّلي', totals['serviceFee']),
                    if (((totals['prepaid'] as num?) ?? 0) > 0)
                      _amount('المقدم', totals['prepaid']),
                    _receiptDivider(),
                    _amount(
                      delivered
                          ? (due < 0 ? 'الرد عند التسليم' : 'المبلغ عند التسليم')
                          : (due < 0 ? 'يُردّ لك' : 'المتبقي عند التسليم'),
                      due.abs(),
                      emphasis: true,
                    ),
                  ],
                ),
              if (hasFinalBill && receiptImages.isNotEmpty)
                _card(
                  title: 'صور الفواتير',
                  icon: Icons.photo_library_outlined,
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 0.82,
                      children: [
                        for (final raw in receiptImages)
                          InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            onTap: () => _openReceipt(raw['imageUrl'] as String),
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Column(children: [
                                Expanded(
                                  child: Image.network(
                                    raw['imageUrl'] as String,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    cacheWidth: 420,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined,
                                          color: AppColors.muted),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  color: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                  child: Text(
                                    _money(raw['amountPiastres']),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: AppTypography.bodySmall,
                                      color: AppColors.orangeDeep,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              if (status == 'summary_pending') ...[
                FilledButton.icon(
                  onPressed: _busy ? null : () => _act('approve-summary', {
                    'expectedSummaryRevision': (order['summaryRevision'] as num?)?.toInt() ?? -1,
                  }),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('موافق على الحساب النهائي'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _busy ? null : () => _act('reject-summary'),
                  child: const Text('مش موافق — راجع الحساب مع المندوب'),
                ),
              ],
              if (status == 'summary_approved') ...[
                if (_pin != null && _pin!.isNotEmpty)
                  _PinCard(pin: _pin!)
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _showPin,
                    icon: const Icon(Icons.pin_outlined),
                    label: const Text('إظهار رمز التسليم'),
                  ),
              ],
              if (status == 'open') ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل الطلب'),
                ),
              ],
              if (status == 'open' || status == 'accepted')
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: _busy ? null : _cancel,
                  child: const Text('إلغاء الطلب'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// رأس الحالة: اسم الحالة الحالية وخطوات الطلب بشكل مفهوم.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status, required this.area});

  final String status;
  final String area;

  static const _steps = <(String, IconData)>[
    ('بانتظار مندوب', Icons.hourglass_top_rounded),
    ('المندوب استلم', Icons.delivery_dining_rounded),
    ('بيشتري طلبك', Icons.shopping_bag_outlined),
    ('الحساب', Icons.receipt_long_rounded),
    ('تم التسليم', Icons.verified_rounded),
  ];

  /// رقم الخطوة الحالية (0..4)، أو -1 لو الطلب ملغي.
  static int stepOf(String status) => switch (status) {
        'open' => 0,
        'accepted' || 'assigned' || 'awaiting_advance' => 1,
        'shopping' || 'purchasing' => 2,
        'summary_pending' || 'summary_approved' => 3,
        'delivered' => 4,
        'cancelled' || 'canceled' => -1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final current = stepOf(status);
    final cancelled = current < 0;
    return Container(
      key: const Key('quick-status-header'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: cancelled ? null : AppColors.headerGradient,
        color: cancelled ? AppColors.dangerSoft : null,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            quickOrderStatusLabel(status),
            style: TextStyle(
              color: cancelled ? AppColors.danger : Colors.white,
              fontSize: AppTypography.headline,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (area.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'الحي: $area',
              style: TextStyle(
                color: cancelled ? AppColors.inkSoft : Colors.white.withValues(alpha: 0.85),
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ],
          if (!cancelled) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: Column(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= current
                              ? AppColors.orange
                              : Colors.white.withValues(alpha: 0.16),
                        ),
                        child: Icon(_steps[i].$2, size: 18, color: Colors.white),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _steps[i].$1,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: i <= current ? 1 : 0.7),
                          fontSize: AppTypography.caption,
                          fontWeight: i == current ? FontWeight.w900 : FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('quick-pin-card'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.orange, width: 1.6),
        ),
        child: Column(children: [
          const Text('رمز التسليم', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            pin,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontSize: 40,
              letterSpacing: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'ادّي الرمز للمندوب بعد ما تستلم طلبك بس.',
            textAlign: TextAlign.center,
            style: AppTypography.secondary,
          ),
        ]),
      );
}


class _ReceiptDividerPainter extends CustomPainter {
  const _ReceiptDividerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 8) {
      final end = (x + 4).clamp(0.0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0.5), Offset(end, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_ReceiptDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}
