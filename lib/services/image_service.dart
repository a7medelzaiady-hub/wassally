import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'navigation.dart';
import 'order_gateway.dart';

/// رفع الصور عبر Order Gateway؛ الخادم يتحقق من المستخدم والصلاحية والحجم وبصمة الملف قبل Cloudinary.
///
/// لو true: الرفع من المعرض شغال.
/// لو false: بيظهر للمستخدم نافذة يلصق فيها رابط الصورة (https) بدل الرفع.
// ignore: prefer_const_declarations
final bool kImageUploadEnabled = true;

class ImageService {
  const ImageService._();

  /// المجلدات المسموحة؛ الخادم يربط المستخدم بالمحل ويتحقق من صلاحية الرفع.
  static const Set<String> _allowedFolders = {'stores', 'products', 'banners', 'special_requests'};

  /// بيفتح معرض الصور في الموبايل، وبعد ما تختار صورة بيرفعها على Cloudinary
  /// في المجلد [folder] (stores / products / banners / special_requests) وبيرجّع رابط الصورة (https).
  ///
  /// صور الطلبات الخاصة تُحفظ في مجلد منفصل خاص بالعميل، وصور المحل/المنتجات للمالك، والبانرات للإدارة فقط.
  ///
  /// بيرجّع null لو المستخدم لغى الاختيار. ولو الرفع فشل بيرمي استثناء
  /// (عشان الشاشة تعرض رسالة الخطأ بدل ما يفشل في صمت).
  static Future<String?> pickAndUpload(String folder, {String? storeId}) async {
    if (!kImageUploadEnabled) return _askForUrl();

    if (!_allowedFolders.contains(folder)) {
      throw ArgumentError('مجلد غير مسموح: $folder');
    }

    // البوسترات بجودة أعلى (لحد 1600) علشان تفضل واضحة على الشاشات الكبيرة.
    final maxSide = folder == 'banners' ? 1600.0 : 1024.0;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 80, // ضغط محلي قبل الرفع لتقليل استهلاك البيانات والمساحة
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    // حد أقصى 5MB قبل الرفع.
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('الصورة كبيرة (أقصى حجم 5MB)');
    }
    return _upload(
      bytes: bytes,
      filename: picked.name.isEmpty ? 'upload' : picked.name,
      folder: folder,
      storeId: storeId,
    );
  }

  /// رفع رسالة صوتية للطلب الخاص (m4a) على Cloudinary عن طريق الـWorker.
  /// الطلب بيشيل الرابط بس، والملف بيتمسح بعد التسليم زي الصور.
  static Future<String> uploadVoice(List<int> bytes, {required String storeId}) async {
    if (bytes.isEmpty) throw StateError('التسجيل الصوتي فارغ. حاول مرة أخرى.');
    if (bytes.length > 1024 * 1024) {
      throw StateError('الرسالة الصوتية أكبر من الحد المسموح. سجل رسالة أقصر.');
    }
    return _upload(
      bytes: bytes,
      filename: 'voice.m4a',
      folder: 'special_requests',
      storeId: storeId,
    );
  }

  /// صورة فاتورة «طلباتك على السريع»: الكاميرا افتراضيًا، والرفع لمجلد quick_receipts للطلب ده بس.
  /// الـWorker بيرفض الرفع لو المندوب مش المعيّن أو الطلب مش «جاري الشراء».
  /// بيرجّع null لو المندوب لغى التصوير.
  static Future<String?> pickAndUploadQuickReceipt(
    String orderId, {
    ImageSource source = ImageSource.camera,
  }) async {
    if (orderId.isEmpty) throw ArgumentError('orderId');
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('الصورة كبيرة (أقصى حجم 5MB)');
    }
    return _upload(
      bytes: bytes,
      filename: picked.name.isEmpty ? 'receipt.jpg' : picked.name,
      folder: 'quick_receipts',
      orderId: orderId,
    );
  }

  /// صورة «صوّر طلبك» للطلب السريع: الكاميرا أو المعرض، والرفع لمجلد العميل نفسه.
  /// بيرجّع null لو العميل لغى الاختيار. الصور بتتمسح بعد تأكيد الاستلام.
  static Future<String?> pickAndUploadQuickRequest({
    ImageSource source = ImageSource.camera,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('الصورة كبيرة (أقصى حجم 5MB)');
    }
    return _upload(
      bytes: bytes,
      filename: picked.name.isEmpty ? 'order.jpg' : picked.name,
      folder: 'quick_requests',
    );
  }

  static Future<String> _upload({
    required List<int> bytes,
    required String filename,
    required String folder,
    String? storeId,
    String? orderId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل الدخول قبل رفع الصورة.');
    if (!OrderGateway.isConfigured) {
      throw StateError('خدمة رفع الصور الآمنة غير مهيأة في إصدار التطبيق.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('تعذر تأكيد تسجيل الدخول. سجّل الدخول مرة أخرى.');
    }

    final root = OrderGateway.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final appCheck = await OrderGateway.appCheckHeaders();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$root/v1/uploads'),
    )
      ..headers.addAll(appCheck)
      ..headers['Authorization'] = 'Bearer $idToken'
      ..headers['Accept'] = 'application/json'
      ..fields['folder'] = folder
      ..fields['storeId'] = storeId ?? ''
      ..fields['orderId'] = orderId ?? ''
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

    final uploadResponse = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 90)),
    );
    if (uploadResponse.statusCode != 200) {
      String message = 'تعذر رفع الصورة (${uploadResponse.statusCode}).';
      try {
        final data = jsonDecode(uploadResponse.body);
        if (data is Map && data['error'] is String) {
          message = data['error'] as String;
        }
      } catch (_) {}
      throw StateError(message);
    }

    final result = jsonDecode(uploadResponse.body);
    final url = result is Map ? result['url'] as String? : null;
    if (url == null || !isValidImageUrl(url) ||
        !((Uri.parse(url).host == 'res.cloudinary.com') ||
          Uri.parse(url).host.endsWith('.res.cloudinary.com'))) {
      throw StateError('خدمة الصور لم ترجع رابطًا آمنًا صالحًا.');
    }
    return url;
  }
}

/// بيتأكد إن النص رابط صورة https صالح (وبحد أقصى 450 حرف عشان يدخل في حدود القواعد).
bool isValidImageUrl(String input) {
  final t = input.trim();
  if (t.isEmpty || t.length > 450) return false;
  final u = Uri.tryParse(t);
  return u != null && u.scheme == 'https' && u.host.contains('.');
}

Future<String?> _askForUrl() async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => const Directionality(
      textDirection: TextDirection.rtl,
      child: _ImageUrlDialog(),
    ),
  );
}

class _ImageUrlDialog extends StatefulWidget {
  const _ImageUrlDialog();

  @override
  State<_ImageUrlDialog> createState() => _ImageUrlDialogState();
}

class _ImageUrlDialogState extends State<_ImageUrlDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _ok() {
    final t = _ctrl.text.trim();
    if (!isValidImageUrl(t)) {
      setState(() => _error = 'اكتب رابط صورة صحيح يبدأ بـ https://');
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('رابط الصورة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'رفع الصور من المعرض متوقف مؤقتًا. الصق رابط الصورة (https) من أي موقع صور.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'https://...',
              errorText: _error,
            ),
            onSubmitted: (_) => _ok(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        TextButton(onPressed: _ok, child: const Text('تأكيد')),
      ],
    );
  }
}