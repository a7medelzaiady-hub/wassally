import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/form_draft.dart';

import '../services/cart_model.dart';
import '../services/delivery_service.dart';
import '../services/promo_service.dart';
import '../services/navigation.dart';
import '../services/order_service.dart';
import '../services/update_service.dart';
import '../services/order_gateway.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../utils/delivery_pin_notice.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/app_notice.dart';
import '../widgets/app_snack.dart';
import '../widgets/checkout_invoice.dart';
import '../widgets/delivery_eta_line.dart';

/// كود الخصم مخفي مؤقتًا من شاشة الطلب. لإرجاعه اجعل القيمة true.
// ignore: prefer_const_declarations
final bool kPromoCodesEnabled = false;

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
  final _addressFocus = FocusNode();
  String _savedAddress = '';
  final _notes = TextEditingController();
  final _courierNotes = TextEditingController();
  final _promo = TextEditingController();
  bool _submitting = false;
  bool _checkingPromo = false;
  bool _quotingPoints = false;
  int _referralPoints = 0;
  int _referralDiscountMinor = 0;

  Future<void> _applyReferralPoints() async {
    if (_quotingPoints || _submitting) return;
    if (_referralPoints > 0) {
      setState(() {
        _referralPoints = 0;
        _referralDiscountMinor = 0;
      });
      return;
    }
    setState(() => _quotingPoints = true);
    try {
      final quote = await OrderGateway.quoteReferralPoints((cart.subtotal * 100).round());
      if (!mounted) return;
      final points = quote['points'] as int;
      if (points == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack('مفيش نقاط متاحة للطلب ده.'),
        );
      }
      setState(() {
        _referralPoints = points;
        _referralDiscountMinor = quote['discountMinor'] as int;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack('تعذر تحميل خصم النقاط. حاول تاني.'),
        );
      }
    } finally {
      if (mounted) setState(() => _quotingPoints = false);
    }
  }
  List<DeliveryArea> _areas = const [];

  @override
  void initState() {
    super.initState();
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
    // #339: المسودة بتتستعاد بعد بيانات الحساب عشان ما تتكتبش فوقها.
    unawaited(_prefill().then((_) => _restoreDraft()));
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
        appSnack('الكود ده مش صحيح أو منتهي.'),
      );
    } else {
      cart.setPromo(r.code, r.percent);
      messenger.showSnackBar(
        appSnack('تم تفعيل الخصم ${r.percent.toStringAsFixed(0)}%'),
      );
    }
  }

  /// مسودة بيانات الطلب بعد ما أندرويد يقفل التطبيق (محليًا، من غير Firestore).
  late final FormDraft _draft = FormDraft('checkout', () => {
        'name': _name.text,
        'phone': _phone.text,
        'address': _address.text,
        'notes': _notes.text,
        'courierNotes': _courierNotes.text,
      });

  Future<void> _restoreDraft() async {
    final saved = await _draft.loadIfResumed();
    if (!mounted) return;
    if (saved != null) {
      final byKey = {
        'name': _name, 'phone': _phone, 'address': _address,
        'notes': _notes, 'courierNotes': _courierNotes,
      };
      setState(() {
        saved.forEach((key, value) {
          if (value.isNotEmpty) byKey[key]?.text = value;
        });
      });
    }
    _draft.attach([_name, _phone, _address, _notes, _courierNotes]);
  }

  Future<void> _prefill() async {
    final profile = await UserService.load();
    if (!mounted) return;
    setState(() {
      if (profile.name.isNotEmpty) _name.text = profile.name;
      if (_phone.text.isEmpty) _phone.text = profile.phone;
      _savedAddress = profile.address.trim();
      if (_address.text.isEmpty) _address.text = profile.address;
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _addressFocus.dispose();
    _notes.dispose();
    _courierNotes.dispose();
    _promo.dispose();
    super.dispose();
  }

  /// تأكيد العنوان قبل الإرسال (زي تطبيقات التوصيل): لو العميل مش في العنوان ده يغيّره.
  Future<bool> _confirmAddress() async {
    final address = _address.text.trim();
    final differs = _savedAddress.isNotEmpty && _savedAddress != address;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'هنوصّل الطلب فين؟',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, color: kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (cart.area.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('المنطقة: ${cart.area}'),
              ],
              if (differs) ...[
                const SizedBox(height: 10),
                Text(
                  'ده مختلف عن عنوانك المحفوظ.',
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'إنت موجود في العنوان ده؟ لو لأ، غيّره قبل ما نبعت الطلب عشان المندوب يوصلك صح.',
                style: TextStyle(height: 1.5),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('غيّر العنوان'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أيوه، ابعت الطلب'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) return true;
    if (mounted) {
      _addressFocus.requestFocus();
    }
    return false;
  }

  Future<void> _submit() async {
    if (_submitting || _quotingPoints) return;
    if (!(_form.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final wait = await OrderService.cooldownRemaining();
    if (!mounted) return;
    if (wait > Duration.zero) {
      messenger.showSnackBar(
        appSnack('لسه مبعوت لك طلب من شوية. استنى ${wait.inSeconds + 1} ثانية وابعت تاني.'),
      );
      return;
    }
    if (!await _confirmAddress() || !mounted) return;
    if (await DeliveryService.checkOrdersPaused()) {
      if (!mounted) return;
      messenger.showSnackBar(
        appSnack('استقبال الطلبات متوقف مؤقتًا. جرّب بعد شوية.'),
      );
      return;
    }
    if (!mounted) return;

    setState(() => _submitting = true);
    try {
      await OrderService.placeOrder(
        cart: cart,
        name: _name.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'[\s\-]'), ''),
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        courierNotes: _courierNotes.text.trim(),
        referralPoints: _referralPoints,
        referralDiscountMinor: _referralDiscountMinor,
      );

      await _draft.clear(); // الطلب اتأكد: مفيش مسودة تفضل.
      // Only navigate after the Worker/Firestore confirms successful creation.
      // The entry screen may still be the root (e.g. checkout via "Browse stores"),
      // so selecting shellTab alone would leave the customer on entry cards.
      if (!mounted) return;
      openCustomerTab(context, 2); // طلباتي
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) messenger.hideCurrentSnackBar();
        showAppNotice(
          title: 'تم إرسال طلبك بنجاح',
          message: kDeliveryPinKeepNotice,
        );
      });
    } on OrderLimitException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(appSnack(e.message));
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.message.contains('تم تحديث نظام تأكيد الطلبات')) {
        UpdateService.showProtocolUpdateRequired(context);
      } else {
        messenger.showSnackBar(appSnack(e.message));
      }
    } on FirebaseException catch (e) {
      debugPrint('CHECKOUT FIREBASE ERROR: code=${e.code}, message=${e.message}');
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        appSnack('تعذر إرسال الطلب (${e.code}). حاول تاني أو تواصل مع الدعم.'),
      );
    } catch (e) {
      debugPrint('CHECKOUT ERROR: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        appSnack('تعذر إرسال الطلب. تأكد من الاتصال وحاول تاني.'),
      );
    }
  }

  /// حقول مضغوطة: نفس شكل التطبيق بس أقصر، والأيقونة أصغر.
  InputDecoration _dense(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: kMuted, fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        prefixIcon: Icon(icon, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      );

  Widget _section(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 10);

    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'إتمام الطلب'),
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                children: [
                  _section('بيانات التوصيل'),
                  // الاسم والموبايل جنب بعض بدل سطرين.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _name,
                          inputFormatters: [LengthLimitingTextInputFormatter(80)],
                          textInputAction: TextInputAction.next,
                          decoration: _dense('الاسم', Icons.person_outline),
                          validator: (v) =>
                              (v == null || v.trim().length < 2) ? 'اكتب اسمك' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          textDirection: TextDirection.ltr,
                          decoration: _dense('رقم الموبايل', Icons.phone_outlined, hint: '01012345678'),
                          validator: (v) => isValidEgyptianMobile(v ?? '')
                              ? null
                              : 'رقم مصري صحيح (11 رقم)',
                        ),
                      ),
                    ],
                  ),
                  gap,
                  TextFormField(
                    controller: _address,
                    focusNode: _addressFocus,
                    inputFormatters: [LengthLimitingTextInputFormatter(300)],
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.next,
                    decoration: _dense(
                      'العنوان بالتفصيل',
                      Icons.location_on_outlined,
                      hint: 'المنطقة، الشارع، رقم العمارة والدور',
                    ),
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'اكتب العنوان بالتفصيل عشان المندوب يوصلك'
                        : null,
                  ),
                  if (_areas.isNotEmpty) ...[
                    gap,
                    DropdownButtonFormField<String>(
                      initialValue: cart.area.isEmpty ? null : cart.area,
                      isExpanded: true,
                      decoration: _dense('منطقة التوصيل', Icons.map_outlined),
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
                  gap,
                  // الملاحظتين جنب بعض، والتنبيه جوه الخانة بدل سطر تحتها.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('checkout-store-notes'),
                          controller: _notes,
                          inputFormatters: [LengthLimitingTextInputFormatter(500)],
                          minLines: 1,
                          maxLines: 3,
                          decoration: _dense(
                            'ملاحظة للمحل',
                            Icons.edit_note,
                            hint: 'من غير رقمك أو عنوانك',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('checkout-courier-notes'),
                          controller: _courierNotes,
                          inputFormatters: [LengthLimitingTextInputFormatter(300)],
                          minLines: 1,
                          maxLines: 3,
                          decoration: _dense(
                            'ملاحظة للمندوب',
                            Icons.two_wheeler_outlined,
                            hint: 'الدور، علامة مميزة',
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Text(
                      'الملاحظات اختيارية: المحل بيشوف ملاحظته بس، والمندوب ملاحظته بس.',
                      style: TextStyle(color: kMuted, fontSize: 11.5),
                    ),
                  ),
                  if (kPromoCodesEnabled) ...[
                    gap,
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promo,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _dense('كود خصم (اختياري)', Icons.local_offer_outlined),
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
                  ],
                  const SizedBox(height: 14),
                  // طريقة الدفع في سطر واحد مع العنوان.
                  _section(
                    'طريقة الدفع',
                    trailing: Container(
                      key: const Key('checkout-payment'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kPrimarySoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: kPrimary, width: 1.3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.payments_outlined, color: kPrimary, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'الدفع عند الاستلام',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle, color: kPrimary, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _section('ملخص الطلب'),
                  ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => CheckoutInvoice(
                      storeName: cart.storeName ?? '',
                      eta: (cart.storeId ?? '').isNotEmpty
                          ? CheckoutEtaLine(storeId: cart.storeId!)
                          : null,
                      items: [
                        for (final e in cart.items.entries)
                          InvoiceItem(e.key.name, e.value, e.key.price),
                      ],
                      totals: [
                        InvoiceTotal('المجموع', formatPrice(cart.subtotal)),
                        InvoiceTotal('رسوم التوصيل', formatPrice(cart.fee)),
                        if (cart.serviceFee > 0)
                          InvoiceTotal('رسوم الخدمة', formatPrice(cart.serviceFee)),
                        if (cart.discount > 0)
                          InvoiceTotal('خصم (${cart.promoCode})', '- ${formatPrice(cart.discount)}'),
                        if (_referralPoints > 0)
                          InvoiceTotal('خصم $_referralPoints نقطة',
                              '- ${formatPrice(_referralDiscountMinor / 100)}'),
                      ],
                      beforeTotal: OrderGateway.referralCampaignEnabled &&
                              OrderGateway.serverOrdersEnabled
                          ? TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: _quotingPoints || _submitting ? null : _applyReferralPoints,
                              icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                              label: Text(_referralPoints > 0
                                  ? 'إلغاء استخدام النقاط'
                                  : 'استخدم نقاط الدعوات'),
                            )
                          : null,
                      grandTotal: formatPrice(cart.total - _referralDiscountMinor / 100),
                      note: 'تقدر تعدّل المنتجات أو الكميات أو بيانات التوصيل من «طلباتي» '
                          'طالما المندوب لسه ما استلمش الطلب.',
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
}
