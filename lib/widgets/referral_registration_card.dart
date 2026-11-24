import 'package:flutter/material.dart';

import '../models/referral.dart';

/// The Worker authorizes only claims made during the first five minutes of
/// the first Google registration. This is a UI hint, never an authorization
/// check: the Worker always verifies the account and code independently.
bool isWithinReferralRegistrationWindow({
  required DateTime? accountCreatedAt,
  required DateTime? lastSignInAt,
  DateTime? now,
}) {
  if (accountCreatedAt == null || lastSignInAt == null) return false;
  final age = (now ?? DateTime.now()).difference(accountCreatedAt);
  final signInDelay = lastSignInAt.difference(accountCreatedAt);
  return !age.isNegative &&
      age <= const Duration(minutes: 5) &&
      signInDelay >= const Duration(seconds: -2) &&
      signInDelay <= const Duration(seconds: 2);
}

/// Code entry lives inside the authenticated referral page, not on Google
/// sign-in. Saving is explicit, optional, and confirmed by the trusted Worker.
class ReferralRegistrationCard extends StatefulWidget {
  const ReferralRegistrationCard({super.key, required this.onSubmit});

  final Future<void> Function(String code) onSubmit;

  @override
  State<ReferralRegistrationCard> createState() =>
      _ReferralRegistrationCardState();
}

class _ReferralRegistrationCardState extends State<ReferralRegistrationCard> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _saved || !_formKey.currentState!.validate()) return;
    final code = normalizeReferralCode(_controller.text);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message
            : 'تعذر حفظ الكود. جرّب تاني.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _saved
            ? const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(child: Text('تم حفظ كود الدعوة بنجاح، ومش هينفع تغيّره.')),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'عندك كود دعوة؟',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ادخل الكود هنا بعد أول تسجيل بجوجل. متاح مرة واحدة خلال أول ٥ دقايق من إنشاء الحساب.',
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _controller,
                      enabled: !_saving,
                      textDirection: TextDirection.ltr,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: 'كود الدعوة (اختياري)',
                        hintText: 'اكتب كود الدعوة اللي وصلك',
                        border: OutlineInputBorder(),
                      ),
                      validator: (input) =>
                          isReferralCodeFormatValid(
                            normalizeReferralCode(input ?? ''),
                          )
                              ? null
                              : 'اكتب كود من ٦ إلى ١٢ حرفًا إنجليزيًا أو رقمًا.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: Text(_saving ? 'بيتحفظ...' : 'تأكيد كود الدعوة'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
