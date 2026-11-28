import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/route_key.dart';
import 'admin_inbox_page.dart';
import 'admin_tools_page.dart';
import 'checkout_page.dart';
import 'notifications_page.dart';
import 'order_details_page.dart';
import 'quick_courier_orders_page.dart';
import 'quick_courier_order_page.dart';
import 'quick_customer_orders_page.dart';
import 'quick_order_customer_detail_page.dart';
import 'store_directory_page.dart';

/// #339: الصفحات اللي ينفع تتستعاد من اسم المسار بس (من غير بيانات متخزنة).
/// الصفحة بتحمّل بياناتها بنفسها زي ما بتعمل لما المستخدم يفتحها، فمفيش قراءات زيادة.
/// صفحات الموظفين بترجع null لو الحساب مالوش الدور، فمفيش صلاحية بتتوسّع بالاستعادة.
class RestorableRoutes {
  RestorableRoutes._();

  static Widget? pageFor(String name, {required Set<AppRole> held}) {
    final key = RouteKey.parse(name);
    if (key == null) return null;
    final id = key.id ?? '';
    switch (key.kind) {
      case 'order':
        return OrderDetailsPage(orderId: id);
      case 'quick-order':
        return QuickOrderCustomerDetailPage(orderId: id);
      case 'quick-orders':
        return const QuickCustomerOrdersPage();
      case 'notifications':
        return const NotificationsPage();
      case 'stores':
        return const StoreDirectoryPage();
      case 'checkout':
        return const CheckoutPage();
      case 'courier-quick':
        return held.contains(AppRole.courier) ? QuickCourierOrderPage(orderId: id) : null;
      case 'courier-quick-orders':
        return held.contains(AppRole.courier) ? const QuickCourierOrdersPage() : null;
      case 'admin-inbox':
        return held.contains(AppRole.admin) ? const AdminInboxPage() : null;
      case 'admin-tools':
        return held.contains(AppRole.admin) ? const AdminToolsPage() : null;
    }
    return null;
  }

  /// بيفتح المسارات المحفوظة بالترتيب فوق الصفحة الحالية. بيرجّع عدد اللي اتفتحت.
  static int restore(
    NavigatorState navigator,
    List<String> names, {
    required Set<AppRole> held,
  }) {
    var opened = 0;
    for (final name in names) {
      final page = pageFor(name, held: held);
      if (page == null) continue;
      navigator.push(MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ));
      opened++;
    }
    return opened;
  }
}
