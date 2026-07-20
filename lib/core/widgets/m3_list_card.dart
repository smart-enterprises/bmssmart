// lib/core/widgets/m3_list_card.dart

import 'package:flutter/material.dart';
import '../theme/m3_theme.dart';

/// Card wrapper with a small-caps section title and a child column below it
/// — used to group cell-voltage rows, nearby-device rows, chart cards, etc.
class M3ListCard extends StatelessWidget {
  const M3ListCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.margin,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(color: M3Colors.surfaceContainerLow, borderRadius: BorderRadius.circular(M3Radii.card)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: M3Colors.onSurfaceVariant, letterSpacing: 0.3),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
