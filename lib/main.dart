import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:zart_player/src/navigation_service.dart';
import 'package:zart_player/src/ui/app_theme.dart';
import 'package:zart_player/src/ui/screens/home_screen.dart';

final _log = Logger.root;

void main() {
  _log.level = Level.WARNING;
  _log.onRecord.listen((record) {
    print(record);
  });
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
