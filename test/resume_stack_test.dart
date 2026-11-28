// #339: مكدّس الصفحات ومواضع التمرير بعد ما أندرويد يقفل التطبيق.
import 'package:city_store/services/resume_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 11, 28, 12, 0);

  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> background() async {
    await ResumeSession.markBackground(now: t0);
  }

  Future<void> restart({Duration after = const Duration(minutes: 2)}) async {
    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(after));
  }

  test('the page stack comes back in order, once, for the same account', () async {
    ResumeSession.trackPush('u1', 'notifications');
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPush('u1', 'quick-order:q1');
    await background();
    await restart();

    expect(ResumeSession.takeStack('u1'), ['notifications', 'order:o1', 'quick-order:q1']);
    expect(ResumeSession.takeStack('u1'), isEmpty, reason: 'مرة واحدة بس');
  });

  test('another account never gets the previous account stack', () async {
    ResumeSession.trackPush('u1', 'order:o1');
    await background();
    await restart();
    expect(ResumeSession.takeStack('u2'), isEmpty);
  });

  test('popped and closed pages are not restored', () async {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPush('u1', 'order:o2');
    ResumeSession.trackPush('u1', 'notifications');
    ResumeSession.trackPop('notifications'); // المستخدم قفلها
    ResumeSession.closeRoute('order:o1'); // الطلب خلص
    await background();
    await restart();
    expect(ResumeSession.takeStack('u1'), ['order:o2']);
  });

  test('an emptied stack clears the saved value', () async {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPop('order:o1');
    await background();
    await restart();
    expect(ResumeSession.takeStack('u1'), isEmpty);
  });

  test('a finished order is closed even while its page is still on screen', () async {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.closeIfFinished('order:o1', false);
    expect(ResumeSession.stack, ['order:o1']);
    ResumeSession.closeIfFinished('order:o1', true);
    expect(ResumeSession.stack, isEmpty);
    ResumeSession.closeIfFinished(null, true); // مفيش مفتاح: مفيش حاجة تحصل
  });

  test('re-pushing a key moves it to the top without duplicates', () {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPush('u1', 'notifications');
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPush('u1', 'order:o1');
    expect(ResumeSession.stack, ['notifications', 'order:o1']);
  });

  test('a push by another account starts a clean stack', () {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.trackPush('u2', 'notifications');
    expect(ResumeSession.stack, ['notifications']);
  });

  test('invalid names and empty uid are ignored', () {
    ResumeSession.trackPush('', 'order:o1');
    ResumeSession.trackPush('u1', 'store:abc');
    ResumeSession.trackPush('u1', 'order:أحمد');
    ResumeSession.trackPush('u1', '/s/abc');
    expect(ResumeSession.stack, isEmpty);
  });

  test('the stack is capped so storage stays small', () async {
    for (var i = 0; i < 30; i++) {
      ResumeSession.trackPush('u1', 'order:o$i');
    }
    expect(ResumeSession.stack.length, 12);
    expect(ResumeSession.stack.last, 'order:o29');
    expect(ResumeSession.stack.first, 'order:o18');
  });

  test('a stale launch (30 minutes or more) restores nothing and wipes storage', () async {
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.remember('u1', 'order:o1/items', 400);
    await background();
    await restart(after: ResumeSession.window);

    expect(ResumeSession.resumedRecently, isFalse);
    expect(ResumeSession.takeStack('u1'), isEmpty);
    expect(ResumeSession.takeRemembered('u1', 'order:o1/items'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('resume_stack'), isNull);
    expect(prefs.getString('resume_state'), isNull);
  });

  test('stored names that are not valid routes are dropped on load', () async {
    SharedPreferences.setMockInitialValues({
      'resume_paused_at': t0.millisecondsSinceEpoch,
      'resume_stack': 'u1|order:o1,evil:thing,order:أحمد,notifications,order:o1,/s/x',
    });
    await ResumeSession.load(now: t0.add(const Duration(minutes: 1)));
    expect(ResumeSession.takeStack('u1'), ['order:o1', 'notifications']);
  });

  test('a deep link or notification wins: nothing is restored over it', () async {
    ResumeSession.setLocation('u1', 'shell:2');
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.remember('u1', 'shell/orders', 300);
    await background();
    await restart();

    ResumeSession.suppressRestore();
    expect(ResumeSession.takeLocation('u1'), isNull);
    expect(ResumeSession.takeStack('u1'), isEmpty);
    expect(ResumeSession.takeRemembered('u1', 'shell/orders'), isNull);
  });

  group('scroll and tab state', () {
    test('values survive a restart for the same account, once', () async {
      ResumeSession.remember('u1', 'shell/orders', 640);
      ResumeSession.remember('u1', 'owner/tab', 1);
      await background();
      await restart();

      expect(ResumeSession.takeRemembered('u1', 'shell/orders'), 640);
      expect(ResumeSession.takeRemembered('u1', 'shell/orders'), isNull);
      expect(ResumeSession.takeRemembered('u1', 'owner/tab'), 1);
    });

    test('never given to another account', () async {
      ResumeSession.remember('u1', 'shell/orders', 640);
      await background();
      await restart();
      expect(ResumeSession.takeRemembered('u2', 'shell/orders'), isNull);
    });

    test('closing a page clears its remembered positions', () async {
      ResumeSession.trackPush('u1', 'order:o1');
      ResumeSession.remember('u1', 'order:o1/items', 500);
      ResumeSession.remember('u1', 'shell/orders', 100);
      ResumeSession.trackPop('order:o1');
      await background();
      await restart();

      expect(ResumeSession.takeRemembered('u1', 'order:o1/items'), isNull);
      expect(ResumeSession.takeRemembered('u1', 'shell/orders'), 100);
    });

    test('forget removes a normally closed screen', () async {
      ResumeSession.remember('u1', 'store:s1/products', 900);
      ResumeSession.forget('u1', 'store:s1/products');
      await background();
      await restart();
      expect(ResumeSession.takeRemembered('u1', 'store:s1/products'), isNull);
    });

    test('rejects unsafe keys, negative values and unlimited growth', () async {
      ResumeSession.remember('u1', 'has space', 1);
      ResumeSession.remember('u1', 'a=b', 1);
      ResumeSession.remember('u1', 'a;b', 1);
      ResumeSession.remember('u1', 'neg', -5);
      ResumeSession.remember('', 'k', 1);
      for (var i = 0; i < 100; i++) {
        ResumeSession.remember('u1', 'k$i', i);
      }
      await background();
      await restart();
      expect(ResumeSession.takeRemembered('u1', 'has space'), isNull);
      expect(ResumeSession.takeRemembered('u1', 'a=b'), isNull);
      expect(ResumeSession.takeRemembered('u1', 'neg'), isNull);
      expect(ResumeSession.takeRemembered('u1', 'k0'), 0);
      expect(ResumeSession.takeRemembered('u1', 'k63'), 63);
      expect(ResumeSession.takeRemembered('u1', 'k64'), isNull, reason: 'حد أقصى 64 قيمة');
    });
  });

  test('clearAll (sign out / account switch) leaves nothing behind', () async {
    ResumeSession.setLocation('u1', 'shell:2');
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.remember('u1', 'shell/orders', 300);
    await background();

    await ResumeSession.clearAll();
    expect(ResumeSession.stack, isEmpty);
    expect(ResumeSession.current, isNull);
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['resume_location', 'resume_stack', 'resume_state', 'resume_paused_at']) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }

    await restart();
    expect(ResumeSession.resumedRecently, isFalse);
    expect(ResumeSession.takeLocation('u1'), isNull);
    expect(ResumeSession.takeStack('u1'), isEmpty);
  });

  test('persisted values are ids only: no names, phones or addresses', () async {
    ResumeSession.setLocation('u1', 'shell:2');
    ResumeSession.trackPush('u1', 'order:o1');
    ResumeSession.remember('u1', 'shell/orders', 300);
    await background();
    final prefs = await SharedPreferences.getInstance();
    final stored = [
      prefs.getString('resume_location'),
      prefs.getString('resume_stack'),
      prefs.getString('resume_state'),
    ].join(' ');
    expect(stored, 'u1|shell:2 u1|order:o1 u1|shell/orders=300');
  });
}
