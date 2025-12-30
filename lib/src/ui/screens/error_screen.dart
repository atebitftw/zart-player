import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Error screen displayed when the game encounters a fatal error.
/// Features a themed "eaten by a Grue" aesthetic.
class ErrorScreen extends StatelessWidget {
  final String errorMessage;

  const ErrorScreen({super.key, required this.errorMessage});

  // ASCII art Grue skull
  static const String _grueArt = '''
     .-"        "-.
    /              \\
    |              |
    |,  .-.  .-.  ,|
    | )(__/  \\__)( |
    |/     /\\     \\|
    (_     ^^     _)
    \\__|IIIIII|__/
     |\\IIIIII/ |
     \\          /
     `~~~~~~~~~`
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ASCII Grue Art
                Text(
                  _grueArt,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color.fromARGB(
                      255,
                      132,
                      132,
                      132,
                    ), // Dark cyan
                    fontSize: 14,
                    height: 1.0,
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // "Eaten by a Grue" message
                Text(
                  'This game was eaten by a Grue...',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color.fromARGB(
                      255,
                      166,
                      17,
                      0,
                    ), // Bright green
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Error message box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    border: Border.all(
                      color: const Color.fromARGB(255, 155, 155, 155),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '> ERROR:',
                        style: GoogleFonts.jetBrainsMono(
                          color: const Color(0xFFFF6B6B), // Red
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        errorMessage,
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Return to Home button
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home),
                  label: const Text('Return to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00CED1),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    textStyle: GoogleFonts.jetBrainsMono(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
