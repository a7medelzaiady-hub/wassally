import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A transient HTTP/network/5xx failure; the committed order event may be retried.
class RetryableOrderPushException implements Exception {
  const RetryableOrderPushException();
}

/// A 4xx/auth/validation error; retrying the same payload would not help.
class PermanentOrderPushException implements Exception {
  const PermanentOrderPushException();
}

class PendingOrderPush {
  const PendingOrderPush({
    required this.uid,
    required this.orderId,
    required this.event,
    required this.occurredAtMs,
    this.status,
  });

  final String uid;
  final String orderId;
  final String event;
  final String? status;
  final int occurredAtMs;

  String get key => jsonEncode([uid, orderId, event, status ?? '']);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'orderId': orderId,
        'event': event,
        if (status != null) 'status': status,
        'occurredAtMs': occurredAtMs,
      };

  static PendingOrderPush? fromJson(Object? value) {
    if (value is! Map) return null;
    final uid = value['uid'], orderId = value['orderId'];
    final event = value['event'], at = value['occurredAtMs'];
    final status = value['status'];
    if (uid is! String || uid.isEmpty ||
        orderId is! String || orderId.isEmpty ||
        event is! String || !{'created', 'assigned', 'ready', 'status'}.contains(event) ||
        at is! int || (status != null && status is! String)) {
      return null;
    }
    return PendingOrderPush(
      uid: uid,
      orderId: orderId,
      event: event,
      status: status as String?,
      occurredAtMs: at,
    );
  }
}

/// Persistent local retry queue. Never reads Firestore, starts a Firestore listener,
/// or queues payloads older than the Worker's 10-minute validity window.
class OrderEventOutbox {
  OrderEventOutbox({
    required Future<void> Function(PendingOrderPush) send,
    Future<void> Function(Duration)? sleep,
    int Function()? clockMs,
    this.storageKey = 'wasally_order_events_pending_v1',
  })  : _send = send,
        _sleep = sleep ?? _defaultSleep,
        _clockMs = clockMs ?? _systemClock;

  final Future<void> Function(PendingOrderPush) _send;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clockMs;
  final String storageKey;
  final Set<String> _active = {};
  Future<void> _lock = Future<void>.value();

  static const int maxAgeMs = 10 * 60 * 1000;
  static const int maxEntries = 40;
  static const List<Duration> retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;
  static Future<void> _defaultSleep(Duration duration) => Future<void>.delayed(duration);

  Future<T> _withLock<T>(Future<T> Function() action) {
    final current = _lock.then((_) => action());
    _lock = current.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return current;
  }

  bool _fresh(PendingOrderPush item) =>
      item.occurredAtMs <= _clockMs() + 60 * 1000 &&
      _clockMs() - item.occurredAtMs < maxAgeMs;

  Future<List<PendingOrderPush>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString(storageKey) ?? '[]');
      if (raw is! List) return [];
      return raw.map(PendingOrderPush.fromJson)
          .whereType<PendingOrderPush>()
          .where(_fresh)
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<PendingOrderPush> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(
      items.where(_fresh).toList().reversed.take(maxEntries).toList().reversed
          .map((item) => item.toJson()).toList(),
    ));
  }

  Future<void> _remove(String key) => _withLock(() async {
        final pending = await _load();
        pending.removeWhere((item) => item.key == key);
        await _save(pending);
      });

  /// Persist before attempting: a process killed during the backoff will not lose an event.
  Future<void> recordAndSend(PendingOrderPush item) async {
    if (!_fresh(item)) return;
    await _withLock(() async {
      final pending = await _load();
      pending.removeWhere((entry) => entry.key == item.key);
      pending.add(item);
      await _save(pending);
    });
    await _attempt(item, withBackoff: true);
  }

  Future<void> replay(String? currentUid) async {
    if (currentUid == null || currentUid.isEmpty) return;
    final pending = await _withLock(() async {
      final items = await _load();
      // Also clear expired records when opening/resuming the app.
      await _save(items);
      return items.where((item) => item.uid == currentUid).toList();
    });
    for (final item in pending) {
      // Replays are single-shot to avoid a 22-second retry storm on each network poll.
      await _attempt(item, withBackoff: false);
    }
  }

  Future<bool> get hasPending => _withLock(() async {
        final pending = await _load();
        await _save(pending);
        return pending.isNotEmpty;
      });

  Future<void> _attempt(PendingOrderPush item, {required bool withBackoff}) async {
    if (!_active.add(item.key)) return;
    try {
      final attempts = withBackoff ? retryDelays.length + 1 : 1;
      for (var attempt = 0; attempt < attempts; attempt++) {
        if (!_fresh(item)) {
          await _remove(item.key);
          return;
        }
        if (attempt > 0) await _sleep(retryDelays[attempt - 1]);
        if (!_fresh(item)) {
          await _remove(item.key);
          return;
        }
        try {
          await _send(item);
          await _remove(item.key);
          return;
        } on PermanentOrderPushException {
          await _remove(item.key);
          return;
        } catch (_) {
          // Only the HTTP adapter below should throw retryable failures.
          // Keep the locally stored event if the final attempt fails.
        }
      }
    } finally {
      _active.remove(item.key);
    }
  }
}
