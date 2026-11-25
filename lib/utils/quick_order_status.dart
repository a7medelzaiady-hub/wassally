/// Customer-facing labels shared by quick-order history and details.
String quickOrderStatusLabel(String status) => switch (status) {
  'open' => 'بانتظار مندوب',
  'accepted' || 'assigned' => 'المندوب استلم الطلب',
  'awaiting_advance' => 'بانتظار تأكيد المبلغ المقدم',
  'shopping' || 'purchasing' => 'المندوب بيشتري طلبك',
  'summary_pending' => 'جاهز للتسليم برمز الاستلام',
  'summary_approved' => 'جاهز للتسليم برمز الاستلام',
  'delivered' => 'تم التسليم',
  'cancelled' || 'canceled' => 'ملغي',
  _ => 'جارٍ متابعة الطلب',
};
