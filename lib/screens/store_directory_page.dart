import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/promo_banners.dart';
import '../widgets/app_header.dart';

import '../models/store.dart';
import '../models/home_category.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync.dart';
import '../theme/app_tokens.dart';
import '../utils/img.dart';
import 'store_page.dart';
import '../widgets/cached_net_image.dart';
import '../widgets/curved_nav_bar.dart';

/// صفحة التسوق (دليل المحلات).
///
/// الهيدر والبانر والبحث بيتحركوا لفوق مع التمرير علشان المحلات تاخد
/// مساحة الشاشة، والهيدر يرجع أول ما العميل يمرر لفوق. شريط الأقسام
/// بيفضل ظاهر (صغير) علشان التصفية تفضل في متناول الإيد.
class StoreDirectoryPage extends StatefulWidget {
  final String? initialCategory;
  const StoreDirectoryPage({
    super.key,
    this.initialCategory,
    this.loader,
    this.showBanners = true,
  });

  /// للاختبارات فقط: مصدر بديل للمحلات بدل Firestore.
  final Future<List<CatalogDoc>> Function()? loader;

  /// للاختبارات فقط: البانرات بتقرا من Firestore.
  final bool showBanners;

  @override
  State<StoreDirectoryPage> createState() => _StoreDirectoryPageState();
}

