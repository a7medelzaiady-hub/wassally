import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'navigation.dart';

/// رفع الصور على Cloudinary باستخدام unsigned presets (من غير سيرفر ولا Blaze).
/// فيه 3 presets في Cloudinary، كل واحد له Asset folder ثابت:
///   stores_unsigned / products_unsigned / banners_unsigned
///
/// لو true: الرفع من المعرض شغال.
/// لو false: بيظهر للمستخدم نافذة يلصق فيها رابط الصورة (https) بدل الرفع.
// ignore: prefer_const_declarations
final bool kImageUploadEnabled = true;

class ImageService {
  const ImageService._();

  static const String _cloudName = 'g3n5pdfz';

  /// المجلدات المسموحة (كل واحد ليه preset اسمه `<folder>_unsigned`).
  static const Set<String> _allowedFolders = {'stores', 'products', 'banners'};

  /// بيفتح معرض الصور في الموبايل، وبعد ما تختار صورة بيرفعها على Cloudinary
  /// في المجلد [folder] (stores / products / banners) وبيرجّع رابط الصورة (https).
  ///
  /// [storeId] متساب في التوقيع عشان الشاشات اللي بتستدعيه متتأثرش،
  /// بس مش مستخدم دلوقتي لأن مفيش توقيع من السيرفر.
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

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = '${folder}_unsigned'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode != 200) {
      throw StateError('Upload failed: ${response.statusCode}');
    }
    final url = (jsonDecode(response.body) as Map)['secure_url'] as String?;
    if (url == null || url.isEmpty) throw StateError('No URL returned');
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