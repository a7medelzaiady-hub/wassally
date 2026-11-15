import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';
import '../models/store.dart';
import '../services/catalog_service.dart';

/// محلات تجريبية. بتترفع لـ Firestore من حساب الأدمن (شاشة حسابي).
const List<Store> seedStores = [
  Store(
    id: 'store_restaurant',
    name: 'مطعم الأصيل',
    category: 'مطاعم',
    iconKey: 'restaurant',
    colorHex: 0xFFF75A07,
    rating: 4.7,
    time: '25-35 د',
    products: [
      Product('ساندوتش باذنجان', 10),
      Product('ساندوتش بطاطس', 12),
      Product('طبق مسقعة', 15),
      Product('ساندوتش فول', 8),
    ],
  ),
  Store(
    id: 'store_supermarket',
    name: 'سوبر ماركت الفهد',
    category: 'سوبرماركت',
    iconKey: 'basket',
    colorHex: 0xFF2E9E6B,
    rating: 4.5,
    time: '30-40 د',
    products: [
      Product('أرز 1 كجم', 35),
      Product('زيت 1 لتر', 60),
      Product('سكر 1 كجم', 28),
      Product('مكرونة', 10),
    ],
  ),
  Store(
    id: 'store_flowers',
    name: 'ورد الياسمين',
    category: 'ورد',
    iconKey: 'flowers',
    colorHex: 0xFFD6336C,
    rating: 4.6,
    time: '35-45 د',
    products: [
      Product('بوكيه ورد بلدي', 150),
      Product('بوكيه ورد جوري', 250),
      Product('وردة منفردة', 15),
    ],
  ),
];

/// بترفع المحلات التجريبية. بترجع عدد المحلات اللي اترفعت.
Future<int> seedDemoStores() async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  for (var i = 0; i < seedStores.length; i++) {
    final s = seedStores[i];
    batch.set(db.collection('stores').doc(s.id), s.toMap(i));
  }
  await batch.commit();
  await CatalogService.bump();
  return seedStores.length;
}
