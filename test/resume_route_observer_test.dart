// #339: التتبع المركزي لمسارات الـ Navigator (push / pushOnce / replace / pop / popUntil).
import 'package:city_store/services/navigation.dart';
import 'package:city_store/services/resume_route_observer.dart';
import 'package:city_store/services/resume_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Route<void> _route(String? name) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => Scaffold(body: Text('page ${name ?? 'unnamed'}')),
    );

void main() {
  late String uid;

  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
    uid = 'u1';
  });

  Future<NavigatorState> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [ResumeRouteObserver(uidOf: () => uid)],
      home: const Scaffold(body: Text('home')),
    ));
    return rootNavigatorKey.currentState!;
  }

  testWidgets('push and pop are tracked', (tester) async {
    final nav = await pump(tester);

    nav.push(_route('order:o1'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['order:o1']);

    nav.push(_route('quick-order:q1'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['order:o1', 'quick-order:q1']);

    nav.pop();
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['order:o1']);

    nav.pop();
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, isEmpty);
  });

  testWidgets('pushOnce routes are tracked under their key', (tester) async {
    await pump(tester);
    final context = tester.element(find.text('home'));

    final done = pushOnce<void>(context, 'notifications', (_) => const Scaffold(body: Text('n')));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['notifications']);

    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await done;
    expect(ResumeSession.stack, isEmpty);
  });

  testWidgets('unnamed, service and unknown routes are ignored', (tester) async {
    final nav = await pump(tester);
    nav.push(_route(null));
    nav.push(_route('service:quick'));
    nav.push(_route('store:abc'));
    nav.push(_route('/s/abc'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, isEmpty);
  });

  testWidgets('pushReplacement swaps the tracked page', (tester) async {
    final nav = await pump(tester);
    nav.push(_route('quick-orders'));
    await tester.pumpAndSettle();

    nav.pushReplacement(_route('quick-order:q9'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['quick-order:q9']);
  });

  testWidgets('popUntil first clears every tracked page (openCustomerTab / logout)', (tester) async {
    final nav = await pump(tester);
    nav.push(_route('notifications'));
    nav.push(_route('order:o1'));
    nav.push(_route('quick-order:q1'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack.length, 3);

    nav.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, isEmpty);
  });

  testWidgets('removeRoute and pushAndRemoveUntil drop removed pages', (tester) async {
    final nav = await pump(tester);
    final first = _route('order:o1');
    nav.push(first);
    nav.push(_route('notifications'));
    await tester.pumpAndSettle();

    nav.removeRoute(first);
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['notifications']);

    nav.pushAndRemoveUntil(_route('checkout'), (route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['checkout']);
  });

  testWidgets('a page opened by another account starts a clean stack', (tester) async {
    final nav = await pump(tester);
    nav.push(_route('order:o1'));
    await tester.pumpAndSettle();

    uid = 'u2';
    nav.push(_route('notifications'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, ['notifications']);
  });

  testWidgets('nothing is tracked without a signed-in account', (tester) async {
    uid = '';
    final nav = await pump(tester);
    nav.push(_route('order:o1'));
    await tester.pumpAndSettle();
    expect(ResumeSession.stack, isEmpty);
  });
}
