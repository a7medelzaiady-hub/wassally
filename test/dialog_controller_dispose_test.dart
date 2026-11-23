import 'package:city_store/models/order.dart';
import 'package:city_store/screens/admin_orders_page.dart';
import 'package:city_store/utils/dialog_controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('حوار فيه TextField: المسح المؤجل ما يوقعش التطبيق وهو بيتقفل', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final ctrl = TextEditingController();
    final result = showDialog<String>(
      context: ctx,
      builder: (d) => AlertDialog(
        content: TextField(controller: ctrl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('ok'))],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('ok'));
    await tester.pump(); // الحوار بدأ يتقفل
    expect(await result, '25');
    disposeAfterDialogCloses(ctrl);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  test('الطلب الملغي أو المسلّم: الحالة مقفولة عند الإدارة', () {
    expect(adminStatusLocked(OrderStatus.cancelled), isTrue);
    expect(adminStatusLocked(OrderStatus.delivered), isTrue);
    expect(adminStatusLocked(OrderStatus.preparing), isFalse);
  });
}
