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
      home: const CustomerEntry(loadHeroPhoto: false),
    ));
    await tester.pump();

    expect(find.text('كل اللي بتحبه...'), findsOneWidget);
    expect(find.byKey(const Key('entry-hero-phone-photo')), findsOneWidget);
    expect(find.byIcon(Icons.phone_in_talk_rounded), findsOneWidget);
    final photo = tester.getRect(find.byKey(const Key('entry-hero-phone-photo')));
    final title = tester.getRect(find.text('كل اللي بتحبه...'));
    expect(photo.right, lessThan(title.left));
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('تصفح العروض'), findsOneWidget);
    expect(find.text('تصفح المحلات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('صور الخدمات ملاصقة للكروت بدون طبقة بيضاء وعلى شاشة صغيرة',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(loadHeroPhoto: false),
    ));
    await tester.pump();

    for (final label in [
      'خدمة وصّلي ع السريع',
      'تصفح العروض',
      'تصفح المحلات',
    ]) {
      final art = find.byKey(ValueKey<String>('entry-art-$label'));
      expect(art, findsOneWidget);
      await tester.ensureVisible(art);
      await tester.pump();
      // The artwork fills half of the card rather than being reduced by
      // a 40px white fade or an inset margin.
      expect(tester.getSize(art).width, greaterThan(120));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('مواقع الرئيسية والسلة معكوسة حسب اعتماد RTL',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: CustomerEntry(loadHeroPhoto: false),
      ),
    ));
    await tester.pump();

    // Under RTL, the first entry in the Row is the rightmost slot.
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('السلة'), findsOneWidget);
    expect(tester.getCenter(find.text('السلة')).dx,
        greaterThan(tester.getCenter(find.text('الرئيسية')).dx));
    expect(find.text('تصفح المحلات'), findsOneWidget);
    expect(find.text('تصفح العروض'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('البانر يحمل صورة حقيقية لعميلة بتتكلم في الهاتف', () {
    expect(const CustomerEntry().loadHeroPhoto, isTrue);
    final uri = Uri.parse(kEntryHeroPhoneImageUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'images.unsplash.com');
    expect(uri.path, contains('photo-1758876201450-cf77ab8b95bc'));
  });

  testWidgets('صاحب المحل يحصل على نفس صفحة الترحيب مع مدخل لوحته',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const CustomerEntry(
        loadHeroPhoto: false,
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
