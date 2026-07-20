// lib/core/widgets/m3_top_app_bar.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// Shared M3 top app bar used by all three tabs: a tonal surface with
/// bottom-rounded corners, a small eyebrow label, and a large title.
class M3TopAppBar extends StatelessWidget {
  const M3TopAppBar({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.leading,
    this.child,
  });

  /// Small label above the title. Pass a [Text] for a plain string, or any
  /// widget (e.g. a device-name + status-dot row) for a composite eyebrow.
  final Widget eyebrow;

  /// Pass a [Text] for a plain string title, or any widget (e.g. a brand
  /// logo image) to replace the title text entirely.
  final Widget title;
  final Widget? trailing;
  final Widget? leading;

  /// Optional content placed below the title (e.g. the SOC gauge on Home).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 20),
      decoration: const BoxDecoration(
        color: M3Colors.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(M3Radii.topBar),
          bottomRight: Radius.circular(M3Radii.topBar),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: M3Colors.onSurfaceVariant),
                      child: eyebrow,
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: M3Colors.onSurface, letterSpacing: -0.2),
                      child: title,
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          ?child,
        ],
      ),
    );
  }
}
