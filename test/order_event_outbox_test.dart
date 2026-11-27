import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:city_store/services/order_event_outbox.dart';
import 'package:city_store/services/order_gateway.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PendingOrderPush item(int now, {String uid = 'courier'}) => PendingOrderPush(
        uid: uid,
        orderId: 'order_123',
        event: 'status',
        status: 'preparing',
        occurredAtMs: now,
      );

  test('only retry network-transient gateway statuses including Worker throttle', () {
    for (final status in [429, 500, 502, 503, 504]) {
      expect(OrderGateway.shouldRetryOrderPushStatus(status), isTrue);
    }
    for (final status in [200, 400, 401, 403, 404, 409]) {
      expect(OrderGateway.shouldRetryOrderPushStatus(status), isFalse);
    }
  });

  test('successful send drops the persisted event immediately', () async {
    var requests = 0;
    final outbox = OrderEventOutbox(
      clockMs: () => 100000,
      send: (_) async { requests++; },
    );
    await outbox.recordAndSend(item(100000));
    expect(requests, 1);
    expect(await outbox.hasPending, isFalse);
  });

  test('network and 5xx failures get exactly three retries at 2/5/15 seconds', () async {
    final delays = <Duration>[];
    var requests = 0;
    final outbox = OrderEventOutbox(
      clockMs: () => 100000,
      sleep: (delay) async { delays.add(delay); },
      send: (_) async {
        requests++;
        throw const RetryableOrderPushException();
      },
    );
    await outbox.recordAndSend(item(100000));
    expect(requests, 4);
    expect(delays, OrderEventOutbox.retryDelays);
    expect(await outbox.hasPending, isTrue);

    final restored = OrderEventOutbox(
      clockMs: () => 100100,
      send: (_) async { requests++; },
    );
    await restored.replay('courier');
    expect(requests, 5);
    expect(await restored.hasPending, isFalse);
  });

  test('one temporary failure then success never leaves duplicate events', () async {
    var attempts = 0;
    final outbox = OrderEventOutbox(
      clockMs: () => 100000,
      sleep: (_) async {},
      send: (_) async {
        attempts++;
        if (attempts == 1) throw const RetryableOrderPushException();
      },
    );
    await outbox.recordAndSend(item(100000));
    expect(attempts, 2);
    expect(await outbox.hasPending, isFalse);
  });

  test('permanent 4xx failures are not retried or persisted', () async {
    var attempts = 0;
    final outbox = OrderEventOutbox(
      clockMs: () => 100000,
      sleep: (_) async {},
      send: (_) async {
        attempts++;
        throw const PermanentOrderPushException();
      },
    );
    await outbox.recordAndSend(item(100000));
    expect(attempts, 1);
    expect(await outbox.hasPending, isFalse);
  });

  test('recovery only sends for current user and discards events over 10 minutes', () async {
    var clock = 100000;
    final outbox = OrderEventOutbox(
      clockMs: () => clock,
      sleep: (_) async {},
      send: (_) async { throw const RetryableOrderPushException(); },
    );
    await outbox.recordAndSend(item(clock, uid: 'first'));
    await outbox.recordAndSend(item(clock, uid: 'second'));
    final sent = <String>[];
    final recovery = OrderEventOutbox(
      clockMs: () => clock,
      send: (value) async { sent.add(value.uid); },
    );
    await recovery.replay('second');
    expect(sent, ['second']);
    expect(await recovery.hasPending, isTrue);
    clock += OrderEventOutbox.maxAgeMs;
    await recovery.replay('first');
    expect(sent, ['second']); // stale events must never be replayed
    expect(await recovery.hasPending, isFalse);
  });
}
