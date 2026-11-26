import 'package:flutter/material.dart';

import '../services/data_saver.dart';
import '../theme/brand.dart';
import 'app_snack.dart';

/// مفتاح «توفير الباقة» في صفحة الحساب.
class DataSaverTile extends StatelessWidget {
  const DataSaverTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DataSaver.enabled,
      builder: (context, on, _) => SwitchListTile(
        key: const Key('account-data-saver'),
        value: on,
        secondary: Icon(Icons.data_saver_on_outlined, color: Brand.green),
        title: const Text('توفير الباقة'),
        subtitle: const Text('صور أخف بتستهلك نت أقل'),
        onChanged: (value) async {
          await DataSaver.set(value);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(appSnack(
            value
                ? 'اتفعّل توفير الباقة. الصور الجديدة هتتحمّل أخف.'
                : 'اتقفل توفير الباقة. الصور هترجع بجودتها العادية.',
          ));
        },
      ),
    );
  }
}
