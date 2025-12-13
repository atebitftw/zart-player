import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:zart_player/src/ui/screens/game_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart_player/src/ui/widgets/animated_background.dart';

import 'dart:async';

/// The home screen for the app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

  Future<void> _playMiniZork() async {
    // Get minizork.z3 from asset bundle
    final ByteData data = await rootBundle.load('${kDebugMode ? '' : 'assets/'}minizork.z3');
    final Uint8List bytes = data.buffer.asUint8List();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(gameData: bytes, gameName: 'Mini-Zork'),
        ),
      );
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Z-machine files can have various extensions .z5, .z8, .dat
        withData: true,
      );

      if (result != null) {
        PlatformFile file = result.files.first;
        Uint8List? fileBytes = file.bytes;

        if (fileBytes != null) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GameScreen(gameData: fileBytes, gameName: file.name),
              ),
            );
          }
        }
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        children: [
          // Animated Background
          const Positioned.fill(child: AnimatedBackground()),

          // Main Content
          Center(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.95), // Higher opacity to stand out against text
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '> Zart Player',
                    style: GoogleFonts.overpassMono(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Image.asset("${kDebugMode ? '' : 'assets/'}zart_logo.png", width: 200),
                  const SizedBox(height: 16),
                  Text(
                    'Web Interactive Fiction (IF) Player',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.overpassMono(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "You can upload any .z3, .z5, .z7, .z8, and most .dat game files.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.overpassMono(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 32),
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.tealAccent)
                      : ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Select Game File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                            textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                  const SizedBox(height: 8),
                  Text(
                    "Or...",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _playMiniZork,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Mini-Zork'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
