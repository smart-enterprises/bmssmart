// lib/core/widgets/m3_tonal_button.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// M3 filled-tonal pill toggle button — used for the Charging/Discharge row.
/// Active = solid [activeColor] fill + white text/icon; inactive =
/// surfaceContainerHigh fill + onSurfaceVariant text/icon.
class M3TonalButton extends StatelessWidget {
  const M3TonalButton({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : M3Colors.onSurfaceVariant;
    return Expanded(
      child: Material(
        color: active ? activeColor : M3Colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
