// lib/core/widgets/pill_switch.dart
//
// iOS-style pill toggle, ported from the design's Switch() component.

import 'package:flutter/material.dart';

class PillSwitch extends StatelessWidget {
  const PillSwitch({
    super.key,
    required this.on,
    required this.onChanged,
    required this.activeColor,
  });

  final bool on;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? activeColor : const Color(0x66949EAE),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3)],
          ),
        ),
      ),
    );
  }
}
