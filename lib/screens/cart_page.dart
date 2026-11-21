import 'package:flutter/material.dart';

import '../services/cart_model.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/qty_stepper.dart';
import '../widgets/app_header.dart';
import 'checkout_page.dart';
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
      listenable: cart,
      builder: (context, _) {
        final clearButton = cart.isEmpty
            ? null
            : TextButton(
                onPressed: () => _clear(context),
                child: const Text('تفريغ'),
              );

        return Column(
          children: [
            if (showBackButton)
              InnerHeader(title: 'سلتي', trailing: clearButton)
            else
              AppHeader(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'سلتي',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ?clearButton,
                  ],
                ),
              ),
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

class _CartBody extends StatelessWidget {
  const _CartBody();

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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      'الطلب من ${cart.storeName ?? ''}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
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
              if (cart.completionSuggestions.isNotEmpty)
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
                      Text('🛒 ناقصك حاجة؟ كمّل طلبك!',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
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
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
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
                      IconButton(
                        tooltip: 'حذف الصنف من السلة',
                        onPressed: () => cart.removeItem(e.key),
                        icon: const Icon(Icons.delete_outline_rounded),
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
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: kLine)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SummaryRow(
                  label: 'المجموع',
                  value: formatPrice(cart.subtotal),
                ),
                const SizedBox(height: 6),
                _SummaryRow(
                  label: 'رسوم التوصيل',
                  value: formatPrice(cart.fee),
                ),
                if (cart.serviceFee > 0) ...[
                  const SizedBox(height: 6),
                  _SummaryRow(
                    label: 'رسوم الخدمة',
                    value: formatPrice(cart.serviceFee),
                  ),
                ],
                const Divider(height: 20),
                _SummaryRow(
                  label: 'الإجمالي',
                  value: formatPrice(cart.total),
                  strong: true,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: cart.items.isEmpty ? null : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CheckoutPage()),
                    ),
                    child: Text(cart.items.isEmpty ? 'ضيف منتجًا أولًا' : 'كمّل الطلب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
        ? base?.copyWith(fontWeight: FontWeight.w800, fontSize: 18)
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
