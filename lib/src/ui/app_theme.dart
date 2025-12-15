import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ZartTheme {
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.tealAccent,
        brightness: Brightness.dark,
        surface: const Color(0xFF1E1E1E),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        contentTextStyle: GoogleFonts.firaCode(color: Colors.greenAccent, fontSize: 14),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.greenAccent, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
      ),
    );
  }
}
