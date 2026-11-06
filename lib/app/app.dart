import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/shell/presentation/screens/main_shell_screen.dart';

/// MARKET MMS - Kök Uygulama Widget'ı
class MarketPosApp extends StatelessWidget {
  const MarketPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainShellScreen(),
    );
  }
}

