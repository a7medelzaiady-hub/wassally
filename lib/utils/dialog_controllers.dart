import 'package:flutter/widgets.dart';

/// بيمسح controller كان مستخدم في حوار، بعد ما الحوار يخلص حركة الإغلاق.
///
/// المسح فورًا بعد `await showDialog(...)` بيخلّي الـTextField لسه مرسوم والحوار بيختفي
/// وهو بيستخدم controller ممسوح، وده بيوقّع Flutter بالشاشة الحمرا
/// (`'_dependents.isEmpty': is not true`). ثانية واحدة أطول من أي حركة إغلاق.
void disposeAfterDialogCloses(TextEditingController controller) {
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
}
