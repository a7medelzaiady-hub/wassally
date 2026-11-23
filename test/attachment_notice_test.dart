import 'package:city_store/utils/attachment_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مرفقات موجودة: تنبيه إنها هتتحذف بعد الاستلام', () {
    expect(specialAttachmentNotice({'imageUrl': 'https://x/y.jpg'}), kAttachmentsWillBeDeleted);
    expect(specialAttachmentNotice({'voiceUrl': 'https://x/v.m4a'}), kAttachmentsWillBeDeleted);
    expect(specialAttachmentNotice({'voiceBase64': 'AAAA'}), kAttachmentsWillBeDeleted);
  });

  test('بعد الحذف: رسالة إن المرفقات اتحذفت (حتى لو الروابط اتمسحت)', () {
    expect(
      specialAttachmentNotice({'cleanupStatus': 'deleted', 'description': 'x'}),
      kAttachmentsDeleted,
    );
  });

  test('بدون مرفقات أو بعد فشل الحذف بدون روابط: مفيش تنبيه مضلل', () {
    expect(specialAttachmentNotice({'description': 'x'}), isNull);
    expect(specialAttachmentNotice({'imageUrl': '', 'voiceUrl': ''}), isNull);
  });

  test('فشل الحذف مع بقاء الروابط: لسه التنبيه إنها هتتحذف', () {
    expect(
      specialAttachmentNotice({'cleanupStatus': 'failed', 'imageUrl': 'https://x/y.jpg'}),
      kAttachmentsWillBeDeleted,
    );
  });
}
