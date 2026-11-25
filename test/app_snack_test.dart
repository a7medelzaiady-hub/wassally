import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/widgets/app_snack.dart';

void main() {
  test('نوع الرسالة بيتعرف من كلامها', () {
    expect(guessSnackKind('تم إرسال طلبك السريع'), AppSnackKind.success);
    expect(guessSnackKind('تعذر رفع الصورة، جرّب تاني.'), AppSnackKind.error);
    expect(guessSnackKind('اكتب اسمك ورقم الموبايل'), AppSnackKind.error);
    expect(guessSnackKind('جاري تحديد موقعك...'), AppSnackKind.info);
  });

  testWidgets('الرسالة بتظهر في الإطار الموحّد بأيقونة وعنوان', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              appSnack('احتفظ برمز التسليم', title: 'تم إرسال طلبك بنجاح'),
            ),
            child: const Text('show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('تم إرسال طلبك بنجاح'), findsOneWidget);
    expect(find.text('احتفظ برمز التسليم'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
