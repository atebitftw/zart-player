import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart/zart.dart';

class Window1Painter extends CustomPainter {
  final List<List<Cell>> grid;
  final int targetCols;
  final double charWidth;
  final double lineHeight;
  final Color Function(int code, {required bool isBackground}) resolveColor;

  Window1Painter({
    required this.grid,
    required this.targetCols,
    required this.charWidth,
    required this.lineHeight,
    required this.resolveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Cache base style to avoid repeated font lookups
    final baseStyle = GoogleFonts.firaCode(fontSize: 16, height: 1.0);

    for (int y = 0; y < grid.length; y++) {
      final row = grid[y];

      // Pass 1: Draw Backgrounds (Coalesced to fix artifacts)
      {
        // Removed running state variables (style persistence)
        // Each cell is atomic. Default (1) means Default/Black.

        int bgStartX = -1;
        Color? lastBgColor;

        // Note: We use row.length instead of targetCols to avoid extending the
        // background color beyond the actual text content.
        void flushBg(int currentX) {
          if (bgStartX != -1 && lastBgColor != null) {
            final rect = Rect.fromLTRB(
              bgStartX * charWidth,
              y * lineHeight,
              currentX * charWidth,
              // Add +1.0 to height to overlap with next row and eliminate horizontal gaps/artifacts
              (y + 1) * lineHeight + 1.0,
            );
            final paint = Paint()
              ..color = lastBgColor!
              ..style = PaintingStyle.fill;
            canvas.drawRect(rect, paint);
          }
          bgStartX = -1;
          lastBgColor = null;
        }

        // Note: Iterate full targetCols to ensure background fills the line if active style demands it.
        // This solves the "width logic" issue by letting the Z-Machine spec (via screen model state)
        // dictate where the background ends, rather than arbitrarily cutting it off.
        // Note: Iterate full targetCols to ensure background fills the line if active style demands it.
        // This solves the "width logic" issue by letting the Z-Machine spec (via screen model state)
        // dictate where the background ends, rather than arbitrarily cutting it off.
        for (int x = 0; x < targetCols; x++) {
          Cell cell;
          if (x < row.length) {
            cell = row[x];
          } else {
            cell = Cell.empty();
          }

          // Direct style resolution (No persistence)
          // 1 is Default (Black/Transparent)
          int effectiveFg = cell.fg;
          int effectiveBg = cell.bg;
          int effectiveStyle = cell.style;

          Color fgColor = resolveColor(effectiveFg, isBackground: false);
          Color bgColor = resolveColor(effectiveBg, isBackground: true);

          if ((effectiveStyle & 1) != 0) {
            // Reverse video
            final temp = fgColor;
            fgColor = bgColor;
            bgColor = temp;
          }

          if (bgColor != lastBgColor) {
            flushBg(x);
            // Start new segment if not black (or update logic if black needs handling)
            if (bgColor != Colors.black) {
              bgStartX = x;
              lastBgColor = bgColor;
            }
          }
        }
        flushBg(targetCols);
      }

      // Pass 2: Draw Text (Optimized)
      {
        final spans = <TextSpan>[];
        StringBuffer lineBuffer = StringBuffer();

        // Initial state
        Color? currentFgColor;
        FontWeight? currentWeight;
        FontStyle? currentStyle;

        void flushSpan() {
          if (lineBuffer.isEmpty) return;

          spans.add(
            TextSpan(
              text: lineBuffer.toString(),
              style: baseStyle.copyWith(color: currentFgColor, fontWeight: currentWeight, fontStyle: currentStyle),
            ),
          );
          lineBuffer.clear();
        }

        for (int x = 0; x < targetCols; x++) {
          Cell cell;
          if (x < row.length) {
            cell = row[x];
          } else {
            cell = Cell.empty();
          }

          // Direct style resolution (No persistence)
          int effectiveFg = cell.fg;
          int effectiveBg = cell.bg;
          int effectiveStyle = cell.style;

          Color fgColor = resolveColor(effectiveFg, isBackground: false);
          Color bgColor = resolveColor(effectiveBg, isBackground: true);

          if ((effectiveStyle & 1) != 0) {
            // Reverse video: Text color becomes background color
            fgColor = bgColor;
          }

          // Determine font properties
          final fontWeight = ((effectiveStyle & 2) != 0) ? FontWeight.bold : FontWeight.normal;
          final fontStyle = ((effectiveStyle & 4) != 0) ? FontStyle.italic : FontStyle.normal;

          // Check for state change
          if (fgColor != currentFgColor || fontWeight != currentWeight || fontStyle != currentStyle) {
            flushSpan();
            currentFgColor = fgColor;
            currentWeight = fontWeight;
            currentStyle = fontStyle;
          }

          // Append char (use space for empty cells)
          lineBuffer.write(cell.char.isEmpty ? ' ' : cell.char);
        }
        flushSpan(); // Flush remaining text

        if (spans.isNotEmpty) {
          textPainter.text = TextSpan(children: spans);
          textPainter.layout();
          // Vertically center the line
          final yOffset = (lineHeight - textPainter.height) / 2;
          textPainter.paint(canvas, Offset(0, (y * lineHeight) + yOffset));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant Window1Painter oldDelegate) {
    return true; // Always repaint for simplicity when update triggers
  }
}
