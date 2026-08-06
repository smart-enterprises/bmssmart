// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/warrior_theme.dart';
import 'features/bms/presentation/screens/splash_screen.dart';

void main() {
  runApp(const ProviderScope(child: SmartBmsApp()));
}

class SmartBmsApp extends StatelessWidget {
  const SmartBmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartBMS',
      theme: buildWarriorTheme(),
      home: const SplashScreen(),
    );
  }
}