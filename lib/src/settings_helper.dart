import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsHelper {
  static const String _textColorKey = 'zart_player_text_color_index';

  static const List<Color> availableColors = [
    Color(0xFFB9F6CA), // Green (Default - Colors.greenAccent[100])
    Colors.white,
    Color(0xFFB0BEC5), // Light Grey (Blue Grey 200) - Softer reads
    Colors.amber,
    Colors.cyanAccent,
    Color(0xFFF48FB1), // Pink (Colors.pink[200])
  ];

  static const List<String> colorNames = [
    "Retro Green",
    "Classic White",
    "Dim White",
    "Amber",
    "Cyan",
    "Soft Pink",
  ];

  /// Loads the saved text color index, defaults to 0 (Green).
  Future<int> loadTextColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_textColorKey) ?? 0;
  }

  /// Saves the selected text color index.
  Future<void> saveTextColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_textColorKey, index);
  }

  /// Returns the Color object for a given index.
  Color getColor(int index) {
    if (index < 0 || index >= availableColors.length) {
      return availableColors[0];
    }
    return availableColors[index];
  }
}
