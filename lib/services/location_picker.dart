import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/brand.dart';
import 'performance_monitor.dart';
import 'saved_address.dart';
import '../widgets/app_snack.dart';

/// موقع اتحدد بالـGPS: الإحداثيات + الحي + العنوان المقروء.
class PickedLocation {
  const PickedLocation({
    required this.lat,
    required this.lng,
    required this.area,
    required this.address,
  });

  final double lat;
  final double lng;

  /// الحي/المدينة (ممكن يبقى فاضي لو الخريطة مرجعتش اسم).
  final String area;
  final String address;

  /// «31.05123, 30.12345» — المندوب يفتحها على الخريطة بالظبط.
  String get coordinates => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// اختيار عنوان التوصيل (من الرئيسية أو من صفحة ما بعد الدخول).
/// نفس السلوك السابق بالظبط: موافقة قبل الموقع، كتابة يدوية، وحفظ في الحساب.
class DeliveryLocationPicker {
  DeliveryLocationPicker._();

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(appSnack(msg));
  }

  static Future<void> _saveAddress(BuildContext context, String address, {double? lat, double? lng}) async {
    SavedAddress.update(address);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'address': address,
        'lat': ?lat,
        'lng': ?lng,
      }, SetOptions(merge: true));
      if (context.mounted) _toast(context, 'تم حفظ موقعك');
    } catch (e) {
      debugPrint('Save address error: $e');
      if (context.mounted) _toast(context, 'تعذر حفظ العنوان');
    }
  }

  /// شرح واضح قبل طلب إذن الموقع (متطلب سياسة جوجل بلاي: طلب الإذن في سياقه).
  static Future<bool> _confirmLocationUse(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'استخدام موقعك',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'هنستخدم موقع جهازك مرة واحدة بس عشان نحدد عنوان التوصيل، '
            'ونحفظ العنوان في حسابك لتسهيل طلباتك الجاية. '
            'مش بنتتبع موقعك في الخلفية، وتقدر تكتب عنوانك بنفسك بدل كده.',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('اكتب العنوان بنفسي'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  /// يحدد موقع الجهاز مرة واحدة (بعد موافقة واضحة) ويرجّع الحي والعنوان.
  /// null لو العميل رفض أو الموقع مش متاح (بيظهر له السبب).
  static Future<PickedLocation?> locate(BuildContext context) async {
    if (!await _confirmLocationUse(context) || !context.mounted) return null;
    _toast(context, 'جاري تحديد موقعك...');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (context.mounted) _toast(context, 'فعّل خدمة الموقع (GPS) من الإعدادات');
        await Geolocator.openLocationSettings();
        return null;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        if (context.mounted) _toast(context, 'محتاجين إذن الموقع عشان نحدد مكانك');
        return null;
      }
      if (perm == LocationPermission.deniedForever) {
        if (context.mounted) _toast(context, 'إذن الموقع مرفوض. فعّله من إعدادات التطبيق');
        await Geolocator.openAppSettings();
        return null;
      }

      final pos = await PerformanceMonitor.trace(
        'map_gps_location',
        () => Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ),
      );

      var text =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      var area = '';
      try {
        final marks = await PerformanceMonitor.trace(
          'map_reverse_geocode',
          () => placemarkFromCoordinates(pos.latitude, pos.longitude),
        );
        if (marks.isNotEmpty) {
          final m = marks.first;
          String clean(String? v) => (v ?? '').trim();
          final parts = [
            m.street,
            m.subLocality,
            m.locality,
            m.administrativeArea,
          ].map(clean).where((e) => e.isNotEmpty).toList();
          if (parts.isNotEmpty) text = parts.join('، ');
          area = [clean(m.subLocality), clean(m.locality)]
              .where((e) => e.isNotEmpty)
              .join('، ');
          if (area.isEmpty) area = clean(m.administrativeArea);
        }
      } catch (e) {
        debugPrint('Reverse geocoding error: $e');
      }
      if (area.length > 60) area = area.substring(0, 60);
      return PickedLocation(lat: pos.latitude, lng: pos.longitude, area: area, address: text);
    } catch (e) {
      debugPrint('GPS error: $e');
      if (context.mounted) _toast(context, 'تعذر تحديد الموقع، جرّب تاني أو اكتب العنوان بنفسك');
      return null;
    }
  }

  static Future<void> _useGps(BuildContext context) async {
    final picked = await locate(context);
    if (picked == null || !context.mounted) return;
    await _saveAddress(context, picked.address, lat: picked.lat, lng: picked.lng);
  }

  /// شيت اختيار عنوان التوصيل: موقعي الحالي (GPS) أو كتابة العنوان.
  /// الشيت بيرجّع الاختيار والتنفيذ بيحصل بعد ما يتقفل (الكنترولر بيتمسح مع الشيت نفسه).
  static Future<void> open(BuildContext context) async {
    final choice = await showModalBottomSheet<_AddressChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddressSheet(initial: SavedAddress.value.value),
    );
    if (choice == null || !context.mounted) return;
    if (choice.gps) {
      await _useGps(context);
    } else {
      await _saveAddress(context, choice.text);
    }
  }

}


class _AddressChoice {
  const _AddressChoice.gps() : gps = true, text = '';
  const _AddressChoice.text(this.text) : gps = false;
  final bool gps;
  final String text;
}

class _AddressSheet extends StatefulWidget {
  const _AddressSheet({required this.initial});
  final String initial;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اختر موقع التوصيل',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Brand.ink),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(const _AddressChoice.gps()),
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('استخدم موقعي الحالي'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'أو اكتب عنوانك (الحي، الشارع، علامة مميزة)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                final t = _ctrl.text.trim();
                if (t.isEmpty) return;
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop(_AddressChoice.text(t));
              },
              child: const Text('حفظ العنوان'),
            ),
          ],
        ),
      );
}
