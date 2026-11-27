import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/stock_photo_search.dart';
import 'cached_net_image.dart';

/// نتائج CC0 للمراجعة اليدوية: لا تُعيَّن صورة لمنتج دون اختيار المستخدم.
Future<StockPhotoCandidate?> showStockPhotoPicker(
  BuildContext context, {
  required String name,
}) {
  return showDialog<StockPhotoCandidate>(
    context: context,
    builder: (_) => _StockPhotoPicker(initialName: name),
  );
}

class _StockPhotoPicker extends StatefulWidget {
  final String initialName;
  const _StockPhotoPicker({required this.initialName});

  @override
  State<_StockPhotoPicker> createState() => _StockPhotoPickerState();
}

class _StockPhotoPickerState extends State<_StockPhotoPicker> {
  late final TextEditingController _query = TextEditingController(
    text: StockPhotoSearch.suggestedQuery(widget.initialName),
  );
  List<StockPhotoCandidate> _results = const [];
  String? _error;
  bool _busy = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _query.text.trim().length >= 2) _search();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _searched = false;
      _error = null;
      _results = const [];
    });
    try {
      final result = await StockPhotoSearch.search(_query.text);
      if (!mounted) return;
      setState(() {
        _results = result;
        _searched = true;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر البحث الآن. راجع الإنترنت أو استخدم صورة من جهازك.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dialog يظل قابلًا للاستخدام مع ظهور لوحة المفاتيح على شاشة صغيرة.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final height = (screenHeight - keyboardHeight - 52)
        .clamp(200.0, screenHeight * 0.78);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: SizedBox(
        width: 580,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('اختار صورة مناسبة للصنف',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                maxLength: 90,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'ابحث باسم الصنف أو وصفه بالإنجليزي',
                  hintText: 'مثل: tomato, milk, rice',
                  suffixIcon: IconButton(
                    onPressed: _busy ? null : _search,
                    icon: const Icon(Icons.search),
                    tooltip: 'بحث',
                  ),
                ),
              ),
              const Text(
                'صور توضيحية مجانية (CC0) من Openverse. اختار صورة مطابقة للنوع '
                'قبل اعتمادها؛ النتائج مش بالضرورة نفس الماركة أو حجم العبوة.',
                style: TextStyle(fontSize: 11.5, height: 1.3),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!, textAlign: TextAlign.center))
                        : _results.isEmpty
                            ? Center(child: Text(_searched
                                ? 'مفيش صور مطابقة. جرّب كلمة إنجليزية أو ارفع صورتك.'
                                : 'اكتب اسم الصنف واضغط بحث.'))
                            : GridView.builder(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 0.8,
                                ),
                                itemCount: _results.length,
                                itemBuilder: (_, i) {
                                  final photo = _results[i];
                                  return Semantics(
                                    button: true,
                                    label: 'اختيار صورة ${i + 1}: ${photo.title}',
                                    child: InkWell(
                                      key: Key('stock-photo-${i + 1}'),
                                      onTap: () => Navigator.pop(context, photo),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: CachedNetImage(
                                                url: photo.previewUrl,
                                                width: double.infinity,
                                                memCacheWidth: 220,
                                                errorWidget: const Center(
                                                  child: Icon(Icons.broken_image_outlined)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  photo.title.isEmpty ? 'صورة CC0' : photo.title,
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                  style: const TextStyle(fontSize: 10.5),
                                                ),
                                              ),
                                              InkWell(
                                                key: Key('stock-photo-source-${i + 1}'),
                                                onTap: () => launchUrl(
                                                  Uri.parse(photo.sourcePageUrl),
                                                  mode: LaunchMode.externalApplication,
                                                ),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(3),
                                                  child: Icon(Icons.open_in_new, size: 14),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
