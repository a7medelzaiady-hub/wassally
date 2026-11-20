import 'package:city_store/services/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('أرقام بدء التشغيل بالمللي ثانية ومن غير قيم سالبة', () {
    expect(
      PerformanceMonitor.startupMetrics(
        bootstrap: const Duration(milliseconds: 820),
        firstFrame: const Duration(milliseconds: 1310),
      ),
      {'bootstrap_ms': 820, 'first_frame_ms': 1310},
    );
    expect(
      PerformanceMonitor.startupMetrics(
        bootstrap: const Duration(milliseconds: -5),
        firstFrame: Duration.zero,
      ),
      {'bootstrap_ms': 0, 'first_frame_ms': 0},
    );
  });

  test('التسجيل ما بيعملش حاجة في الاختبار (من غير Firebase) وما بيرميش خطأ', () async {
    await PerformanceMonitor.recordStartup({'bootstrap_ms': 1});
  });
}
