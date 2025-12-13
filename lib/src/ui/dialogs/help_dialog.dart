import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart/zart.dart';

class HelpDialog extends StatelessWidget {
  const HelpDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return const HelpDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: Text('About Zart Player', style: GoogleFonts.outfit(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Zart Player Uses:",
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(getPreamble().join('\n'), style: GoogleFonts.inter(color: Colors.grey[300], fontSize: 14)),
            const SizedBox(height: 16),
            Text(
              'Tips for Saving & Restoring Games',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '• While playing the game, type "save" to save your game progress.\n'
              '• Type "restore" to load a saved game.\n'
              '• On web, saves usually default to your "Downloads" folder.\n',
              style: GoogleFonts.inter(color: Colors.grey[300], fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
