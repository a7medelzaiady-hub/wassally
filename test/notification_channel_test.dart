import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:city_store/services/notification_service.dart';

void main() {
  test('local foreground notifications share the Worker FCM order channel', () {
    expect(NotificationService.ordersChannelId, 'wasally_orders');
    expect(NotificationService.ordersChannel.id, 'wasally_orders');
    expect(NotificationService.ordersChannel.importance, Importance.high);
    expect(NotificationService.ordersChannel.playSound, isTrue);
    expect(NotificationService.ordersAndroidDetails.channelId, 'wasally_orders');
    expect(NotificationService.ordersAndroidDetails.importance, Importance.high);
    expect(NotificationService.ordersAndroidDetails.priority, Priority.high);
    expect(NotificationService.ordersAndroidDetails.playSound, isTrue);
  });
}
