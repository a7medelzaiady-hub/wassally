import 'package:flutter/material.dart';

import '../services/cart_book.dart';
import '../services/cart_model.dart';
import '../services/navigation.dart';
import '../services/order_gateway.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import 'cart_page.dart';
import 'store_directory_page.dart';
import 'store_page.dart';

/// «سلّاتي»: كل سلال العميل (سلة لكل محل) في صفحة واحدة.
/// العميل يراجع كل سلة ويأكدها أو يعدّلها أو يمسحها، وكل سلة بتتطلب كطلب مستقل.
class MyCartsPage extends StatelessWidget {
  final CartBook? _book;

  /// تجميع الطلبات بيشتغل مع بوابة الطلبات بس (السيرفر هو اللي بيتحقق من الرقم).
  final bool? _allowGrouping;
  const MyCartsPage({super.key, CartBook? book, bool? allowGrouping})
      : _book = book,
        _allowGrouping = allowGrouping;

  CartBook get book => _book ?? carts;
  bool get allowGrouping => _allowGrouping ?? OrderGateway.serverOrdersEnabled;

  @override
  Widget build(BuildContext context) {
    // العميل شاف سلاله الراجعة من آخر مرة: التنبيه يختفي.
    if (book.restoredCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => book.markRestoredSeen());
    }
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([book, book.active]),
        builder: (context, _) {
          final list = <CartSnapshot>[
            if (!book.active.isEmpty) book.active.snapshot(),
            ...book.parked,
          ];
          // السلال اللي لسه ما اتبعتتش الأول، واللي اتبعت طلبها في الآخر (بنفس ترتيبها).
          final all = <CartSnapshot>[
            ...list.where((c) => c.submittedOrderId == null),
            ...list.where((c) => c.submittedOrderId != null),
          ];
          return Column(
            children: [
              const InnerHeader(title: 'سلّاتي'),
              Expanded(
                child: all.isEmpty
                    ? EmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: 'مفيش سلال',
                        message: 'ضيف منتجات من أي محل وهتظهر هنا.',
                        actionLabel: 'تصفّح المحلات',
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StoreDirectoryPage()),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                        children: [
                          _CartsNote(count: all.length),
                          if (allowGrouping && (all.length >= 2 || book.groupingOn))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: kLine),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SwitchListTile(
                                key: const Key('carts-group-switch'),
                                dense: true,
                                contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 2, 8, 2),
                                value: book.groupingOn,
                                onChanged: (v) => book.setGrouping(v),
                                secondary: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: kAccent.withValues(alpha: 0.10),
                                  child: Icon(Icons.route_rounded, size: 19, color: kAccent),
                                ),
                                title: const Text(
                                  'اجمع الطلبات في رحلة واحدة',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  book.groupingOn
                                      ? 'مفعّل: مندوب واحد هيجيب السلال مع بعض'
                                      : 'اختياري: مندوب واحد يجيب السلال مع بعض',
                                  style: TextStyle(fontSize: 12, color: kMuted),
                                ),
                              ),
                              ),
                            ),
                          for (final c in all)
                            _CartCard(
                              snap: c,
                              isActive: c.storeId != null && c.storeId == book.active.storeId,
                              book: book,
                            ),
                          TextButton.icon(
                            key: const Key('carts-shop-other'),
                            icon: const Icon(Icons.add_business_outlined, size: 20),
                            label: const Text('تسوّق من محل تاني'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const StoreDirectoryPage()),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartCard extends StatelessWidget {
  final CartSnapshot snap;
  final bool isActive;
  final CartBook book;
  const _CartCard({required this.snap, required this.isActive, required this.book});

  String get _storeId => snap.storeId ?? '';

  Future<void> _review(BuildContext context) async {
    book.switchTo(_storeId);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Scaffold(body: CartPage(showBackButton: true))),
    );
  }

  Future<void> _addMore(BuildContext context) async {
    final store = book.storeFor(_storeId);
    if (store == null) return;
    book.switchTo(_storeId);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StorePage(store: store)));
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'مسح السلة',
      message: 'هتتمسح سلة ${snap.storeName ?? 'المحل'} بكل اللي فيها. متأكد؟',
      confirmLabel: 'امسح',
      destructive: true,
    );
    if (!ok) return;
    if (isActive) {
      book.active.clear();
    } else {
      book.removeParked(_storeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final e in snap.items.entries) '${e.key.name} × ${e.value}',
      if (snap.specialRequest != null) 'طلب خاص',
    ];
    // عدد الأصناف = الأصناف المختلفة، مش مجموع الكميات (بطاطس × 5 = صنف واحد).
    final kinds = snap.items.length + (snap.specialRequest != null ? 1 : 0);
    final canAddMore = book.storeFor(_storeId) != null;
    final submitted = snap.submittedOrderId != null;
    return Container(
      key: Key('cart-card-$_storeId'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive && !submitted ? kPrimary.withValues(alpha: 0.55) : kLine),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: kAccent.withValues(alpha: 0.10),
                child: Icon(Icons.storefront_rounded, size: 20, color: kAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snap.storeName ?? 'محل',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names.join('، '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: kMuted),
                    ),
                  ],
                ),
              ),
              if (submitted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kSuccess.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 13, color: kSuccess),
                      SizedBox(width: 3),
                      Text(
                        'اتبعت',
                        style: TextStyle(fontSize: 11, color: kSuccess, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                )
              else if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'السلة الحالية',
                    style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Text(
                formatPrice(snap.subtotal),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snap.fee > 0
                      ? '$kinds صنف • توصيل ${formatPrice(snap.fee)}'
                      : '$kinds صنف',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: submitted
                      ? OutlinedButton.icon(
                          key: Key('cart-review-$_storeId'),
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: const Text('تابع في «طلباتي»'),
                          onPressed: () => openCustomerTab(context, 2),
                        )
                      : FilledButton(
                          key: Key('cart-review-$_storeId'),
                          onPressed: () => _review(context),
                          child: const Text('أكمل الطلب'),
                        ),
                ),
              ),
              if (canAddMore && !submitted) ...[
                const SizedBox(width: 8),
                _SquareIcon(
                  key: Key('cart-add-more-$_storeId'),
                  tooltip: 'إضافة منتجات من نفس المحل',
                  icon: Icons.add_shopping_cart_rounded,
                  color: kAccent,
                  onPressed: () => _addMore(context),
                ),
              ],
              const SizedBox(width: 8),
              _SquareIcon(
                key: Key('cart-delete-$_storeId'),
                tooltip: 'امسح السلة',
                icon: Icons.delete_outline_rounded,
                color: kDanger,
                onPressed: () => _delete(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _SquareIcon({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 21),
        style: IconButton.styleFrom(
          side: BorderSide(color: kLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// سطر تعريفي قصير فوق السلال (بدل فقرة الشرح الطويلة).
class _CartsNote extends StatelessWidget {
  final int count;
  const _CartsNote({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: kMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == 1
                  ? 'سلتك محفوظة على موبايلك لحد ما تفرّغها بنفسك.'
                  : 'عندك $count سلال، كل سلة بتتطلب لوحدها برسوم توصيلها. محفوظة على موبايلك لحد ما تفرّغها بنفسك.',
              style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
