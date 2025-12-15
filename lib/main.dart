import 'package:flutter/material.dart';
import 'package:zart_player/src/navigation_service.dart';
import 'package:zart_player/src/ui/app_theme.dart';
import 'package:zart_player/src/ui/screens/home_screen.dart';

void main() {
  runApp(const ZartPlayerApp());
}

class ZartPlayerApp extends StatelessWidget {
  const ZartPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey,
      title: 'Zart Player',
      debugShowCheckedModeBanner: false,
      theme: ZartTheme.themeData,
      home: const HomeScreen(),
    );
  }
}
