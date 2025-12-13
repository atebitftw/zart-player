import 'package:flutter/material.dart';

import 'package:zart_player/src/styled_char.dart';
import 'package:zart_player/src/ui/widgets/matrix_painter.dart';

/// A widget that tries to approximate a Z-Machine screen
/// using a matrix of styled characters.
class MatrixDisplay extends StatefulWidget {
  final List<List<StyledChar>> grid;
  final int cursorRow; // 0-based
  final int cursorCol; // 0-based
  final bool showCursor;
  final double fontSize;
  final double cellWidth;
  final double cellHeight;
  final int version; // To force repaint on grid mutation

  const MatrixDisplay({
    super.key,
    required this.grid,
    required this.cursorRow,
    required this.cursorCol,
    this.showCursor = true,
    this.fontSize = 16.0,
    this.cellWidth = 10.0,
    this.cellHeight = 20.0,
    this.version = 0,
  });

  @override
  State<MatrixDisplay> createState() => _MatrixDisplayState();
}

class _MatrixDisplayState extends State<MatrixDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _cursorBlinkController;

  @override
  void initState() {
    super.initState();
    _cursorBlinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorBlinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cursorBlinkController,
      builder: (context, child) {
        return CustomPaint(
          painter: MatrixPainter(
            grid: widget.grid,
            cursorRow: widget.cursorRow,
            cursorCol: widget.cursorCol,
            showCursor: widget.showCursor && _cursorBlinkController.value > 0.5,
            fontSize: widget.fontSize,
            cellWidth: widget.cellWidth,
            cellHeight: widget.cellHeight,
            version: widget.version,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
