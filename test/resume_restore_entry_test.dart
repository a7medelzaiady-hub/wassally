// #339: CustomerEntry بيرجّع الصفحات المفتوحة بعد قفل أندرويد للتطبيق، وبأمان.
import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/screens/restorable_routes.dart';
import 'package:city_store/screens/store_link_page.dart';
import 'package:city_store/services/navigation.dart';
import 'package:city_store/services/resume_route_observer.dart';
import 'package:city_store/services/resume_session.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 11, 28, 12);

/// تجهيز حالة محفوظة من تشغيل سابق للحساب [savedUid]، ثم «قفل العملية» وفتح التطبيق بعد [after].
Future<void> _previousRun(
  WidgetTester tester, {
  String savedUid = 'staff1',
  String? location = 'dashboard',
  List<String> stack = const [],
  Duration after = const Duration(minutes: 2),
}) async {
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    ResumeSession.reset();
    if (location != null) ResumeSession.setLocation(savedUid, location);
    for (final key in stack) {
      ResumeSession.trackPush(savedUid, key);
    }
    await ResumeSession.markBackground(now: _t0);
    ResumeSession.reset();
    await ResumeSession.load(now: _t0.add(after));
  });
}

Future<void> _launchStaff(WidgetTester tester, {String uid = 'staff1'}) async {
  CustomerEntry.debugUidOf = () => uid;
  RestorableRoutes.debugPageFor = (name, {required held}) => Scaffold(body: Text('restored $name'));
  addTearDown(() {
    CustomerEntry.debugUidOf = null;
    RestorableRoutes.debugPageFor = null;
  });
  // شجرة جديدة تمامًا (زي تشغيل جديد للتطبيق)، مش تحديث لشجرة قديمة.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    navigatorKey: rootNavigatorKey,
    navigatorObservers: [ResumeRouteObserver(uidOf: () => uid)],
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const CustomerEntry(dashboard: Text('dash'), dashboardLabel: 'لوحة'),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('same account: dashboard comes back with its pages on top, in order', (tester) async {
    await _previousRun(tester, stack: ['order:o1', 'notifications']);
    await _launchStaff(tester);

    expect(find.text('restored notifications'), findsOneWidget, reason: 'آخر صفحة كانت مفتوحة');
    expect(ResumeSession.stack, ['order:o1', 'notifications']);

    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('restored order:o1'), findsOneWidget);

    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('dash'), findsOneWidget);
    expect(ResumeSession.stack, isEmpty);
  });

  testWidgets('another account gets nothing from the previous account', (tester) async {
    await _previousRun(tester, savedUid: 'staff1', stack: ['order:o1']);
    await _launchStaff(tester, uid: 'staff2');

    expect(find.textContaining('restored'), findsNothing);
    expect(find.text('dash'), findsNothing, reason: 'مفيش location لحساب staff2: صفحة الخدمات');
  });

  testWidgets('a launch after the 30 minute window is a fresh start', (tester) async {
    await _previousRun(tester, stack: ['order:o1'], after: ResumeSession.window);
    await _launchStaff(tester);
    expect(find.textContaining('restored'), findsNothing);
  });

  testWidgets('a store deep link wins over the saved pages', (tester) async {
    await _previousRun(tester, stack: ['order:o1']);
    StoreLinkPage.routeFor(const RouteSettings(name: '/s/abc'));
    await _launchStaff(tester);
    expect(find.textContaining('restored'), findsNothing);
  });

  testWidgets('a page the user closed leaves the saved stack (so it is not restored next launch)', (tester) async {
    await _previousRun(tester, stack: ['order:o1', 'notifications']);
    await _launchStaff(tester);
    expect(ResumeSession.stack, ['order:o1', 'notifications']);

    rootNavigatorKey.currentState!.pop(); // قفل الإشعارات
    await tester.pumpAndSettle();

    // نفس الحالة الحية هي اللي بتتحفظ للتشغيل الجاي (الحفظ نفسه متغطي في resume_stack_test).
    expect(ResumeSession.stack, ['order:o1']);
    expect(ResumeSession.current, 'dashboard');
  });

  testWidgets('pages with an empty stack and no location leave the entry untouched', (tester) async {
    await _previousRun(tester, location: null);
    await _launchStaff(tester);
    expect(find.textContaining('restored'), findsNothing);
  });
}
