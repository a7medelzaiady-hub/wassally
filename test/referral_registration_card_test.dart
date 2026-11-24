import 'package:city_store/widgets/referral_registration_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('in-app referral card sends a normalized code and confirms success',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferralRegistrationCard(
          onSubmit: (code) async { submitted = code; },
        ),
      ),
    ));

    expect(find.text('عندك كود دعوة؟'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'abcd1234');
    await tester.tap(find.text('تأكيد كود الدعوة'));
    await tester.pumpAndSettle();

    expect(submitted, 'ABCD1234');
    expect(find.text('تم حفظ كود الدعوة بنجاح، ومش هينفع تغيّره.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('invalid in-app referral codes cannot be submitted',
      (tester) async {
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferralRegistrationCard(
          onSubmit: (code) async { submitted = code; },
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
