import 'package:city_store/widgets/star_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('النجوم ما بتطلعش برّه مساحة ضيقة (من غير overflow) والفاضية رمادي', (tester) async {
    var picked = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          // نفس عرض محتوى الحوار على موبايل صغير تقريبًا.
          child: SizedBox(
            width: 200,
            child: StarPicker(value: 3, size: 40, onChanged: (v) => picked = v),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons, hasLength(5));
    expect(icons.where((i) => i.color == StarPicker.emptyColor), hasLength(2));
    expect(icons.where((i) => i.color != StarPicker.emptyColor), hasLength(3));

    await tester.tap(find.byKey(const ValueKey('star_5')));
    expect(picked, 5);
  });
}
