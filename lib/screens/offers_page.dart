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
  final String name, image, text;
  final double price, oldPrice;

  const _Offer({
    required this.store,
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
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // صفحة العروض تتجاوز كاش الكتالوج عمدًا؛ لازم تعرض أحدث العروض عند فتحها.
  Future<QuerySnapshot<Map<String, dynamic>>> _load() =>
      CatalogService.get(
        FirebaseFirestore.instance.collection('stores'),
        'stores',
        cacheable: false,
      );

  List<_Offer> _offers(QuerySnapshot<Map<String, dynamic>> snap) {
    final result = <_Offer>[];
    final seen = <String>{};

    void add(Store store, Map<String, dynamic> data) {
      final name = (data['name'] ?? '').toString().trim();
      final price = (data['price'] as num?)?.toDouble() ?? 0;
      final old = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final text = (data['offerText'] ?? '').toString().trim();
      final ends = data['offerEndsAt'];
      final expired = isOfferExpired(
        ends is Timestamp ? ends.toDate() : null,
        DateTime.now(),
      );
      final hasDiscount = old > price && price > 0;
      if (name.isEmpty || price <= 0 || expired ||
          (!hasDiscount && text.isEmpty)) {
        return;
      }

      final key = '${store.id}/${name.toLowerCase()}';
      if (!seen.add(key)) return;
      result.add(_Offer(
        store: store,
        name: name,
        image: (data['image'] ?? '').toString(),
        price: price,
        oldPrice: hasDiscount ? old : 0,
        text: text,
      ));
    }

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['active'] == false) continue;

      Store store;
      try {
        store = Store.fromMap(doc.id, data);
      } catch (_) {
        continue;
      }

      // ملخص العروض المزامن من كتالوج منتجات المحل.
      final highlights = data['offerItems'];
      if (highlights is List) {
        for (final entry in highlights) {
          if (entry is Map) add(store, Map<String, dynamic>.from(entry));
        }
      }

      // توافق مع المنتجات القديمة المخزنة داخل مستند المحل.
      final legacy = data['products'];
      if (legacy is List) {
        for (final entry in legacy) {
          if (entry is Map) add(store, Map<String, dynamic>.from(entry));
        }
      }
    }

    return result;
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
      '',
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
        body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

            final items = _offers(snap.data!);
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
                          childAspectRatio: 0.67,
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
            ..translate(0.0, (1 - value) * 22),
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
                      top: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
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
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
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
                        ),
                      ),
                      Text(
                        item.store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (item.hasPriceDiscount)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              formatPrice(item.oldPrice),
                              style: const TextStyle(
                                color: Color(0xFFE34B55),
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatPrice(item.price),
                              style: TextStyle(
                                color: Brand.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          item.text,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Brand.greenDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: FilledButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 17,
                          ),
                          label: const Text('أضف للسلة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brand.green,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
