import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/services/navigation.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpEntry(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Widget entry = const CustomerEntry(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: entry,
  ));
  await tester.pump();
}

void main() {
  testWidgets('صفحة ما بعد الدخول: هيدر وبانر وثلاثة كروت بدون overflow',
      (tester) async {
    await _pumpEntry(tester);

    expect(find.byKey(const Key('entry-location')), findsOneWidget);
    expect(find.byKey(const Key('entry-search')), findsOneWidget);
    expect(find.byKey(const Key('entry-banner')), findsOneWidget);
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('تصفح العروض'), findsOneWidget);
    expect(find.text('تصفح المحلات'), findsOneWidget);
    expect(customerShellAvailable.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('صور الخدمات تملأ نصف الكارت على شاشة صغيرة وبخط مكبّر',
      (tester) async {
    for (final scale in [1.0, 1.3]) {
      await _pumpEntry(tester, size: const Size(320, 640), textScale: scale);
      for (final label in [
        'خدمة وصّلي ع السريع',
        'تصفح العروض',
        'تصفح المحلات',
      ]) {
        final art = find.byKey(ValueKey<String>('entry-art-$label'));
        await tester.scrollUntilVisible(art, 120,
            scrollable: find.descendant(
              of: find.byKey(const Key('entry-list')),
              matching: find.byType(Scrollable),
            ));
        await tester.pump();
        expect(tester.getSize(art).width, greaterThan(120));
      }
      expect(tester.takeException(), isNull, reason: 'textScale $scale');
    }
  });

  testWidgets('ترتيب الشريط المعتمد في RTL: السلة يمين الرئيسية',
      (tester) async {
    await _pumpEntry(tester);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('السلة'), findsOneWidget);
    expect(tester.getCenter(find.text('السلة')).dx,
        greaterThan(tester.getCenter(find.text('طلباتي')).dx));
    expect(tester.getCenter(find.text('طلباتي')).dx,
        greaterThan(tester.getCenter(find.text('الرئيسية')).dx));
    expect(tester.getCenter(find.text('الرئيسية')).dx,
        greaterThan(tester.getCenter(find.text('حسابي')).dx));
  });

  testWidgets('الهيدر ثابت: زر الإشعارات يستجيب أثناء ارتداد القائمة',
      (tester) async {
    await _pumpEntry(tester, size: const Size(360, 640));
    final bellBefore = tester.getTopLeft(find.byKey(const ValueKey('entry-الإشعارات')));
    await tester.fling(find.byKey(const Key('entry-list')), const Offset(0, -500), 2500);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopLeft(find.byKey(const ValueKey('entry-الإشعارات'))), bellBefore);
    await tester.pumpAndSettle();
  });

  testWidgets('على موبايل عادي البانر والكروت الثلاثة ظاهرين بدون تمرير',
      (tester) async {
    for (final size in const [Size(390, 844), Size(412, 915), Size(360, 780)]) {
      await _pumpEntry(tester, size: size);
      final navTop = tester.getTopLeft(find.text('الرئيسية')).dy - 20;
      expect(tester.getRect(find.byKey(const Key('entry-banner'))).top, greaterThan(0));
      for (final label in ['خدمة وصّلي ع السريع', 'تصفح العروض', 'تصفح المحلات']) {
        final card = tester.getRect(find.byKey(ValueKey<String>('entry-card-$label')));
        expect(card.bottom, lessThanOrEqualTo(navTop), reason: '$label on $size');
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('صاحب المحل يحصل على نفس الصفحة ولوحته من «لوحتي»',
      (tester) async {
    await _pumpEntry(
      tester,
      entry: const CustomerEntry(
        dashboard: Text('لوحة المحل'),
        dashboardLabel: 'لوحة المحل',
      ),
    );
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(customerShellAvailable.value, isFalse);
    await tester.tap(find.text('لوحتي'));
    await tester.pump();
    expect(find.text('لوحة المحل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
