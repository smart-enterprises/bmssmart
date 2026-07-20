// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
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
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          surface: AppColors.card,
          error: AppColors.danger,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: AppColors.text,
              displayColor: AppColors.text,
            ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.text,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}