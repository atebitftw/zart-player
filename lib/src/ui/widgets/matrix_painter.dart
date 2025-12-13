import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart_player/src/styled_char.dart';

class MatrixPainter extends CustomPainter {
  final List<List<StyledChar>> grid;
  final int cursorRow;
  final int cursorCol;
  final bool showCursor;
  final double fontSize;
  final double cellWidth;
  final double cellHeight;
  final int version;

  MatrixPainter({
    required this.grid,
    required this.cursorRow,
    required this.cursorCol,
    required this.showCursor,
    required this.fontSize,
    required this.cellWidth,
    required this.cellHeight,
    required this.version,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Backgrounds first (batch if possible, but simple loop is fine for 80x25)
    final bgPaint = Paint();

    // We can optimize text drawing by batching same-style chars,
    // but drawing char-by-char with a single text layout per char is easiest to implement first.
    // For performance, we should ideally construct a Paragraph for the entire grid,
    // but alignment is tricky with variable width fonts.
    // We MUST use a Monospace font and fixed cell width.

    final textStyle = GoogleFonts.firaCode(fontSize: fontSize, color: Colors.white);

    for (int r = 0; r < grid.length; r++) {
      final line = grid[r];
      for (int c = 0; c < line.length; c++) {
        final char = line[c];
        final x = c * cellWidth;
        final y = r * cellHeight;

        // Draw Cell Background
        if (char.bg != -1) {
          bgPaint.color = _getZColor(char.bg) ?? Colors.transparent;
          if (bgPaint.color != Colors.transparent) {
            canvas.drawRect(Rect.fromLTWH(x, y, cellWidth, cellHeight), bgPaint);
          }
        }

        // Draw Char
        if (char.char.isNotEmpty && char.char != ' ') {
          final span = TextSpan(
            text: char.char,
            style: textStyle.copyWith(
              color: _getZColor(char.fg) ?? Colors.white,
              fontWeight: (char.style & 2 != 0) ? FontWeight.bold : FontWeight.normal,
              fontStyle: (char.style & 4 != 0) ? FontStyle.italic : FontStyle.normal,
              backgroundColor: null, // BG drawn manually
            ),
          );

          final textPainter = TextPainter(text: span, textDirection: TextDirection.ltr);
          textPainter.layout();
          // Center text in cell? Or top-left? Top-left usually for terminals.
          textPainter.paint(canvas, Offset(x, y));
        }
      }
    }

    // 2. Draw Cursor
    if (showCursor) {
      final cx = cursorCol * cellWidth;
      final cy = cursorRow * cellHeight;

      final cursorPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      // Block cursor or Underscore?
      // Block is more retro/visible.
      canvas.drawRect(Rect.fromLTWH(cx, cy, cellWidth, cellHeight), cursorPaint);

      // Invert text under cursor?
      // Too complex for now, just drawing over it is fine or using exclusion blend mode.
    }
  }

  Color? _getZColor(int code) {
    // Z-Machine Colors:
    // 2=Black, 3=Red, 4=Green, 5=Yellow, 6=Blue, 7=Magenta, 8=Cyan, 9=White
    switch (code) {
      case 2:
        return Colors.black;
      case 3:
        return Colors.redAccent;
      case 4:
        return Colors.greenAccent;
      case 5:
        return Colors.yellowAccent;
      case 6:
        return Colors.blueAccent;
      case 7:
        return Colors.purpleAccent;
      case 8:
        return Colors.cyanAccent;
      case 9:
        return Colors.white;
      default:
        return null;
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter oldDelegate) {
    return oldDelegate.version != version ||
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.showCursor != showCursor;
  }
}
