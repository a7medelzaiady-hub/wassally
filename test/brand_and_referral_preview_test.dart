import 'package:city_store/screens/admin_navigation_page.dart';
import 'package:city_store/screens/login_screen.dart';
import 'package:city_store/services/order_gateway.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/theme/brand.dart';
import 'package:city_store/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('أجهزة التحديث تستخدم هوية وصّلي المعتمدة فقط', () async {
    SharedPreferences.setMockInitialValues({'app_palette': 'green'});
    await ThemeController.instance.load();

    expect(Brand.palette.id, 'wasally');
    expect(AppPalette.all.map((palette) => palette.id), ['wasally']);
    await ThemeController.instance.select(AppPalette.green);
    expect(Brand.palette.id, 'wasally');
    expect(buildAppTheme().colorScheme.primary, AppPalette.wasally.primary);
    expect(buildAppTheme().appBarTheme.backgroundColor, AppPalette.wasally.ink);
  });

  testWidgets('شاشة جوجل لا تعرض إدخال كود الإحالة',
      (tester) async {
    tester.view.physicalSize = const Size(430, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const LoginScreen(),
    ));
    await tester.pump();

    expect(
      find.text('عندي كود إحالة'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('لوحة الإدارة تعرض إدارة المكافآت في بناء الحملة',
      (tester) async {
    tester.view.physicalSize = const Size(430, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const AdminNavigationPage(),
    ));
    await tester.pump();

    expect(
      find.text('إدارة الدعوات'),
      OrderGateway.referralCampaignEnabled ? findsOneWidget : findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
