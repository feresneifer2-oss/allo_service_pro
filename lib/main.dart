import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/presentation/splash_screen.dart';

void main() {
  runApp(const AlloServiceProApp());
}

class AlloServiceProApp extends StatelessWidget {
  const AlloServiceProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Allo Service Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}