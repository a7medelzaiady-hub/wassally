import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/brand.dart';
import '../utils/share_links.dart';
import 'app_snack.dart';

/// مشاركة نص (واتساب أو أي تطبيق يختاره المستخدم). أي فشل بيظهر رسالة بس.
Future<void> shareText(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {
    messenger.showSnackBar(appSnack('تعذر فتح المشاركة. جرّب تاني.'));
  }
}

/// كود QR لمحل صاحب المحل: يطبعه ويلزقه على الكاشير أو يبعته كصورة.
Future<void> showStoreQrSheet(
  BuildContext context, {
  required String storeName,
  required String storeId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StoreQrSheet(storeName: storeName, storeId: storeId),
  );
}

class StoreQrSheet extends StatefulWidget {
  final String storeName;
  final String storeId;
  const StoreQrSheet({super.key, required this.storeName, required this.storeId});

  @override
  State<StoreQrSheet> createState() => _StoreQrSheetState();
}

class _StoreQrSheetState extends State<StoreQrSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _shareImage() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final boundary =
          _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('qr not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('no bytes');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/wasally-store-qr.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: ShareLinks.storeMessage(
          storeName: widget.storeName,
          storeId: widget.storeId,
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(appSnack('تعذر تجهيز صورة الكود. جرّب تاني.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final link = ShareLinks.playLink(storeId: widget.storeId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: _key,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.storeName,
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Brand.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'اطلب مننا على تطبيق وصّلي',
                      style: text.bodyMedium?.copyWith(color: Brand.ink),
                    ),
                    const SizedBox(height: 14),
                    QrImageView(
                      key: const Key('store-qr'),
                      data: link,
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Brand.green,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Brand.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'امسح الكود بكاميرا الموبايل ونزّل وصّلي',
                      style: text.bodySmall?.copyWith(color: Brand.goldDeep),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('store-qr-share'),
                onPressed: _busy ? null : _shareImage,
                style: FilledButton.styleFrom(backgroundColor: Brand.gold),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('مشاركة أو حفظ الكود'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
