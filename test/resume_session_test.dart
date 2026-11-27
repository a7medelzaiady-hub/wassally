// #326: returning after Android killed Wasally in the background.
import 'package:city_store/services/resume_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 11, 27, 21, 0);

  setUp(ResumeSession.reset);

  test('return within 30 minutes restores the last screen once (same account)', () async {
    SharedPreferences.setMockInitialValues({});
    ResumeSession.setLocation('u1', 'shell:2');
    await ResumeSession.markBackground(now: t0);
    await Future<void>.delayed(Duration.zero);

    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(const Duration(minutes: 5)));
    expect(ResumeSession.resumedRecently, isTrue);
    expect(ResumeSession.takeLocation('u1'), 'shell:2');
    expect(ResumeSession.takeLocation('u1'), isNull, reason: 'مرة واحدة بس');
  });

  test('another account never gets the previous screen', () async {
    SharedPreferences.setMockInitialValues({});
    ResumeSession.setLocation('u1', 'store:abc');
    await ResumeSession.markBackground(now: t0);
    await Future<void>.delayed(Duration.zero);

    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(const Duration(minutes: 1)));
    expect(ResumeSession.takeLocation('u2'), isNull);
  });

  test('a later open is a fresh start (ads allowed, no restore)', () async {
    SharedPreferences.setMockInitialValues({});
    ResumeSession.setLocation('u1', 'shell:1');
    await ResumeSession.markBackground(now: t0);
    await Future<void>.delayed(Duration.zero);

    ResumeSession.reset();
    await ResumeSession.load(now: t0.add(ResumeSession.window));
    expect(ResumeSession.resumedRecently, isFalse);
    expect(ResumeSession.takeLocation('u1'), isNull);
  });

  test('first ever launch is a fresh start', () async {
    SharedPreferences.setMockInitialValues({});
    await ResumeSession.load(now: t0);
    expect(ResumeSession.resumedRecently, isFalse);
  });
}
