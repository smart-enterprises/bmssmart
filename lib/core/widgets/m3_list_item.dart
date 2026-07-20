// lib/core/widgets/m3_list_item.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// M3 list row: leading icon in a tonal circle, headline/supporting text
/// column, optional trailing content. Reused for cell-voltage rows, device
/// rows, and (if ever needed) event rows.
class M3ListItem extends StatelessWidget {
  const M3ListItem({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.headline,
    required this.supporting,
    this.trailing,
    this.last = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String headline;
  final String supporting;
  final Widget? trailing;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: M3Colors.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(headline, style: const TextStyle(fontSize: 16, color: M3Colors.onSurface), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(supporting, style: const TextStyle(fontSize: 13, color: M3Colors.onSurfaceVariant), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
