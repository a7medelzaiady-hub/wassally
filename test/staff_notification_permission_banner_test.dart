import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/widgets/staff_notification_permission_banner.dart';

void main() {
  testWidgets('staff permission warning appears only when notifications are off', (tester) async {
    var granted = false;
    var enableCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffNotificationPermissionBanner(
          checkPermission: () async => granted,
          enablePermission: () async {
            enableCalls++;
            granted = true;
            return granted;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('الإشعارات مقفولة'), findsOneWidget);
    expect(find.text('فعّل'), findsOneWidget);
    await tester.tap(find.text('فعّل'));
    await tester.pumpAndSettle();
    expect(enableCalls, 1);
    expect(find.textContaining('الإشعارات مقفولة'), findsNothing);
  });

  testWidgets('already granted permission keeps the banner hidden', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffNotificationPermissionBanner(
          checkPermission: () async => true,
          enablePermission: () async => true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('فعّل'), findsNothing);
  });
}
