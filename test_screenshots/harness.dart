import 'dart:io';
import 'dart:typed_data';

import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

bool _fontsLoaded = false;

/// Loads the real app font (Tajawal) and Material icons so screenshots look
/// like the phone instead of the default test boxes.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final tajawal = FontLoader('Tajawal');
  for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold', 'Black']) {
    final bytes = File('assets/fonts/Tajawal-$weight.ttf').readAsBytesSync();
    tajawal.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await tajawal.load();

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
      await loader.load();
    }
  }
}

Future<void> _precacheImages(WidgetTester tester) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isEmpty) return;
  final context = tester.element(find.byType(Image).first);
  await tester.runAsync(() async {
    for (final image in images) {
      try {
        await precacheImage(image.image, context);
      } catch (_) {}
    }
  });
}

/// Renders [child] like the app (RTL Arabic, app theme, phone padding) and
/// writes `goldens/<name>.png`.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
  EdgeInsets padding = const EdgeInsets.only(top: 28, bottom: 16),
  Future<void> Function(WidgetTester tester)? before,
}) async {
  await loadAppFonts();
  const dpr = 2.0;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = FakeViewPadding(
    top: padding.top * dpr,
    bottom: padding.bottom * dpr,
  );
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
  });

  await tester.pumpWidget(RepaintBoundary(
    key: const Key('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: child,
    ),
  ));
  await tester.pump();
  await _precacheImages(tester);
  await tester.pump(const Duration(milliseconds: 50));
  if (before != null) await before(tester);
  await _precacheImages(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(find.byKey(const Key('shot')), matchesGoldenFile('goldens/$name.png'));
}
