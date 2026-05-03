import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/bms/presentation/screens/bms_dashboard.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BMS App',
      theme: ThemeData(
        primaryColor: const Color(0xFFFF8C00),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home:  BmsDashboard(),
    );
  }
}