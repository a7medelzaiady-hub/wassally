import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/order_issue_service.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';

/// زرار «عندي مشكلة في الطلب» في تفاصيل الطلب. بيظهر بعد ما المحل يأكد الطلب
/// (قبل كده فيه شريط «مستني المحل يأكد» وزرار واتساب).
class OrderIssueButton extends StatefulWidget {
  final AppOrder order;
  const OrderIssueButton({super.key, required this.order});

  static bool visibleFor(AppOrder order) => order.status != OrderStatus.newOrder;

  @override
  State<OrderIssueButton> createState() => _OrderIssueButtonState();
}

class _OrderIssueButtonState extends State<OrderIssueButton> {
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    OrderIssueService.alreadySent(widget.order.id).then((sent) {
      if (mounted && sent) setState(() => _sent = true);
    });
  }

  Future<void> _open() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => OrderIssueSheet(order: widget.order),
    );
    if (ok == true && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!OrderIssueButton.visibleFor(widget.order)) return const SizedBox.shrink();
    if (_sent) {
      return const Padding(
        key: Key('order-issue-sent'),
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'بلاغك وصل لفريق وصّلي وهيتابعوه معاك.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const Key('order-issue-open'),
        onPressed: _open,
        icon: const Icon(Icons.report_gmailerrorred_outlined, size: 19),
        label: const Text('عندي مشكلة في الطلب'),
        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
      ),
    );
  }
}

class OrderIssueSheet extends StatefulWidget {
  final AppOrder order;

  /// للاختبارات: بدل الإرسال الحقيقي.
  final Future<bool> Function(OrderIssueType type, String note)? submit;

  const OrderIssueSheet({super.key, required this.order, this.submit});

  @override
  State<OrderIssueSheet> createState() => _OrderIssueSheetState();
}

class _OrderIssueSheetState extends State<OrderIssueSheet> {
  OrderIssueType? _type;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final type = _type;
    if (type == null) {
      setState(() => _error = 'اختار نوع المشكلة الأول.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final submit = widget.submit;
      final ok = submit != null
          ? await submit(type, _note.text)
          : await OrderIssueService.report(widget.order, type: type, note: _note.text);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack('بلاغك وصل. فريق وصّلي هيراجعه ويتواصل معاك.'),
        );
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إرسال البلاغ. تأكد من النت وحاول تاني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إيه المشكلة؟',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'طلب ${widget.order.storeName}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in OrderIssueType.values)
                  ChoiceChip(
                    key: Key('order-issue-${t.key}'),
                    label: Text(t.label),
                    selected: _type == t,
                    showCheckmark: false,
                    onSelected: _busy ? null : (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('order-issue-note'),
              controller: _note,
              enabled: !_busy,
              maxLength: OrderIssueService.maxNote,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'اكتب التفاصيل باختصار (اختياري) — مثلًا: ناقص كيس لبن',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
              ),
            FilledButton(
              key: const Key('order-issue-send'),
              onPressed: _busy ? null : _send,
              child: Text(_busy ? 'بيتبعت...' : 'ابعت البلاغ'),
            ),
          ],
        ),
      ),
    );
  }
}
