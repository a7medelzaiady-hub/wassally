import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/category_tile.dart';
import '../widgets/landing_highlights.dart';
import 'main_shell.dart';

/// آخر مستخدم شاف شاشة الأقسام في الجلسة دي (عشان ما تظهرش تاني لو السمة اتغيّرت مثلًا).
String? _landingSeenFor;

/// نقطة دخول العميل: شاشة الأقسام الأول، وبعدها الرئيسية.
class CustomerEntry extends StatefulWidget {
  const CustomerEntry({super.key});

  @override
  State<CustomerEntry> createState() => _CustomerEntryState();
}

class _CustomerEntryState extends State<CustomerEntry> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late bool _show = _landingSeenFor != _uid;

  void _pick(String? category) {
    homeCategoryRequest.value = category;
    shellTab.value = 0;
    _landingSeenFor = _uid;
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const MainShell();
    return CategoriesLandingPage(onPick: _pick);
  }
}

// صور حقيقية لكل قسم. تقدر تغيّرها من Firestore: app_info/category_images
// بحقول نصية للأقسام المتاحة وقيمتها رابط الصورة (مثلاً من Cloudinary).
const Map<String, String> kCategoryPhotos = {
  'مطاعم': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=700&q=70',
  'سوبرماركت': 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=700&q=70',
  'ورد': 'https://images.unsplash.com/photo-1490750967868-88aa4486c946?auto=format&fit=crop&w=700&q=70',
};

class CategoriesLandingPage extends StatelessWidget {
  final void Function(String? category) onPick;
  const CategoriesLandingPage({super.key, required this.onPick});

  String _firstName() {
    final u = FirebaseAuth.instance.currentUser;
    final n = (u?.displayName ?? '').trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final name = _firstName();
    return Scaffold(
      body: Column(
        children: [
          BrandHeader(
            title: name.isEmpty ? 'أهلاً بيك' : 'أهلاً يا $name',
            subtitle: 'عايز تطلب إيه النهارده؟',
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('app_info')
                  .doc('category_images')
                  .snapshots(),
              builder: (context, snap) {
                final over = snap.data?.data() ?? const <String, dynamic>{};
                String photo(String c) {
                  final v = (over[c] ?? '').toString().trim();
                  return v.isNotEmpty ? v : (kCategoryPhotos[c] ?? '');
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  children: [
                    Text(
                      'اختار القسم',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.0,
                      children: [
                        for (final c in kCategories)
                          _CategoryCard(
                            info: c,
                            photo: photo(c.category),
                            onTap: () => onPick(c.category),
                          ),
                      ],
                    ),
                    const LandingHighlights(),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => onPick(null),
                        child: const Text(
                          'عرض كل المحلات',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// كارت بصورة حقيقية بتأثير ثلاثي الأبعاد: ميلان خفيف بمنظور، ظلال طبقات،
/// وحافة لامعة، وبيتحرّك لما تضغط عليه.
class _CategoryCard extends StatefulWidget {
  final CategoryInfo info;
  final String photo;
  final VoidCallback onTap;
  const _CategoryCard({
    required this.info,
    required this.photo,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _down = false;

  Widget _placeholder() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [widget.info.tint, widget.info.accent],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final tilt = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateX(_down ? 0.10 : -0.045)
      ..rotateY(_down ? -0.06 : 0.035);

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transformAlignment: Alignment.center,
        transform: tilt,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: info.accent.withValues(alpha: _down ? 0.20 : 0.38),
              blurRadius: _down ? 10 : 24,
              offset: Offset(0, _down ? 4 : 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.photo.isEmpty
                  ? _placeholder()
                  : Image.network(
                      widget.photo,
                      fit: BoxFit.cover,
                      frameBuilder: (context, child, frame, sync) =>
                          AnimatedOpacity(
                            opacity: (frame != null || sync) ? 1 : 0,
                            duration: const Duration(milliseconds: 350),
                            child: child,
                          ),
                      errorBuilder: (_, _, _) => _placeholder(),
                    ),
              // خلفية بتظهر قبل ما الصورة تحمّل
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.35, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // لمعة زجاجية علوية
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 70,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.28),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // حافة لامعة
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      info.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
