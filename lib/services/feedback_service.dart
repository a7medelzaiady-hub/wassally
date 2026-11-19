/// أنواع الملاحظات اللي بتتبعت للإدارة على واتساب (الشكاوى والدعم بقوا على واتساب بدل Firestore).
enum FeedbackKind {
  complaint('complaint', 'شكوى', 'السلام عليكم، عندي شكوى بخصوص وصّلي:\n'),
  suggestion('suggestion', 'اقتراح', 'السلام عليكم، عندي اقتراح لتطوير وصّلي:\n'),
  orderIssue('order_issue', 'مشكلة في طلب',
      'السلام عليكم، عندي مشكلة في طلب.\nرقم الطلب: \nالمشكلة: '),
  restrictionAppeal('restriction_appeal', 'اعتراض على تقييد',
      'السلام عليكم، عايز أعترض على تقييد حسابي.\nرقم الطلب المرتبط: \nالتفاصيل: ');

  final String key;
  final String label;

  /// بداية الرسالة الجاهزة على واتساب.
  final String template;
  const FeedbackKind(this.key, this.label, this.template);
}
