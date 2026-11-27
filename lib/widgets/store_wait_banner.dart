import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order.dart';
import '../screens/info_pages.dart' show openWasallyWhatsApp;
import '../theme/app_theme.dart';
import '../utils/store_wait.dart';

/// شريط للعميل في تفاصيل الطلب طول ما المحل لسه ما أكدش الطلب.
///
/// محسوب من حالة الطلب ووقته بس: من غير أي قراءة أو مستمع جديد. الطلب نفسه
/// بيتحدّث من المستمع الموجود، فأول ما المحل يبدأ التجهيز الشريط بيختفي لوحده.
/// المؤقت بيحدّث العدّاد كل 30 ثانية بس طول ما فيه انتظار.
class StoreWaitBanner extends StatefulWidget {
  final AppOrder order;

  /// للاختبارات بس.
  final DateTime Function() clock;

  const StoreWaitBanner({super.key, required this.order, this.clock = DateTime.now});

  @override
  State<StoreWaitBanner> createState() => _StoreWaitBannerState();
}

class _StoreWaitBannerState extends State<StoreWaitBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant StoreWaitBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  bool get _waiting =>
      storeWaitStageOf(widget.order, widget.clock()) != StoreWaitStage.none;

  void _syncTimer() {
    if (_waiting) {
      _tick ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_waiting) _stop();
      });
    } else {
      _stop();
    }
  }

  void _stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final now = widget.clock();
    final stage = storeWaitStageOf(order, now);
    if (stage == StoreWaitStage.none) return const SizedBox.shrink();

    final late = stage == StoreWaitStage.late;
    final age = order.createdAt == null
        ? ''
        : storeWaitAgeText(storeWaitElapsed(order.createdAt!, now));
    final title = late ? 'المحل اتأخر في تأكيد طلبك' : 'مستني المحل يأكد طلبك';
    final body = late
        ? 'الطلب اتبعت ${age.isEmpty ? '' : '($age) '}والمحل لسه ما بدأش يجهّزه. '
            'التأخير ظاهر لفريق وصّلي، ولو حابب تطمن كلّمنا.'
        : 'طلبك وصل للمحل${age.isEmpty ? '' : ' ($age)'}. '
            'هنبلّغك أول ما يبدأ يجهّزه.';
    final fg = late ? AppColors.danger : AppColors.warning;
    final bg = late ? AppColors.dangerSoft : AppColors.warningSoft;

    return Container(
      key: Key(late ? 'store-wait-late' : 'store-wait-waiting'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(late ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                  size: 20, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.4),
          ),
          if (late)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('store-wait-support'),
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                // قراءة واحدة لرقم الدعم وقت الضغط بس (نفس زرار «تواصل معنا»).
                onPressed: () => openWasallyWhatsApp(_supportMessage(order)),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('كلّم وصّلي على واتساب'),
              ),
            ),
        ],
      ),
    );
  }
}

String _supportMessage(AppOrder order) {
  final ref = order.id.length > 6 ? order.id.substring(0, 6) : order.id;
  final store = order.storeName.trim().isEmpty ? 'المحل' : order.storeName.trim();
  return 'السلام عليكم، طلبي من $store (رقم $ref) لسه مستني تأكيد المحل.';
}
