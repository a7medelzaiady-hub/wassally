import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/order.dart';
import '../theme/brand.dart';
import '../utils/order_receipt.dart';
import 'app_snack.dart';

/// بيفتح معاينة الإيصال، ومنها العميل يشاركه أو يحفظه كصورة.
/// الصورة بتترسم على الموبايل من بيانات الطلب: صفر قراءات وصفر كتابات.
Future<void> showOrderReceiptSheet(BuildContext context, AppOrder order) =>
    showReceiptSheet(context, OrderReceipt.of(order));

/// نفس المعاينة لأي إيصال (طلب أو سلة).
Future<void> showReceiptSheet(BuildContext context, OrderReceipt receipt) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OrderReceiptSheet(receipt: receipt),
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
      text: widget.receipt.shareText,
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
    // خلفية رمادي فاتح عشان الورقة البيضا وحوافها المقصوصة تبان.
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE9E9EC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
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
      ),
    );
  }
}

/// شكل الإيصال نفسه (هو اللي بيتحوّل لصورة): ورقة فاتورة حرارية
/// (ورق أبيض ضيق، حواف مقصوصة، خطوط متقطعة، أبيض وأسود، وQR لتحميل التطبيق).
class OrderReceiptCard extends StatelessWidget {
  final OrderReceipt receipt;

  /// جوه صفحة تفاصيل الطلب: من غير QR وسطر الشكر (بيظهروا في الصورة بس).
  final bool inline;
  const OrderReceiptCard({super.key, required this.receipt, this.inline = false});

  static const _ink = Color(0xFF1B1B1B);
  static const _faded = Color(0xFF5E5E5E);
  static const _paper = Color(0xFFFFFEFA);

  @override
  Widget build(BuildContext context) {
    const numbers = [FontFeature.tabularFigures()];
    TextStyle base(double size, {FontWeight w = FontWeight.w500, Color c = _ink}) =>
        TextStyle(fontSize: size, fontWeight: w, color: c, height: 1.35, fontFeatures: numbers);

    Widget row(ReceiptLine l, {double size = 13.5}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l.label,
                  style: base(l.strong ? 15.5 : size, w: l.strong ? FontWeight.w900 : FontWeight.w500),
                ),
              ),
              if (l.value.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  l.value,
                  style: base(l.strong ? 15.5 : size, w: l.strong ? FontWeight.w900 : FontWeight.w700),
                ),
              ],
            ],
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: ClipPath(
          clipper: const _TornEdges(),
          child: Container(
            color: _paper,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('وصّلي', textAlign: TextAlign.center, style: base(26, w: FontWeight.w900)),
                Text(receipt.title, textAlign: TextAlign.center, style: base(13, c: _faded)),
                if (receipt.storeName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(receipt.storeName, textAlign: TextAlign.center, style: base(15, w: FontWeight.w800)),
                ],
                const _Dashes(),
                if (receipt.orderNumber.isNotEmpty) row(ReceiptLine('رقم الطلب', receipt.orderNumber), size: 12.5),
                if (receipt.date.isNotEmpty) row(ReceiptLine('التاريخ', receipt.date), size: 12.5),
                const _Dashes(),
                for (final l in receipt.items) row(l),
                const _Dashes(),
                for (final l in receipt.totals) row(l),
                if (receipt.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(receipt.note, textAlign: TextAlign.center, style: base(11, c: _faded)),
                ],
                if (!inline) const _Dashes(),
                if (!inline && receipt.qrLink.isNotEmpty) ...[
                  Center(
                    child: QrImageView(
                      key: const Key('receipt-qr'),
                      data: receipt.qrLink,
                      size: 92,
                      padding: EdgeInsets.zero,
                      backgroundColor: _paper,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: _ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('امسح الكود وحمّل التطبيق', textAlign: TextAlign.center, style: base(11, c: _faded)),
                  const SizedBox(height: 8),
                ],
                if (!inline)
                  Text('شكرًا لاستخدامك وصّلي', textAlign: TextAlign.center, style: base(12.5, w: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// خط متقطع زي ورق الكاشير.
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final count = (c.maxWidth / 7).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
              (_) => const SizedBox(
                width: 4,
                height: 1.2,
                child: ColoredBox(color: Color(0xFF8A8A8A)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// حواف فوق وتحت مقصوصة على شكل سنون (زي الورقة المقطوعة من الماكينة).
class _TornEdges extends CustomClipper<Path> {
  const _TornEdges();

  @override
  Path getClip(Size size) {
    const tooth = 8.0;
    const depth = 5.0;
    final path = Path()..moveTo(0, depth);
    var x = 0.0;
    var up = true;
    while (x < size.width) {
      x = (x + tooth / 2).clamp(0, size.width).toDouble();
      path.lineTo(x, up ? 0 : depth);
      up = !up;
    }
    path.lineTo(size.width, size.height - depth);
    x = size.width;
    up = true;
    while (x > 0) {
      x = (x - tooth / 2).clamp(0, size.width).toDouble();
      path.lineTo(x, up ? size.height : size.height - depth);
      up = !up;
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
