import 'package:city_store/services/navigation.dart';
import 'package:city_store/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replica of the old home bell: a 38px button with the unread badge drawn on
/// top of its corner.
Widget _oldBell(VoidCallback onTap) => Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
        ),
        Positioned(
          top: -5,
          left: -5,
          child: Container(
            key: const Key('old-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Text('3', style: TextStyle(fontSize: 10)),
          ),
        ),
      ],
    );

Widget _host(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.deepPurple,
          body: Center(child: child),
        ),
      ),
    );

void main() {
  testWidgets('السبب: الشارة القديمة كانت بتاخد الضغطة بدل الجرس', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(_oldBell(() => taps++)));
    // Tap where the badge overlaps the bell (inside the button's bounds).
    final badge = tester.getRect(find.byKey(const Key('old-badge')));
    await tester.tapAt(badge.bottomRight - const Offset(3, 3));
    await tester.pump();
    expect(taps, 0, reason: 'the red badge swallowed the tap');
  });

  testWidgets('الإصلاح: الضغط على الشارة أو أي جزء من الجرس يفتح من أول مرة',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(NotificationBell(count: 3, onTap: () => taps++)));

    final bell = find.byKey(const Key('notification-bell'));
    final badge = find.byKey(const Key('notification-bell-badge'));
    expect(badge, findsOneWidget);
    expect(tester.getSize(bell), const Size(48, 48));

    await tester.tap(badge);
    await tester.pump();
    expect(taps, 1);

    await tester.tap(bell);
    await tester.pump();
    expect(taps, 2);

    // Near the edge of the 48px circle still counts.
    final rect = tester.getRect(bell);
    await tester.tapAt(rect.center + const Offset(0, 20));
    await tester.pump();
    expect(taps, 3);
  });

  testWidgets('الجرس يعرض 9+ ويعلن عدد غير المقروء لقارئ الشاشة', (tester) async {
    await tester.pumpWidget(_host(NotificationBell(count: 25, onTap: () {})));
    expect(find.text('9+'), findsOneWidget);
    expect(find.bySemanticsLabel('الإشعارات، 25 غير مقروءة'), findsOneWidget);
  });

  testWidgets('الضغط السريع المتكرر يفتح صفحة الإشعارات مرة واحدة',
      (tester) async {
    final observer = _PushCounter();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: NotificationBell(
              onTap: () => pushOnce<void>(context, 'notifications',
                  (_) => const Scaffold(body: Text('صفحة الإشعارات'))),
            ),
          ),
        ),
      ),
    ));
    final bell = find.byKey(const Key('notification-bell'));
    await tester.tap(bell);
    await tester.tap(bell, warnIfMissed: false);
    await tester.tap(bell, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('صفحة الإشعارات'), findsOneWidget);
    expect(observer.pushes, 2, reason: 'home route + one notifications page');

    // After closing, it opens again normally with one tap.
    Navigator.of(tester.element(find.text('صفحة الإشعارات'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(find.text('صفحة الإشعارات'), findsOneWidget);
    expect(observer.pushes, 3);
  });
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}
