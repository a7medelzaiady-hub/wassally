import 'package:flutter/widgets.dart';

import '../models/app_role.dart';
import 'role_service.dart';

/// التبويب المفتوح حاليًا في الشاشة الرئيسية:
/// 0 الرئيسية، 1 السلة، 2 طلباتي، 3 حسابي.
final ValueNotifier<int> shellTab = ValueNotifier<int>(0);

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
