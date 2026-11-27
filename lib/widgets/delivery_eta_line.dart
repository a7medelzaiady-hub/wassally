import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/store_eta.dart';
import '../theme/app_theme.dart';
import '../utils/delivery_eta.dart';

/// صفحة الدفع: «التوصيل المتوقع: 25–35 دقيقة بعد ما المحل يأكد».
class CheckoutEtaLine extends StatelessWidget {
  final String storeId;
  const CheckoutEtaLine({super.key, required this.storeId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EtaRange>(
      future: StoreEta.rangeFor(storeId),
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return const SizedBox.shrink();
        return Row(
          key: const Key('checkout-eta'),
          children: [
            const Icon(Icons.schedule_rounded, size: 18, color: AppColors.purple),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'التوصيل المتوقع: ${etaRangeText(r)} بعد ما المحل يأكد طلبك',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// تفاصيل الطلب: «متوقع يوصلك بين 6:25 و 6:40 م». بيتحدّث كل دقيقة طول ما فيه تقدير.
class OrderEtaLine extends StatefulWidget {
  final AppOrder order;

  /// للاختبارات بس.
  final DateTime Function() clock;
  final EtaRange? storeEtaOverride;

  const OrderEtaLine({
    super.key,
    required this.order,
    this.clock = DateTime.now,
    this.storeEtaOverride,
  });

  @override
  State<OrderEtaLine> createState() => _OrderEtaLineState();
}

class _OrderEtaLineState extends State<OrderEtaLine> {
  EtaRange? _storeEta;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _storeEta = widget.storeEtaOverride;
    if (_storeEta == null) {
      StoreEta.rangeFor(widget.order.storeId).then((r) {
        if (mounted) setState(() => _storeEta = r);
      });
    }
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeEta = _storeEta;
    if (storeEta == null) return const SizedBox.shrink();
    final eta = deliveryEtaFor(widget.order, storeEta, widget.clock());
    if (eta == null) return const SizedBox.shrink();
    final color = eta.overdue ? AppColors.warning : AppColors.purple;
    final text = eta.overdue
        ? 'اتأخر شوية عن المتوقع (كان ${eta.text}). لو قلقان كلّم المندوب أو وصّلي.'
        : 'متوقع يوصلك ${eta.text}';
    return Container(
      key: Key(eta.overdue ? 'order-eta-overdue' : 'order-eta'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: eta.overdue ? AppColors.warningSoft : AppColors.purpleSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