class _StoreDirectoryPageState extends State<StoreDirectoryPage> {
  late String? _category = widget.initialCategory;
  final _search = TextEditingController();
  late Future<List<CatalogDoc>> _future;
  bool _gridMode = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CatalogDoc>> _load() =>
      widget.loader?.call() ??
      CatalogReader.activeStores(
        () => CatalogService.get(
          FirebaseFirestore.instance
              .collection('stores')
              .where('active', isEqualTo: true),
          'stores',
        ),
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<({Store store, Map<String, dynamic> data})> _parse(List<CatalogDoc> docs) {
    final stores = <({Store store, Map<String, dynamic> data})>[];
    for (final doc in docs) {
      try {
        final data = doc.data();
        final store = Store.fromMap(doc.id, data);
        if (store.active) stores.add((store: store, data: data));
      } catch (e) {
        debugPrint('Store parse error ${doc.id}: $e');
      }
    }
    stores.sort((a, b) => a.store.order.compareTo(b.store.order));
    return stores;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        bottomNavigationBar: const CustomerPageNav(),
        body: FutureBuilder<List<CatalogDoc>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;
            final stores = _parse(snapshot.data ?? const <CatalogDoc>[]);
            final q = _search.text.trim().toLowerCase();
            final visible = stores.where((item) {
              final categoryOk = _category == null ||
                  matchesDirectoryCategory(_category!, item.store.category);
              return categoryOk &&
                  (q.isEmpty || item.store.name.toLowerCase().contains(q));
            }).toList();
            final categories = stores
                .map((e) => e.store.isPharmacy ? 'صيدليات' : e.store.category)
                .where((e) => e.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            final scroll = CustomScrollView(
              key: const Key('directory-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverAppBar(
                  key: const Key('directory-app-bar'),
                  title: const Text('تسوق'),
                  floating: true,
                  snap: true,
                  actions: const [HomeActionButton()],
                ),
                if (widget.showBanners)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: AppSpacing.md),
                      child: PromoBanners(),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xs),
                    child: TextField(
                      key: const Key('directory-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'ابحث عن محل أو ماركت...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(_search.clear),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          borderSide: const BorderSide(color: AppColors.purple, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ChipsHeader(
                    height: MediaQuery.textScalerOf(context).scale(AppTypography.bodySmall) + 46,
                    child: ListView(
                      key: const Key('directory-chips'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      children: [
                        _FilterChip(
                          label: 'الكل',
                          selected: _category == null,
                          onTap: () => setState(() => _category = null),
                        ),
                        // A home card may represent multiple real store categories.
                        // Show its name while selected, instead of a blank chip state.
                        if (homeCategoryForId(_category) case final group?)
                          _FilterChip(
                            label: group.title,
                            selected: true,
                            onTap: () => setState(() => _category = null),
                          ),
                        for (final category in categories)
                          _FilterChip(
                            label: category,
                            selected: _category == category,
                            onTap: () => setState(() => _category = category),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!loading && !snapshot.hasError && visible.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
                      child: Row(
                        children: [
                          Text('المحلات (${visible.length})',
                              style: AppTypography.sectionTitle),
                          const Spacer(),
                          Text(_gridMode ? 'عرض شبكي' : 'عرض قائمة',
                              style: AppTypography.secondary),
                          IconButton(
                            key: const Key('directory-layout-toggle'),
                            tooltip: _gridMode
                                ? 'عرض المحلات في قائمة'
                                : 'عرض المحلات اتنين جنب بعض',
                            onPressed: () =>
                                setState(() => _gridMode = !_gridMode),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.purpleSoft,
                              foregroundColor: AppColors.purple,
                            ),
                            icon: Icon(_gridMode
                                ? Icons.view_agenda_rounded
                                : Icons.grid_view_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('تعذر تحميل المحلات.', style: AppTypography.bodyText),
                        TextButton.icon(
                          onPressed: () => setState(() => _future = _load()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ]),
                    ),
                  )
                else if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('لا توجد محلات مطابقة حاليًا', style: AppTypography.secondary),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
                    sliver: _gridMode
                        ? SliverGrid.builder(
                            itemCount: visible.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: AppSpacing.sm,
                              mainAxisSpacing: AppSpacing.md,
                              mainAxisExtent: 282,
                            ),
                            itemBuilder: (context, index) => _CompactStoreCard(
                              store: visible[index].store,
                              data: visible[index].data,
                            ),
                          )
                        : SliverList.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, index) => _StoreCard(
                              store: visible[index].store,
                              data: visible[index].data,
                            ),
                          ),
                  ),
              ],
            );
            // شريط الحالة يفضل بلون الهوية لما الهيدر يطلع لفوق، والشريط
            // المثبت (الأقسام) يقف تحته مباشرة بدل ما يتغطى.
            return Column(children: [
              Container(height: top, color: AppColors.purpleDeep),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: scroll,
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.data});

  final Store store;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final minOrder = data['minOrder'] ?? data['minimumOrder'];
    final ratingCount = (data['ratingCount'] as num?)?.toInt();
    final fallback = ColoredBox(
      color: AppColors.purpleSoft,
      child: Icon(store.icon, size: 40, color: AppColors.purple),
    );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => StorePage(store: store))),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: store.imageUrl.isEmpty
                        ? fallback
                        : CachedNetImage(
                            url: thumb(store.imageUrl, w: 260),
                            memCacheWidth: 260,
                            errorWidget: fallback,
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sectionTitle,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 20),
                        const SizedBox(width: 2),
                        Text(
                          store.rating > 0 ? store.rating.toStringAsFixed(1) : 'جديد',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.ink,
                          ),
                        ),
                        if (ratingCount != null)
                          Text('  ($ratingCount)', style: AppTypography.secondary),
                      ]),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        store.time.isEmpty ? store.category : '${store.category} • ${store.time}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.secondary,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(children: [
                        if (minOrder != null)
                          Flexible(
                            child: Text(
                              'الحد الأدنى $minOrder ج',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppTypography.caption,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // حالة المحل فقط، ولا نعتمد على عدد أصناف قديم.
                        _StoreStatusBadge(isOpen: store.isOpen),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// عرض مضغوط: محلّين في الصف بدون قطع الاسم أو إخفاء حالة الفتح.
class _CompactStoreCard extends StatelessWidget {
  const _CompactStoreCard({required this.store, required this.data});

  final Store store;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final minOrder = data['minOrder'] ?? data['minimumOrder'];
    final fallback = ColoredBox(
      color: AppColors.purpleSoft,
      child: Icon(store.icon, size: 36, color: AppColors.purple),
    );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => StorePage(store: store))),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(
                  height: 106,
                  child: store.imageUrl.isEmpty
                      ? fallback
                      : CachedNetImage(
                          url: thumb(store.imageUrl, w: 320),
                          memCacheWidth: 320,
                          errorWidget: fallback,
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                store.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFFFA000), size: 17),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      store.rating > 0
                          ? store.rating.toStringAsFixed(1)
                          : 'جديد',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                store.time.isEmpty
                    ? store.category
                    : '${store.category} • ${store.time}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.secondary,
              ),
              if (minOrder != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'الحد الأدنى $minOrder ج',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
              const Spacer(),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StoreStatusBadge(isOpen: store.isOpen),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// الشارة ثابتة في كلا العرضين؛ عدد المنتجات ليس دليلًا على حالة المحل.
class _StoreStatusBadge extends StatelessWidget {
  const _StoreStatusBadge({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: isOpen ? AppColors.successSoft : AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          isOpen ? 'مفتوح الآن' : 'مغلق الآن',
          style: TextStyle(
            color: isOpen ? AppColors.success : AppColors.danger,
            fontWeight: FontWeight.w800,
            fontSize: AppTypography.caption,
          ),
        ),
      );
}

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        boxShadow: overlapsContent || shrinkOffset > 0
            ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _ChipsHeader oldDelegate) => true;
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          selectedColor: AppColors.purple,
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: AppTypography.bodySmall,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
          side: BorderSide(color: selected ? AppColors.purple : AppColors.line),
          shape: const StadiumBorder(),
        ),
      );
}
