import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('صفحة وصّلي تظهر كروت الخدمات بعد دخول العميل بدون overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(),
    ));
    await tester.pump();

    // The approved entry hero uses royal purple, not the legacy navy palette.
    final purpleHero = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      final gradient = decoration.gradient;
      return gradient is LinearGradient &&
          gradient.colors.contains(const Color(0xFF38156D)) &&
          gradient.colors.contains(const Color(0xFF24104F));
    });
    expect(purpleHero, findsWidgets);
    expect(find.text('وصّلي...\\nلحد عندي'), findsOneWidget);
    // Approved five-slot navigation with the cart in the middle.
    expect(find.text('السلة'), findsOneWidget);
    expect(find.text('المفضلة'), findsOneWidget);
    expect(find.text('الأقسام'), findsOneWidget);
    final cartX = tester.getCenter(find.text('السلة')).dx;
    expect(cartX, greaterThan(125));
    expect(cartX, lessThan(265));

    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('تصفح العروض'), findsOneWidget);
    expect(find.text('تصفح المحلات'), findsOneWidget);
    // All three entry actions must fit in the initial 390x844 viewport.
    final stores = find.text('تصفح المحلات');
    expect(stores.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(stores).dy, lessThan(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('الصفحة لا تعرض حقل دعوة مضلل للحسابات القديمة',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(),
    ));
    await tester.pump();
    expect(find.text('كود الدعوة متاح عند إنشاء حساب جديد فقط'),
        findsNothing);
    expect(find.text('اكتب هنا كود الدعوة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('التصميم المضغوط يظهر كل الخدمات على شاشة قصيرة',
      (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(),
    ));
    await tester.pump();
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('تصفح العروض'), findsOneWidget);
    expect(find.text('تصفح المحلات'), findsOneWidget);
    expect(find.text('تصفح المحلات').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('صاحب المحل يحصل على نفس صفحة الترحيب مع مدخل لوحته',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(
        dashboard: SizedBox.shrink(),
        dashboardLabel: 'لوحة المحل',
      ),
    ));
    await tester.pump();
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pump();
    expect(find.text('لوحة المحل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
