import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:zart_web_player/src/navigation_service.dart';
import 'package:zart_web_player/src/ui/app_theme.dart';
import 'package:zart_web_player/src/ui/screens/home_screen.dart';

final _log = Logger.root;

void main() {
  if (kDebugMode) {
    _log.level = Level.INFO;
    _log.onRecord.listen((record) {
      // ignore: avoid_print
      print(record);
    });
  }

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
