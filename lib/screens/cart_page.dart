import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cart_book.dart';
import '../services/cart_model.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/qty_stepper.dart';
import '../widgets/app_header.dart';
import 'checkout_page.dart';
import 'my_carts_page.dart';
import 'store_directory_page.dart';

/// السلة. بتتعرض كتبويب في الشاشة الرئيسية، أو كصفحة مستقلة (showBackButton).
class CartPage extends StatelessWidget {
  final bool showBackButton;
  const CartPage({super.key, this.showBackButton = false});

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'تفريغ السلة',
      message: 'هتتمسح كل المنتجات من السلة. متأكد؟',
      confirmLabel: 'تفريغ',
      destructive: true,
    );
    if (ok) cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([cart, carts]),
      builder: (context, _) {
        final clearButton = cart.isEmpty
            ? null
            : TextButton(
                // On the purple header: white text.
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => _clear(context),
                child: const Text('تفريغ'),
              );

        return Column(
          children: [
            if (showBackButton)
              InnerHeader(title: 'سلتي', trailing: clearButton)
            else
              AppHeader(
                gradient: Brand.headerGradient,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'سلتي',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    ?clearButton,
                  ],
                ),
              ),
            if (carts.hasParked || carts.restoredCount > 0) const MyCartsBanner(),
            Expanded(
              child: cart.isEmpty
                  ? EmptyState(
                      icon: Icons.shopping_basket_outlined,
                      title: 'السلة فاضية',
                      message: 'ضيف منتجات من أي محل وهتظهر هنا.',
                      actionLabel: 'تصفّح المحلات',
                      // بيفتح قائمة كل المحلات (نفس شاشة "تسوق" اللي في الرئيسية).
                      onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoreDirectoryPage(),
                        ),
                      ),
                    )
                  : const _CartBody(),
            ),
          ],
        );
      },
    );
  }
}

class _CartBody extends StatefulWidget {
  const _CartBody();

  @override
  State<_CartBody> createState() => _CartBodyState();
}

