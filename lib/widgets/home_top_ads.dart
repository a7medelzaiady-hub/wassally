import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../theme/app_tokens.dart';
import '../utils/img.dart';
import 'cached_net_image.dart';
import 'quick_order_promo.dart';

/// مكان البوستر في الرئيسية (حقل placement في مجموعة banners).
const kTopAdPlacement = 'top';

/// مقاس إعلانات أعلى الرئيسية: 3:2 (مثلًا 1200×800 بكسل).
const double kTopAdAspectRatio = 1.5;

/// صفحات الإعلان اللي بعد تسجيل الدخول (شاشة كاملة طولية 1080×1920).
const kTourPlacement = 'tour';
const double kTourAspectRatio = 9 / 16;

/// أماكن ليها عرض خاص، فمتظهرش في شريط البوسترات العادي.
const kSpecialPlacements = {kTopAdPlacement, kTourPlacement};

/// روابط البوسترات المفعّلة لمكان معيّن، بالترتيب.
List<String> bannerPostersFor(QuerySnapshot<Map<String, dynamic>>? snap, String placement) {
  if (snap == null) return const [];
  final docs = snap.docs.where((d) {
    final m = d.data();
    return (m['active'] as bool? ?? true) &&
        m['placement'] == placement &&
        (m['image'] ?? '').toString().isNotEmpty;
  }).toList()
    ..sort((a, b) =>
        ((a.data()['order'] as num?) ?? 0).compareTo((b.data()['order'] as num?) ?? 0));
  return [for (final d in docs) d.data()['image'].toString()];
}

/// بوسترات الجولة (نفس قراءة البوسترات المحفوظة في الكاش). أي خطأ = مفيش.
Future<List<String>> loadTourPosters() async {
  try {
    final snap = await CatalogService.get(FirebaseFirestore.instance.collection('banners'), 'banners')
        .timeout(const Duration(seconds: 4));
    return bannerPostersFor(snap, kTourPlacement);
  } catch (_) {
    return const [];
  }
}

/// إعلانات أعلى الرئيسية: بوسترات الإدارة (placement = top) متحركة.
/// لو مفيش بوسترات مرفوعة، بيظهر إعلان «وصّلي ع السريع» المدمج.
/// نفس قراءة البوسترات المحفوظة في الكاش (مفيش قراءات إضافية).
class HomeTopAds extends StatefulWidget {
  const HomeTopAds({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<HomeTopAds> createState() => _HomeTopAdsState();
}

class _HomeTopAdsState extends State<HomeTopAds> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _future = CatalogService.get(
    FirebaseFirestore.instance.collection('banners'),
    'banners',
  );


  Widget _poster(String url) => Material(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shadowColor: AppColors.purple.withValues(alpha: 0.25),
        child: InkWell(
          onTap: widget.onTap,
          child: CachedNetImage(
            url: thumb(url, w: 1200),
            memCacheWidth: 1200,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorWidget: QuickOrderPromo(onTap: widget.onTap),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final urls = bannerPostersFor(snap.data, kTopAdPlacement);
        return PromoCarousel(
          aspectRatio: kTopAdAspectRatio,
          slides: urls.isEmpty
              ? [
                  QuickOrderPromo(onTap: widget.onTap),
                  if (kQuickPhotoOrdersEnabled) PhotoOrderPromo(onTap: widget.onTap),
                ]
              : [for (final url in urls) _poster(url)],
        );
      },
    );
  }
}
