import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart_player/src/settings_helper.dart';

class SettingsDialog extends StatelessWidget {
  final int selectedColorIndex;
  final ValueChanged<int> onColorSelected;

  const SettingsDialog({super.key, required this.selectedColorIndex, required this.onColorSelected});

  static void show(
    BuildContext context, {
    required int selectedColorIndex,
    required ValueChanged<int> onColorSelected,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(selectedColorIndex: selectedColorIndex, onColorSelected: onColorSelected);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: Text('Settings', style: GoogleFonts.outfit(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Text Color:', style: GoogleFonts.inter(color: Colors.grey[400])),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: List.generate(SettingsHelper.availableColors.length, (index) {
                final isSelected = index == selectedColorIndex;
                return GestureDetector(
                  onTap: () {
                    onColorSelected(index);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: SettingsHelper.availableColors[index],
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
