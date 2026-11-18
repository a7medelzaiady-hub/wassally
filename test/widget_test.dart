import 'package:city_store/widgets/empty_state.dart';
import 'package:city_store/widgets/app_header.dart';
import 'package:city_store/widgets/qty_stepper.dart';
import 'package:city_store/widgets/curved_nav_bar.dart';
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

  testWidgets('شريط التنقل يعرض أيقونة السلة مرة واحدة بمحاذاة اسمها', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CurvedNavBar(
            index: 2,
            onTap: (value) => selected = value,
            items: const [
              AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'الرئيسية'),
              AppNavItem(icon: Icons.receipt_outlined, selectedIcon: Icons.receipt, label: 'طلباتي'),
              AppNavItem(icon: Icons.shopping_cart_outlined, selectedIcon: Icons.shopping_cart, label: 'السلة'),
              AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'حسابي'),
              AppNavItem(icon: Icons.notifications_outlined, selectedIcon: Icons.notifications, label: 'الإشعارات'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('السلة'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart), findsOneWidget);
    await tester.tap(find.text('السلة'));
    expect(selected, 2);
  });

  testWidgets('زر الرئيسية يرجع من الصفحة الداخلية إلى جذر التطبيق', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(actions: const [HomeActionButton()]),
                      body: const Text('صفحة داخلية'),
                    ),
                  ),
                ),
                child: const Text('افتح الصفحة'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('افتح الصفحة'));
    await tester.pumpAndSettle();
    expect(find.text('صفحة داخلية'), findsOneWidget);

    await tester.tap(find.byTooltip('الرئيسية'));
    await tester.pumpAndSettle();
    expect(find.text('افتح الصفحة'), findsOneWidget);
    expect(find.text('صفحة داخلية'), findsNothing);
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
