import 'package:city_store/services/cart_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 11, 26, 18);

  test('خرج وعنده سلة: تذكير بعد ساعة', () {
    final p = CartReminderPolicy();
    final at = p.onLeave(now: t0, hasOpenCart: true);
    expect(at, t0.add(CartReminderPolicy.delay));
    expect(p.pendingAt, at);
  });

  test('خرج من غير سلة: مفيش تذكير', () {
    final p = CartReminderPolicy();
    expect(p.onLeave(now: t0, hasOpenCart: false), isNull);
    expect(p.pendingAt, isNull);
  });

  test('رجع قبل المعاد: التذكير بيتلغي ومفيش فترة انتظار', () {
    final p = CartReminderPolicy()..onLeave(now: t0, hasOpenCart: true);
    expect(p.onReturn(now: t0.add(const Duration(minutes: 20))), isTrue);
    expect(p.pendingAt, isNull);
    expect(p.nextAllowedAt, isNull);
    // يقدر يتذكّر تاني لو خرج تاني.
    expect(p.onLeave(now: t0.add(const Duration(minutes: 30)), hasOpenCart: true), isNotNull);
  });

  test('التذكير اتبعت: مفيش تذكير تاني قبل 20 ساعة', () {
    final p = CartReminderPolicy()..onLeave(now: t0, hasOpenCart: true);
    final fired = t0.add(CartReminderPolicy.delay);
    // بنلغي حتى بعد المعاد، علشان لو أندرويد أخّر الإشعار ما يظهرش والتطبيق مفتوح.
    expect(p.onReturn(now: fired.add(const Duration(minutes: 5))), isTrue);
    expect(p.nextAllowedAt, fired.add(CartReminderPolicy.cooldown));

    expect(p.onLeave(now: fired.add(const Duration(hours: 2)), hasOpenCart: true), isNull);
    expect(
      p.onLeave(now: fired.add(CartReminderPolicy.cooldown), hasOpenCart: true),
      isNotNull,
    );
  });

  test('خروج تاني والتذكير لسه متجدول: ما نكررش', () {
    final p = CartReminderPolicy()..onLeave(now: t0, hasOpenCart: true);
    expect(p.onLeave(now: t0.add(const Duration(minutes: 1)), hasOpenCart: true), isNull);
  });

  test('بعت طلبه أو فضّى السلة: التذكير بيتلغي', () {
    final p = CartReminderPolicy()..onLeave(now: t0, hasOpenCart: true);
    expect(p.onCartsCleared(), isTrue);
    expect(p.pendingAt, isNull);
    expect(p.onCartsCleared(), isFalse);
  });

  test('نص الإشعار بيذكر المحل لو معروف ويستخدم «سلتك»', () {
    expect(CartReminderPolicy.body('بقالة الحاج سيد'), contains('سلتك من بقالة الحاج سيد'));
    expect(CartReminderPolicy.body(null), startsWith('سلتك'));
    expect(CartReminderPolicy.body('  '), startsWith('سلتك لسه'));
  });

  test('رجع في نفس لحظة المعاد: بنلغي ونبدأ فترة الانتظار', () {
    final p = CartReminderPolicy()..onLeave(now: t0, hasOpenCart: true);
    final at = t0.add(CartReminderPolicy.delay);
    expect(p.onReturn(now: at), isTrue);
    expect(p.nextAllowedAt, at.add(CartReminderPolicy.cooldown));
  });

  test('رجوع من غير تذكير متجدول: مفيش إلغاء', () {
    expect(CartReminderPolicy().onReturn(now: t0), isFalse);
  });
}
