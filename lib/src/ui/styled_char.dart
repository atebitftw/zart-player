class StyledChar {
  final String char;
  final int fg;
  final int bg;
  final int style;

  const StyledChar(this.char, this.fg, this.bg, this.style);

  // Helper for empty char
  static const empty = StyledChar(' ', -1, -1, 0);
}
