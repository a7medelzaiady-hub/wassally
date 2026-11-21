import 'package:city_store/models/product.dart';
import 'package:city_store/widgets/option_groups_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات محرر خيارات الصنف (زر «تم» / التعديل / الحذف / الحدود).
/// الهدف: إثبات إن الضغط على «تم» بيرجّع القيم بدون أي استثناء بعد قفل الحوار.
Future<void> _open(
  WidgetTester tester,
  List<OptionGroup> initial,
  void Function(List<OptionGroup>?) onResult,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async =>
                onResult(await showOptionGroupsEditor(context, initial)),
            child: const Text('افتح'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('إضافة مجموعة جديدة ثم «تم» ترجّع المجموعة بأسعارها بدون استثناء', (tester) async {
    List<OptionGroup>? result;
    await _open(tester, const [], (r) => result = r);
    await tester.tap(find.text('إضافة مجموعة خيارات'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'الإضافات');
    await tester.enterText(fields.at(1), 'سادة\nمظبوط\nكوكيز = 90');
    await tester.tap(find.text('تم'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(result, isNotNull);
    expect(result, hasLength(1));
    expect(result!.single.title, 'الإضافات');
    expect(result!.single.options.map((o) => o.name), ['سادة', 'مظبوط', 'كوكيز']);
    expect(result!.single.options.last.price, 90);
  });

  testWidgets('إعادة فتح مجموعة محفوظة ثم تعديلها وحفظها', (tester) async {
    List<OptionGroup>? result;
    final saved = [
      OptionGroup('السكر', [ProductOption('سادة'), ProductOption('زيادة', 5)], min: 1),
    ];
    await _open(tester, saved, (r) => result = r);
    expect(find.text('السكر'), findsOneWidget);
    expect(find.textContaining('زيادة = 5'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'درجة السكر');
    await tester.tap(find.text('تم'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(result!.single.title, 'درجة السكر');
    expect(result!.single.required, isTrue);
    expect(result!.single.options.last.price, 5);
    // تحويل المجموعة لخريطة وإعادة قراءتها (نفس اللي بيتكتب في Firestore) بيرجّع نفس القيم.
    final again = OptionGroup.tryParse(result!.single.toMap())!;
    expect(again.title, 'درجة السكر');
    expect(again.min, 1);
    expect(again.options.map((o) => o.name), ['سادة', 'زيادة']);
  });

  testWidgets('حذف مجموعة ثم «تم» ما يوقعش التطبيق', (tester) async {
    List<OptionGroup>? result;
    final saved = [
      OptionGroup('أ', [ProductOption('1'), ProductOption('2')]),
      OptionGroup('ب', [ProductOption('3'), ProductOption('4')]),
    ];
    await _open(tester, saved, (r) => result = r);
    await tester.tap(find.byTooltip('حذف المجموعة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تم'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(result!.map((g) => g.title), ['ب']);
  });

  testWidgets('المجموعة الناقصة (بدون اسم أو بدون اختيارات) بتتجاهل', (tester) async {
    List<OptionGroup>? result;
    await _open(tester, const [], (r) => result = r);
    await tester.tap(find.text('إضافة مجموعة خيارات'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'اسم بدون اختيارات');
    await tester.tap(find.text('تم'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(result, isEmpty);
  });

  testWidgets('إلغاء الحوار بيرجّع null', (tester) async {
    List<OptionGroup>? result = [];
    await _open(tester, const [], (r) => result = r);
    await tester.tap(find.text('إلغاء'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(result, isNull);
  });

  testWidgets('حد المجموعات: زر الإضافة بيختفي عند 10 (مطابق للقواعد)', (tester) async {
    final ten = [
      for (var i = 0; i < kMaxOptionGroups; i++)
        OptionGroup('م$i', [ProductOption('a'), ProductOption('b')]),
    ];
    await _open(tester, ten, (_) {});
    expect(find.text('إضافة مجموعة خيارات'), findsNothing);
    expect(kMaxOptionGroups, 10);
  });

  test('حد الاختيارات في المجموعة وقيم max/min بتتظبط عند القراءة', () {
    final tooMany = {
      'title': 'ز',
      'min': 9,
      'max': 99,
      'options': [
        for (var i = 0; i < 3; i++) {'name': 'o$i', 'price': 0},
      ],
    };
    final g = OptionGroup.tryParse(tooMany)!;
    expect(g.max, 3);
    expect(g.min, 3);
    expect(OptionGroup.tryParse({'title': '', 'options': []}), isNull);
    expect(OptionGroup.tryParse('x'), isNull);
    expect(parseOptionGroups('x'), isEmpty);
    expect(parseOptionGroups(null), isEmpty);
  });
}
