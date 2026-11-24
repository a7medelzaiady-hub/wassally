import 'package:city_store/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('بروتوكول الطلب القديم يعرض تحديث إجباري دون زر لاحقًا',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => UpdateService.showProtocolUpdateRequired(context),
          child: const Text('راجع الإصدار'),
        ),
      )),
    ));
    await tester.tap(find.text('راجع الإصدار'));
    await tester.pumpAndSettle();
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(find.text('لاحقاً'), findsNothing);
    expect(find.textContaining('المنتجات هتفضل محفوظة'), findsOneWidget);
    // تنظيف نافذة الاختبار حتى لا تبقى حالة الحماية فعّالة للاختبارات التالية.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
  });

  group('UpdateService.isNewer', () {
    test('إصدار أحدث', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isTrue);
      expect(UpdateService.isNewer('1.2.0', '1.10.0'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.1'), isTrue);
    });

    test('نفس الإصدار أو أقدم', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.1'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isFalse);
      expect(UpdateService.isNewer('1.0.1', '1.0'), isFalse);
    });

    test('الأصفار الزايدة ورقم البناء مبيأثروش', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.1.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0+3', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0+1', '1.0.1+9'), isTrue);
    });
  });

  group('UpdateService.isNewerRelease', () {
    test('يكتشف رقم بناء أحدث حتى لو الإصدار نفسه', () {
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.0.0', currentBuild: 8,
        latestVersion: '1.0.0', latestBuild: 9,
      ), isTrue);
    });

    test('لا يعرض تحديث لنفس رقم البناء أو الأقدم', () {
      for (final build in [7, 8]) {
        expect(UpdateService.isNewerRelease(
          currentVersion: '1.0.0', currentBuild: 8,
          latestVersion: '1.0.0', latestBuild: build,
        ), isFalse);
      }
    });

    test('يبقى متوافقًا مع المستندات القديمة بدون latest_build', () {
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.0.0', currentBuild: 8,
        latestVersion: '1.0.0',
      ), isFalse);
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.0.0', currentBuild: 8,
        latestVersion: '1.0.1',
      ), isTrue);
    });

    test('لا يعلن عن بناء أحدث لإصدار أقدم', () {
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.1.0', currentBuild: 8,
        latestVersion: '1.0.0', latestBuild: 99,
      ), isFalse);
    });

    test('يقبل latest_build كنص رقمي ويتجاهل القيم غير الصالحة', () {
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.0.0', currentBuild: 8,
        latestVersion: '1.0.0', latestBuild: '9',
      ), isTrue);
      expect(UpdateService.isNewerRelease(
        currentVersion: '1.0.0', currentBuild: 8,
        latestVersion: '1.0.0', latestBuild: 'invalid',
      ), isFalse);
    });
  });

  group('Update reminder scheduling', () {
    final now = DateTime(2026, 11, 18, 12);

    test('التأجيل يستمر 24 ساعة كاملة', () {
      final until = UpdateService.snoozeUntil(now);
      expect(until, DateTime(2026, 11, 19, 12));
      expect(now.isBefore(until), isTrue);
      expect(until.isAfter(now.add(const Duration(hours: 23, minutes: 59))), isTrue);
    });

    test('الفحص عند الرجوع لا يتكرر قبل مرور 6 ساعات', () {
      expect(
        UpdateService.shouldRefreshOnResume(now, now.add(const Duration(hours: 5, minutes: 59))),
        isFalse,
      );
      expect(
        UpdateService.shouldRefreshOnResume(now, now.add(const Duration(hours: 6))),
        isTrue,
      );
    });

    test('التذكير العادي يحترم التأجيل ويمنع التكرار', () {
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: false, snoozed: true, alreadyShown: false,
      ), isFalse);
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: false, snoozed: false, alreadyShown: true,
      ), isFalse);
    });

    test('يظهر التذكير مرة واحدة فقط بعد انتهاء التأجيل', () {
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: false, snoozed: false, alreadyShown: false,
      ), isTrue);
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: false, snoozed: false, alreadyShown: true,
      ), isFalse);
    });

    test('التحديث الإجباري يتجاوز التأجيل ومنع التكرار', () {
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: true, snoozed: true, alreadyShown: true,
      ), isTrue);
    });

    test('لا يظهر إذا لم يوجد تحديث متاح', () {
      expect(UpdateService.shouldShowResumeReminder(
        available: false, force: false, snoozed: false, alreadyShown: false,
      ), isFalse);
    });
  });
}
