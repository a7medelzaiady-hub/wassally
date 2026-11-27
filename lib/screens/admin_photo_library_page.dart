import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/image_service.dart';
import '../services/photo_library.dart';
import '../services/stock_photo_search.dart';
import '../utils/product_photo.dart';
import '../theme/app_theme.dart';
import '../utils/img.dart';
import '../widgets/app_snack.dart';
import '../widgets/cached_net_image.dart';
import '../widgets/dialogs.dart';
import '../widgets/stock_photo_picker.dart';

/// «مكتبة صور وصّلي» للإدارة: صورة حقيقية لكل اسم صنف شائع، بتظهر في كل المحلات
/// للأصناف اللي من غير صورة. قراءة واحدة لما الصفحة تفتح.
class AdminPhotoLibraryPage extends StatefulWidget {
  const AdminPhotoLibraryPage({super.key});

  @override
  State<AdminPhotoLibraryPage> createState() => _AdminPhotoLibraryPageState();
}

class _AdminPhotoLibraryPageState extends State<AdminPhotoLibraryPage> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future = PhotoLibrary.doc.get();
  bool _busy = false;

  void _reload() => setState(() => _future = PhotoLibrary.doc.get());

  Future<void> _add() async {
    final name = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('صورة جديدة للمكتبة'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 90,
          decoration: const InputDecoration(
            labelText: 'اسم الصنف',
            hintText: 'مثلًا: طماطم، زيت موبيل، فراخ بيضا',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            child: const Text('من الجهاز'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'search'),
            icon: const Icon(Icons.search),
            label: const Text('بحث عن صورة'),
          ),
        ],
      ),
    );
    final text = name.text.trim();
    name.dispose();
    if (choice == null || text.isEmpty || !mounted) return;

    StockPhotoCandidate? suggested;
    if (choice == 'search') {
      suggested = await showStockPhotoPicker(context, name: text);
      if (suggested == null || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final url = suggested == null
          ? await ImageService.pickAndUpload('banners')
          : await ImageService.uploadSuggestedStockPhoto(
              suggested, folder: 'banners');
      if (url == null) return;
      await PhotoLibrary.put(
        text, url,
        sourcePageUrl: suggested?.sourcePageUrl,
        creator: suggested?.creator,
      );
      messenger.showSnackBar(appSnack(
        'اتضافت صورة «$text». هتظهر للأصناف المطابقة في كل المحلات.'));
      _reload();
      // جهاز الإدارة يشوف الصورة فورًا؛ باقي الموبايلات في خلال يوم.
      unawaited(PhotoLibrary.load(force: true));
    } catch (e) {
      messenger.showSnackBar(appSnack('تعذر إضافة الصورة: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «إضافة صور»: صورة واحدة (بحث أو من الجهاز) أو كذا صورة مرة واحدة كملفات.
  Future<void> _chooseAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-library-add-one'),
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('صورة واحدة'),
              subtitle: const Text('تكتب الاسم وتختار من الجهاز أو تبحث'),
              onTap: () => Navigator.pop(ctx, 'one'),
            ),
            ListTile(
              key: const Key('photo-library-add-many'),
              leading: const Icon(Icons.collections_outlined),
              title: const Text('كذا صورة مرة واحدة'),
              subtitle: Text('لحد $kLibraryBulkMax صورة، والاسم بيتاخد من اسم الملف'),
              onTap: () => Navigator.pop(ctx, 'many'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'one') await _add();
    if (choice == 'many') await _addMany();
  }

  /// الرفع المتعدد: اختيار ملفات ← مراجعة الأسماء ← رفع واحدة ورا التانية ← كتابة واحدة للمستند.
  Future<void> _addMany() async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: false, // بنقرا كل ملف وقت رفعه بس عشان الذاكرة
      );
    } catch (e) {
      messenger.showSnackBar(appSnack('تعذر فتح الملفات: $e'));
      return;
    }
    if (result == null || result.files.isEmpty || !mounted) return;
    var files = result.files;
    if (files.length > kLibraryBulkMax) {
      files = files.take(kLibraryBulkMax).toList();
      messenger.showSnackBar(appSnack(
          'اخترت أكتر من $kLibraryBulkMax صورة، هنكمل بأول $kLibraryBulkMax بس.'));
    }

    final existing = <String>{};
    try {
      existing.addAll(PhotoLibrary.entriesFrom((await _future).data()).keys);
    } catch (_) {}
    if (!mounted) return;

    final drafts = [
      for (final f in files)
        LibraryBulkDraft(
          filename: f.name,
          path: f.path,
          bytes: f.bytes,
          size: f.size,
          name: libraryNameFromFilename(f.name),
        ),
    ];
    final confirmed = await Navigator.of(context).push<List<LibraryBulkDraft>>(
      MaterialPageRoute(
        builder: (_) => LibraryBulkReviewPage(drafts: drafts, existingKeys: existing),
      ),
    );
    if (confirmed == null || confirmed.isEmpty || !mounted) return;
    await _uploadDrafts(confirmed);
  }

  Future<void> _uploadDrafts(List<LibraryBulkDraft> drafts) async {
    final messenger = ScaffoldMessenger.of(context);
    final status = ValueNotifier<String>('بنجهّز الرفع...');
    setState(() => _busy = true);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, text, _) => Row(children: [
              const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 14),
              Expanded(child: Text(text, key: const Key('photo-library-bulk-status'))),
            ]),
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    final done = <({String name, String url})>[];
    final failed = <LibraryBulkDraft>[];
    final reasons = <String>[];
    try {
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        status.value = 'بيرفع ${i + 1} من ${drafts.length}: «${d.name.trim()}»';
        String? url;
        for (var attempt = 0; attempt < 3 && url == null; attempt++) {
          try {
            url = await ImageService.uploadLibraryPhoto(await d.readBytes(), d.filename);
          } on UploadRateLimitedError {
            // حد الـWorker: 10 صور في الدقيقة. نستنى ونكمل لوحدنا بدل ما نوقف.
            for (var s = 60; s > 0; s--) {
              status.value = 'اترفع ${done.length} من ${drafts.length}. '
                  'حد الرفع 10 صور في الدقيقة، هنكمل لوحدنا بعد $s ثانية...';
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          } catch (e) {
            reasons.add('«${d.name.trim()}»: ${e is StateError ? e.message : e}');
            break;
          }
        }
        if (url == null) {
          failed.add(d);
        } else {
          done.add((name: d.name.trim(), url: url));
        }
      }
      if (done.isNotEmpty) {
        status.value = 'بنحفظ ${done.length} صورة في المكتبة...';
        await PhotoLibrary.putMany(done);
      }
    } catch (e) {
      reasons.add('تعذر الحفظ في المكتبة: $e');
      failed
        ..clear()
        ..addAll(drafts);
      done.clear();
    } finally {
      if (dialogOpen && mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _reload();
    unawaited(PhotoLibrary.load(force: true));
    if (failed.isEmpty) {
      messenger.showSnackBar(appSnack(
          'اتضافت ${done.length} صورة للمكتبة، وهتظهر للأصناف المطابقة في كل المحلات.'));
      return;
    }
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('اترفع ${done.length} وفشل ${failed.length}'),
        content: SingleChildScrollView(
          child: Text(reasons.isEmpty
              ? failed.map((d) => '«${d.name.trim()}»').join('، ')
              : reasons.join('\n')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          FilledButton(
            key: const Key('photo-library-bulk-retry'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('جرّب الفاشلين تاني'),
          ),
        ],
      ),
    );
    if (retry == true && mounted) await _uploadDrafts(failed);
  }

  Future<void> _remove(String key, String name) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف الصورة',
      message: 'هتتشال صورة «$name» من المكتبة، والأصناف هترجع للصورة التوضيحية.',
      confirmLabel: 'احذف',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PhotoLibrary.remove(key);
      _reload();
      unawaited(PhotoLibrary.load(force: true));
    } catch (e) {
      messenger.showSnackBar(appSnack('تعذر الحذف: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مكتبة صور وصّلي')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('photo-library-add'),
        onPressed: _busy ? null : _chooseAdd,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('إضافة صور'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('تعذر التحميل، جرّب تاني'),
              ),
            );
          }
          final photos = snap.data?.data()?['photos'];
          final items = <({String key, String name, String url})>[];
          if (photos is Map) {
            photos.forEach((k, v) {
              if (v is Map) {
                items.add((
                  key: k.toString(),
                  name: (v['name'] ?? k).toString(),
                  url: (v['url'] ?? '').toString(),
                ));
              }
            });
          }
          items.sort((a, b) => a.name.compareTo(b.name));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ارفع صورة حقيقية لكل صنف شائع مرة واحدة (طماطم، بطاطس، فراخ، زيت موبيل...). '
                  'تقدر ترفع كذا صورة مرة واحدة، وسمّي الملف باسم الصنف عشان الاسم يتكتب لوحده. '
                  'أو ابحث عن صورة CC0 مناسبة واختارها بنفسك، من غير مفاتيح Pexels أو Pixabay. '
                  'أي محل عنده صنف بالاسم ده ومن غير صورة، هيظهر بالصورة دي بدل الصورة التوضيحية. '
                  'صورة المحل نفسه لو رفعها بتفضل هي الأساس.',
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: kMuted),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: Text('لسه مفيش صور في المكتبة')),
                ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.8,
                children: [
                  for (final it in items)
                    GestureDetector(
                      onLongPress: () => _remove(it.key, it.name),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetImage(
                                url: thumb(it.url, w: 300),
                                width: double.infinity,
                                memCacheWidth: 300,
                                errorWidget: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(it.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                              ),
                              InkWell(
                                onTap: () => _remove(it.key, it.name),
                                child: Icon(Icons.delete_outline, size: 18, color: kDanger),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}


/// أقصى عدد صور في الرفع المتعدد الواحد.
const int kLibraryBulkMax = 20;

/// صورة واحدة في الرفع المتعدد قبل ما تترفع.
class LibraryBulkDraft {
  LibraryBulkDraft({
    required this.filename,
    required this.name,
    this.path,
    this.bytes,
    this.size = 0,
  });

  final String filename;
  final String? path;
  final Uint8List? bytes;
  final int size;
  String name;

  /// مستبعدة من الرفع (الإدارة شالت العلامة).
  bool include = true;

  bool get tooBig => size > 5 * 1024 * 1024;

  Future<List<int>> readBytes() async {
    final b = bytes;
    if (b != null && b.isNotEmpty) return b;
    final p = path;
    if (p == null) throw StateError('تعذر قراءة الملف.');
    return File(p).readAsBytes();
  }
}

/// مراجعة الرفع المتعدد: اسم لكل صورة (متعدّل)، وتنبيه للأسماء المكررة أو الموجودة.
class LibraryBulkReviewPage extends StatefulWidget {
  const LibraryBulkReviewPage({
    super.key,
    required this.drafts,
    required this.existingKeys,
  });

  final List<LibraryBulkDraft> drafts;

  /// مفاتيح الأسماء الموجودة في المكتبة (مطبّعة).
  final Set<String> existingKeys;

  @override
  State<LibraryBulkReviewPage> createState() => _LibraryBulkReviewPageState();
}

class _LibraryBulkReviewPageState extends State<LibraryBulkReviewPage> {
  late final _ctrls = [
    for (final d in widget.drafts) TextEditingController(text: d.name),
  ];

  @override
  void initState() {
    super.initState();
    for (final d in widget.drafts) {
      if (d.tooBig) d.include = false;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  List<LibraryBulkDraft> get _selected =>
      [for (final d in widget.drafts) if (d.include && !d.tooBig) d];

  /// المفاتيح اللي متكررة جوه الدفعة نفسها.
  Set<String> get _dupInBatch {
    final seen = <String>{};
    final dup = <String>{};
    for (final d in _selected) {
      final k = normalizeProductPhotoKey(d.name);
      if (k.isEmpty) continue;
      if (!seen.add(k)) dup.add(k);
    }
    return dup;
  }

  String? get _problem {
    final sel = _selected;
    if (sel.isEmpty) return 'اختار صورة واحدة على الأقل';
    if (sel.any((d) => normalizeProductPhotoKey(d.name).isEmpty)) {
      return 'اكتب اسم الصنف لكل صورة معلّمة';
    }
    if (_dupInBatch.isNotEmpty) return 'فيه اسمين متكررين، غيّر واحد منهم';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dup = _dupInBatch;
    final problem = _problem;
    final selected = _selected.length;
    return Scaffold(
      appBar: AppBar(title: Text('مراجعة ${widget.drafts.length} صورة')),
      body: ListView.separated(
        key: const Key('photo-library-bulk-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: widget.drafts.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Text(
              'راجع اسم كل صورة. الاسم هو اللي هيتطابق مع أسماء الأصناف في المحلات.',
              style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.5),
            );
          }
          final index = i - 1;
          final d = widget.drafts[index];
          final key = normalizeProductPhotoKey(d.name);
          final exists = key.isNotEmpty && widget.existingKeys.contains(key);
          final repeated = d.include && dup.contains(key);
          return Opacity(
            opacity: d.include ? 1 : 0.55,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 64, height: 64, child: _thumb(d)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: Key('photo-library-bulk-name-$index'),
                        controller: _ctrls[index],
                        enabled: !d.tooBig,
                        maxLength: 90,
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'اسم الصنف (مثلًا: طماطم)',
                        ),
                        onChanged: (v) => setState(() => d.name = v),
                      ),
                      const SizedBox(height: 4),
                      if (d.tooBig)
                        Text('أكبر من 5MB، مش هتترفع',
                            style: TextStyle(fontSize: 12, color: kDanger))
                      else if (repeated)
                        Text('الاسم ده متكرر في الصور اللي اخترتها',
                            style: TextStyle(fontSize: 12, color: kDanger))
                      else if (exists && d.include)
                        Text('الاسم موجود في المكتبة، الصورة القديمة هتتبدل',
                            style: TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                ),
                Checkbox(
                  key: Key('photo-library-bulk-include-$index'),
                  value: d.include && !d.tooBig,
                  onChanged: d.tooBig ? null : (v) => setState(() => d.include = v ?? false),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(problem,
                      key: const Key('photo-library-bulk-problem'),
                      style: TextStyle(color: kDanger, fontSize: 12.5)),
                ),
              FilledButton.icon(
                key: const Key('photo-library-bulk-upload'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: problem != null ? null : () => Navigator.pop(context, _selected),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text('ارفع $selected صورة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(LibraryBulkDraft d) {
    const fallback = ColoredBox(
      color: Color(0x11000000),
      child: Icon(Icons.image_outlined),
    );
    final b = d.bytes;
    if (b != null && b.isNotEmpty) {
      return Image.memory(b, fit: BoxFit.cover, cacheWidth: 160,
          errorBuilder: (_, _, _) => fallback);
    }
    final p = d.path;
    if (p != null) {
      return Image.file(File(p), fit: BoxFit.cover, cacheWidth: 160,
          errorBuilder: (_, _, _) => fallback);
    }
    return fallback;
  }
}
