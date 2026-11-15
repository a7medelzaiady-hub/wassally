import 'package:flutter/material.dart';

import 'main_shell.dart';

/// نقطة دخول العميل بعد تسجيل الدخول.
/// تم إلغاء شاشة اختيار الأقسام الوسيطة والانتقال مباشرةً إلى الرئيسية.
class CustomerEntry extends StatelessWidget {
  const CustomerEntry({super.key});

  @override
  Widget build(BuildContext context) => const MainShell();
}
