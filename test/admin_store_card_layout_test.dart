import 'package:city_store/screens/admin_stores_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('كارت المحل: الاسم في سطر واحد على شاشة موبايل ضيقة حتى مع 4 أزرار إجراءات', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            AdminStoreCardLayout(
              onTap: () {},
              title: 'الزيت والسيارات',
              subtitle: 'سيارات • 11 صنف\nظاهر',
              leading: const Icon(Icons.store),
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.delete_outline_rounded)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.account_balance_wallet_outlined)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.lock_open_rounded)),
                Switch(value: true, onChanged: (_) {}),
              ],
            ),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final titleBox = tester.getSize(find.text('الزيت والسيارات'));
    // سطر واحد (الارتفاع أقل بكتير من ارتفاع اسم متكسر حرف حرف) وعرضه معقول.
    expect(titleBox.height, lessThan(30));
    expect(titleBox.width, greaterThan(80));
    // كل الأزرار الأربعة ظاهرة.
    expect(find.byType(IconButton), findsNWidgets(3));
    expect(find.byType(Switch), findsOneWidget);
  });
}
