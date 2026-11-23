import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../legal/legal_content.dart';
import '../services/auth_service.dart';
import '../services/e2e_support.dart';
import 'legal_page.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in failed: ${e.code} | ${e.message}');
      if (mounted) {
        final msg = e.code == 'network-request-failed'
            ? 'مفيش اتصال بالإنترنت. جرّب تاني.'
            : e.code == 'google-sign-in-interrupted'
                ? 'جوجل رجّعك من اختيار الحساب قبل إكمال تسجيل الدخول. جرّب مرة تانية.'
                : e.code == 'google-sign-in-failed'
                    ? 'تعذر تسجيل الدخول: ${e.message ?? e.code}'
                : e.code == 'canceled' || e.code == 'web-context-canceled'
                    ? 'عملية تسجيل الدخول ما اكتملتش. جرّب تاني.'
                    : 'تعذر تسجيل الدخول (${e.code}). حاول تاني.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الدخول. حاول تاني.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // خط احترافي لشاشة الدخول بس، باقي التطبيق على Tajawal.
    final baseTheme = Theme.of(context);
    final loginTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontFamily: _loginFont),
    );
    final text = loginTheme.textTheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const ink = Color(0xFF0E0E10);

    return Theme(
      data: loginTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: _loginFont),
        child: Scaffold(
      backgroundColor: ink,
      body: Stack(
        children: [
          // صورة علوية متلاشية
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: Image.network(
                // الصورة الأصلية لصفحة الدخول (كانت قبل commit 2c223a8)، زي ما كانت بالظبط.
                'https://images.unsplash.com/photo-1504674900247-0877df9cc836?q=80&w=1000',
                fit: BoxFit.cover,
                // لو الإنترنت ضعيف أو الصورة ما نزلتش، بنعرض الخلفية المحلية بدل فراغ.
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/login_bg.webp',
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottomInset * 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: kPrimary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delivery_dining,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'وصلي',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'اطلب أي حاجة\n',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: 'وهتوصلك ',
                          style: TextStyle(
                            color: kPrimary,
                            fontSize: 26,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(
                          text: 'في ثواني',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 26,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    ' تسوق من محلات مدينتك لحد باب بيتك',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(color: kPrimary),
                          )
                        : FilledButton(
                            onPressed: _signIn,
                            style: FilledButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontFamily: _loginFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('المتابعة بحساب جوجل'),
                          ),
                  ),
                  if (E2eSupport.enabled) ...[
                    const SizedBox(height: 10),
                    for (final r in const [
                      ('customer', 'عميل'),
                      ('owner', 'صاحب محل'),
                      ('courier', 'مندوب'),
                    ])
                      TextButton(
                        onPressed: () => E2eSupport.signInAs(
                          'sub-${r.$1}',
                          '${r.$1}@e2e.test',
                        ),
                        child: Text(
                          'دخول تجريبي: ${r.$2}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'بالمتابعة أنت بتوافق على ',
                        style: text.bodySmall?.copyWith(color: Colors.white54, fontSize: 12),
                      ),
                      _LegalLink(
                        label: 'شروط الاستخدام',
                        onTap: () => LegalPage.open(
                          context,
                          title: 'شروط الاستخدام',
                          sections: kTermsSections,
                        ),
                      ),
                      Text(
                        ' و',
                        style: text.bodySmall?.copyWith(color: Colors.white54, fontSize: 11.5),
                      ),
                      _LegalLink(
                        label: 'سياسة الخصوصية',
                        onTap: () => LegalPage.open(
                          context,
                          title: 'سياسة الخصوصية',
                          sections: kPrivacySections,
                        ),
                      ),
                    ],
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

const _loginFont = 'PlexArabic';

class _LegalLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LegalLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 11.5),
        ),
      ),
    );
  }
}
