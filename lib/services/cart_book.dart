import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../models/store.dart';
import 'cart_model.dart';

/// مكان حفظ السلال على الموبايل (قابل للاستبدال في الاختبارات).
abstract class CartStorage {
  Future<String?> read();
  Future<void> write(String? value);
}

class PrefsCartStorage implements CartStorage {
  const PrefsCartStorage();
  static const String key = 'wasally_carts_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// «سلّاتي»: سلة لكل محل. السلة الحالية هي [cart] (المسار القديم زي ما هو)،
/// والسلال التانية محفوظة هنا. كل سلة بتتطلب كطلب مستقل بنظام الطلبات الحالي.
///
/// كل السلال بتتحفظ على موبايل العميل (مش Firebase، فمفيش تكلفة) وبترجع لما يفتح التطبيق تاني،
/// لمدة [keepFor] من آخر تعديل في كل سلة. الأسعار بتتراجع من قائمة المحل لما يفتحه،
/// والسيرفر بيراجعها تاني وقت الطلب.
class CartBook extends ChangeNotifier {
  CartBook(this.active, {CartStorage storage = const PrefsCartStorage()}) : _storage = storage {
    active.addListener(_onActiveChanged);
  }

  static const Duration keepFor = Duration(days: 3);

  /// السلة الحالية (نفس [cart] في التطبيق).
  final CartModel active;
  final CartStorage _storage;

  final Map<String, CartSnapshot> _parked = {};
  final Map<String, DateTime> _touched = {};
  final Map<String, Store> _stores = {};
  bool _loaded = false;
  bool _saving = false;
  bool _saveAgain = false;

  /// عدد السلال اللي رجعت من آخر مرة (للتنبيه). بيتصفر لما العميل يشوف «سلّاتي».
  int restoredCount = 0;

  // ── تجميع الطلبات (اختياري، العميل بيختاره من «سلّاتي») ──
  // رقم مشترك للطلبات اللي هتتأكد من السلال دي. كل طلب بيفضل مستقل برقمه وحالته ورسومه.
  // السيرفر بيربط الرقم بحساب العميل ويرفض أي محل متكرر أو رقم منتهي أو مش تبعه.
  static const int groupMaxOrders = 5;
  static const Duration groupKeepFor = Duration(hours: 5, minutes: 50); // أقل من مدة السيرفر (6 ساعات)
  String? _groupId;
  DateTime? _groupStartedAt;
  final Set<String> _groupStores = {};

  bool get groupingOn => _groupId != null;

  /// الكود اللي هيظهر للمندوب (آخر 6 حروف).
  String? get groupCode => _groupId?.substring(_groupId!.length - 6).toUpperCase();

  /// يشغّل أو يقفل تجميع الطلبات الجاية.
  void setGrouping(bool on, {Random? random}) {
    if (on == groupingOn) return;
    if (on) {
      _groupId = newGroupId(random ?? Random.secure());
      _groupStartedAt = DateTime.now();
    } else {
      _groupId = null;
      _groupStartedAt = null;
    }
    _groupStores.clear();
    notifyListeners();
  }

  /// رقم التجميع اللي يتبعت مع طلب المحل ده، أو null (الطلب يتبعت لوحده):
  /// التجميع مقفول، أو المحل اتطلب منه قبل كده في نفس المجموعة، أو المجموعة اتملت أو قربت تنتهي.
  String? groupIdFor(String? storeId, {DateTime? now}) {
    final id = _groupId;
    final started = _groupStartedAt;
    if (id == null || started == null || storeId == null || storeId.isEmpty) return null;
    if (_groupStores.contains(storeId) || _groupStores.length >= groupMaxOrders) return null;
    if ((now ?? DateTime.now()).difference(started) > groupKeepFor) return null;
    return id;
  }

  /// الطلب اتبعت ضمن المجموعة.
  void markGroupedOrder(String storeId) {
    if (_groupId != null) _groupStores.add(storeId);
  }

  /// صيغة رقم التجميع اللي السيرفر بيقبلها: grp_ + 20 حرف/رقم عشوائي (من غير بيانات العميل).
  static String newGroupId(Random random) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return 'grp_${List.generate(20, (_) => chars[random.nextInt(chars.length)]).join()}';
  }

