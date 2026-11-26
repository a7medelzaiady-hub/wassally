import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_tokens.dart';
import '../utils/img.dart';
import '../widgets/cached_net_image.dart';
import '../widgets/quick_order_promo.dart' show kQuickPhotoOrdersEnabled;

/// الجولة الإعلانية بتظهر لحد مرتين في اليوم لكل حساب (محليًا، بدون Firestore).
class OnboardingStore {
  OnboardingStore._();

  /// أقصى عدد مرات ظهور في اليوم.
  static const maxPerDay = 2;

  static String _dayKey(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  static String _key(String uid, DateTime now) => 'onboarding_${uid}_${_dayKey(now)}';

  static String? get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // Firebase not initialized (widget tests).
    }
  }

  /// فيه حساب مسجل دخول؟ (متزامن: بيحدد هل صفحة ما بعد الدخول تستنى قرار الجولة.)
  static bool get hasAccount => _uid != null;

  /// هل الجولة محتاجة تظهر للحساب الحالي؟
  static Future<bool> shouldShow({String? uid, DateTime? now}) async {
    final id = uid ?? _uid;
    if (id == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(_key(id, now ?? DateTime.now())) ?? 0) < maxPerDay;
    } catch (_) {
      return false;
    }
  }

  /// بيتسجل لما الجولة تتقفل (تخطي أو «يلا نبدأ»).
  static Future<void> markDone({String? uid, DateTime? now}) async {
    final id = uid ?? _uid;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(id, now ?? DateTime.now());
      await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
    } catch (_) {}
  }
}

class _Step {
  const _Step(this.asset, this.alignment, this.hook, this.body, this.icon);
  final String asset;
  final Alignment alignment;
  final String hook;
  final String body;
  final IconData icon;
}

/// جولة إعلانية من 3 شاشات عند فتح التطبيق (لحد مرتين في اليوم).
/// «التالي» و«تخطي» دايمًا تحت، ومؤشر ١/٣. ما بتطلبش أي صلاحيات.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.onDone, this.posters = const []});

  /// صور الإدارة (شاشة كاملة 1080×1920). لو فاضية بتظهر الجولة المدمجة.
  final List<String> posters;

  /// للاختبارات: بديل لإغلاق الصفحة.
  final VoidCallback? onDone;

  static List<_Step> get _steps => [
        kQuickPhotoOrdersEnabled
            ? const _Step(
                'assets/images/quick_photo_ad.jpg',
                Alignment(-0.1, -0.3),
                'مستعجل؟ صوّر طلبك وخلاص! 📸',
                'اكتب اللي ناقصك، أو صوّر ورقة طلباتك… والمندوب يتواصل معاك بعد ما يستلم الطلب.',
                Icons.photo_camera_outlined,
              )
            : const _Step(
                'assets/images/entry_quick.jpg',
                Alignment(-0.3, 0),
                'مستعجل؟ اكتب طلبك وخلاص! ⚡',
                'اكتب اللي ناقصك من أي محل… والمندوب يتواصل معاك بعد ما يستلم الطلب ويوصّله لحد بابك.',
                Icons.bolt_rounded,
              ),
        const _Step(
          'assets/images/entry_offers.jpg',
          Alignment(-0.4, 0),
          'متفوّتش العروض الحلوة! 🎁',
          'شوف عروض المحلات والمكافآت المتاحة، واختار اللي يناسبك.',
          Icons.local_offer_rounded,
        ),
        const _Step(
          'assets/images/entry_stores.jpg',
          Alignment(-0.4, 0),
          'كل اللي محتاجه من محلات منطقتك 🛍️',
          'اختار القسم، تصفّح المحلات، واطلب من محلك المفضّل.',
          Icons.storefront_rounded,
        ),
      ];

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static String _ar(int n) =>
      n.toString().split('').map((c) => '٠١٢٣٤٥٦٧٨٩'[int.parse(c)]).join();

  int get _count =>
      widget.posters.isNotEmpty ? widget.posters.length : OnboardingPage._steps.length;

  Widget _posterView(String url) => CachedNetImage(
        url: thumb(url, w: 1080),
        memCacheWidth: 1080,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorWidget: const ColoredBox(color: AppColors.purpleDeep),
      );

  Future<void> _finish() async {
    await OnboardingStore.markDone();
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      // pop مش maybePop: الـPopScope بتاع الجولة بيمنع maybePop.
      Navigator.of(context).pop();
    }
  }

  void _next() {
    if (_page == _count - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _stepView(_Step step) {
    return LayoutBuilder(builder: (context, box) {
      return Column(
        children: [
          // صورة واقعية تملأ النص العلوي وبتذوب في البنفسجي.
          SizedBox(
            height: box.maxHeight * 0.58,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  step.asset,
                  fit: BoxFit.cover,
                  alignment: step.alignment,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.purple),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.55, 1],
                      colors: [Color(0x00000000), AppColors.purpleDeep],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.md),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppColors.actionGradient,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(step.icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      step.hook,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.display,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      step.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: AppTypography.body,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final steps = OnboardingPage._steps;
    final count = _count;
    final last = _page == count - 1;
    return PopScope(
      // الرجوع من أول شاشة = تخطي (المستخدم ما يتعلقش جوه الجولة).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_page > 0) {
          _controller.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _finish();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.purpleDeep,
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                key: const Key('onboarding-pages'),
                controller: _controller,
                itemCount: count,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => widget.posters.isNotEmpty
                    ? _posterView(widget.posters[i])
                    : _stepView(steps[i]),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                child: Row(
                  children: [
                    Flexible(
                      child: TextButton(
                        key: const Key('onboarding-skip'),
                        onPressed: _finish,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const FittedBox(fit: BoxFit.scaleDown, child: Text('تخطي')),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < count; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _page ? 20 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _page ? AppColors.orange : Colors.white38,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_ar(_page + 1)}/${_ar(count)}',
                            key: const Key('onboarding-progress'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: AppTypography.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('onboarding-next'),
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 48),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          shape: const StadiumBorder(),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(last ? 'يلا نبدأ' : 'التالي'),
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
    );
  }
}
