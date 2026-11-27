import 'package:city_store/screens/admin_photo_library_page.dart';
import 'package:city_store/services/photo_library.dart';
import 'package:city_store/utils/product_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('اسم الصنف من اسم الملف', () {
    test('اسم الملف بيبقى اسم الصنف', () {
      expect(libraryNameFromFilename('طماطم.jpg'), 'طماطم');
      expect(libraryNameFromFilename('زيت_موبيل-1لتر.png'), 'زيت موبيل 1لتر');
      expect(libraryNameFromFilename('/storage/emulated/0/Download/فراخ بيضا (1).webp'), 'فراخ بيضا');
      expect(libraryNameFromFilename('scaled_onion.jpeg'), 'onion');
    });

    test('أسماء الكاميرا والواتساب والأرقام بترجع فاضية', () {
      expect(libraryNameFromFilename('IMG_20261127_101010.jpg'), '');
      expect(libraryNameFromFilename('IMG-20261127-WA0003.jpg'), '');
      expect(libraryNameFromFilename('PXL_20261127_1.jpg'), '');
      expect(libraryNameFromFilename('Screenshot_2026.png'), '');
      expect(libraryNameFromFilename('WhatsApp Image 2026-11-27 at 10.jpeg'), '');
      expect(libraryNameFromFilename('1000012345.jpg'), '');
    });
  });

  LibraryBulkDraft draft(String name, {int size = 1000}) =>
      LibraryBulkDraft(filename: '$name.jpg', name: name, size: size);

  Future<List<LibraryBulkDraft>?> openReview(
    WidgetTester tester,
    List<LibraryBulkDraft> drafts, {
    Set<String> existing = const {},
  }) async {
    List<LibraryBulkDraft>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<LibraryBulkDraft>>(
                MaterialPageRoute(
                  builder: (_) => LibraryBulkReviewPage(drafts: drafts, existingKeys: existing),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('مراجعة: الاسم الفاضي بيقفل الرفع لحد ما يتكتب', (tester) async {
    final drafts = [draft('طماطم'), draft('')];
    await openReview(tester, drafts);
    expect(find.byKey(const Key('photo-library-bulk-problem')), findsOneWidget);
    final upload = find.byKey(const Key('photo-library-bulk-upload'));
    expect(tester.widget<FilledButton>(upload).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('photo-library-bulk-name-1')), 'بطاطس');
    await tester.pump();
    expect(find.byKey(const Key('photo-library-bulk-problem')), findsNothing);
    expect(tester.widget<FilledButton>(upload).onPressed, isNotNull);
    expect(find.text('ارفع 2 صورة'), findsOneWidget);
  });

  testWidgets('مراجعة: اسم متكرر بيتنبه، والصورة الكبيرة بتتستبعد', (tester) async {
    final drafts = [draft('بصل'), draft('بصل'), draft('جبنة', size: 6 * 1024 * 1024)];
    await openReview(tester, drafts, existing: {normalizeProductPhotoKey('جبنة')});
    expect(find.text('فيه اسمين متكررين، غيّر واحد منهم'), findsOneWidget);
    expect(find.text('أكبر من 5MB، مش هتترفع'), findsOneWidget);

    // شيل العلامة من التكرار التاني فالرفع يتفتح لصورة واحدة.
    await tester.tap(find.byKey(const Key('photo-library-bulk-include-1')));
    await tester.pump();
    expect(find.text('ارفع 1 صورة'), findsOneWidget);
  });

  testWidgets('مراجعة: الاسم الموجود في المكتبة بيقول إن الصورة هتتبدل وبيرجع المختار', (tester) async {
    final drafts = [draft('طماطم'), draft('خيار')];
    List<LibraryBulkDraft>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<LibraryBulkDraft>>(
                MaterialPageRoute(
                  builder: (_) => LibraryBulkReviewPage(
                    drafts: drafts,
                    existingKeys: {normalizeProductPhotoKey('طماطم')},
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('الاسم موجود في المكتبة، الصورة القديمة هتتبدل'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo-library-bulk-upload')));
    await tester.pumpAndSettle();
    expect(result?.map((d) => d.name), ['طماطم', 'خيار']);
  });
}
