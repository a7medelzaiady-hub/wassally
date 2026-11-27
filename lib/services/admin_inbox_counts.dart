import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// أعداد اللي محتاج تصرف من المدير في «الطلبات والرسائل»، من غير ما يدخل جوه.
/// بيتحسب بـ count() (قراءة واحدة لكل استعلام لحد 1000 مستند) ومتخزن دقيقتين،
/// فمفيش مستمعات ولا قراءات متكررة مع كل إعادة رسم للشاشة.
class AdminInboxCounts {
  final int joinRequests;
  final int deliveryIssues;

  /// بلاغات «عندي مشكلة في الطلب» المفتوحة.
  final int orderIssues;

  const AdminInboxCounts({this.joinRequests = 0, this.deliveryIssues = 0, this.orderIssues = 0});

  int get total => joinRequests + deliveryIssues + orderIssues;

  /// نص الشارة: لحد 9 بالرقم، وبعد كده 9+.
  static String badgeText(int n) => n > 9 ? '9+' : '$n';

  /// نص تنبيه فتح التطبيق، أو null لو مفيش حاجة.
  static String? alertText(AdminInboxCounts c) {
    if (c.total == 0) return null;
    final parts = <String>[
      if (c.joinRequests > 0) '${c.joinRequests} طلب انضمام',
      if (c.deliveryIssues > 0) '${c.deliveryIssues} بلاغ تعذر تسليم',
      if (c.orderIssues > 0) '${c.orderIssues} مشكلة في طلب',
    ];
    return 'محتاج مراجعتك: ${parts.join(' و')}.';
  }

  /// حالات بلاغ التسليم اللي لسه محتاجة قرار أو متابعة.
  static const openIssueStatuses = [
    'open',
    'in_review',
    'return_to_store',
    'returned_to_store',
  ];

  static const _ttl = Duration(minutes: 2);
  static Future<AdminInboxCounts>? _cached;
  static DateTime? _at;

  /// بيرجع آخر قيمة لو عمرها أقل من دقيقتين، إلا لو [force].
  static Future<AdminInboxCounts> load({bool force = false}) {
    final at = _at;
    if (!force && _cached != null && at != null &&
        DateTime.now().difference(at) < _ttl) {
      return _cached!;
    }
    _at = DateTime.now();
    return _cached = _fetch();
  }

  static Future<AdminInboxCounts> _fetch() async {
    final db = FirebaseFirestore.instance;
    try {
      final r = await Future.wait([
        db.collection('role_requests').where('status', isEqualTo: 'pending').count().get(),
        db.collection('delivery_issues').where('status', whereIn: openIssueStatuses).count().get(),
        db.collection('order_issues').where('status', isEqualTo: 'open').count().get(),
      ]);
      return AdminInboxCounts(
        joinRequests: r[0].count ?? 0,
        deliveryIssues: r[1].count ?? 0,
        orderIssues: r[2].count ?? 0,
      );
    } catch (e) {
      // الأعداد مساعدة بس؛ فشلها ما يوقفش الشاشة. نسمح بإعادة المحاولة بعد كده.
      debugPrint('Admin inbox counts failed: $e');
      _at = null;
      return const AdminInboxCounts();
    }
  }
}
