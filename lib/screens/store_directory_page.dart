import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/catalog_service.dart';
import '../theme/brand.dart';
import '../utils/img.dart';
import 'store_page.dart';

/// دليل المحلات: قائمة رأسية مريحة، مع الاحتفاظ بنفس بيانات كتالوج المحلات.
class StoreDirectoryPage extends StatefulWidget {
  final String? initialCategory;
  const StoreDirectoryPage({super.key, this.initialCategory});

  @override
  State<StoreDirectoryPage> createState() => _StoreDirectoryPageState();
}

class _StoreDirectoryPageState extends State<StoreDirectoryPage> {
  late String? _category = widget.initialCategory;
  final _search = TextEditingController();
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _load() => CatalogService.get(
    FirebaseFirestore.instance.collection('stores').where('active', isEqualTo: true),
    'stores',
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('تسوق', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: true,
        ),
        body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('تعذر تحميل المحلات.'),
                  TextButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ]),
              );
            }
            final stores = <({Store store, Map<String, dynamic> data})>[];
            for (final doc in snapshot.data?.docs ?? []) {
              try {
                final data = doc.data();
                final store = Store.fromMap(doc.id, data);
                if (store.active) stores.add((store: store, data: data));
              } catch (e) {
                debugPrint('Store parse error ${doc.id}: $e');
              }
            }
            stores.sort((a, b) => a.store.order.compareTo(b.store.order));
            final q = _search.text.trim().toLowerCase();
            final visible = stores.where((item) {
              final categoryOk = _category == null ||
                  (isPharmacyCategory(_category!)
                      ? item.store.isPharmacy
                      : item.store.category == _category);
              return categoryOk && (q.isEmpty || item.store.name.toLowerCase().contains(q));
            }).toList();

            final categories = stores.map((e) => e.store.isPharmacy ? 'صيدليات' : e.store.category).where((e) => e.trim().isNotEmpty).toSet().toList()..sort();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن محل أو ماركت...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                ),
              ),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _FilterChip(label: 'الكل', selected: _category == null, onTap: () => setState(() => _category = null)),
                    for (final category in categories)
                      _FilterChip(label: category, selected: _category == category, onTap: () => setState(() => _category = category)),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('لا توجد محلات مطابقة حاليًا'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final store = item.store;
                          final data = item.data;
                          final minOrder = data['minOrder'] ?? data['minimumOrder'];
                          final productCount = store.products.length;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            elevation: 1,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StorePage(store: store))),
                              child: SizedBox(
                                height: 138,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(17),
                                      child: SizedBox(
                                        width: 112,
                                        height: 110,
                                        child: store.imageUrl.isEmpty
                                            ? Container(
                                                color: Brand.softGradient.colors.first,
                                                child: Icon(store.icon, size: 42, color: Brand.green),
                                              )
                                            : Image.network(thumb(store.imageUrl, w: 260), fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Container(color: Brand.green.withValues(alpha: .08), child: Icon(store.icon, size: 40, color: Brand.green))),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 7),
                                          Row(children: [
                                            const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 19),
                                            Text(store.rating > 0 ? store.rating.toStringAsFixed(1) : 'جديد',
                                                style: const TextStyle(fontWeight: FontWeight.w800)),
                                            if ((data['ratingCount'] as num?) != null)
                                              Text('  (${(data['ratingCount'] as num).toInt()})', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                                          ]),
                                          const SizedBox(height: 6),
                                          Text(store.time.isEmpty ? store.category : '${store.category} • ${store.time}',
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                          const Spacer(),
                                          Row(children: [
                                            if (minOrder != null) Text('الحد الأدنى $minOrder ج', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                            const Spacer(),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(color: const Color(0xFFFFF1E7), borderRadius: BorderRadius.circular(16)),
                                              child: Text('$productCount منتج', style: const TextStyle(color: Color(0xFFE66A16), fontWeight: FontWeight.w800, fontSize: 12)),
                                            ),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFFFE2CD),
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: selected ? const Color(0xFFE66A16) : Colors.black87),
      side: BorderSide(color: selected ? const Color(0xFFFFA66B) : Colors.black12),
    ),
  );
}
