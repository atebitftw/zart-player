import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:zart_player/src/ui/widgets/typing_prompt.dart';

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with SingleTickerProviderStateMixin {
  final List<Widget> _prompts = [];
  final Random _random = Random();
  late Ticker _ticker;
  Duration _lastPromptTime = Duration.zero;

  // Classic Interactive Fiction prompts
  // Commands loaded from asset
  List<String> _commands = [];

  Future<void> _loadCommands() async {
    try {
      final String data = await rootBundle.loadString('${kDebugMode ? '' : 'assets/'}commands.txt');
      if (mounted) {
        setState(() {
          _commands = const LineSplitter().convert(data).where((s) => s.trim().isNotEmpty).toList();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading commands: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCommands();

    _ticker = createTicker((elapsed) {
      if (elapsed - _lastPromptTime >= const Duration(milliseconds: 1000)) {
        _lastPromptTime = elapsed;
        _addPrompt();
      }
    });
    _ticker.start();

    // Add initial prompt immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _addPrompt());
  }

  void _addPrompt() {
    if (!mounted) return;

    final size = MediaQuery.of(context).size;

    // Don't add if screen is too small or seemingly invalid, or if commands aren't loaded yet
    if (size.width < 100 || size.height < 100 || _commands.isEmpty) return;

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
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: _prompts);
  }
}
