import 'package:flutter/material.dart';

import 'store.dart';

/// Home cards use the same categories accepted by the store application/rules.
/// Multiple actual store categories can belong to one visual card.
class HomeCategory {
  final String id;
  final String title;
  final String photoUrl;
  final IconData icon;
  final List<String> storeCategories;

  const HomeCategory({
    required this.id,
    required this.title,
    required this.photoUrl,
    required this.icon,
    required this.storeCategories,
  });
}

/// Optimized, fixed Unsplash photo URLs (not Source's random/retired endpoint).
/// Cached on disk using the existing image cache; no extra Firestore reads.
/// Public photography is used for category decoration, never customer media.
const homeCategories = <HomeCategory>[
  HomeCategory(
    id: 'restaurants',
    title: 'مطاعم',
    photoUrl: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.restaurant_rounded,
    storeCategories: ['مطاعم'],
  ),
  HomeCategory(
    id: 'market',
    title: 'ماركت وخضروات',
    photoUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.shopping_basket_rounded,
    storeCategories: ['سوبرماركت', 'سوبر ماركت', 'بقالة', 'خضار وفاكهة', 'خضار وفواكه'],
  ),
  HomeCategory(
    id: 'meat',
    title: 'لحوم ودواجن',
    photoUrl: 'https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.set_meal_rounded,
    storeCategories: ['لحوم ودواجن'],
  ),
  HomeCategory(
    id: 'bakery',
    title: 'مخبوزات',
    photoUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.bakery_dining_rounded,
    storeCategories: ['مخبوزات وحلويات', 'مخبوزات'],
  ),
  HomeCategory(
    id: 'pharmacy',
    title: 'صيدليات',
    photoUrl: 'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.local_pharmacy_rounded,
    storeCategories: ['صيدليات'],
  ),
  HomeCategory(
    id: 'roastery',
    title: 'محمصات',
    photoUrl: 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.grain_rounded,
    storeCategories: ['محمصات وعطارة', 'محمصات'],
  ),
  HomeCategory(
    id: 'cafe',
    title: 'كافيهات ومشروبات',
    photoUrl: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.local_cafe_rounded,
    storeCategories: ['كافيه ومشروبات', 'كافيهات'],
  ),
  HomeCategory(
    id: 'flowers',
    title: 'ورد وهدايا',
    photoUrl: 'https://images.unsplash.com/photo-1490750967868-88aa4486c946?w=280&h=280&fit=crop&auto=format&q=80',
    icon: Icons.local_florist_rounded,
    storeCategories: ['ورد وهدايا'],
  ),
];

HomeCategory? homeCategoryForId(String? id) {
  if (id == null) return null;
  for (final category in homeCategories) {
    if (category.id == id) return category;
  }
  return null;
}

/// Supports grouped home categories and native categories entered by store owners.
/// No server-side queries/listeners: the directory filters its already loaded list.
bool matchesDirectoryCategory(String filter, String actual) {
  final home = homeCategoryForId(filter);
  if (home != null) {
    if (home.id == 'pharmacy') return isPharmacyCategory(actual);
    return home.storeCategories.contains(actual.trim());
  }
  return isPharmacyCategory(filter)
      ? isPharmacyCategory(actual)
      : filter == actual;
}
