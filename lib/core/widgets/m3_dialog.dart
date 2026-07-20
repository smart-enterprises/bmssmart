// lib/core/widgets/m3_dialog.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// M3 basic dialog — scrim, elevated surface, icon in a tonal circle,
/// title, message, two text buttons. Replaces the MOSFET-confirm and
/// location-services AlertDialogs, and provides the outer chrome reused by
/// the manual-MAC dialog.
class M3Dialog extends StatelessWidget {
  const M3Dialog({
    super.key,
    required this.icon,
    this.iconColor = M3Colors.primary,
    required this.title,
    required this.message,
    this.cancelLabel = 'Cancel',
    this.okLabel = 'OK',
    this.destructive = false,
    this.onCancel,
    this.onOk,
    this.showCancel = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String cancelLabel;
  final String okLabel;
  final bool destructive;
  final bool showCancel;
  final VoidCallback? onCancel;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: M3Colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(M3Radii.dialog)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: destructive ? M3Colors.primaryContainer : M3Colors.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: destructive ? M3Colors.primary : M3Colors.onSecondaryContainer),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400, color: M3Colors.onSurface)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 14, color: M3Colors.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showCancel)
                  TextButton(
                    onPressed: onCancel ?? () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel, style: const TextStyle(color: M3Colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ),
                TextButton(
                  onPressed: onOk ?? () => Navigator.of(context).pop(true),
                  child: Text(
                    okLabel,
                    style: TextStyle(color: destructive ? M3Colors.primary : M3Colors.secondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows an [M3Dialog] as a yes/no confirmation and returns the result
/// (true = OK pressed, false/null = cancelled).
Future<bool?> showM3Dialog(
  BuildContext context, {
  required IconData icon,
  Color iconColor = M3Colors.primary,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String okLabel = 'OK',
  bool destructive = false,
  bool showCancel = true,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => M3Dialog(
      icon: icon,
      iconColor: iconColor,
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      okLabel: okLabel,
      destructive: destructive,
      showCancel: showCancel,
      onCancel: () => Navigator.of(ctx).pop(false),
      onOk: () => Navigator.of(ctx).pop(true),
    ),
  );
}
