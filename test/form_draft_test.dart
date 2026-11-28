// #339: المسودة بتتحفظ بعد الكتابة، وبتتستعاد بس بعد قفل أندرويد للتطبيق، وبتتمسح بعد الإرسال.
import 'package:city_store/services/draft_store.dart';
import 'package:city_store/services/form_draft.dart';
import 'package:city_store/services/resume_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _wait([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 11, 28, 12);

  setUp(() {
    ResumeSession.reset();
    SharedPreferences.setMockInitialValues({});
  });

  FormDraft make(
    TextEditingController a,
    TextEditingController b, {
    String uid = 'u1',
    Duration delay = const Duration(milliseconds: 40),
  }) =>
      FormDraft('errand', () => {'a': a.text, 'b': b.text}, uidOf: () => uid, delay: delay);

  Future<void> markResumed() async {
    await ResumeSession.markBackground(now: t0);
    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(const Duration(minutes: 1)));
  }

  test('typing saves after a short pause', () async {
    final a = TextEditingController();
    final b = TextEditingController();
    final draft = make(a, b, delay: const Duration(milliseconds: 150))..attach([a, b]);

    a.text = 'مكان';
    await _wait(30);
    expect(await DraftStore.load('u1', 'errand'), isNull, reason: 'لسه ما خلصش التأخير');
    await _wait(300);
    expect(await DraftStore.load('u1', 'errand'), {'a': 'مكان'});

    draft.dispose();
    a.dispose();
    b.dispose();
  });

  test('restores only when the app came back after Android closed it', () async {
    final a = TextEditingController();
    final b = TextEditingController();
    final first = make(a, b)..attach([a, b]);
    a.text = 'مسودة';
    await first.flush();
    // قفل أندرويد للعملية: مفيش dispose.
    await markResumed();

    expect(await make(a, b).loadIfResumed(), {'a': 'مسودة'});

    // فتح عادي بعد وقت طويل: مفيش استعادة.
    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(const Duration(hours: 5)));
    expect(await make(a, b).loadIfResumed(), isNull);

    first.dispose();
    a.dispose();
    b.dispose();
  });

  test('leaving the page yourself clears the draft', () async {
    final a = TextEditingController(text: 'x');
    final b = TextEditingController();
    final draft = make(a, b)..attach([a, b]);
    await draft.flush();
    expect(await DraftStore.load('u1', 'errand'), isNotNull);

    draft.dispose();
    await _wait(50);
    expect(await DraftStore.load('u1', 'errand'), isNull);
    a.dispose();
    b.dispose();
  });

  test('a successful submit clears it and later edits do not bring it back', () async {
    final a = TextEditingController(text: 'x');
    final b = TextEditingController();
    final draft = make(a, b)..attach([a, b]);
    await draft.flush();

    await draft.clear();
    a.text = 'بعد الإرسال';
    await _wait(200);
    expect(await DraftStore.load('u1', 'errand'), isNull);

    draft.dispose();
    a.dispose();
    b.dispose();
  });

  test('another account never sees the draft', () async {
    final a = TextEditingController(text: 'سري');
    final b = TextEditingController();
    final draft = make(a, b)..attach([a, b]);
    await draft.flush();
    await markResumed();

    expect(await make(a, b, uid: 'u2').loadIfResumed(), isNull);
    draft.dispose();
    a.dispose();
    b.dispose();
  });

  test('going to the background saves immediately', () async {
    final a = TextEditingController();
    final b = TextEditingController();
    final draft = make(a, b, delay: const Duration(seconds: 30))..attach([a, b]);

    a.text = 'قبل الخلفية';
    draft.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _wait(60);
    expect(await DraftStore.load('u1', 'errand'), {'a': 'قبل الخلفية'});

    draft.dispose();
    a.dispose();
    b.dispose();
  });

  test('fields added later (a second store) are watched too', () async {
    final a = TextEditingController();
    final b = TextEditingController();
    final second = TextEditingController();
    final draft = FormDraft(
      'errand',
      () => {'a': a.text, 'late': second.text},
      uidOf: () => 'u1',
      delay: const Duration(milliseconds: 40),
    )..attach([a, b]);
    draft.watch(second);

    second.text = 'محل تاني';
    await _wait(200);
    expect(await DraftStore.load('u1', 'errand'), {'late': 'محل تاني'});

    draft.dispose();
    a.dispose();
    b.dispose();
    second.dispose();
  });
}
