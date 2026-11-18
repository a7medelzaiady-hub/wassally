import 'package:city_store/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    test('التذكير لا يظهر أثناء التأجيل أو للتحديث الإجباري أو بعد عرضه', () {
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: false, snoozed: true, alreadyShown: false,
      ), isFalse);
      expect(UpdateService.shouldShowResumeReminder(
        available: true, force: true, snoozed: false, alreadyShown: false,
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

    test('التحديث الإجباري يتجاوز التأجيل ولا يمكن إخفاؤه', () {
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
