import 'package:flutter/material.dart';

import '../models/app_role.dart';
import 'role_service.dart';

/// التبويب المفتوح حاليًا في الشاشة الرئيسية:
/// 0 الرئيسية، 1 السلة، 2 طلباتي، 3 حسابي.
final ValueNotifier<int> shellTab = ValueNotifier<int>(0);

/// يطلب من شريط التنقل فتح قسم العروض داخل الرئيسية دون إنشاء شاشة أو قراءة إضافية.
final ValueNotifier<int> homeOffersRequest = ValueNotifier<int>(0);

/// القسم اللي اختاره العميل من شاشة الأقسام بعد الدخول. الرئيسية بتقراه مرة واحدة وتفضّيه.
final ValueNotifier<String?> homeCategoryRequest = ValueNotifier<String?>(null);

/// اللوحة اللي المستخدم بدّل ليها (لو حسابه له أكتر من دور). null = دوره الأساسي.
final ValueNotifier<AppRole?> activePanel = ValueNotifier<AppRole?>(null);

/// لما الدور يتحدّث بعد تسجيل دور جديد (مثلاً الأدمن يسجّل نفسه كمندوب)، البوابة بتقراه.
final ValueNotifier<RoleInfo?> roleInfoOverride = ValueNotifier<RoleInfo?>(
  null,
);

/// مفتاح الـ Navigator الرئيسي: بنستخدمه لعرض نوافذ من داخل الخدمات (مثلًا إدخال رابط صورة).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// صفحة الترحيب بتعلن إن شريط العميل متاح (العميل فقط، مش لوحات الأدوار التانية).
final ValueNotifier<bool> customerShellAvailable = ValueNotifier<bool>(false);

/// طلب من صفحة الترحيب إنها تفتح الواجهة الأساسية (الرئيسية/السلة/طلباتي/حسابي).
final ValueNotifier<int> enterShellRequest = ValueNotifier<int>(0);

/// يفتح تبويب العميل من أي صفحة داخلية: يرجع لجذر التطبيق بدل تكديس الصفحات.
void openCustomerTab(BuildContext context, int tab) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  shellTab.value = tab;
  enterShellRequest.value++;
}

final Set<String> _routesInFlight = <String>{};

/// يفتح الصفحة مرة واحدة حتى لو المستخدم ضغط بسرعة أكتر من مرة.
/// المفتاح بيتحرر لما الصفحة تتقفل.
Future<T?> pushOnce<T>(
  BuildContext context,
  String key,
  WidgetBuilder builder,
) async {
  if (!_routesInFlight.add(key)) return null;
  try {
    return await Navigator.of(context).push<T>(MaterialPageRoute<T>(
      settings: RouteSettings(name: key),
      builder: builder,
    ));
  } finally {
    _routesInFlight.remove(key);
  }
}
