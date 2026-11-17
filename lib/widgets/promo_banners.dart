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
      image: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1100&q=80',
      title: 'كل اللي بتحبه.. أقرب ليك',
      subtitle: 'اكتشف أحلى المحلات والعروض حواليك',
    ),
    _Slide(
      image: 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=1100&q=80',
      title: 'كل احتياجات بيتك',
      subtitle: 'اختار طلبك وسيبه علينا',
    ),
    _Slide(
      image: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1100&q=80',
      title: 'لحظتك الحلوة تبدأ هنا',
      subtitle: 'مشروبات ومذاق يوصلك لحد عندك',
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
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _next());
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
    final title = s.title.isEmpty ? 'كل اللي بتحبه.. أقرب ليك' : s.title;
    final subtitle =
        s.subtitle.isEmpty ? 'اكتشف محلات وعروض قريبة منك' : s.subtitle;

    if (s.image != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            s.image!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => DecoratedBox(
              decoration: BoxDecoration(gradient: Brand.headerGradient),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Brand.greenDark.withValues(alpha: 0.88),
                  Brand.greenDark.withValues(alpha: 0.48),
                  Colors.transparent,
                ],
                stops: const [0, 0.56, 1],
              ),
            ),
          ),
          PositionedDirectional(
            start: 18,
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'وصّلي • اكتشف',
                style: TextStyle(
                  color: Brand.greenDark,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 18,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: 220,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 9,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      'اكتشف دلوقتي',
                      style: TextStyle(
                        color: Brand.greenDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: Brand.headerGradient),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        '$title\n$subtitle',
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          height: 1.5,
          fontWeight: FontWeight.w900,
        ),
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
