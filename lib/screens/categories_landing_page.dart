import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../widgets/cached_net_image.dart';
import '../theme/brand.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'notifications_page.dart';
import 'quick_order_create_page.dart';
import 'store_directory_page.dart';

/// Photo by Vitaly Gariev on Unsplash (free Unsplash license).
/// https://unsplash.com/photos/a-woman-smiling-while-talking-on-a-cell-phone-3KgSopqBgYI
/// A customer talking on the phone, not a delivery courier or food stock photo.
const kEntryHeroPhoneImageUrl =
    'https://images.unsplash.com/photo-1758876201450-cf77ab8b95bc'
    '?auto=format&fit=crop&crop=faces&w=540&h=500&q=80';

/// A single signed-in landing experience for every role.
/// Other roles keep their own dashboard and permissions behind the "لوحتي" entry.
class CustomerEntry extends StatefulWidget {
  const CustomerEntry({
    super.key,
    this.dashboard,
    this.dashboardLabel,
    this.loadHeroPhoto = true,
  });

  final Widget? dashboard;
  final String? dashboardLabel;

  /// Set false in deterministic widget tests; production always loads the
  /// licensed portrait with the existing disk cache and an offline fallback.
  final bool loadHeroPhoto;

  @override
  State<CustomerEntry> createState() => _CustomerEntryState();
}

class _CustomerEntryState extends State<CustomerEntry> {
  bool _entered = false;

  void _enter([Widget? destination, int tab = 0]) {
    if (_entered) return;
    if (destination != null) {
      // Leaving a service must return to the entry cards, not skip them.
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
        colors: [Brand.palette.accent, Brand.palette.accentDeep],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          left: 0,
          bottom: 8,
          width: height < 200 ? 144 : 188,
          height: height < 200 ? 124 : 160,
          child: ClipRRect(
            key: const Key('entry-hero-phone-photo'),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(22),
              bottomRight: Radius.circular(12),
            ),
            child: widget.loadHeroPhoto
                ? CachedNetImage(
                    key: const Key('entry-hero-phone-network'),
                    url: kEntryHeroPhoneImageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 540,
                    errorWidget: _phonePhotoFallback(),
                  )
                : _phonePhotoFallback(),
          ),
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
        const Positioned(
          top: 7,
          left: 105,
          right: 105,
          height: 100,
          // Use the authentic bag-and-speed logo from the approved artwork.
          child: _EntryArtwork(Rect.fromLTWH(247, 156, 221, 173)),
        ),
        Positioned(
          top: height < 200 ? 100 : 111,
          right: 12,
          left: height < 200 ? 152 : 194,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('كل اللي بتحبه...', maxLines: 2,
                style: TextStyle(color: Colors.white,
                    fontSize: height < 200 ? 16 : 19,
                    height: 1.10, fontWeight: FontWeight.w900)),
              RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(fontFamily: 'Tajawal',
                    color: Colors.white, fontSize: height < 200 ? 15 : 18,
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

  Widget _phonePhotoFallback() => ColoredBox(
        color: Brand.palette.accentDeep,
        child: const Center(
          child: Icon(
            Icons.phone_in_talk_rounded,
            color: Colors.white,
            size: 46,
          ),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Art and copy touch directly: no white fade or spacer
                // masking the photographed half of the card.
                Expanded(
                  child: SizedBox.expand(
                    key: ValueKey<String>('entry-art-$title'),
                    child: _EntryArtwork(art),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 0, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Icon(icon, color: Brand.green, size: 23),
                        ),
                        const SizedBox(height: 2),
                        Text(title, maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Brand.ink,
                            fontSize: 18, height: 1.08, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(subtitle, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Brand.palette.muted,
                            fontSize: 11, height: 1.1, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Brand.palette.primaryLight, Brand.green,
                            ]),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [BoxShadow(
                              color: Brand.green.withValues(alpha: 0.22),
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
    // Keep the welcome cards readable on smaller Android screens.
    final compact = MediaQuery.sizeOf(context).height < 800;
    final heroHeight = compact ? 188.0 : 236.0;
    final cardHeight = compact ? 134.0 : 146.0;
    final cardGap = compact ? 9.0 : 14.0;
    return Scaffold(
      backgroundColor: Brand.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          children: [
            _hero(height: heroHeight),
            SizedBox(height: compact ? 9 : 16),
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
                _navButton(Icons.home_rounded, 'الرئيسية', () => _enter(), selected: true),
                if (isCustomer)
                  _navButton(Icons.receipt_long_outlined, 'طلباتي', () => _enter(null, 2))
                else
                  _navButton(Icons.notifications_none, 'الإشعارات', () => _enter(const NotificationsPage())),
                if (isCustomer)
                  _navButton(Icons.shopping_cart_outlined, 'السلة', () => _enter(null, 1))
                else
                  _navButton(Icons.dashboard_outlined, 'لوحتي', () => _enter()),
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