class _CartBodyState extends State<_CartBody> {
  bool _showSuggestions = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _showSuggestions = prefs.getBool('cart_suggestions_enabled') ?? true);
    });
  }

  Future<void> _toggleSuggestions(bool enabled) async {
    setState(() => _showSuggestions = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cart_suggestions_enabled', enabled);
  }


  // الودجت دي بتتعمل const من CartPage، يعني Flutter بيتخطّى إعادة بنائها لما السلة تتغيّر.
  // عشان كده بتسمع للسلة بنفسها، وإلا أزرار + و − و حذف الصنف بتغيّر الكميات من غير ما الشاشة تتحدّث.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cart,
    builder: (context, _) => _buildBody(context),
  );

  Widget _buildBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final entries = cart.items.entries.toList();
    final locked = cart.submittedOrderId != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: kAccent.withValues(alpha: 0.10),
                      child: Icon(Icons.storefront_rounded, size: 19, color: kAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cart.storeName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${entries.length} صنف في السلة',
                            style: text.bodySmall?.copyWith(color: kMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (cart.specialRequest != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5B85C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('طلب خاص مرفق بالطلب',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            tooltip: 'إزالة الطلب الخاص',
                            onPressed: cart.clearSpecialRequest,
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ],
                      ),
                      if ((cart.specialRequest!['description'] ?? '').toString().isNotEmpty)
                        Text(cart.specialRequest!['description'].toString()),
                      Text('الكمية المطلوبة: ${cart.specialRequest!['quantity'] ?? 1}'),
                      if ((cart.specialRequest!['imageUrl'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              cart.specialRequest!['imageUrl'].toString(),
                              height: 110,
                              width: 110,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      if ((cart.specialRequest!['voiceUrl'] ?? '').toString().isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.mic, size: 18),
                              SizedBox(width: 6),
                              Text('رسالة صوتية مرفقة بالطلب'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              if (!_showSuggestions)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => _toggleSuggestions(true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('إظهار اقتراحات كمّل طلبك'),
                  ),
                ),
              if (_showSuggestions && cart.completionSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F8F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCCE7D2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text('🛒 ناقصك حاجة؟ كمّل طلبك!',
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                        TextButton.icon(
                          onPressed: () => _toggleSuggestions(false),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('إيقاف الاقتراحات'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      for (final p in cart.completionSuggestions)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatPrice(p.price)),
                          trailing: IconButton(
                            tooltip: 'إضافة للسلة',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => cart.add(p,
                              storeId: cart.storeId ?? '',
                              storeName: cart.storeName ?? ''),
                          ),
                        ),
                    ],
                  ),
                ),
              for (final e in entries)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kLine),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.key.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatPrice(e.key.price * e.value),
                              style: text.bodyMedium?.copyWith(
                                color: kPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // بعد إرسال الطلب السلة بتتقفل: الكمية بتتعرض بس من غير تعديل.
                      if (locked)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('× ${e.value}',
                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        )
                      else ...[
                        IconButton(
                          tooltip: 'حذف الصنف من السلة',
                          onPressed: () => cart.removeItem(e.key),
                          icon: const Icon(Icons.delete_outline_rounded, size: 21),
                          color: kDanger,
                          visualDensity: VisualDensity.compact,
                        ),
                        QtyStepper(
                          qty: e.value,
                          onAdd: () => cart.add(
                            e.key,
                            storeId: cart.storeId ?? '',
                            storeName: cart.storeName ?? '',
                          ),
                          onRemove: () => cart.remove(e.key),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        _CartFooter(locked: locked),
      ],
    );
  }
}

/// الشريط اللي تحت: الإجمالي وزرار واحد. تفاصيل الرسوم بتتفتح بالضغط
/// عشان الملخص ما ياخدش نص الشاشة ويغطي الأصناف.
class _CartFooter extends StatefulWidget {
  final bool locked;
  const _CartFooter({required this.locked});

  @override
  State<_CartFooter> createState() => _CartFooterState();
}

class _CartFooterState extends State<_CartFooter> {
  bool _open = false;

  Future<void> _reorder() async {
    final ok = await confirmDialog(
      context,
      title: 'طلب جديد بنفس الأصناف',
      message: 'هتبدأ طلب جديد بنفس محتويات السلة. '
          'تأكد إنك مش بتكرر الطلب اللي بعتّه.',
      confirmLabel: 'ابدأ طلب جديد',
    );
    if (ok) cart.beginNewOrder();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked)
              Container(
                key: const Key('submitted-cart-notice'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: kSuccess),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'طلبك اتبعت بنجاح، ومش هيتبعت مرتين.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        children: [
                          _SummaryRow(label: 'المجموع', value: formatPrice(cart.subtotal)),
                          const SizedBox(height: 4),
                          _SummaryRow(label: 'رسوم التوصيل', value: formatPrice(cart.fee)),
                          if (cart.serviceFee > 0) ...[
                            const SizedBox(height: 4),
                            _SummaryRow(label: 'رسوم الخدمة', value: formatPrice(cart.serviceFee)),
                          ],
                          const Divider(height: 14),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('cart-total-toggle'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatPrice(cart.total),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'الإجمالي شامل الرسوم',
                                style: TextStyle(fontSize: 12, color: kMuted),
                              ),
                              Icon(
                                _open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                                size: 18,
                                color: kMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: locked
                      ? OutlinedButton.icon(
                          key: const Key('cart-reorder-explicit'),
                          onPressed: _reorder,
                          icon: const Icon(Icons.replay_rounded, size: 19),
                          label: const Text('طلب جديد بنفس الأصناف'),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                          ),
                          onPressed: cart.items.isEmpty
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const CheckoutPage()),
                                ),
                          child: Text(cart.items.isEmpty ? 'ضيف منتجًا أولًا' : 'كمّل الطلب'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge;
    final style = strong
        ? base?.copyWith(fontWeight: FontWeight.w800, fontSize: 17)
        : base?.copyWith(color: kMuted, fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

/// تنبيه في السلة: عند العميل سلال تانية محفوظة في «سلّاتي».
class MyCartsBanner extends StatelessWidget {
  const MyCartsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final others = carts.parked.length;
    final restored = carts.restoredCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('my-carts-banner'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyCartsPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kAccent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.shopping_basket_rounded, size: 20, color: kAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    restored > 0
                        ? 'رجّعنالك ${restored == 1 ? 'سلتك' : '$restored سلال'} من آخر مرة (بتفضل محفوظة على موبايلك لحد ما تفرّغها بنفسك). افتح «سلّاتي» وراجعها؛ الأسعار بتتراجع تاني قبل الطلب.'
                        : others == 1
                            ? 'عندك سلة تانية محفوظة'
                            : 'عندك $others سلال تانية محفوظة',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
                Text('سلّاتي', style: TextStyle(fontSize: 13, color: kAccent, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_left, color: kAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
