import 'package:city_store/widgets/referral_balance_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('أرصدة الدعوات واضحة بدون قص على شاشة هاتف صغيرة', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        ReferralBalanceTile(
          icon: Icons.stars_rounded,
          title: 'رصيد النقاط',
          value: '120 نقطة',
          explanation: 'نقاط خصم عند التسوق',
        ),
        ReferralBalanceTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'رصيد المكافآت النقدية',
          value: '150.00 ج.م',
          explanation: 'مكافأة قابلة للسحب',
        ),
        ReferralBalanceTile(
          icon: Icons.percent_rounded,
          title: 'رصيد خصم العمولة',
          value: '80.00 ج.م',
          explanation: 'ليس رصيدًا نقديًا',
        ),
      ])))),
    ));
    await tester.pump();
    expect(find.text('رصيد النقاط'), findsOneWidget);
    expect(find.text('رصيد المكافآت النقدية'), findsOneWidget);
    expect(find.text('رصيد خصم العمولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
