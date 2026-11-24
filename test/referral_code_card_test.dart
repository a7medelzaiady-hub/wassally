import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/widgets/referral_code_card.dart';

void main() {
  testWidgets('shows issued code and copy action', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ReferralCodeCard(serverIssuedCode: 'abc12345')),
    ));
    expect(find.text('ABC12345'), findsOneWidget);
    expect(find.text('نسخ الكود'), findsOneWidget);
    expect(find.text('مشاركة'), findsNothing);
  });

  testWidgets('does not show copy action for unavailable code', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ReferralCodeCard(serverIssuedCode: null)),
    ));
    expect(find.text('كود الدعوة غير متاح حاليًا'), findsOneWidget);
    expect(find.text('نسخ الكود'), findsNothing);
  });

  testWidgets('share action appears only when supplied', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ReferralCodeCard(
        serverIssuedCode: 'ABC12345',
        onShare: () {},
      )),
    ));
    expect(find.text('مشاركة'), findsOneWidget);
  });
}
