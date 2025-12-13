import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TypingPrompt extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;

  const TypingPrompt({super.key, required this.text, required this.onComplete});

  @override
  State<TypingPrompt> createState() => _TypingPromptState();
}

class _TypingPromptState extends State<TypingPrompt> with TickerProviderStateMixin {
  late AnimationController _typingController;
  late AnimationController _fadeController;
  late Animation<double> _opacity;
  late Animation<int> _characterCount;

  @override
  void initState() {
    super.initState();

    // typing duration: 100ms per character
    final typingDuration = Duration(milliseconds: widget.text.length * 100);

    _typingController = AnimationController(vsync: this, duration: typingDuration);
    _characterCount = StepTween(begin: 0, end: widget.text.length).animate(_typingController);

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(_fadeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      });

    // Start typing
    _typingController.forward().then((_) {
      // Wait a bit before fading out
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _fadeController.forward();
        }
      });
    });
  }

  @override
  void dispose() {
    _typingController.dispose();
    _fadeController.dispose();
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

    return AnimatedBuilder(
      animation: Listenable.merge([_typingController, _fadeController]),
      builder: (context, child) {
        final textToShow = widget.text.substring(0, _characterCount.value);
        return Opacity(
          opacity: _opacity.value,
          child: Text(
            textToShow,
            style: GoogleFonts.firaCode(
              fontSize: 16 + Random().nextDouble() * 8, // Random size between 16 and 24
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
