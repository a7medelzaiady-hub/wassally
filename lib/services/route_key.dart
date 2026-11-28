/// #339: اسم المسار القابل للاستعادة. بيتحفظ على الموبايل بس، فمسموح فيه
/// نوع الصفحة ومعرّف مستند عشوائي (Firestore id) ومفيش أي بيانات شخصية:
/// لا اسم ولا تليفون ولا عنوان ولا نص حر. أي اسم برا القايمة البيضا بيتتجاهل.
class RouteKey {
  const RouteKey._(this.kind, this.id);

  final String kind;
  final String? id;

  /// أنواع بدون معرّف.
  static const plainKinds = {
    'notifications',
    'stores',
    'checkout',
    'quick-orders',
    'courier-quick-orders',
    'admin-inbox',
    'admin-tools',
  };

  /// أنواع لازم يكون ليها معرّف مستند.
  static const idKinds = {'order', 'quick-order', 'courier-quick'};

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// أرقام فقط وطويلة (شكل رقم تليفون): مش معرّف مستند، ما نحطهاش في اسم مسار.
  static final _phoneLike = RegExp(r'^\d{9,}$');

  static const notifications = 'notifications';
  static const stores = 'stores';
  static const checkout = 'checkout';
  static const quickOrders = 'quick-orders';
  static const courierQuickOrders = 'courier-quick-orders';
  static const adminInbox = 'admin-inbox';
  static const adminTools = 'admin-tools';

  /// حالات الطلب اللي بعدها مفيش معنى لاستعادة صفحته.
  static bool isFinalStatus(String? status) =>
      status == 'delivered' || status == 'cancelled' || status == 'canceled';

  static String? order(String id) => make('order', id);
  static String? quickOrder(String id) => make('quick-order', id);
  static String? courierQuick(String id) => make('courier-quick', id);

  /// بيبني الاسم، أو null لو النوع مش معروف أو المعرّف مش آمن.
  static String? make(String kind, [String? id]) {
    if (idKinds.contains(kind)) {
      if (id == null || !_idPattern.hasMatch(id) || _phoneLike.hasMatch(id)) return null;
      return '$kind:$id';
    }
    if (plainKinds.contains(kind)) {
      return id == null || id.isEmpty ? kind : null;
    }
    return null;
  }

  /// بيقرا الاسم، أو null لو مش مسار قابل للاستعادة (مثلاً `/` أو `service:quick`).
  static RouteKey? parse(String? name) {
    if (name == null || name.isEmpty || name.length > 200) return null;
    final sep = name.indexOf(':');
    final kind = sep < 0 ? name : name.substring(0, sep);
    final id = sep < 0 ? null : name.substring(sep + 1);
    final canonical = make(kind, id);
    return canonical == name ? RouteKey._(kind, id) : null;
  }

  @override
  String toString() => id == null ? kind : '$kind:$id';
}
