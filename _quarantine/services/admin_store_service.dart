import 'package:cloud_firestore/cloud_firestore.dart';

import 'catalog_service.dart';

class AdminStoreService {
  static final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>
      _products(String storeId) {
    return _db
        .collection('stores')
        .doc(storeId)
        .collection('products');
  }

  /// إضافة محل جديد.
  static Future<String> addStore({
    required String name,
    required String phone,
    required String category,
    String? imageUrl,
  }) async {
    final docRef = await _db.collection('stores').add({
      'name': name,
      'phone': phone,
      'category': category,
      'imageUrl': imageUrl ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await CatalogService.bump();

    return docRef.id;
  }

  /// إضافة صنف داخل المحل الصحيح.
  static Future<String> addProduct({
    required String storeId,
    required String productName,
    required double price,
    required String imageUrl,
  }) async {
    final docRef = await _products(storeId).add({
      'name': productName,
      'price': price,
      'image': imageUrl,
      'isAvailable': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await CatalogService.bump();

    return docRef.id;
  }

  /// تعديل صنف باستخدام معرفه الحقيقي.
  static Future<void> updateProduct({
    required String storeId,
    required String productId,
    required String productName,
    required double price,
    required String imageUrl,
  }) async {
    await _products(storeId).doc(productId).update({
      'name': productName,
      'price': price,
      'image': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await CatalogService.bump();
  }

  /// حذف صنف.
  static Future<void> deleteProduct({
    required String storeId,
    required String productId,
  }) async {
    await _products(storeId).doc(productId).delete();

    await CatalogService.bump();
  }

  /// تحديث صورة محل.
  static Future<void> updateStoreImage({
    required String storeId,
    required String imageUrl,
  }) async {
    await _db.collection('stores').doc(storeId).update({
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await CatalogService.bump();
  }

  /// تعديل بيانات المحل.
  static Future<void> updateStore({
    required String storeId,
    required String name,
    required String phone,
    required String category,
    required String imageUrl,
  }) async {
    await _db.collection('stores').doc(storeId).update({
      'name': name,
      'phone': phone,
      'category': category,
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await CatalogService.bump();
  }
}
