import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart_player/src/navigation_service.dart';
import 'package:zart_player/src/ui/upload_screen.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
          surface: const Color(0xFF1E1E1E),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const UploadScreen(),
    );
  }
}
