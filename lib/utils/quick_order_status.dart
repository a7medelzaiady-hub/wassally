/// Customer-facing labels shared by quick-order history and details.
String quickOrderStatusLabel(String status) => switch (status) {
  'open' => 'بانتظار مندوب',
  'accepted' || 'assigned' => 'المندوب استلم الطلب',
  'awaiting_advance' => 'بانتظار تأكيد المبلغ المقدم',
  'shopping' || 'purchasing' => 'المندوب بيشتري طلبك',
  'summary_pending' => 'راجع الحساب النهائي',
  'summary_approved' => 'تمت الموافقة على الحساب',
  'delivered' => 'تم التسليم',
  'cancelled' || 'canceled' => 'ملغي',
  _ => 'جارٍ متابعة الطلب',
};
