/// Approximate prices are guidance only. They must never be used for
/// advance-payment thresholds, final receipts, or courier settlement.
class QuickPriceItem {
  final String id;
  final String name;
  final String unit;
  final int pricePiastres;

  const QuickPriceItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.pricePiastres,
  });

  /// Match either the item name or its unit without extra Firestore reads.
  bool matchesSearch(String query) {
    final term = query.trim().toLowerCase();
    return term.isEmpty || name.toLowerCase().contains(term) ||
        unit.toLowerCase().contains(term);
  }

  factory QuickPriceItem.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final name = (map['name'] ?? '').toString().trim();
    final unit = (map['unit'] ?? '').toString().trim();
    final price = map['pricePiastres'];
    if (id.isEmpty || name.isEmpty || unit.isEmpty ||
        price is! int || price < 0) {
      throw const FormatException('Invalid quick price guide item');
    }
    return QuickPriceItem(
      id: id, name: name, unit: unit, pricePiastres: price,
    );
  }
}

class QuickPriceGuide {
  final int version;
  final List<QuickPriceItem> items;

  const QuickPriceGuide({required this.version, required this.items});

  factory QuickPriceGuide.fromMap(Map<String, dynamic> map) {
    final version = map['version'];
    final raw = map['items'];
    if (version is! int || version < 0 || raw is! List) {
      throw const FormatException('Invalid quick price guide');
    }
    final items = raw.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Invalid quick price guide entry');
      }
      return QuickPriceItem.fromMap(Map<String, dynamic>.from(entry));
    }).toList(growable: false);
    if (items.map((e) => e.id).toSet().length != items.length) {
      throw const FormatException('Duplicate quick price guide item ID');
    }
    return QuickPriceGuide(version: version, items: items);
  }
}

class QuickPriceSelection {
  final QuickPriceItem item;
  final int quantity;
  const QuickPriceSelection({required this.item, required this.quantity})
      : assert(quantity >= 1 && quantity <= 99);

  int get subtotalPiastres => item.pricePiastres * quantity;

  Map<String, dynamic> toWorkerMap() => {
    'name': item.name,
    'qty': quantity,
    'unitPricePiastres': item.pricePiastres,
  };
}

class QuickPriceEstimate {
  const QuickPriceEstimate._();

  static int totalPiastres(Iterable<QuickPriceSelection> selections) {
    var total = 0;
    for (final selection in selections) {
      if (selection.quantity < 1 || selection.quantity > 99) {
        throw ArgumentError('Quantity must be 1–99');
      }
      total += selection.subtotalPiastres;
    }
    return total;
  }

  static const disclaimer = 'الأسعار تقريبية وقد تزيد أو تقل حسب المحل';
}
