import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/brand.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'quick_order_create_page.dart';
import 'store_directory_page.dart';

/// The signed-in customer's starting page.
class CustomerEntry extends StatefulWidget {
  const CustomerEntry({super.key});

  @override
  State<CustomerEntry> createState() => _CustomerEntryState();
}

class _CustomerEntryState extends State<CustomerEntry> {
  bool _entered = false;

  void _enter([Widget? destination]) {
    if (_entered) return;
    shellTab.value = 0;
    setState(() => _entered = true);
    if (destination != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entered) return const MainShell();

    return Scaffold(
      backgroundColor: Brand.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          children: [
            Material(
              color: Brand.ink,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'وصّلي',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'كل اللي بتحبه لحد باب بيتك',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 126,
                    height: 136,
                    child: _EntryArtwork(Rect.fromLTWH(12, 311, 310, 207)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _EntryCard(
              title: 'طلباتك على السريع',
              action: 'اطلب الآن',
              icon: Icons.bolt_rounded,
              art: const Rect.fromLTWH(20, 541, 303, 195),
              onTap: () => _enter(const QuickOrderCreatePage()),
            ),
            _EntryCard(
              title: 'تصفح العروض',
              action: 'شاهد العروض',
              icon: Icons.local_offer_outlined,
              art: const Rect.fromLTWH(22, 796, 295, 173),
              onTap: () => _enter(const HomePage(offersOnly: true)),
            ),
            _EntryCard(
              title: 'تصفح المحلات',
              action: 'استعرض المحلات',
              icon: Icons.storefront_outlined,
              art: const Rect.fromLTWH(22, 1026, 305, 174),
              onTap: () => _enter(const StoreDirectoryPage()),
            ),
            TextButton.icon(
              onPressed: () => _enter(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('الرئيسية'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.title,
    required this.action,
    required this.icon,
    required this.art,
    required this.onTap,
  });

  final String title;
  final String action;
  final IconData icon;
  final Rect art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Brand.palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Brand.green, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          color: Brand.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        action,
                        style: TextStyle(
                          color: Brand.palette.primaryDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 124, height: 108, child: _EntryArtwork(art)),
            ],
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
