import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cart_model.dart';
import '../services/delivery_service.dart';
import '../services/promo_service.dart';
import '../services/navigation.dart';
import '../services/order_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _courierNotes = TextEditingController();
  final _promo = TextEditingController();
  bool _submitting = false;
  bool _checkingPromo = false;
  List<DeliveryArea> _areas = const [];

  @override
  void initState() {
    super.initState();
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
    _prefill();
    // أي منطقة/كوبون من محاولة قديمة بنبدأ منها من جديد.
    cart.fee = CartModel.deliveryFee;
    cart.area = '';
    cart.promoCode = '';
    cart.promoPercent = 0;
    DeliveryService.load().then((a) {
      if (mounted) setState(() => _areas = a);
    });
  }

  Future<void> _applyPromo() async {
    if (_checkingPromo) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checkingPromo = true);
    final r = await PromoService.check(_promo.text);
    if (!mounted) return;
    setState(() => _checkingPromo = false);
    if (r == null) {
      cart.setPromo('', 0);
      messenger.showSnackBar(
        const SnackBar(content: Text('الكود ده مش صحيح أو منتهي.')),
      );
    } else {
      cart.setPromo(r.code, r.percent);
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم تفعيل الخصم ${r.percent.toStringAsFixed(0)}%'),
        ),
      );
    }
  }

  Future<void> _prefill() async {
    final profile = await UserService.load();
    if (!mounted) return;
    setState(() {
      if (profile.name.isNotEmpty) _name.text = profile.name;
      if (_phone.text.isEmpty) _phone.text = profile.phone;
      if (_address.text.isEmpty) _address.text = profile.address;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    _courierNotes.dispose();
    _promo.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await OrderService.placeOrder(
        cart: cart,
        name: _name.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'[\s\-]'), ''),
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        courierNotes: _courierNotes.text.trim(),
      );
      navigator.popUntil((route) => route.isFirst);
      shellTab.value = 2;
      final dialogContext = navigator.context;
      if (dialogContext.mounted) {
        showDialog<void>(
          context: dialogContext,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'تم إرسال طلبك',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: const Text(
                'هنبدأ نجهّزه حالًا. تابع حالة طلبك ومعرفة الديليفري وصل لفين من صفحة «طلباتي».',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.5),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: const Text('تابع طلبي'),
                ),
              ],
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('تم إرسال طلبك. تابعه من صفحة طلباتي.')),
        );
      }
    } on OrderLimitException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on StateError catch (e) {
      // رسائل placeOrder (المحل مقفول، صلاحيات، كود الخطأ...) كانت بتتبلع هنا.
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('CHECKOUT ERROR: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب (${e.runtimeType}). تأكد من الاتصال وحاول تاني.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'إتمام الطلب'),
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'بيانات التوصيل',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    inputFormatters: [LengthLimitingTextInputFormatter(80)],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'اكتب اسمك' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الموبايل',
                      hintText: '01012345678',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => isValidEgyptianMobile(v ?? '')
                        ? null
                        : 'اكتب رقم موبايل مصري صحيح (11 رقم)',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                    minLines: 2,
                    maxLines: 3,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'العنوان بالتفصيل',
                      hintText: 'المنطقة، الشارع، رقم العمارة والدور',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'اكتب العنوان بالتفصيل عشان المندوب يوصلك'
                        : null,
                  ),
                  if (_areas.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cart.area.isEmpty ? null : cart.area,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'منطقة التوصيل',
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                      items: [
                        for (final a in _areas)
                          DropdownMenuItem(
                            value: a.name,
                            child: Text('${a.name} — ${formatPrice(a.fee)}'),
                          ),
                      ],
                      onChanged: (v) {
                        final a = _areas.firstWhere((x) => x.name == v);
                        cart.setArea(a.name, a.fee);
                      },
                      validator: (v) =>
                          v == null ? 'اختار منطقة التوصيل' : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات للمحل (اختياري)',
                      helperText: 'المحل بيشوفها، فمتكتبش رقمك أو عنوانك هنا',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _courierNotes,
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات للمندوب (اختياري)',
                      helperText:
                          'الدور، علامة مميزة... المندوب بس هو اللي بيشوفها',
                      prefixIcon: Icon(Icons.two_wheeler_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promo,
                          textDirection: TextDirection.ltr,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'كود خصم (اختياري)',
                            prefixIcon: Icon(Icons.local_offer_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _checkingPromo ? null : _applyPromo,
                        child: _checkingPromo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('تطبيق'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'طريقة الدفع',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kPrimarySoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPrimary, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.payments_outlined, color: kPrimary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'الدفع عند الاستلام',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(Icons.check_circle, color: kPrimary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ملخص الطلب',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kLine),
                    ),
                    child: ListenableBuilder(
                      listenable: cart,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cart.storeName ?? '',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final e in cart.items.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('${e.value} × ${e.key.name}'),
                                  ),
                                  Text(formatPrice(e.key.price * e.value)),
                                ],
                              ),
                            ),
                          const Divider(height: 22),
                          _line('المجموع', formatPrice(cart.subtotal)),
                          const SizedBox(height: 4),
                          _line(
                            'رسوم التوصيل',
                            formatPrice(cart.fee),
                          ),
                          if (cart.discount > 0) ...[
                            const SizedBox(height: 4),
                            _line(
                              'خصم (${cart.promoCode})',
                              '- ${formatPrice(cart.discount)}',
                            ),
                          ],
                          const SizedBox(height: 8),
                          _line(
                            'الإجمالي',
                            formatPrice(cart.total),
                            strong: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('تأكيد الطلب'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool strong = false}) {
    final style = strong
        ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)
        : TextStyle(color: kMuted, fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
