import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/referral.dart';
import '../services/order_gateway.dart';
import '../theme/app_tokens.dart';

/// خانة «اكتب كود الدعوة هنا» في هيدر صفحة ما بعد الدخول.
///
/// نفس مسار حفظ الكود الموجود (الـWorker بيتحقق من الكود وأهلية الحساب)،
/// من غير أي قراءة إضافية من Firestore. بعد الحفظ الناجح الخانة بتتقفل
/// وبتعرض إن الكود اتسجل (محفوظة على الجهاز لكل حساب).
class InviteCodeField extends StatefulWidget {
  const InviteCodeField({super.key, this.onSubmit});

  /// للاختبارات فقط: بديل لاستدعاء الـWorker.
  final Future<void> Function(String code)? onSubmit;

  @override
  State<InviteCodeField> createState() => _InviteCodeFieldState();
}

class _InviteCodeFieldState extends State<InviteCodeField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;
  bool _saved = false;

  static String _keyFor(String uid) => 'invite_code_saved_$uid';

  String? get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // Firebase not initialized (widget tests).
    }
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && prefs.getBool(_keyFor(uid)) == true) {
        setState(() => _saved = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _claim(String code) async {
    final custom = widget.onSubmit;
    if (custom != null) return custom(code);
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw StateError('سجّل الدخول من جديد.');
    }
    await OrderGateway.claimRegistrationReferral(idToken: token, code: code);
  }

  Future<void> _submit() async {
    if (_saving || _saved) return;
    final code = normalizeReferralCode(_controller.text);
    if (!isReferralCodeFormatValid(code)) {
      _toast('اكتب كود من ٦ إلى ١٢ حرفًا إنجليزيًا أو رقمًا.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _claim(code);
      _focus.unfocus();
      if (!mounted) return;
      setState(() => _saved = true);
      _toast('تم حفظ كود الدعوة بنجاح.');
      final uid = _uid;
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyFor(uid), true);
      }
    } catch (error) {
      if (mounted) {
        _toast(error is StateError ? error.message : 'تعذر حفظ الكود. جرّب تاني.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 2,
      shadowColor: Colors.black26,
      child: SizedBox(
        height: 46,
        child: _saved
            ? const Row(
                key: Key('invite-code-saved'),
                children: [
                  SizedBox(width: AppSpacing.lg),
                  Icon(Icons.check_circle_rounded, color: AppColors.success),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'تم حفظ كود الدعوة',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: AppSpacing.lg),
                  const Icon(Icons.card_giftcard_rounded, color: AppColors.muted, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      key: const Key('invite-code-input'),
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !_saving,
                      maxLength: 12,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'اكتب كود الدعوة هنا',
                        counterText: '',
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: _saving
                        ? const SizedBox(
                            width: 40,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              ),
                            ),
                          )
                        : IconButton(
                            key: const Key('invite-code-submit'),
                            tooltip: 'تأكيد كود الدعوة',
                            onPressed: _submit,
                            icon: const Icon(Icons.arrow_back_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.purple,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(40, 40),
                              fixedSize: const Size(40, 40),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
