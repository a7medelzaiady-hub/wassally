import 'package:city_store/services/navigation.dart' show rootNavigatorKey;
import 'package:city_store/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: Text('home')),
      ));

  testWidgets('الرسالة بتظهر في نص الشاشة ببرواز ورسمة وبتتقفل بزرار تمام', (tester) async {
    await pumpApp(tester);
    showAppNotice(title: 'تم إرسال طلبك بنجاح', message: 'احتفظ برمز التسليم');
    await tester.pumpAndSettle();

    expect(find.text('تم إرسال طلبك بنجاح'), findsOneWidget);
    expect(find.text('احتفظ برمز التسليم'), findsOneWidget);
    expect(find.byKey(const Key('app-notice-frame')), findsOneWidget);
    expect(find.byKey(const Key('app-notice-illustration')), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag_rounded), findsOneWidget);

    // في نص الشاشة تقريبًا.
    final frame = tester.getCenter(find.byKey(const Key('app-notice-frame')));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect((frame.dy - screen.height / 2).abs(), lessThan(screen.height * 0.15));

    await tester.tap(find.byKey(const Key('app-notice-ok')));
    await tester.pumpAndSettle();
    expect(find.text('تم إرسال طلبك بنجاح'), findsNothing);
  });

  testWidgets('رسالة واحدة بس في المرة، والإشعار بيقفل لوحده', (tester) async {
    await pumpApp(tester);
    showAppNotice(title: 'أول', message: 'a', kind: AppNoticeKind.info);
    await tester.pumpAndSettle();
    showAppNotice(
      title: 'تاني',
      message: 'b',
      kind: AppNoticeKind.info,
      autoClose: const Duration(seconds: 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('أول'), findsNothing);
    expect(find.text('تاني'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('تاني'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
