import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/service_entry_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('كارت «وصّلي ع السريع» في الرئيسية: صورة + عنوان + زرار، والضغط بيفتح الخدمة',
      (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ServiceEntryCard(
              title: 'خدمة وصّلي ع السريع',
              subtitle: 'اطلب احتياجاتك من أي مكان',
              action: 'اطلب الآن',
              asset: 'assets/images/entry_quick.jpg',
              height: 118,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(find.text('اطلب الآن'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('entry-art-خدمة وصّلي ع السريع')), findsOneWidget);
    await tester.tap(find.text('اطلب الآن'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
