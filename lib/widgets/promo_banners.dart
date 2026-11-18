import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../theme/brand.dart';

class _Slide {
  final String? image;
  final String title;
  final String subtitle;
  final List<Color>? colors;
  final IconData icon;
  const _Slide({
    this.image,
    this.title = '',
    this.subtitle = '',
    this.colors,
    this.icon = Icons.delivery_dining_rounded,
  });
}

/// بانر إعلانات بيتحرك لوحده ولفة مستمرة. بيقرأ من كولكشن `banners`
/// (كل مستند: image، order، active) وبتتحكم فيه من صفحة "بوسترات الرئيسية".
/// لو الكولكشن فاضي بيعرض 3 بوسترات جاهزة.
class PromoBanners extends StatefulWidget {
  const PromoBanners({super.key});

  @override
  State<PromoBanners> createState() => _PromoBannersState();
}

class _PromoBannersState extends State<PromoBanners> {
  static const _base = 3000;

  List<_Slide> get _fallback => [
    _Slide(
      title: 'توصيل لحد باب بيتك',
      subtitle: 'اطلب من محلات بلدك في دقايق',
      colors: [Brand.greenDark, Brand.green],
      icon: Icons.delivery_dining_rounded,
    ),
    _Slide(
      title: 'عروض النهاردة',
      subtitle: 'خصومات من أحلى المطاعم والمحلات',
      colors: [Brand.goldDeep, Brand.gold],
      icon: Icons.local_offer_rounded,
    ),
    _Slide(
      title: 'أكلك سخن وبسرعة',
      subtitle: 'من المطبخ لحد بابك',
      colors: [Brand.green, Brand.greenLight],
      icon: Icons.restaurant_rounded,
    ),
  ];

  final PageController _pageCtrl = PageController(
    viewportFraction: 0.9,
    initialPage: _base,
  );
  // البوسترات بتتحمّل مرة واحدة (من الكاش لو الكتالوج ما اتغيرش).
  late final Future<QuerySnapshot<Map<String, dynamic>>> _future =
      CatalogService.get(
        FirebaseFirestore.instance.collection('banners'),
        'banners',
      );

  Timer? _timer;
  int _count = 1;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) => _next());
  }

  void _next() {
    if (!mounted || _count < 2 || !_pageCtrl.hasClients) return;
    final pos = _pageCtrl.position;
    if (!pos.haveDimensions) return;
    final current = (_pageCtrl.page ?? _base.toDouble()).round();
    _pageCtrl.animateToPage(
      current + 1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  List<_Slide> _slides(QuerySnapshot<Map<String, dynamic>>? snap) {
    if (snap == null) return _fallback;
    final docs =
        snap.docs.where((d) => (d.data()['active'] as bool?) ?? true).toList()
          ..sort(
            (a, b) => ((a.data()['order'] as num?) ?? 0).compareTo(
              (b.data()['order'] as num?) ?? 0,
            ),
          );
    final slides = [
      for (final d in docs)
        if ((d.data()['image'] ?? '').toString().isNotEmpty)
          _Slide(image: d.data()['image'].toString()),
    ];
    return slides.isEmpty ? _fallback : slides;
  }

  Widget _slideView(_Slide s) {
    if (s.image != null) {
      return Image.network(
        s.image!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                color: Brand.green.withValues(alpha: 0.10),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Brand.green,
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, _, _) => Container(
          color: Brand.green.withValues(alpha: 0.10),
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Brand.green,
            size: 32,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: s.colors ?? [Brand.green, Brand.greenLight],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -30,
            bottom: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            left: 50,
            top: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  s.icon,
                  size: 62,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final slides = _slides(snap.data);
        _count = slides.length;
        final activeDot = _index % slides.length;

        return Column(
          children: [
            SizedBox(
              height: 160,
              // لو لمست البانر الحركة التلقائية بتقف لحد ما تشيل إيدك
              child: Listener(
                onPointerDown: (_) => _timer?.cancel(),
                onPointerUp: (_) => _startTimer(),
                onPointerCancel: (_) => _startTimer(),
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) =>
                      setState(() => _index = (i - _base) % _count),
                  itemBuilder: (context, i) {
                    final slide = slides[(i - _base) % slides.length];
                    return AnimatedBuilder(
                      animation: _pageCtrl,
                      builder: (context, child) {
                        var page = _base.toDouble();
                        if (_pageCtrl.hasClients &&
                            _pageCtrl.position.haveDimensions) {
                          page = _pageCtrl.page ?? page;
                        }
                        final scale = (1 - (page - i).abs() * 0.08).clamp(
                          0.88,
                          1.0,
                        );
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _slideView(slide),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == activeDot ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == activeDot
                          ? Brand.gold
                          : Brand.green.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
