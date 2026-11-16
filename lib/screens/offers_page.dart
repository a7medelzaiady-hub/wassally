import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../models/product.dart';
import '../models/product_offer.dart';
import '../services/cart_model.dart';
import '../services/catalog_service.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../widgets/app_header.dart';
import '../widgets/empty_state.dart';
import 'cart_page.dart';
import 'store_page.dart';

class _Offer {
  final Store store;
  final String id, name, image, text;
  final double price, oldPrice;

  const _Offer({
    required this.store,
    this.id = '',
    required this.name,
    required this.image,
    required this.price,
    required this.oldPrice,
    this.text = '',
  });

  bool get hasPriceDiscount => oldPrice > price && price > 0;
}

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  late Future<List<_Offer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // صفحة العروض تتجاوز كاش الكتالوج عمدًا؛ لازم تعرض أحدث العروض عند فتحها.
  Future<List<_Offer>> _load() async {
    final snap = await CatalogService.get(
      FirebaseFirestore.instance.collection('stores'),
      'stores',
      cacheable: false,
    );
    final storeDocs = snap.docs.where((d) => d.data()['active'] != false);
    final groups = await Future.wait(storeDocs.map((doc) async {
      final data = doc.data();
      Store store;
      try {
        store = Store.fromMap(doc.id, data);
      } catch (_) {
        return <_Offer>[];
      }
      final result = <_Offer>[];
      final seen = <String>{};

      void add(Map<String, dynamic> item, {String id = ''}) {
        final name = (item['name'] ?? '').toString().trim();
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final old = (item['oldPrice'] as num?)?.toDouble() ?? 0;
        final text = (item['offerText'] ?? '').toString().trim();
        final ends = item['offerEndsAt'];
        final expired = isOfferExpired(
          ends is Timestamp ? ends.toDate() : null,
          DateTime.now(),
        );
        final hasDiscount = old > price && price > 0;
        if (name.isEmpty || price <= 0 || expired ||
            item['available'] == false || item['isAvailable'] == false ||
            (!hasDiscount && text.isEmpty)) {
          return;
        }
  
        final key = '${store.id}/${name.toLowerCase()}';
        if (!seen.add(key)) return;
        result.add(_Offer(
          store: store,
          id: id,
          name: name,
          image: (item['image'] ?? '').toString(),
          price: price,
          oldPrice: hasDiscount ? old : 0,
          text: text,
        ));
      }

      // المصدر الأساسي للعروض هو كتالوج المحل نفسه. نقرأ على صفحات
      // حتى لا تختفي العروض الموجودة بعد أول 200 أو 500 صنف.
      var catalogHasDocuments = false;
      try {
        Query<Map<String, dynamic>> query =
            doc.reference.collection('products').limit(200);
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        do {
          if (cursor != null) {
            query = doc.reference
                .collection('products')
                .limit(200)
                .startAfterDocument(cursor);
          }
          final products =
              await query.get(const GetOptions(source: Source.server));
          if (products.docs.isNotEmpty) catalogHasDocuments = true;
          for (final product in products.docs) {
            add(product.data(), id: product.id);
          }
          cursor = products.docs.isEmpty ? null : products.docs.last;
          if (products.docs.length < 200) break;
        } while (cursor != null);
      } catch (error) {
        debugPrint('Offers products load failed for ${doc.id}: $error');
      }

      // نستخدم الملخص والبيانات القديمة كبديل عند تعذر قراءة الكتالوج فقط؛
      // لا نسمح لملخص قديم بإظهار عرض تم إلغاؤه أو انتهى بالفعل.
      if (!catalogHasDocuments) {
        final highlights = data['offerItems'];
        if (highlights is List) {
          for (final entry in highlights) {
            if (entry is Map) add(Map<String, dynamic>.from(entry));
          }
        }
        final legacy = data['products'];
        if (legacy is List) {
          for (final entry in legacy) {
            if (entry is Map) add(Map<String, dynamic>.from(entry));
          }
        }
      }
      return result;
    }));
    return groups.expand((group) => group).toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  void _add(_Offer item) {
    final product = Product(
      item.name,
      item.price,
      item.image,
      item.id,
      true,
      item.oldPrice,
      item.text,
    );
    if (!cart.add(product, storeId: item.store.id, storeName: item.store.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('السلة فيها منتجات من ${cart.storeName ?? 'محل تاني'}'),
          action: SnackBarAction(
            label: 'فتح السلة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartPage()),
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة ${item.name} للسلة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        body: FutureBuilder<List<_Offer>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Column(
                children: [
                  const BrandHeader(title: 'عروض وخصومات'),
                  Expanded(
                    child: EmptyState(
                      icon: Icons.cloud_off,
                      title: 'تعذر تحميل العروض',
                      message: 'تأكد من الاتصال بالإنترنت وحاول تاني.',
                      actionLabel: 'إعادة المحاولة',
                      onAction: () => setState(() => _future = _load()),
                    ),
                  ),
                ],
              );
            }
            if (!snap.hasData) {
              return const Column(
                children: [
                  BrandHeader(title: 'عروض وخصومات'),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }

            final items = snap.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  const SliverToBoxAdapter(
                    child: BrandHeader(
                      title: 'عروض وخصومات',
                      subtitle: 'وفّر أكتر مع أفضل عروض المحلات',
                    ),
                  ),
                  if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.local_offer_outlined,
                        title: 'مفيش عروض متاحة حاليًا',
                        message: 'اسحب الشاشة لأسفل لتحديث العروض الجديدة.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final item = items[i];
                          final discount = item.hasPriceDiscount
                              ? ((1 - item.price / item.oldPrice) * 100).round()
                              : 0;
                          return _OfferCard(
                            item: item,
                            discount: discount,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => StorePage(store: item.store),
                              ),
                            ),
                            onAdd: () => _add(item),
                          );
                        }, childCount: items.length),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final _Offer item;
  final int discount;
  final VoidCallback onTap, onAdd;

  const _OfferCard({
    required this.item,
    required this.discount,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX((1 - value) * 0.07)
            ..translateByDouble(0.0, (1 - value) * 22, 0.0, 1.0),
          child: Transform.scale(scale: 0.96 + value * 0.04, child: child),
        ),
      ),
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // نفس كارت المنتجات في صفحة المحل: صورة كبيرة وزر (+) دائري
              // فوق الصورة، بدون زر "أضف للسلة" العريض أسفل الكارت.
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.image.isEmpty
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: Brand.softGradient,
                            ),
                            child: Icon(
                              Icons.local_offer_rounded,
                              size: 48,
                              color: Brand.green.withValues(alpha: 0.6),
                            ),
                          )
                        : Image.network(
                            thumb(item.image, w: 500),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              decoration: BoxDecoration(
                                gradient: Brand.softGradient,
                              ),
                            ),
                          ),
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Brand.green,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          item.store.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE83F50),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          item.hasPriceDiscount
                              ? 'خصم $discount%'
                              : 'عرض خاص',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 8,
                      end: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatPrice(item.price),
                              style: TextStyle(
                                color: Brand.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            if (item.hasPriceDiscount) ...[
                              const SizedBox(width: 5),
                              Text(
                                formatPrice(item.oldPrice),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 10.5,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 8,
                      start: 8,
                      child: Material(
                        color: Brand.green,
                        elevation: 3,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Brand.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 14,
                            color: Brand.green,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.store.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!item.hasPriceDiscount)
                        Text(
                          item.text,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Brand.greenDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
