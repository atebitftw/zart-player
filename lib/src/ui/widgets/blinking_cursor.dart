import 'dart:async';

import 'package:flutter/material.dart';

/// Blinking cursor widget
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> {
  Timer? _timer;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _isVisible = !_isVisible;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Duration.zero,
      opacity: _isVisible ? 1.0 : 0.0,
      child: Transform.translate(
        offset: const Offset(0, 2),
        child: Container(
          width: 2, // Line cursor
          height: 20,
          color: const Color(0xFFC0C0C0), // Light grey
        ),
      ),
    );
  }
}
