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

  Widget _topButton(IconData icon, String label, Widget page) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: label,
        icon: Icon(icon, color: Brand.palette.ink, size: 26),
        onPressed: () => _enter(page),
      ),
    );
  }

  Widget _hero({double height = 236}) => Container(
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [const Color(0xFF6530A5), const Color(0xFF38156D)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          left: -4,
          bottom: -4,
          width: 190,
          height: 146,
          child: const _EntryArtwork(Rect.fromLTWH(12, 311, 310, 207)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 8,
          child: ColoredBox(color: Brand.palette.primary),
        ),
        Positioned(
          top: 10,
          left: 12,
          child: _topButton(Icons.notifications_none_rounded, 'الإشعارات', const NotificationsPage()),
        ),
        Positioned(
          top: 10,
          right: 12,
          child: _topButton(Icons.person_outline_rounded, 'حسابي', const AccountPage()),
        ),
        Positioned(
          top: 7,
          left: 105,
          right: 105,
          height: height < 190 ? 80 : 100,
          // Use the authentic bag-and-speed logo from the approved artwork.
          child: _EntryArtwork(Rect.fromLTWH(247, 156, 221, 173)),
        ),
        Positioned(
          top: height < 190 ? 88 : 111,
          right: 18,
          left: height < 190 ? 132 : 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('كل اللي بتحبه...', maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white,
                    fontSize: height < 190 ? 15 : 19,
                    fontWeight: FontWeight.w900)),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontFamily: 'Tajawal',
                    color: Colors.white, fontSize: height < 190 ? 14 : 18,
                    fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(text: 'يوصلك ', style: TextStyle(color: Brand.palette.primaryLight)),
                    const TextSpan(text: 'لحد باب بيتك'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
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
        child: ListView(
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
        ),
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
                if (isCustomer) ...[
                  _navButton(Icons.receipt_long_outlined, 'طلباتي', () => _enter(null, 2)),
                  _navButton(Icons.home_rounded, 'الرئيسية', () => _enter(), selected: true),
                  _navButton(Icons.shopping_cart_outlined, 'السلة', () => _enter(null, 1)),
                ] else ...[
                  _navButton(Icons.dashboard_outlined, 'لوحتي', () => _enter()),
                  _navButton(Icons.notifications_none, 'الإشعارات', () => _enter(const NotificationsPage())),
                  _navButton(Icons.home_rounded, 'الرئيسية', () => _enter(), selected: true),
                ],
                _navButton(Icons.person_outline, 'حسابي', () => _enter(const AccountPage())),
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
