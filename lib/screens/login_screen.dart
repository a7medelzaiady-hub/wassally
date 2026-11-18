import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../legal/legal_content.dart';
import '../services/auth_service.dart';
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
                    : 'تعذر تسجيل الدخول (' + e.code + '). حاول تاني.';
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
    final text = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const ink = Color(0xFF0E0E10);

    return Scaffold(
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
                'https://images.unsplash.com/photo-1504674900247-0877df9cc836?q=80&w=1000',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
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
                            fontSize: 40,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        TextSpan(
                          text: 'وهتوصلك ',
                          style: TextStyle(
                            color: kPrimary,
                            fontSize: 40,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const TextSpan(
                          text: 'في ثواني',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 40,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
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
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
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
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Text('المتابعة بحساب جوجل'),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'بالمتابعة أنت بتوافق على ',
                        style: text.bodySmall?.copyWith(color: Colors.white54),
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
                        style: text.bodySmall?.copyWith(color: Colors.white54),
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
    );
  }
}

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
              ?.copyWith(color: kPrimary, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
