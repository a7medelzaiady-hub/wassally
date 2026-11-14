import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// أزرار الزيادة والنقصان (− 2 +).
class QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const QtyStepper({
    super.key,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  Widget _button(IconData icon, String tooltip, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Icon(icon, size: 20, color: kPrimary)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kPrimarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove, 'نقص', onRemove),
          SizedBox(
            width: 26,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          _button(Icons.add, 'زيادة', onAdd),
        ],
      ),
    );
  }
}
