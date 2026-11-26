import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/order.dart';
import '../theme/brand.dart';
import '../utils/order_receipt.dart';
import 'app_snack.dart';

/// بيفتح معاينة الإيصال، ومنها العميل يشاركه أو يحفظه كصورة.
/// الصورة بتترسم على الموبايل من بيانات الطلب: صفر قراءات وصفر كتابات.
Future<void> showOrderReceiptSheet(BuildContext context, AppOrder order) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OrderReceiptSheet(receipt: OrderReceipt.of(order)),
  );
}

class OrderReceiptSheet extends StatefulWidget {
  final OrderReceipt receipt;
  const OrderReceiptSheet({super.key, required this.receipt});

  @override
  State<OrderReceiptSheet> createState() => _OrderReceiptSheetState();
}

class _OrderReceiptSheetState extends State<OrderReceiptSheet> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  /// بيحوّل كارت الإيصال لصورة PNG على الموبايل.
  Future<Uint8List> _capture() async {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('receipt not ready');
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('no bytes');
    return bytes.buffer.asUint8List();
  }

  Future<void> _shareBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${widget.receipt.fileName}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: 'إيصال طلب ${widget.receipt.orderNumber} من وصّلي',
    ));
  }

  Future<void> _share() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _shareBytes(await _capture());
    } catch (_) {
      messenger.showSnackBar(appSnack('تعذر تجهيز صورة الإيصال. جرّب تاني.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// حفظ مباشر في معرض الصور (ألبوم «وصّلي»). على الأجهزة القديمة اللي
  /// محتاجة صلاحية تخزين (أندرويد 9 وأقل) بنفتح المشاركة بدل الحفظ،
  /// والعميل يختار منها «حفظ».
  Future<void> _save() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      bytes = await _capture();
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(
        bytes,
        album: 'وصّلي',
        name: widget.receipt.fileName.replaceAll('.png', ''),
      );
      messenger.showSnackBar(appSnack('اتحفظ الإيصال في الصور (ألبوم وصّلي).'));
    } catch (_) {
      if (bytes != null) {
        try {
          await _shareBytes(bytes);
        } catch (_) {
          messenger.showSnackBar(appSnack('تعذر حفظ الإيصال. جرّب تاني.'));
        }
      } else {
        messenger.showSnackBar(appSnack('تعذر تجهيز صورة الإيصال. جرّب تاني.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: OrderReceiptCard(receipt: widget.receipt),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('receipt-save'),
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: Brand.gold),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: const Text('حفظ في الصور'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('receipt-share'),
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('مشاركة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// شكل الإيصال نفسه (هو اللي بيتحوّل لصورة).
class OrderReceiptCard extends StatelessWidget {
  final OrderReceipt receipt;
  const OrderReceiptCard({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(ReceiptLine l) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l.label,
                  style: l.strong
                      ? text.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                      : text.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.value,
                style: l.strong
                    ? text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Brand.goldDeep,
                      )
                    : text.bodyMedium,
              ),
            ],
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Brand.green,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(
                  'وصّلي',
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  'إيصال طلب',
                  style: text.titleSmall?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                row(ReceiptLine('رقم الطلب', receipt.orderNumber)),
                if (receipt.date.isNotEmpty)
                  row(ReceiptLine('التاريخ', receipt.date)),
                if (receipt.storeName.isNotEmpty)
                  row(ReceiptLine('المحل', receipt.storeName)),
                const Divider(height: 18),
                for (final l in receipt.items) row(l),
                const Divider(height: 18),
                for (final l in receipt.totals) row(l),
                const SizedBox(height: 12),
                Text(
                  'شكرًا لاستخدامك وصّلي',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: Brand.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
