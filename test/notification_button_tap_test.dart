import 'package:city_store/services/navigation.dart';
import 'package:city_store/widgets/scroll_following_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list({required ScrollController controller, Widget? headerButton}) {
  return CustomScrollView(
    controller: controller,
    physics: const BouncingScrollPhysics(),
    slivers: [
      SliverToBoxAdapter(
        child: Container(
          height: 120,
          color: Colors.deepPurple,
          alignment: AlignmentDirectional.topEnd,
          padding: const EdgeInsets.all(8),
          child: headerButton ?? const SizedBox(width: 44, height: 44),
        ),
      ),
      SliverList.builder(
        itemCount: 60,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('صف $i')),
      ),
    ],
  );
}

void main() {
  testWidgets('السبب: الزر داخل القائمة يضيع أول ضغطة أثناء الارتداد',
      (tester) async {
    var taps = 0;
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _list(
          controller: controller,
          headerButton: IconButton(
            key: const Key('bell'),
            onPressed: () => taps++,
            icon: const Icon(Icons.notifications),
          ),
        ),
      ),
    ));
    // Pull down past the top and release: the list bounces back.
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1500);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const Key('bell')), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0, reason: 'Flutter ignores taps inside a Scrollable while it settles');
    await tester.pumpAndSettle();
  });

  testWidgets('الإصلاح: زر الإشعارات فوق القائمة يفتح من أول ضغطة أثناء الارتداد',
      (tester) async {
    var taps = 0;
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          _list(controller: controller),
          ScrollFollowingOverlay(
            controller: controller,
            top: 8,
            end: 8,
            hideAfter: 52,
            child: IconButton(
              key: const Key('bell'),
              onPressed: () => taps++,
              icon: const Icon(Icons.notifications),
            ),
          ),
        ]),
      ),
    ));
    final restingTop = tester.getTopLeft(find.byKey(const Key('bell'))).dy;

    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1500);
    await tester.pump(const Duration(milliseconds: 30));
    // The button follows the content while the list bounces...
    expect(tester.getTopLeft(find.byKey(const Key('bell'))).dy, greaterThan(restingTop));
    // ...and the very first tap is delivered.
    await tester.tap(find.byKey(const Key('bell')));
    await tester.pump();
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('bell'))).dy, restingTop);

    // Scrolled away with the header: the button disappears with it.
    controller.jumpTo(400);
    await tester.pump();
    expect(find.byKey(const Key('bell')), findsNothing);
  });

  testWidgets('الضغط السريع المتكرر يفتح صفحة الإشعارات مرة واحدة',
      (tester) async {
    final observer = _PushCounter();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: IconButton(
              key: const Key('bell'),
              icon: const Icon(Icons.notifications),
              onPressed: () => pushOnce<void>(context, 'notifications',
                  (_) => const Scaffold(body: Text('الإشعارات'))),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('bell')));
    await tester.tap(find.byKey(const Key('bell')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('bell')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات'), findsOneWidget);
    expect(observer.pushes, 2, reason: 'home route + one notifications page');

    // After closing, it opens again normally.
    Navigator.of(tester.element(find.text('الإشعارات'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bell')));
    await tester.pumpAndSettle();
    expect(find.text('الإشعارات'), findsOneWidget);
  });
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}
