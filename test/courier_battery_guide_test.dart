import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:city_store/widgets/courier_battery_guide.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('battery guide appears only once per courier account, without Firestore', () async {
    expect(await CourierBatteryGuidePolicy.shouldShowOnce('courier_a'), isTrue);
    expect(await CourierBatteryGuidePolicy.shouldShowOnce('courier_a'), isFalse);
    expect(await CourierBatteryGuidePolicy.shouldShowOnce('courier_b'), isTrue);
  });

  testWidgets('courier guidance names all five Android vendors and opens settings', (tester) async {
    var settingsOpened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => CourierBatteryGuide.show(
              context,
              openBatterySettings: () async { settingsOpened = true; },
            ),
            child: const Text('إرشاد البطارية'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('إرشاد البطارية'));
    await tester.pumpAndSettle();
    for (final name in ['شاومي / بوكو', 'أوبو', 'ريلمي', 'هواوي', 'سامسونج']) {
      expect(find.textContaining(name, findRichText: true), findsWidgets);
    }
    expect(find.text('افتح إعدادات التطبيق'), findsOneWidget);
    await tester.tap(find.text('افتح إعدادات التطبيق'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    await tester.tap(find.text('تمام'));
    await tester.pumpAndSettle();
    expect(find.text('افتح إعدادات التطبيق'), findsNothing);
  });
}
