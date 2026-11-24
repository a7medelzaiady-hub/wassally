import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/brand.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'notifications_page.dart';
import 'quick_order_create_page.dart';
import 'store_directory_page.dart';

/// A single signed-in landing experience for every role.
/// Other roles keep their own dashboard and permissions behind the "لوحتي" entry.
class CustomerEntry extends StatefulWidget {
  const CustomerEntry({super.key, this.dashboard, this.dashboardLabel});

  final Widget? dashboard;
  final String? dashboardLabel;

  @override
  State<CustomerEntry> createState() => _CustomerEntryState();
}

class _CustomerEntryState extends State<CustomerEntry> {
  bool _entered = false;

  void _enter([Widget? destination, int tab = 0]) {
    if (_entered) return;
    if (destination != null) {
      // Keep the welcome page in the navigation stack: Back returns here.
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
      return;
    }
    shellTab.value = tab;
    setState(() => _entered = true);
  }

  Widget get _dashboard => widget.dashboard ?? const MainShell();

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF38156D), Color(0xFF24104F)],
        begin: Alignment.topRight, end: Alignment.bottomLeft,
      ),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.location_on_outlined, color: Colors.white, size: 23),
        const SizedBox(width: 5),
        const Expanded(child: Text('حدد عنوان التوصيل',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'الإشعارات', onPressed: () => _enter(const NotificationsPage()),
          icon: const Icon(Icons.notifications_none_rounded, color: Colors.white)),
        IconButton(tooltip: 'حسابي', onPressed: () => _enter(const AccountPage()),
          icon: const Icon(Icons.person_outline_rounded, color: Colors.white)),
      ]),
      const SizedBox(height: 2),
      const Text('وصّلي 🛍', style: TextStyle(
        color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
      const Text('Wasally', style: TextStyle(color: Colors.white70, fontSize: 12)),
    ]),
  );

  Widget _hero({double height = 236}) => Container(
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Brand.palette.primary, width: 1.5),
      gradient: const LinearGradient(
        colors: [Color(0xFF38156D), Color(0xFF24104F)],
      ),
    ),
    child: Row(textDirection: TextDirection.ltr, children: [
      Expanded(flex: 6, child: const _EntryArtwork(Rect.fromLTWH(12, 311, 310, 207))),
      Expanded(flex: 5, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('وصّلي...\\nلحد عندي', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: height < 190 ? 21 : 27,
              fontWeight: FontWeight.w900, height: 1.15)),
          SizedBox(height: height < 190 ? 5 : 12),
          FilledButton(
            onPressed: () => _enter(const QuickOrderCreatePage()),
            style: FilledButton.styleFrom(backgroundColor: Brand.palette.primary),
            child: const Text('اطلب الآن'),
          ),
        ]),
      )),
    ]),
  );

  Widget _serviceCard({
    required String title,
    required String subtitle,
    required String action,
    required IconData icon,
    required Rect art,
    required VoidCallback onTap,
    double height = 146,
    double gap = 14,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Material(
        elevation: 5,
        shadowColor: Brand.palette.ink.withValues(alpha: 0.15),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: Brand.palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _EntryArtwork(art),
                      const Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.white, Colors.transparent],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(12, height < 130 ? 4 : 8, 2, height < 130 ? 4 : 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Icon(icon, color: Brand.palette.primary, size: height < 130 ? 18 : 23),
                        ),
                        SizedBox(height: height < 130 ? 0 : 2),
                        Text(title, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Brand.ink,
                            fontSize: height < 130 ? 15 : 18, height: 1.08, fontWeight: FontWeight.w900)),
                        SizedBox(height: height < 130 ? 1 : 3),
                        Text(subtitle, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Brand.palette.muted,
                            fontSize: height < 130 ? 10 : 11, height: 1.1, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          height: height < 130 ? 27 : 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Brand.palette.primaryLight, Brand.palette.primary,
                            ]),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [BoxShadow(
                              color: Brand.palette.primary.withValues(alpha: 0.22),
                              blurRadius: 7, offset: const Offset(0, 3),
                            )],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(action, maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white, fontSize: 13,
                                    fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 19),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? Brand.green : Brand.ink,
                size: selected ? 31 : 25),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected ? Brand.green : Brand.ink,
                  fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_entered) return _dashboard;

    final isCustomer = widget.dashboard == null;
    final availableHeight = MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).vertical - MediaQuery.viewPaddingOf(context).bottom - 92;
    final compact = availableHeight < 800;
    final heroHeight = compact ? 158.0 : 236.0;
    final cardHeight = compact ? 112.0 : 146.0;
    final cardGap = compact ? 7.0 : 14.0;
    return Scaffold(
      backgroundColor: Brand.bg,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(child: ListView(
          // Keep accessibility scrolling available on small screens while
          // the compact layout fits all three service cards on standard phones.
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(12, compact ? 6 : 12, 12, compact ? 6 : 14),
          children: [
            _hero(height: heroHeight),
            SizedBox(height: compact ? 8 : 16),
            // Referral code entry is shown exclusively in RoleGate's secure
            // first-registration dialog. Returning users see no fake field.
            _serviceCard(
              title: 'خدمة وصّلي ع السريع',
              subtitle: 'سجل اللى عاوزه ونوصلهولك بسرعة',
              action: 'اطلب الآن',
              icon: Icons.bolt_rounded,
              art: const Rect.fromLTWH(20, 541, 303, 195),
              height: cardHeight,
              gap: cardGap,
              onTap: () => _enter(const QuickOrderCreatePage()),
            ),
            _serviceCard(
              title: 'تصفح العروض',
              subtitle: 'أقوى الخصومات والعروض الحصرية',
              action: 'شاهد العروض',
              icon: Icons.local_offer_rounded,
              art: const Rect.fromLTWH(22, 796, 295, 173),
              height: cardHeight,
              gap: cardGap,
              onTap: () => _enter(const HomePage(offersOnly: true)),
            ),
            _serviceCard(
              title: 'تصفح المحلات',
              subtitle: 'اكتشف جميع المحلات والأصناف',
              action: 'استعرض المحلات',
              icon: Icons.storefront_rounded,
              art: const Rect.fromLTWH(22, 1026, 305, 174),
              height: cardHeight,
              gap: cardGap,
              onTap: () => _enter(const StoreDirectoryPage()),
            ),
            if (!isCustomer) ...[
              const SizedBox(height: 2),
              FilledButton.icon(
                onPressed: () => _enter(),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: Text(widget.dashboardLabel ?? 'افتح لوحتي'),
              ),
            ],
          ],
        )),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 10),
          child: Material(
            color: Colors.white,
            elevation: 5,
            shadowColor: Brand.ink.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(30),
            child: Row(
              children: [
                _navButton(Icons.person_outline, 'حسابي', () => _enter(const AccountPage())),
                _navButton(Icons.favorite_border_rounded, 'المفضلة', () => _enter()),
                Expanded(
                  child: InkWell(
                    onTap: () => isCustomer ? _enter(null, 1) : _enter(),
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            Brand.palette.primaryLight, Brand.palette.primary,
                          ]),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(isCustomer ? Icons.shopping_cart_outlined : Icons.dashboard_outlined,
                            color: Colors.white, size: 21),
                          Text(isCustomer ? 'السلة' : 'لوحتي',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                        ]),
                      ),
                    ),
                  ),
                ),
                _navButton(Icons.home_outlined, 'الرئيسية', () => _enter(), selected: true),
                _navButton(Icons.grid_view_rounded, 'الأقسام', () => _enter(const StoreDirectoryPage())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryArtwork extends StatelessWidget {
  const _EntryArtwork(this.crop);
  final Rect crop;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: crop.width,
        height: crop.height,
        child: Stack(
          children: [
            Positioned(
              left: -crop.left,
              top: -crop.top,
              width: 691,
              height: 1536,
              child: Image.asset(
                'assets/images/customer_entry_reference.jpg',
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