  /// السلال المحفوظة (غير السلة الحالية)، بترتيب الإضافة.
  List<CartSnapshot> get parked => List.unmodifiable(_parked.values);

  /// عدد كل السلال اللي فيها حاجة (الحالية + المحفوظة).
  int get cartsCount => (active.isEmpty ? 0 : 1) + _parked.length;

  /// عدد الأصناف في كل السلال (لعلامة السلة في الشريط السفلي).
  int get totalItems => active.count + _parked.values.fold(0, (a, c) => a + c.count);

  bool get hasParked => _parked.isNotEmpty;

  CartSnapshot? parkedFor(String storeId) => _parked[storeId];

  /// بيافتكر بيانات المحل عشان زرار «إضافة منتجات من نفس المحل» يفتح صفحته.
  void rememberStore(Store store) => _stores[store.id] = store;

  Store? storeFor(String? storeId) => storeId == null ? null : _stores[storeId];

  /// يخلّي سلة المحل ده هي الحالية: السلة الحالية تتحفظ (لو فيها حاجة)،
  /// وسلة المحل ترجع لو كانت محفوظة، وإلا تبدأ سلة فاضية.
  void switchTo(String storeId) {
    if (active.storeId == storeId) return;
    final current = active.snapshot();
    final target = _parked.remove(storeId);
    if (!current.isEmpty && current.storeId != null) {
      _parked[current.storeId!] = current;
    }
    if (target != null) {
      active.restore(target);
    } else {
      active.clear();
    }
    notifyListeners();
    _scheduleSave();
  }

  /// يمسح سلة محفوظة.
  void removeParked(String storeId) {
    if (_parked.remove(storeId) != null) {
      _touched.remove(storeId);
      notifyListeners();
      _scheduleSave();
    }
  }

  /// العميل شاف التنبيه (فتح «سلّاتي»).
  void markRestoredSeen() {
    if (restoredCount == 0) return;
    restoredCount = 0;
    notifyListeners();
  }

  /// تسجيل خروج: كل السلال تتمسح (من الموبايل كمان).
  void clearAll() {
    _groupId = null;
    _groupStartedAt = null;
    _groupStores.clear();
    _parked.clear();
    _stores.clear();
    _touched.clear();
    restoredCount = 0;
    active.clear();
    notifyListeners();
    _scheduleSave();
  }

  void _onActiveChanged() {
    final id = active.storeId;
    if (id != null && !active.isEmpty) _touched[id] = DateTime.now();
    // كل السلال اتأكدت أو اتمسحت: التجميع خلص.
    if (_groupId != null && cartsCount == 0) {
      _groupId = null;
      _groupStartedAt = null;
      _groupStores.clear();
    }
    _scheduleSave();
  }

  /// بيرجّع السلال المحفوظة على الموبايل (مرة واحدة عند فتح التطبيق).
  /// السلال الأقدم من [keepFor] بتتمسح. أي خطأ = نبدأ من غير سلال (السلة مش حاجة حساسة).
  Future<void> load({DateTime? now}) async {
    if (_loaded) return;
    try {
      final raw = await _storage.read();
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        final decoded = decodeCarts(data, now: now ?? DateTime.now());
        final activeId = data is Map ? data['active']?.toString() : null;
        var restored = 0;
        for (final entry in decoded.entries) {
          final snap = entry.value.snapshot;
          final storeId = entry.key;
          // لو العميل لحق يضيف قبل ما التحميل يخلص، اللي في إيده هو الحالي ومش بنلمسه.
          if (storeId == active.storeId) continue;
          if (storeId == activeId && active.isEmpty) {
            active.restore(snap);
          } else {
            _parked[storeId] = snap;
          }
          _touched[storeId] = entry.value.touchedAt;
          restored++;
        }
        restoredCount = restored;
      }
    } catch (_) {
      // تخزين تالف أو غير متاح: نكمل من غير سلال محفوظة.
    }
    _loaded = true;
    notifyListeners();
    _scheduleSave();
  }

  /// حفظ من غير Timer: لو فيه حفظ شغال، نعيد بعده مرة واحدة بآخر حالة.
  void _scheduleSave() {
    if (!_loaded) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      do {
        _saveAgain = false;
        final all = <CartSnapshot>[if (!active.isEmpty) active.snapshot(), ..._parked.values];
        await _storage.write(all.isEmpty ? null : jsonEncode(encodeCarts(all, active.storeId, _touched)));
      } while (_saveAgain);
    } catch (_) {
      // الحفظ فشل: السلال لسه في الذاكرة طول ما التطبيق مفتوح.
    } finally {
      _saving = false;
    }
  }
}

