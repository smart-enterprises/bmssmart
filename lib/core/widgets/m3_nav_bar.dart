// lib/core/widgets/m3_nav_bar.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

class M3NavItem {
  final IconData icon;
  final String label;
  const M3NavItem({required this.icon, required this.label});
}

/// Floating dark pill bottom nav — net-new, no prior equivalent in this app.
/// Active item shows a filled primary-color pill + white icon/label;
/// inactive items show icon-only in inverseOnSurface.
class M3NavBar extends StatelessWidget {
  const M3NavBar({super.key, required this.items, required this.index, required this.onChanged});

  final List<M3NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: M3Colors.inverseSurface,
        borderRadius: BorderRadius.circular(M3Radii.navPill),
        boxShadow: const [
          BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) _item(items[i], i == index, () => onChanged(i)),
        ],
      ),
    );
  }

  Widget _item(M3NavItem item, bool active, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: active ? 20 : 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? M3Colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 20, color: active ? Colors.white : M3Colors.inverseOnSurface),
              if (active) ...[
                const SizedBox(width: 8),
                Text(item.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
