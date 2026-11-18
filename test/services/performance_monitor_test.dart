import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/performance_monitor.dart';

void main() {
  test('trace preserves the operation result when collection is unavailable', () async {
    final result = await PerformanceMonitor.trace<int>(
      'unit_test_trace',
      () async => 42,
    );
    expect(result, 42);
  });

  test('trace preserves operation errors', () async {
    await expectLater(
      PerformanceMonitor.trace<void>(
        'unit_test_error',
        () async => throw StateError('expected'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('first-event trace preserves stream values', () async {
    final values = await PerformanceMonitor.traceFirstEvent<int>(
      'unit_test_stream',
      Stream<int>.fromIterable([1, 2, 3]),
    ).toList();
    expect(values, [1, 2, 3]);
  });
}
