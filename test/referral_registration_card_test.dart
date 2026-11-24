import 'package:city_store/widgets/referral_registration_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only first Google registration is eligible for in-app referral entry', () {
    final created = DateTime.utc(2026, 11, 24, 9);
    expect(
      isWithinReferralRegistrationWindow(
        accountCreatedAt: created,
        lastSignInAt: created,
        now: created.add(const Duration(minutes: 4)),
      ),
      isTrue,
    );
    expect(
      isWithinReferralRegistrationWindow(
        accountCreatedAt: created,
        lastSignInAt: created,
        now: created.add(const Duration(minutes: 6)),
      ),
      isFalse,
    );
    expect(
      isWithinReferralRegistrationWindow(
        accountCreatedAt: created,
        lastSignInAt: created.add(const Duration(minutes: 1)),
        now: created.add(const Duration(minutes: 2)),
      ),
      isFalse,
    );
    expect(
      isWithinReferralRegistrationWindow(
        accountCreatedAt: null,
        lastSignInAt: null,
        now: created,
      ),
      isFalse,
    );
  });

  testWidgets('in-app referral card sends a normalized code and confirms success',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferralRegistrationCard(
          onSubmit: (code) async => submitted = code,
        ),
      ),
    ));

    expect(find.text('عندك كود دعوة؟'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '2689b4526ef4');
    await tester.tap(find.text('تأكيد كود الدعوة'));
    await tester.pumpAndSettle();

    expect(submitted, '2689B4526EF4');
    expect(find.text('تم حفظ كود الدعوة بنجاح، ومش هينفع تغيّره.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('invalid in-app referral codes cannot be submitted',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferralRegistrationCard(
          onSubmit: (code) async => submitted = code,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextFormField), '123');
    await tester.tap(find.text('تأكيد كود الدعوة'));
    await tester.pumpAndSettle();

    expect(submitted, isNull);
    expect(find.text('اكتب كود من ٦ إلى ١٢ حرفًا إنجليزيًا أو رقمًا.'), findsOneWidget);
  });
}
