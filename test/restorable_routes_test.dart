// #339: أي صفحة بتتستعاد من اسمها بس، وبصلاحيات الحساب الحالية.
import 'package:city_store/models/app_role.dart';
import 'package:city_store/screens/admin_inbox_page.dart';
import 'package:city_store/screens/admin_tools_page.dart';
import 'package:city_store/screens/notifications_page.dart';
import 'package:city_store/screens/order_details_page.dart';
import 'package:city_store/screens/quick_courier_order_page.dart';
import 'package:city_store/screens/quick_courier_orders_page.dart';
import 'package:city_store/screens/quick_customer_orders_page.dart';
import 'package:city_store/screens/quick_order_customer_detail_page.dart';
import 'package:city_store/screens/restorable_routes.dart';
import 'package:city_store/screens/store_directory_page.dart';
import 'package:city_store/services/navigation.dart';
import 'package:city_store/services/resume_route_observer.dart';
import 'package:city_store/services/resume_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const customer = {AppRole.customer};

  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
    RestorableRoutes.debugPageFor = null;
  });
  tearDown(() => RestorableRoutes.debugPageFor = null);

  group('pageFor', () {
    test('customer pages are rebuilt from their ids', () {
      final order = RestorableRoutes.pageFor('order:o1', held: customer);
      expect(order, isA<OrderDetailsPage>());
      expect((order! as OrderDetailsPage).orderId, 'o1');

      final quick = RestorableRoutes.pageFor('quick-order:q1', held: customer);
      expect(quick, isA<QuickOrderCustomerDetailPage>());
      expect((quick! as QuickOrderCustomerDetailPage).orderId, 'q1');

      expect(RestorableRoutes.pageFor('quick-orders', held: customer), isA<QuickCustomerOrdersPage>());
      expect(RestorableRoutes.pageFor('notifications', held: customer), isA<NotificationsPage>());
      expect(RestorableRoutes.pageFor('stores', held: customer), isA<StoreDirectoryPage>());
    });

    test('checkout is not restored when the cart is empty', () {
      expect(RestorableRoutes.pageFor('checkout', held: customer), isNull);
    });

    test('staff pages need the matching role (no privilege gained by restoring)', () {
      for (final name in ['courier-quick:c1', 'courier-quick-orders', 'admin-inbox', 'admin-tools']) {
        expect(RestorableRoutes.pageFor(name, held: customer), isNull, reason: name);
      }
      expect(RestorableRoutes.pageFor('admin-inbox', held: {AppRole.courier}), isNull);
      expect(RestorableRoutes.pageFor('courier-quick:c1', held: {AppRole.admin}), isNull);

      expect(RestorableRoutes.pageFor('admin-inbox', held: {AppRole.admin}), isA<AdminInboxPage>());
      expect(RestorableRoutes.pageFor('admin-tools', held: {AppRole.admin}), isA<AdminToolsPage>());
      expect(RestorableRoutes.pageFor('courier-quick-orders', held: {AppRole.courier}), isA<QuickCourierOrdersPage>());
      final courier = RestorableRoutes.pageFor('courier-quick:c1', held: {AppRole.courier});
      expect(courier, isA<QuickCourierOrderPage>());
      expect((courier! as QuickCourierOrderPage).orderId, 'c1');
    });

    test('unknown, malformed or personal-data names are ignored', () {
      for (final name in ['', 'evil:thing', 'order', 'order:أحمد محمد', 'order:01012345678', '/s/abc', 'service:quick']) {
        expect(RestorableRoutes.pageFor(name, held: {AppRole.admin, AppRole.courier}), isNull, reason: name);
      }
    });
  });

  group('restore', () {
    Future<NavigatorState> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [ResumeRouteObserver(uidOf: () => 'u1')],
        home: const Scaffold(body: Text('home')),
      ));
      return rootNavigatorKey.currentState!;
    }

    testWidgets('opens saved pages in order and skips ones the account cannot open', (tester) async {
      RestorableRoutes.debugPageFor = (name, {required held}) =>
          name == 'admin-inbox' && !held.contains(AppRole.admin) ? null : Scaffold(body: Text('restored $name'));
      final nav = await pump(tester);

      final opened = RestorableRoutes.restore(
        nav,
        ['notifications', 'admin-inbox', 'order:o1'],
        held: customer,
      );
      await tester.pumpAndSettle();

      expect(opened, 2);
      expect(find.text('restored order:o1'), findsOneWidget, reason: 'آخر صفحة فوق');
      expect(ResumeSession.stack, ['notifications', 'order:o1']);

      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('restored notifications'), findsOneWidget);
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(ResumeSession.stack, isEmpty);
    });

    testWidgets('restoring an empty list does nothing', (tester) async {
      final nav = await pump(tester);
      expect(RestorableRoutes.restore(nav, const [], held: customer), 0);
      expect(find.text('home'), findsOneWidget);
    });
  });
}
