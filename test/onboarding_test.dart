import 'package:city_store/screens/onboarding_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, VoidCallback onDone, {Size size = const Size(390, 844), double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: OnboardingPage(onDone: onDone),
  ));
  await tester.pump();
}

void main() {
  test('الجولة تظهر مرة واحدة لكل حساب وتتحفظ محليًا', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await OnboardingStore.shouldShow(uid: 'u1'), isTrue);
    await OnboardingStore.markDone(uid: 'u1');
    expect(await OnboardingStore.shouldShow(uid: 'u1'), isFalse);
    expect(await OnboardingStore.shouldShow(uid: 'u2'), isTrue, reason: 'كل حساب لوحده');
    expect(await OnboardingStore.shouldShow(), isFalse, reason: 'من غير حساب مفيش جولة');
  });

  testWidgets('٣ شاشات بالتالي ثم «يلا نبدأ» تنهي الجولة', (tester) async {
    var done = 0;
    await _pump(tester, () => done++);
    expect(find.text('١/٣'), findsOneWidget);
    expect(find.textContaining('مستعجل؟'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('٢/٣'), findsOneWidget);
    expect(find.textContaining('متفوّتش العروض'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('٣/٣'), findsOneWidget);
    expect(find.text('يلا نبدأ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«تخطي» من أي شاشة ينهي الجولة', (tester) async {
    var done = 0;
    await _pump(tester, () => done++);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('شاشة صغيرة وخط كبير بدون قص أو overflow', (tester) async {
    await _pump(tester, () {}, size: const Size(320, 600), scale: 1.3);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('«تخطي» بيقفل صفحة الجولة فعلًا لما تتفتح كصفحة', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const OnboardingPage(),
              )),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    expect(find.text('١/٣'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.text('١/٣'), findsNothing);
    expect(find.text('افتح'), findsOneWidget);
  });
}
