import 'package:city_store/screens/user_guide_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('دليل المستخدم متاح بلا اتصال وعلى شاشة 320px لكل الأدوار',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const UserGuidePage(),
    ));
    await tester.pump();

    expect(find.text('دليل استخدام وصّلي'), findsOneWidget);
    expect(find.byKey(const Key('guide-للعميل')), findsOneWidget);
    expect(find.byKey(const Key('guide-لصاحب المحل')), findsOneWidget);
    expect(find.byKey(const Key('guide-للمندوب')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-للعميل')));
    await tester.pumpAndSettle();
    expect(find.textContaining('السلة تخص محل واحد فقط'), findsOneWidget);
    expect(find.textContaining('محتويات سلتك بتفضل محفوظة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-للعميل')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guide-لصاحب المحل')));
    await tester.tap(find.byKey(const Key('guide-لصاحب المحل')));
    await tester.pumpAndSettle();
    expect(find.textContaining('بيانات اتصال العميل وعنوانه التفصيلي مش متاحة'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
