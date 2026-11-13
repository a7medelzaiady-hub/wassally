import 'package:city_store/widgets/empty_state.dart';
import 'package:city_store/widgets/qty_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EmptyState بيعرض العنوان وزر الإجراء', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.shopping_basket_outlined,
            title: 'السلة فاضية',
            message: 'ضيف منتجات',
            actionLabel: 'تصفّح المحلات',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('السلة فاضية'), findsOneWidget);
    await tester.tap(find.text('تصفّح المحلات'));
    expect(tapped, isTrue);
  });

  testWidgets('QtyStepper بيزوّد وينقّص', (tester) async {
    var qty = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QtyStepper(
            qty: qty,
            onAdd: () => qty++,
            onRemove: () => qty--,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.remove));
    expect(qty, 2);
  });
}
