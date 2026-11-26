import 'package:city_store/models/referral_admin_choices.dart';
import 'package:city_store/widgets/referral_marketer_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin marketer directory skips duplicates, invalid and disabled IDs', () {
    final choices = referralMarketerChoices([
      {'uid': 'u101', 'name': 'أحمد', 'email': 'one@example.com'},
      {'uid': 'u101', 'name': 'نسخة مكررة'},
      {'uid': 'u202', 'displayName': 'محمد', 'email': 'two@example.com'},
      {'uid': '', 'name': 'بدون حساب'},
      {'uid': 'u303', 'name': 'متوقف', 'active': false},
      {'uid': 'u404', 'name': 'محذوف', 'deleted': true},
    ]);
    expect(choices.length, 2);
    expect(choices.map((c) => c.uid).toSet(), {'u101', 'u202'});
    expect(choices.first.matches('one@'), isTrue);
    expect(choices.first.matches('u202'), isFalse);
    expect(choices.last.matches('محمد'), isTrue);
    expect(choices.last.matches('two@'), isTrue);
  });

  testWidgets('Admin can search and pick an existing account at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    ReferralMarketerChoice? selected;
    final entries = referralMarketerChoices([
      {'uid': 'userOne', 'name': 'أحمد', 'email': 'ahmed@example.com'},
      {'uid': 'userTwo', 'name': 'محمد', 'email': 'mohamed@example.com'},
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              selected = await showModalBottomSheet<ReferralMarketerChoice>(
                context: tester.element(find.byType(ElevatedButton)),
                isScrollControlled: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: 0.75,
                  child: ReferralMarketerPicker(
                    accounts: Future.value(entries),
                  ),
                ),
              );
            },
            child: const Text('افتح الحسابات'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح الحسابات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marketer-account-list')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('marketer-search')), 'mohamed');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('marketer-choice-userOne')), findsNothing);
    expect(find.byKey(const Key('marketer-choice-userTwo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('marketer-choice-userTwo')));
    await tester.pumpAndSettle();

    expect(selected?.uid, 'userTwo');
    expect(tester.takeException(), isNull);
  });
}
