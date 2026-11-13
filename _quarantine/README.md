ملفات معزولة في المرحلة 1 (لم تُحذف). لا يصل إليها أي مسار من lib/main.dart، ومستثناة من flutter analyze.
- admin_orders_screen / courier_orders_screen: حالات قديمة غير موجودة في القواعد.
- driver_dashboard_page: لا يُترجم (قوس زائد سطر 105) ويعتمد على مجموعة drivers بلا قواعد.
- services/notifications_page: نسخة مطابقة حرفيًا لـ screens/notifications_page.dart.
- admin_store_service, bell_sound, banner_slider, rate_driver_dialog, store_card: غير مستوردة.
للاسترجاع: انقل الملف لنفس مساره تحت lib/. الحذف النهائي بقرارك لاحقًا.
