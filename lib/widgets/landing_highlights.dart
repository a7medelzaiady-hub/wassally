import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../screens/store_page.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import 'cached_net_image.dart';

class _S {
  final Store store;
  final Map<String, dynamic> data;
  _S(this.store, this.data);
  String get image => (data['imageUrl'] ?? data['image'] ?? '').toString();
  double get rating {
    final n = (data['ratingCount'] as num?)?.toInt() ?? 0;
    if (n > 0) return ((data['ratingSum'] as num?)?.toDouble() ?? 0) / n;
    return (data['rating'] as num?)?.toDouble() ?? 0;
  }
}

/// أقسام "عروض" و"الأعلى تقييمًا" و"الأكثر مبيعًا" تحت الأقسام في صفحة الترحيب.
/// بتقرأ نفس بيانات المحلات المخزّنة (CatalogService) فمفيش قراءات زيادة.
class LandingHighlights extends StatefulWidget {
  const LandingHighlights({super.key});

  @override
  State<LandingHighlights> createState() => _LandingHighlightsState();
}

class _LandingHighlightsState extends State<LandingHighlights> {
  late final Future<List<_S>> _future = _load();

  Future<List<_S>> _load() async {
    // الفهرس المجمّع أولًا؛ الاستعلام القديم لازم يفلتر active عشان قواعد Firestore تسمح بيه للعميل.
    final docs = await CatalogReader.activeStores(
      () => CatalogService.get(
        FirebaseFirestore.instance
            .collection('stores')
            .where('active', isEqualTo: true),
        'stores',
      ),
    );
    final out = <_S>[];
    for (final d in docs) {
      try {
        final data = d.data();
        if (data['active'] == false) continue;
        out.add(_S(Store.fromMap(d.id, data), data));
      } catch (_) {}
    }
    return out;
  }

  void _open(Store s) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => StorePage(store: s)));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_S>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data;
        if (all == null || all.isEmpty) return const SizedBox.shrink();

        final offers = <(_S, Map<String, dynamic>)>[];
        final best = <(_S, Map<String, dynamic>)>[];
        for (final s in all) {
          for (final k in ['offerItems', 'bestItems']) {
            final raw = s.data[k];
            if (raw is! List) continue;
            for (final e in raw) {
              if (e is! Map) continue;
              (k == 'offerItems' ? offers : best).add((
                s,
                Map<String, dynamic>.from(e),
              ));
            }
          }
        }
        final top = all.where((s) => s.rating > 0).toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (offers.isNotEmpty)
              _row('عروض', [
                for (final o in offers) _itemCard(o.$1, o.$2, offer: true),
              ]),
            if (top.isNotEmpty)
              _row('الأعلى تقييمًا', [
                for (final s in top.take(10)) _storeCard(s),
              ]),
            if (best.isNotEmpty)
              _row('الأكثر مبيعًا', [
                for (final o in best) _itemCard(o.$1, o.$2),
              ]),
          ],
        );
      },
    );
  }

  Widget _row(String title, List<Widget> cards) {
    final shown = cards.length > 12 ? cards.sublist(0, 12) : cards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
        ),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => shown[i],
          ),
        ),
      ],
    );
  }

  Widget _photo(String img) => img.isEmpty
      ? Container(decoration: BoxDecoration(gradient: Brand.softGradient))
      : CachedNetImage(
          url: thumb(img, w: 300),
          memCacheWidth: 300,
          errorWidget: Container(
            decoration: BoxDecoration(gradient: Brand.softGradient),
          ),
        );

  Widget _shell(VoidCallback onTap, Widget photo, Widget info) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 128,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: photo),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: info,
              ),
            ],
          ),
        ),
      );

  Widget _storeCard(_S s) => _shell(
    () => _open(s.store),
    _photo(s.image),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.store.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Brand.ink,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
            const SizedBox(width: 3),
            Text(
              s.rating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _itemCard(_S s, Map<String, dynamic> m, {bool offer = false}) {
    final price = (m['price'] as num?)?.toDouble() ?? 0;
    final old = (m['oldPrice'] as num?)?.toDouble() ?? 0;
    return _shell(
      () => _open(s.store),
      Stack(
        fit: StackFit.expand,
        children: [
          _photo((m['image'] ?? '').toString()),
          if (offer && old > price && old > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kDanger,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${((1 - price / old) * 100).round()}%-',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (m['name'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          Text(
            s.store.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: kMuted),
          ),
          Row(
            children: [
              Text(
                formatPrice(price),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Brand.goldDeep,
                ),
              ),
              if (offer && old > price) ...[
                const SizedBox(width: 5),
                Text(
                  formatPrice(old),
                  style: TextStyle(
                    fontSize: 12,
                    color: kMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
