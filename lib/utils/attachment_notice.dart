/// تنبيه العميل بخصوص مرفقات الطلب الخاص (صورة / رسالة صوتية).
/// المرفقات بتتحذف تلقائيًا من التخزين بعد تأكيد استلام الطلب (من الـWorker).
const String kAttachmentsWillBeDeleted =
    'المرفقات (الصورة والرسالة الصوتية) بتتحذف تلقائيًا بعد ما تأكد استلام الطلب.';
const String kAttachmentsDeleted =
    'تم حذف المرفقات تلقائيًا بعد استلامك للطلب.';

/// null = مفيش مرفقات ومفيش حاجة تتقال.
String? specialAttachmentNotice(Map<String, dynamic> request) {
  if ((request['cleanupStatus'] ?? '').toString() == 'deleted') {
    return kAttachmentsDeleted;
  }
  bool has(String k) => (request[k] ?? '').toString().isNotEmpty;
  if (has('imageUrl') || has('voiceUrl') || has('voiceBase64')) {
    return kAttachmentsWillBeDeleted;
  }
  return null;
}
