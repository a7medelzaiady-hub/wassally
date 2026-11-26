import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'cart_book.dart';

/// قرار «تذكير السلة المنسية» من غير أي اعتماد على المنصة (علشان يتختبر).
///
/// - لما العميل يخرج من التطبيق وعنده سلة لسه ما اتبعتتش → نذكّره بعد [delay].
/// - لو رجع قبل المعاد → التذكير بيتلغي (هو شاف سلته بنفسه).
/// - لو التذكير اتبعت فعلًا → مفيش تذكير تاني قبل [cooldown]، علشان ما نزهقوش.
class CartReminderPolicy {
  static const delay = Duration(hours: 1);
  static const cooldown = Duration(hours: 20);

  /// معاد التذكير اللي متجدول حاليًا (لو فيه).
  DateTime? pendingAt;

  /// أقرب وقت مسموح فيه بتذكير جديد.
  DateTime? nextAllowedAt;

  CartReminderPolicy({this.pendingAt, this.nextAllowedAt});

  /// العميل خرج من التطبيق. بيرجع معاد التذكير لو لازم نجدوله، أو null.
  DateTime? onLeave({required DateTime now, required bool hasOpenCart}) {
    if (!hasOpenCart || pendingAt != null) return null;
    final allowed = nextAllowedAt;
    if (allowed != null && now.isBefore(allowed)) return null;
    return pendingAt = now.add(delay);
  }

  /// العميل رجع للتطبيق. بيرجع true لو لازم نلغي تذكير لسه ما اتبعتش.
  bool onReturn({required DateTime now}) {
    final at = pendingAt;
    if (at == null) return false;
    pendingAt = null;
    if (now.isBefore(at)) return true;
    // التذكير اتبعت وهو بره التطبيق.
    nextAllowedAt = at.add(cooldown);
    return false;
  }

  /// العميل بعت طلبه أو فضّى سلاته: أي تذكير متجدول ملوش لازمة.
  bool onCartsCleared() {
    if (pendingAt == null) return false;
    pendingAt = null;
    return true;
  }

  /// نص الإشعار.
  static String body(String? storeName) {
    final name = storeName?.trim() ?? '';
    return name.isEmpty
        ? 'سلتك لسه مستنياك. كمّل طلبك في دقيقة.'
        : 'سلتك من $name لسه مستنياك. كمّل طلبك في دقيقة.';
  }
}

/// الإشعار المحلي نفسه (من غير FCM ومن غير Firestore: صفر قراءات وصفر كتابات).
class CartReminder with WidgetsBindingObserver {
  CartReminder._();
  static final CartReminder instance = CartReminder._();

  static const _notificationId = 7001;
  static const _pendingKey = 'cart_reminder_pending_ms';
  static const _nextKey = 'cart_reminder_next_ms';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _policy = CartReminderPolicy();
  bool _ready = false;

  /// بتتنادى مرة بعد runApp. أي فشل بيتجاهل: الميزة تكميلية.
  Future<void> start() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getInt(_pendingKey);
      final n = prefs.getInt(_nextKey);
      _policy
        ..pendingAt = p == null ? null : DateTime.fromMillisecondsSinceEpoch(p)
        ..nextAllowedAt = n == null ? null : DateTime.fromMillisecondsSinceEpoch(n);
      _ready = true;
      WidgetsBinding.instance.addObserver(this);
      carts.addListener(_onCartsChanged);
      // التطبيق اتفتح دلوقتي، فده رجوع.
      await _handleReturn();
    } catch (e) {
      debugPrint('Cart reminder disabled: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
    if (state == AppLifecycleState.paused) {
      _handleLeave();
    } else if (state == AppLifecycleState.resumed) {
      _handleReturn();
    }
  }

  Future<void> _handleLeave() async {
    final at = _policy.onLeave(
      now: DateTime.now(),
      hasOpenCart: carts.totalItems > 0,
    );
    if (at == null) return;
    try {
      await _plugin.zonedSchedule(
        _notificationId,
        'وصّلي',
        CartReminderPolicy.body(_storeName()),
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'cart_reminder',
            'تذكير السلة',
            channelDescription: 'تذكير لو سبت سلة من غير ما تكمّل الطلب',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      _policy.pendingAt = null;
      debugPrint('Cart reminder schedule failed: $e');
    }
    await _persist();
  }

  Future<void> _handleReturn() async {
    if (_policy.onReturn(now: DateTime.now())) await _cancel();
    await _persist();
  }

  void _onCartsChanged() {
    if (carts.totalItems > 0) return;
    if (_policy.onCartsCleared()) {
      _cancel();
      _persist();
    }
  }

  String? _storeName() {
    final active = carts.active;
    if (!active.isEmpty && active.submittedOrderId == null) return active.storeName;
    for (final c in carts.parked) {
      if (c.submittedOrderId == null) return c.storeName;
    }
    return null;
  }

  Future<void> _cancel() async {
    try {
      await _plugin.cancel(_notificationId);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = _policy.pendingAt;
      final n = _policy.nextAllowedAt;
      if (p == null) {
        await prefs.remove(_pendingKey);
      } else {
        await prefs.setInt(_pendingKey, p.millisecondsSinceEpoch);
      }
      if (n == null) {
        await prefs.remove(_nextKey);
      } else {
        await prefs.setInt(_nextKey, n.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }
}
