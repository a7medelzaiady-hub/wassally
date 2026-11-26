import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/invite_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

void main() {
  testWidgets('خانة كود الدعوة تحفظ الكود الصحيح وتقفل بعدها', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_host(InviteCodeField(onSubmit: (code) async => sent.add(code))));
    expect(find.text('اكتب كود الدعوة هنا'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invite-code-input')), ' wsl12345 ');
    await tester.tap(find.byKey(const Key('invite-code-submit')));
    await tester.pumpAndSettle();

    expect(sent, ['WSL12345']);
    expect(find.byKey(const Key('invite-code-saved')), findsOneWidget);
    expect(find.text('تم حفظ كود الدعوة بنجاح.'), findsOneWidget);
  });

  testWidgets('كود بصيغة غلط لا يتبعت ويظهر توضيح', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_host(InviteCodeField(onSubmit: (code) async => sent.add(code))));
    await tester.enterText(find.byKey(const Key('invite-code-input')), 'ab');
    await tester.tap(find.byKey(const Key('invite-code-submit')));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.textContaining('اكتب كود من'), findsOneWidget);
  });

  testWidgets('رفض الخادم يظهر رسالته والخانة تفضل مفتوحة', (tester) async {
    await tester.pumpWidget(_host(InviteCodeField(
      onSubmit: (_) async => throw StateError('الكود ده مش صالح لحسابك.'),
    )));
    await tester.enterText(find.byKey(const Key('invite-code-input')), 'WSL12345');
    await tester.tap(find.byKey(const Key('invite-code-submit')));
    await tester.pumpAndSettle();
    expect(find.text('الكود ده مش صالح لحسابك.'), findsOneWidget);
    expect(find.byKey(const Key('invite-code-input')), findsOneWidget);
  });

  testWidgets('صفحة ما بعد الدخول تعرض خانة كود الدعوة مكان البحث', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: CustomerEntry(showInviteCode: true),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('entry-invite-code')), findsOneWidget);
    expect(find.byKey(const Key('entry-search')), findsNothing);
    expect(find.byKey(const Key('entry-header-wave')), findsOneWidget);
    expect(find.byKey(const Key('entry-banner')), findsNothing);
    expect(find.text('خدمة وصّلي ع السريع'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
