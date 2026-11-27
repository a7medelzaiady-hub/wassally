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
  testWidgets('صفحة ما بعد الدخول: هيدر مموج وأربع خدمات بدون overflow',
      (tester) async {
    await _pumpEntry(tester);

    expect(find.byKey(const Key('entry-location')), findsOneWidget);
    expect(find.byKey(const Key('entry-search')), findsOneWidget);
    expect(find.byKey(const Key('entry-banner')), findsNothing);
    expect(find.byKey(const Key('entry-header-wave')), findsOneWidget);
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('مشاويرك علينا'), findsOneWidget);
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
        'مشاويرك علينا',
        'تصفح العروض',
        'تصفح المحلات',
      ]) {
        final art = find.byKey(ValueKey<String>('entry-art-$label'));
        // ListView builds off-screen children lazily: scroll by pixels until
        // the image exists, rather than requiring an unbuilt element.
        for (var attempt = 0; attempt < 12 && art.evaluate().isEmpty; attempt++) {
          await tester.drag(find.byKey(const Key('entry-list')),
              const Offset(0, -100));
          await tester.pump();
        }
        expect(art, findsOneWidget);
        expect(tester.getSize(art).width, greaterThan(120));
      }
      expect(tester.takeException(), isNull, reason: 'textScale $scale');
    }
  });

  testWidgets('الشريط زي المرجع: السلة كبيرة في النص', (tester) async {
    await _pumpEntry(tester);
    final x = {
      for (final l in ['الرئيسية', 'طلباتي', 'السلة', 'المحلات', 'حسابي'])
        l: tester.getCenter(find.text(l)).dx,
    };
    expect(x['الرئيسية']!, greaterThan(x['طلباتي']!));
    expect(x['طلباتي']!, greaterThan(x['السلة']!));
    expect(x['السلة']!, greaterThan(x['المحلات']!));
    expect(x['المحلات']!, greaterThan(x['حسابي']!));
    // The cart is the raised button in the middle of the bar.
    final cart = tester.getRect(find.byKey(const ValueKey('nav-السلة')));
    expect(cart.center.dx, closeTo(195, 2));
    expect(cart.height, greaterThan(60));
    expect(cart.top, lessThan(tester.getTopLeft(find.text('حسابي')).dy - 20));
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

  testWidgets('على موبايل عادي الكروت متاحة بالتمرير بدون overflow',
      (tester) async {
    for (final size in const [Size(390, 844), Size(412, 915), Size(360, 780)]) {
      await _pumpEntry(tester, size: size);
      final navTop = tester.getTopLeft(find.text('الرئيسية')).dy - 20;
      expect(find.byKey(const Key('entry-banner')), findsNothing);
      for (final label in ['خدمة وصّلي ع السريع', 'مشاويرك علينا', 'تصفح العروض', 'تصفح المحلات']) {
        final cardFinder = find.byKey(ValueKey<String>('entry-card-$label'));
        await tester.scrollUntilVisible(cardFinder, 100,
            scrollable: find.descendant(
              of: find.byKey(const Key('entry-list')),
              matching: find.byType(Scrollable),
            ));
        await tester.pump();
        final card = tester.getRect(cardFinder);
        expect(card.top, lessThan(navTop), reason: '$label on $size');
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('الخدمات الأربعة بنفس الشكل وفي شاشة واحدة من غير تمرير',
      (tester) async {
    for (final size in const [Size(390, 844), Size(412, 915)]) {
      await _pumpEntry(tester, size: size);
      final navTop = tester.getTopLeft(find.text('الرئيسية')).dy - 20;
      final list = tester.widget<ListView>(find.byKey(const Key('entry-list')));
      expect(list.physics, isA<NeverScrollableScrollPhysics>(), reason: '$size');
      double? height;
      for (final label in ['خدمة وصّلي ع السريع', 'مشاويرك علينا', 'تصفح العروض', 'تصفح المحلات']) {
        final card = tester.getRect(find.byKey(ValueKey<String>('entry-card-$label')));
        expect(card.bottom, lessThan(navTop), reason: '$label on $size');
        height ??= card.height;
        expect(card.height, closeTo(height, 0.5), reason: '$label on $size');
        // كل كارت ليه صورة/لوحة على اليسار وزرار برتقالي بنفس التصميم.
        expect(find.byKey(ValueKey<String>('entry-art-$label')), findsOneWidget);
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
