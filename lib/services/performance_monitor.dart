import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart';

/// Lightweight Firebase Performance traces. No user IDs, order IDs, locations,
/// addresses, request bodies, or other customer data are attached.
class PerformanceMonitor {
  PerformanceMonitor._();

  static String? _lastScreenName;

  static bool get _platformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _canCollect =>
      !kDebugMode && _platformSupported && Firebase.apps.isNotEmpty;

  /// Enables automatic startup/network collection in release builds only.
  static Future<void> configure() async {
    if (!_platformSupported || Firebase.apps.isEmpty) return;
    try {
      await FirebasePerformance.instance
          .setPerformanceCollectionEnabled(!kDebugMode);
    } catch (_) {
      // Diagnostics must never prevent the app from starting.
    }
  }

  /// Measures one asynchronous operation without changing its result/errors.
  static Future<T> trace<T>(
    String name,
    Future<T> Function() action,
  ) async {
    final trace = await _start(name);
    try {
      return await action();
    } finally {
      await _stop(trace);
    }
  }

  /// Measures only the first snapshot, not the lifetime of a Firestore listener.
  static Stream<T> traceFirstEvent<T>(String name, Stream<T> stream) async* {
    final trace = await _start(name);
    var stopped = false;
    try {
      await for (final value in stream) {
        if (!stopped) {
          stopped = true;
          await _stop(trace);
        }
        yield value;
      }
    } finally {
      if (!stopped) await _stop(trace);
    }
  }

  /// Measures the first rendered frame after switching a main navigation tab.
  static void screenOpened(String screenName) {
    if (!_canCollect || _lastScreenName == screenName) return;
    _lastScreenName = screenName;
    unawaited(_finishScreenOpen(screenName));
  }

  static Future<void> _finishScreenOpen(String screenName) async {
    final trace = await _start('screen_open_$screenName');
    if (trace == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_stop(trace));
    });
  }

  /// أرقام بدء التشغيل بالمللي ثانية (من غير قيم سالبة).
  /// `bootstrap_ms`: من أول main لحد runApp (تهيئة Firebase وApp Check والسمة).
  /// `first_frame_ms`: من أول main لحد أول إطار اترسم على الشاشة.
  static Map<String, int> startupMetrics({
    required Duration bootstrap,
    required Duration firstFrame,
  }) => {
    'bootstrap_ms': bootstrap.inMilliseconds < 0 ? 0 : bootstrap.inMilliseconds,
    'first_frame_ms': firstFrame.inMilliseconds < 0 ? 0 : firstFrame.inMilliseconds,
  };

  /// بيسجّل trace واحد `dart_startup` فيه أرقام الجزء اللي في Dart بس.
  /// الغرض: نفرّق بين بطء الكود وبين قياس `_app_start` بتاع أندرويد اللي بيبدأ
  /// من لحظة تشغيل العملية (حتى لو اشتغلت في الخلفية بسبب إشعار).
  static Future<void> recordStartup(Map<String, int> metrics) async {
    final trace = await _start('dart_startup');
    if (trace == null) return;
    try {
      metrics.forEach(trace.setMetric);
    } catch (_) {}
    await _stop(trace);
  }

  static Future<Trace?> _start(String name) async {
    if (!_canCollect) return null;
    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      return trace;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _stop(Trace? trace) async {
    if (trace == null) return;
    try {
      await trace.stop();
    } catch (_) {
      // Diagnostics must never change the app's business operation.
    }
  }
}