/// سلة راجعة من الموبايل ومعاها آخر وقت اتعدلت فيه.
class StoredCart {
  final CartSnapshot snapshot;
  final DateTime touchedAt;
  const StoredCart(this.snapshot, this.touchedAt);
}

Map<String, dynamic> _encodeLine(Product p, int qty) => {
      'id': p.id,
      'name': p.name,
      'price': p.price,
      if (p.imageUrl.isNotEmpty) 'image': p.imageUrl,
      if (p.chosen.isNotEmpty) 'chosen': [for (final o in p.chosen) o.toMap()],
      'qty': qty,
    };

bool _jsonSafe(Object value) {
  try {
    jsonEncode(value);
    return true;
  } catch (_) {
    return false;
  }
}

/// تحويل السلال لـJSON للحفظ على الموبايل.
Map<String, dynamic> encodeCarts(
  List<CartSnapshot> all,
  String? activeStoreId,
  Map<String, DateTime> touched,
) {
  final now = DateTime.now();
  return {
    'v': 1,
    'active': activeStoreId,
    'carts': [
      for (final c in all)
        if (c.storeId != null)
          {
            'storeId': c.storeId,
            'storeName': c.storeName ?? '',
            'touchedAt': (touched[c.storeId] ?? now).toIso8601String(),
            'area': c.area,
            'fee': c.fee,
            'promoCode': c.promoCode,
            'promoPercent': c.promoPercent,
            if (c.specialRequest != null && _jsonSafe(c.specialRequest!)) 'special': c.specialRequest,
            'items': [for (final e in c.items.entries) _encodeLine(e.key, e.value)],
          },
    ],
  };
}

/// قراءة السلال المحفوظة. السلة الأقدم من [CartBook.keepFor] أو التالفة بتتشال.
Map<String, StoredCart> decodeCarts(Object? data, {required DateTime now}) {
  final result = <String, StoredCart>{};
  if (data is! Map || data['v'] != 1 || data['carts'] is! List) return result;
  for (final raw in data['carts'] as List) {
    if (raw is! Map) continue;
    final storeId = (raw['storeId'] ?? '').toString();
    final touchedAt = DateTime.tryParse((raw['touchedAt'] ?? '').toString());
    if (storeId.isEmpty || touchedAt == null || now.difference(touchedAt) > CartBook.keepFor) continue;
    final items = <Product, int>{};
    if (raw['items'] is List) {
      for (final line in raw['items'] as List) {
        if (line is! Map) continue;
        final name = (line['name'] ?? '').toString();
        final price = line['price'];
        final qty = line['qty'];
        if (name.isEmpty || price is! num || price < 0 || qty is! int || qty < 1) continue;
        final chosen = <ProductOption>[
          if (line['chosen'] is List)
            for (final o in line['chosen'] as List)
              if (ProductOption.tryParse(o) case final opt?) opt,
        ];
        final p = Product(
          name,
          price.toDouble(),
          (line['image'] ?? '').toString(),
          (line['id'] ?? '').toString(),
          true,
          0,
          '',
          null,
          '',
          const [],
          chosen,
        );
        items[p] = (items[p] ?? 0) + qty;
      }
    }
    final special = raw['special'] is Map ? Map<String, dynamic>.from(raw['special'] as Map) : null;
    if (items.isEmpty && special == null) continue;
    final fee = raw['fee'];
    final promo = raw['promoPercent'];
    result[storeId] = StoredCart(
      CartSnapshot.fromParts(
        storeId: storeId,
        storeName: (raw['storeName'] ?? '').toString(),
        items: items,
        specialRequest: special,
        area: (raw['area'] ?? '').toString(),
        fee: fee is num ? fee.toDouble() : CartModel.deliveryFee,
        promoCode: (raw['promoCode'] ?? '').toString(),
        promoPercent: promo is num ? promo.toDouble() : 0,
      ),
      touchedAt,
    );
  }
  return result;
}

/// «سلّاتي» المشتركة في التطبيق كله.
final CartBook carts = CartBook(cart);
