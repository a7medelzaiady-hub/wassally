import 'package:flutter/material.dart';

import '../services/cart_book.dart';
import '../services/cart_model.dart';
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
  const MyCartsPage({super.key, CartBook? book}) : _book = book;

  CartBook get book => _book ?? carts;

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
          final all = <CartSnapshot>[
            if (!book.active.isEmpty) book.active.snapshot(),
            ...book.parked,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7E8),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE5B85C)),
                            ),
                            child: Text(
                              all.length == 1
                                  ? 'عندك سلة واحدة. راجعها وأكد طلبك.'
                                  : 'عندك ${all.length} سلال من ${all.length} محلات. كل سلة بتتطلب لوحدها وليها رسوم توصيل لوحدها. راجع كل سلة: أكدها أو عدّلها أو امسحها. السلال بتتحفظ على موبايلك 3 أيام.',
                              style: const TextStyle(height: 1.5),
                            ),
                          ),
                          for (final c in all)
                            _CartCard(
                              snap: c,
                              isActive: c.storeId != null && c.storeId == book.active.storeId,
                              book: book,
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('carts-shop-other'),
                            icon: const Icon(Icons.storefront),
                            label: const Text('التسوق من محل آخر'),
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
    final canAddMore = book.storeFor(_storeId) != null;
    return Container(
      key: Key('cart-card-$_storeId'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? kPrimary : kLine, width: isActive ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.storefront, color: kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snap.storeName ?? 'محل',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (isActive)
                Text('السلة الحالية', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            names.join('، '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: kMuted, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            '${snap.count} صنف • ${formatPrice(snap.subtotal)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: Key('cart-review-$_storeId'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('راجع وأكد الطلب'),
            onPressed: () => _review(context),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (canAddMore)
                Expanded(
                  child: OutlinedButton(
                    key: Key('cart-add-more-$_storeId'),
                    onPressed: () => _addMore(context),
                    child: const Text('إضافة منتجات من نفس المحل', textAlign: TextAlign.center),
                  ),
                ),
              if (canAddMore) const SizedBox(width: 8),
              TextButton.icon(
                key: Key('cart-delete-$_storeId'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_outline),
                label: const Text('امسح'),
                onPressed: () => _delete(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
