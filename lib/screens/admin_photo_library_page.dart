import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/image_service.dart';
import '../services/photo_library.dart';
import '../services/stock_photo_search.dart';
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
    } catch (e) {
      messenger.showSnackBar(appSnack('تعذر إضافة الصورة: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        onPressed: _busy ? null : _add,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('إضافة صورة'),
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
