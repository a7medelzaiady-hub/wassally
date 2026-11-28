import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/store.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync.dart';
import '../theme/app_theme.dart';
import '../utils/share_links.dart';
import '../widgets/empty_state.dart';
import 'store_page.dart';
import '../services/resume_session.dart';

/// رابط مشاركة المحل (https://<worker>/s/<id> أو wasally://open/s/<id>) بيوصل هنا.
///
/// المحل بيتجاب من قايمة المحلات النشطة اللي التطبيق بيقراها أصلًا (الكاش/الفهرس)،
/// فغالبًا من غير قراءة زيادة. لو المستخدم مش مسجل دخول، الرابط بيتحفظ ويتفتح
/// تلقائيًا بعد تسجيل الدخول.
class StoreLinkPage extends StatefulWidget {
  final String storeId;

  /// للاختبارات بس.
  final Future<Store?> Function(String storeId)? loader;
  final bool Function()? isSignedIn;

  const StoreLinkPage({super.key, required this.storeId, this.loader, this.isSignedIn});

  /// للـMaterialApp.onGenerateRoute: «/s/<id>» → الصفحة دي، وأي مسار تاني → null.
  static Route<void>? routeFor(RouteSettings settings) {
    final name = settings.name ?? '';
    final path = Uri.tryParse(name)?.path ?? name;
    if (!path.startsWith('/s/')) return null;
    // #339: الرابط اللي فتح التطبيق له الأولوية: ما نستعيدش صفحات قديمة فوقه.
    ResumeSession.suppressRestore();
    // رابط /s/ برقم غلط: نفس الصفحة بتقول «المحل مش متاح» بدل خطأ.
    final id = ShareLinks.storeIdFromRoute(name) ?? '';
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => StoreLinkPage(storeId: id),
    );
  }

  /// أي رابط تاني للتطبيق (مسار مش معروف): بيتقفل لوحده من غير ما يبوّظ الشاشة.
  static Route<void> dismissRoute(RouteSettings settings) => PageRouteBuilder<void>(
        settings: settings,
        opaque: false,
        pageBuilder: (context, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        },
      );

  /// رابط اتفتح قبل تسجيل الدخول: بيتفتح بعد الدخول (من الشاشة الرئيسية).
  static String? pendingStoreId;

  /// بيفتح المحل المحفوظ (لو فيه) مرة واحدة.
  static void openPending(BuildContext context) {
    final id = pendingStoreId;
    if (id == null || FirebaseAuth.instance.currentUser == null) return;
    pendingStoreId = null;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreLinkPage(storeId: id)));
  }

  /// المحل النشط برقمه (من كاش الكتالوج، زي روابط المشاركة).
  static Future<Store?> loadActiveStore(String storeId) async {
    if (storeId.isEmpty) return null;
    final docs = await CatalogReader.activeStores(
      () => CatalogService.get(
        FirebaseFirestore.instance.collection('stores').where('active', isEqualTo: true),
        'stores',
      ),
    );
    for (final d in docs) {
      if (d.id != storeId) continue;
      final store = Store.fromMap(d.id, d.data());
      return store.active ? store : null;
    }
    return null;
  }

  @override
  State<StoreLinkPage> createState() => _StoreLinkPageState();
}

class _StoreLinkPageState extends State<StoreLinkPage> {
  late final bool _signedIn =
      widget.isSignedIn?.call() ?? FirebaseAuth.instance.currentUser != null;
  Future<Store?>? _future;

  @override
  void initState() {
    super.initState();
    if (!_signedIn) {
      StoreLinkPage.pendingStoreId = widget.storeId;
      ResumeSession.suppressRestore();
    } else {
      _future = (widget.loader ?? StoreLinkPage.loadActiveStore)(widget.storeId);
      _future!.then((store) {
        if (!mounted || store == null) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => StorePage(store: store)),
        );
      }, onError: (_) {});
    }
  }

  void _retry() => setState(() {
        _future = (widget.loader ?? StoreLinkPage.loadActiveStore)(widget.storeId)
          ..then((store) {
            if (!mounted || store == null) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => StorePage(store: store)),
            );
          }, onError: (_) {});
      });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!_signedIn) {
      body = EmptyState(
        key: const Key('store-link-sign-in'),
        icon: Icons.storefront_outlined,
        title: 'سجّل دخولك الأول',
        message: 'هنفتحلك المحل على طول بعد تسجيل الدخول.',
        actionLabel: 'تسجيل الدخول',
        onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
      );
    } else {
      body = FutureBuilder<Store?>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off,
              title: 'تعذر فتح المحل',
              message: 'تأكد من النت وحاول تاني.',
              actionLabel: 'إعادة المحاولة',
              onAction: _retry,
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: kPrimary));
          }
          if (snap.data == null) {
            return EmptyState(
              key: const Key('store-link-missing'),
              icon: Icons.store_mall_directory_outlined,
              title: 'المحل ده مش متاح دلوقتي',
              message: 'ممكن يكون مقفول أو اتشال من وصّلي. شوف باقي المحلات.',
              actionLabel: 'المحلات',
              onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
            );
          }
          return Center(child: CircularProgressIndicator(color: kPrimary));
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('وصّلي')),
      body: body,
    );
  }
}
