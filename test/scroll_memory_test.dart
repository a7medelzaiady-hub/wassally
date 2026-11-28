// #339: موضع التمرير والتبويب بيرجعوا بعد ما أندرويد يقفل التطبيق.
import 'package:city_store/services/resume_session.dart';
import 'package:city_store/widgets/scroll_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 11, 28, 12);
const _fast = Duration(milliseconds: 10);

/// قفل أندرويد للعملية وفتح التطبيق بعد دقيقتين.
Future<void> _restartProcess() async {
  await ResumeSession.markBackground(now: _t0);
  ResumeSession.reset();
  await ResumeSession.load(now: _t0.add(const Duration(minutes: 2)));
}

Widget _app(ScrollController controller, {int count = 100}) => MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: count,
          itemExtent: 50,
          itemBuilder: (_, i) => Text('item $i'),
        ),
      ),
    );

Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const MaterialApp(home: SizedBox()));

void main() {
  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves the offset while scrolling', (tester) async {
    final memory = ScrollMemory('shell/orders', uidOf: () => 'u1')..attach();
    await tester.pumpWidget(_app(memory.controller));
    memory.controller.jumpTo(700);
    await tester.pump();

    await tester.runAsync(_restartProcess);
    expect(ResumeSession.takeRemembered('u1', 'shell/orders'), 700);
    await _unmount(tester);
    memory.dispose();
  });

  testWidgets('restores the offset after a restart (same account)', (tester) async {
    ResumeSession.remember('u1', 'shell/orders', 900);
    await tester.runAsync(_restartProcess);

    final memory = ScrollMemory('shell/orders', uidOf: () => 'u1', interval: _fast)..attach();
    await tester.pumpWidget(_app(memory.controller));
    await tester.pump(const Duration(milliseconds: 50));
    expect(memory.controller.offset, 900);
    await _unmount(tester);
    memory.dispose();
  });

  testWidgets('another account does not get the offset', (tester) async {
    ResumeSession.remember('u1', 'shell/orders', 900);
    await tester.runAsync(_restartProcess);

    final memory = ScrollMemory('shell/orders', uidOf: () => 'u2', interval: _fast)..attach();
    await tester.pumpWidget(_app(memory.controller));
    await tester.pump(const Duration(milliseconds: 50));
    expect(memory.controller.offset, 0);
    await _unmount(tester);
    memory.dispose();
  });

  testWidgets('waits for the list to load, then jumps to the saved offset', (tester) async {
    ResumeSession.remember('u1', 'shell/orders', 900);
    await tester.runAsync(_restartProcess);

    final memory = ScrollMemory('shell/orders', uidOf: () => 'u1', interval: _fast)..attach();
    final count = ValueNotifier<int>(3); // القايمة لسه بتتحمّل: قصيرة
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: count,
          builder: (_, n, _) => ListView.builder(
            controller: memory.controller,
            itemCount: n,
            itemExtent: 50,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(memory.controller.offset, 0, reason: 'مفيش محتوى يكفي لسه');

    count.value = 100; // الداتا وصلت
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(memory.controller.offset, 900);
    await _unmount(tester);
    memory.dispose();
    count.dispose();
  });

  testWidgets('does not fight the user: stops once they scroll themselves', (tester) async {
    ResumeSession.remember('u1', 'shell/orders', 900);
    await tester.runAsync(_restartProcess);

    final memory = ScrollMemory('shell/orders', uidOf: () => 'u1', interval: _fast)..attach();
    final count = ValueNotifier<int>(3);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: count,
          builder: (_, n, _) => ListView.builder(
            controller: memory.controller,
            itemCount: n,
            itemExtent: 50,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
      ),
    ));
    count.value = 40; // المحتوى طال كفاية، بس الاستعادة لسه ما اشتغلتش
    await tester.pump();
    memory.controller.jumpTo(100); // المستخدم اتحرك بنفسه
    await tester.pump(const Duration(milliseconds: 100));
    expect(memory.controller.offset, 100);
    await _unmount(tester);
    memory.dispose();
    count.dispose();
  });

  testWidgets('gives up after the attempt limit when the list never grows', (tester) async {
    ResumeSession.remember('u1', 'shell/orders', 900);
    await tester.runAsync(_restartProcess);

    final memory = ScrollMemory('shell/orders', uidOf: () => 'u1', interval: _fast, maxAttempts: 5)..attach();
    await tester.pumpWidget(_app(memory.controller, count: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(memory.controller.offset, 0);
    await _unmount(tester);
    memory.dispose();
  });

  testWidgets('a normal close removes the remembered position', (tester) async {
    final memory = ScrollMemory('store:s1/products', uidOf: () => 'u1')..attach();
    await tester.pumpWidget(_app(memory.controller));
    memory.controller.jumpTo(500);
    await tester.pump();
    await _unmount(tester);
    memory.dispose(); // المستخدم قفل الصفحة بنفسه

    await tester.runAsync(_restartProcess);
    expect(ResumeSession.takeRemembered('u1', 'store:s1/products'), isNull);
  });

  testWidgets('RememberScroll builds without a signed-in account and disposes cleanly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RememberScroll(
          name: 'shell/orders',
          builder: (context, controller) => ListView.builder(
            controller: controller,
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
      ),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });

  group('TabIndexMemory', () {
    Widget tabs({required int initial}) => MaterialApp(
          home: DefaultTabController(
            key: ValueKey<int>(initial),
            length: 2,
            initialIndex: initial,
            child: TabIndexMemory(
              name: 'owner/tab',
              uidOf: () => 'u1',
              child: Scaffold(
                appBar: AppBar(bottom: const TabBar(tabs: [Tab(text: 'one'), Tab(text: 'two')])),
                body: const TabBarView(children: [Text('first'), Text('second')]),
              ),
            ),
          ),
        );

    testWidgets('remembers the selected tab and restores it', (tester) async {
      await tester.pumpWidget(tabs(initial: 0));
      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();

      await tester.runAsync(_restartProcess);
      final index = TabIndexMemory.initialIndex('owner/tab', 2, uidOf: () => 'u1');
      expect(index, 1);

      await tester.pumpWidget(tabs(initial: index));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('ignores out-of-range or other-account values', (tester) async {
      ResumeSession.remember('u1', 'owner/tab', 7);
      await tester.runAsync(_restartProcess);
      expect(TabIndexMemory.initialIndex('owner/tab', 2, uidOf: () => 'u1'), 0);

      ResumeSession.reset();
      ResumeSession.remember('u1', 'owner/tab', 1);
      await tester.runAsync(_restartProcess);
      expect(TabIndexMemory.initialIndex('owner/tab', 2, uidOf: () => 'u2'), 0);
    });
  });
}
