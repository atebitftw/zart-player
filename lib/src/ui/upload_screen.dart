import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:zart_player/src/ui/game_screen.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';
import 'dart:math';

/// The home screen for the app.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
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

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> {
  final List<Widget> _prompts = [];
  final Random _random = Random();
  Timer? _timer;

  // Classic Interactive Fiction prompts
  final List<String> _commands = [
    "go north",
    "go south",
    "go east",
    "go west",
    "ne",
    "nw",
    "se",
    "sw",
    "up",
    "down",
    "in",
    "out",
    "inventory",
    "look",
    "look at sky",
    "look under rug",
    "look in chest",
    "examine lamp",
    "open mailbox",
    "read leaflet",
    "take sword",
    "kill troll",
    "xyzzy",
    "plugh",
    "use the key",
    "open the door",
    "close the door",
    "eat apple",
    "drink potion",
    "unlock door",
    "light lamp",
    "turn on lantern",
    "diagnose",
    "wait",
    "again",
    "save",
    "restore",
    "quit",
    "restart",
    "verbose",
    "score",
    "version",
    "take all",
    "get all",
    "drop gold",
    "hide",
    "take the towel",
    "put the towel over my head",
    "wear cloak",
    "remove armor",
    "eat the lunch",
    "hint",
    "help",
    "lie down in the mud",
    "open the mailbox",
    "push button",
    "pull lever",
    "climb rope",
    "talk to elf",
    "ask wizard about potion",
    "tell troll about treasure",
    "enter cave",
    "leave house",
    "exit",
    "sleep",
    "wake up",
    "tie rope",
  ];

  @override
  void initState() {
    super.initState();
    // Start adding prompts periodically
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (mounted) {
        _addPrompt();
      }
    });
    // Add initial prompt immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _addPrompt());
  }

  void _addPrompt() {
    if (!mounted) return;

    final size = MediaQuery.of(context).size;

    // Don't add if screen is too small or seemingly invalid
    if (size.width < 100 || size.height < 100) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final command = _commands[_random.nextInt(_commands.length)];

    // Random position
    // Avoid dead center where the main card is (roughly)
    double left = _random.nextDouble() * (size.width - 200); // adjust for approximate text width
    double top = _random.nextDouble() * (size.height - 50);

    setState(() {
      _prompts.add(
        Positioned(
          key: Key(id),
          left: left,
          top: top,
          child: TypingPrompt(
            text: "> $command",
            onComplete: () {
              if (mounted) {
                setState(() {
                  _prompts.removeWhere((widget) => widget.key == Key(id));
                });
              }
            },
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: _prompts);
  }
}

class TypingPrompt extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;

  const TypingPrompt({super.key, required this.text, required this.onComplete});

  @override
  State<TypingPrompt> createState() => _TypingPromptState();
}

class _TypingPromptState extends State<TypingPrompt> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  String _displayedText = "";
  int _charIndex = 0;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();

    // Typing effect
    _typingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_charIndex < widget.text.length) {
          _charIndex++;
          _displayedText = widget.text.substring(0, _charIndex);
        } else {
          timer.cancel();
          // Start fade out after typing is done and a small pause
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _controller.forward();
            }
          });
        }
      });
    });

    // Fade out controller
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(_controller)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Randomize color slightly for variety
    // Colors.greenAccent, Colors.tealAccent, or white
    final colors = [
      Colors.greenAccent.withValues(alpha: 0.3),
      Colors.tealAccent.withValues(alpha: 0.3),
      Colors.white.withValues(alpha: 0.2),
    ];
    final color = colors[Random().nextInt(colors.length)];

    return FadeTransition(
      opacity: _opacity,
      child: Text(
        _displayedText,
        style: GoogleFonts.firaCode(
          fontSize: 16 + Random().nextDouble() * 8, // Random size between 16 and 24
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
