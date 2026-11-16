import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'navigation.dart';
import 'order_gateway.dart';

/// رفع الصور على Cloudinary بتوقيع قصير العمر يصدره Order Gateway بعد التحقق من المستخدم والصلاحية.
///
/// لو true: الرفع من المعرض شغال.
/// لو false: بيظهر للمستخدم نافذة يلصق فيها رابط الصورة (https) بدل الرفع.
// ignore: prefer_const_declarations
final bool kImageUploadEnabled = true;

class ImageService {
  const ImageService._();

  static const String _cloudName = 'g3n5pdfz';

  /// المجلدات المسموحة؛ التوقيع يربط المستخدم بالمحل على الخادم.
  static const Set<String> _allowedFolders = {'stores', 'products', 'banners'};

  /// بيفتح معرض الصور في الموبايل، وبعد ما تختار صورة بيرفعها على Cloudinary
  /// في المجلد [folder] (stores / products / banners) وبيرجّع رابط الصورة (https).
  ///
  /// صاحب المحل لا يستطيع رفع صور خارج المحل المرتبط بحسابه؛ البانرات للإدارة فقط.
  ///
  /// بيرجّع null لو المستخدم لغى الاختيار. ولو الرفع فشل بيرمي استثناء
  /// (عشان الشاشة تعرض رسالة الخطأ بدل ما يفشل في صمت).
  static Future<String?> pickAndUpload(String folder, {String? storeId}) async {
    if (!kImageUploadEnabled) return _askForUrl();

    if (!_allowedFolders.contains(folder)) {
      throw ArgumentError('مجلد غير مسموح: $folder');
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80, // ضغط محلي قبل الرفع لتقليل استهلاك البيانات والمساحة
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    // حد أقصى 5MB قبل الرفع.
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('الصورة كبيرة (أقصى حجم 5MB)');
    }

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
    final signResponse = await http.post(
      Uri.parse('$root/v1/uploads/sign'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'folder': folder, 'storeId': storeId ?? ''}),
    ).timeout(const Duration(seconds: 20));
    if (signResponse.statusCode != 200) {
      String message = 'تعذر تأمين رفع الصورة (${signResponse.statusCode}).';
      try {
        final data = jsonDecode(signResponse.body);
        if (data is Map && data['error'] is String) message = data['error'] as String;
      } catch (_) {}
      throw StateError(message);
    }

    final signed = jsonDecode(signResponse.body);
    if (signed is! Map) throw StateError('استجابة توقيع الصورة غير صحيحة.');
    final cloudName = (signed['cloudName'] ?? '').toString();
    final apiKey = (signed['apiKey'] ?? '').toString();
    final timestamp = (signed['timestamp'] ?? '').toString();
    final uploadFolder = (signed['folder'] ?? '').toString();
    final allowedFormats = (signed['allowedFormats'] ?? '').toString();
    final signature = (signed['signature'] ?? '').toString();
    final overwrite = signed['overwrite'] == false ? 'false' : '';
    final uniqueFilename = signed['uniqueFilename'] == true ? 'true' : '';
    final useFilename = signed['useFilename'] == false ? 'false' : '';
    if ([cloudName, apiKey, timestamp, uploadFolder, allowedFormats, signature,
      overwrite, uniqueFilename, useFilename]
        .any((value) => value.isEmpty)) {
      throw StateError('بيانات توقيع الصورة ناقصة.');
    }

    final uri = Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = apiKey
      ..fields['timestamp'] = timestamp
      ..fields['folder'] = uploadFolder
      ..fields['allowed_formats'] = allowedFormats
      ..fields['overwrite'] = overwrite
      ..fields['unique_filename'] = uniqueFilename
      ..fields['use_filename'] = useFilename
      ..fields['signature'] = signature
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: picked.name.isEmpty
              ? '${DateTime.now().millisecondsSinceEpoch}.jpg'
              : picked.name,
        ),
      );

    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode != 200) {
      throw StateError('فشل رفع الصورة (${response.statusCode}).');
    }
    final result = jsonDecode(response.body);
    final url = result is Map ? result['secure_url'] as String? : null;
    if (url == null || url.isEmpty) throw StateError('لم يرجع Cloudinary رابط الصورة.');
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