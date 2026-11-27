// #326: no blank white screen when returning to Wasally from the background.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/screens/auth_gate.dart';
import 'package:city_store/widgets/brand_splash.dart';

const _res = 'android/app/src/main/res';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('AuthGate.viewFor', () {
    test('a restored session opens the app immediately (no loading frame)', () {
      expect(AuthGate.viewFor(ConnectionState.waiting, hasUser: true), AuthGateView.signedIn);
      expect(AuthGate.viewFor(ConnectionState.active, hasUser: true), AuthGateView.signedIn);
    });

    test('without a session it waits for the first auth event before login', () {
      expect(AuthGate.viewFor(ConnectionState.none, hasUser: false), AuthGateView.loading);
      expect(AuthGate.viewFor(ConnectionState.waiting, hasUser: false), AuthGateView.loading);
      expect(AuthGate.viewFor(ConnectionState.active, hasUser: false), AuthGateView.signedOut);
    });
  });

  testWidgets('BrandSplash uses the native splash purple, not white', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandSplash()));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, BrandSplash.color);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  group('Android launch configuration', () {
    test('splash color matches BrandSplash.color', () {
      final hex = BrandSplash.color.toARGB32().toRadixString(16).substring(2).toUpperCase();
      expect(_read('$_res/values/colors.xml'), contains('<color name="wasally_splash">#$hex</color>'));
    });

    test('launch backgrounds are branded, never the theme white', () {
      for (final dir in ['drawable', 'drawable-v21']) {
        final xml = _read('$_res/$dir/launch_background.xml');
        expect(xml, isNot(contains('?android:colorBackground')), reason: dir);
        expect(xml, contains('@color/wasally_splash'), reason: dir);
        expect(xml, contains('@drawable/splash_logo'), reason: dir);
      }
      expect(File('$_res/drawable-xhdpi/splash_logo.png').existsSync(), isTrue);
    });

    test('Android 12+ system splash and window background are branded', () {
      for (final dir in ['values-v31', 'values-night-v31']) {
        final xml = _read('$_res/$dir/styles.xml');
        expect(xml, contains('android:windowSplashScreenBackground">@color/wasally_splash'), reason: dir);
      }
      for (final dir in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
        final xml = _read('$_res/$dir/styles.xml');
        expect(RegExp(r'name="NormalTheme"[\s\S]*?windowBackground">@color/wasally_splash').hasMatch(xml),
            isTrue,
            reason: dir);
      }
    });

    test('MainActivity keeps the Flutter engine when Android recreates the activity', () {
      final kt = _read('android/app/src/main/kotlin/com/wassally/app/MainActivity.kt');
      expect(kt, contains('FlutterEngineCache.getInstance().get(ENGINE_ID)'));
      expect(kt, contains('override fun shouldDestroyEngineWithHost(): Boolean = false'));
      // Store links opened while the engine is alive still navigate.
      expect(kt, contains('pushRouteInformation'));
    });
  });
}
