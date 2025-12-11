import 'dart:async';

// ignore_for_file: unused_field
// Some fields exist for Z-Machine spec compliance and future use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/ui/matrix_display.dart';
import 'package:zart_player/src/ui/settings_helper.dart';
import 'package:zart_player/src/ui/styled_char.dart';
import 'package:zart_player/src/zart_io_provider.dart';

/// Z-Machine Screen Model compliant game screen.
/// Implements Z-Machine Standard 1.1 Section 8 for V3 and V5+ (excluding V6).
///
/// Key features:
/// - V3: Interpreter-rendered status line at top
/// - V3/V5+: Upper window (Window 1) and Lower window (Window 0)
/// - Cursor positioning in upper window only (V5+)
/// - Text styles: Roman, Bold, Italic, Reverse Video, Fixed Pitch
/// - Full color support for V5+
class GameScreen extends StatefulWidget {
  final Uint8List gameData;
  final String gameName;

  const GameScreen({super.key, required this.gameData, required this.gameName});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final ZartIOProvider _io;
  final ScrollController _scrollController = ScrollController();

  // Input State
  late final FocusNode _inputFocusNode;
  final TextEditingController _inputController = TextEditingController();
  String _inputBuffer = "";
  final List<String> _inputHistory = [];
  int _historyIndex = -1;

  void _debugLog(String message) {
    if (ZartIOProvider.debugMode && kDebugMode) {
      debugPrint(message);
    }
  }

  // ===== Z-Machine Screen Model State =====

  /// Z-Machine version (3, 4, 5, 7, 8) - read from header byte 0
  int _zVersion = 5;

  /// Screen dimensions in characters (spec §8.4)
  static const int screenWidthChars = 80;
  static const int screenHeightLines = 25;

  // ----- V3 Status Line (spec §8.2) -----
  /// For V3 games, interpreter renders status line from globals
  String _statusLocation = "";
  String _statusRight = ""; // "Score/Turns" or "Time"

  // ----- Window 0 (Lower/Main) - Scrolling (spec §8.6.2, §8.7.3) -----
  final List<TextSpan> _window0History = [];
  final List<TextSpan> _window0CurrentLine = [];

  /// V4: cursor always at bottom. V5+: cursor can be anywhere in lower window.
  int _window0CursorRow = 1; // 1-based, for V5+
  int _window0CursorCol = 1;

  // ----- Window 1 (Upper) - Non-scrolling overlay (spec §8.6.1, §8.7.2) -----
  int _window1Height = 0; // In lines (0 = collapsed)
  final List<List<StyledChar>> _window1Buffer = [];
  int _window1Version = 0; // Force repaint counter

  /// Cursor position in Window 1 (1-based, spec §8.7.2.3)
  int _window1CursorRow = 1;
  int _window1CursorCol = 1;

  /// Tracks recent Window 1 text for duplicate suppression
  final Set<String> _recentWindow1Text = {};

  /// Pending shrink height - defers shrink until input when quote displayed
  int? _pendingShrinkHeight;

  // ----- Active Window (spec §8.6.1, §8.7.2) -----
  /// 0 = lower window, 1 = upper window
  int _activeWindow = 0;

  // ----- Text Style (spec §8.7.1) -----
  /// Bitmask: 0=Roman, 1=Reverse, 2=Bold, 4=Italic, 8=Fixed
  int _textStyle = 0;

  // ----- Colors (spec §8.3) -----
  /// Foreground color code (1=default, 2-9=standard colors)
  int _foregroundColor = 1;

  /// Background color code
  int _backgroundColor = 1;

  // ----- Settings -----
  final SettingsHelper _settingsHelper = SettingsHelper();
  Color _defaultFgColor = SettingsHelper.availableColors[0];
  final Color _defaultBgColor = Colors.black;
  int _selectedColorIndex = 0;

  ZMachineRunState? _engineState;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _io = ZartIOProvider();

    _inputFocusNode = FocusNode(onKeyEvent: (node, event) => _handleKeyEvent(event));

    _startGame();
    _io.outputStream.listen(_handleGameCommand);
  }

  Future<void> _loadSettings() async {
    _selectedColorIndex = await _settingsHelper.loadTextColorIndex();
    setState(() {
      _defaultFgColor = _settingsHelper.getColor(_selectedColorIndex);
    });
  }

  void _startGame() async {
    Debugger.enableDebug = false;
    Debugger.enableVerbose = false;
    Debugger.enableTrace = false;
    Debugger.enableStackTrace = false;

    try {
      var blorbData = Blorb.getZData(widget.gameData);
      Z.io = _io;
      Z.load(blorbData);

      // Detect Z-Machine version from header byte 0
      _zVersion = Z.engine.mem.loadb(0);

      // Per spec §8.6.3 / §8.7.3.3: Clear screen at game start
      _clearAllWindows();

      await _pumpEngine();
    } catch (e) {
      _printToWindow0("Failed to load game: $e\n");
    }
  }

  /// Clears all windows per spec §8.7.3.3
  void _clearAllWindows() {
    setState(() {
      _window0History.clear();
      _window0CurrentLine.clear();
      _window0CursorRow = 1;
      _window0CursorCol = 1;

      _window1Buffer.clear();
      _window1Height = 0;
      _window1CursorRow = 1;
      _window1CursorCol = 1;

      _activeWindow = 0;
      _textStyle = 0;
      _foregroundColor = 1;
      _backgroundColor = 1;
    });
  }

  Future<void> _pumpEngine() async {
    _engineState = await Z.runUntilInput();

    if (_engineState == ZMachineRunState.quit) {
      _printToWindow0("\n*** GAME OVER ***\n");
    }

    if (mounted) {
      _inputFocusNode.requestFocus();
      setState(() {});
    }
  }

  Future<void> _submitInput(String input) async {
    _debugLog('submitInput: input="$input"');
    // Apply any pending window shrink now that user has provided input
    _applyPendingShrink();

    if (_engineState == ZMachineRunState.needsLineInput) {
      _engineState = await Z.submitLineInput(input);
    } else if (_engineState == ZMachineRunState.needsCharInput) {
      final char = input.isEmpty ? '\n' : input;
      _engineState = await Z.submitCharInput(char);
    }

    if (_engineState == ZMachineRunState.quit) {
      _printToWindow0("\n*** GAME OVER ***\n");
    }

    if (mounted) {
      _inputController.clear();
      setState(() {
        _inputBuffer = "";
      });
      _inputFocusNode.requestFocus();
    }
  }

  // ===== Command Handlers =====

  void _handleGameCommand(GameCommand cmd) {
    if (!mounted) return;

    switch (cmd) {
      case PrintText(:final text, :final window):
        _debugLog('PrintText: window=$window, text="${text.length > 40 ? text.substring(0, 40) : text}..."');
        if (window == 0) {
          // Check if this is duplicate content from Window 1 (bracketed)
          final normalized = _normalizeForMatching(text);
          final isDuplicate =
              normalized.isNotEmpty &&
              _recentWindow1Text.any((w1Text) => w1Text.contains(normalized) || normalized.contains(w1Text));
          if (isDuplicate) {
            _debugLog('  -> Suppressing duplicate bracketed content');
            // Skip duplicate bracketed content from Window 1
          } else {
            _printToWindow0(text);
          }
        } else {
          // Only track Window 1 content when it's a quote box (height > 1)
          // Don't track status bar content (height == 1) to avoid false positives
          if (_window1Height > 1) {
            final normalized = _normalizeForMatching(text);
            if (normalized.isNotEmpty) {
              _recentWindow1Text.add(normalized);
            }
          }
          _printToWindow1(text);
          // Window 1 prints are awaited by engine - signal after render
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _io.signalRenderComplete();
          });
        }

      case SplitWindow(:final lines):
        _debugLog('SplitWindow: lines=$lines (current height: $_window1Height)');
        // If shrinking and we have Window 1 content, defer the shrink until input
        if (lines < _window1Height && _recentWindow1Text.isNotEmpty) {
          _debugLog('  -> Deferring shrink until input');
          _pendingShrinkHeight = lines;
          // Still signal complete so engine can continue
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _io.signalRenderComplete();
          });
        } else {
          _handleSplitWindow(lines);
          // Signal after frame renders - engine awaits this for splitWindow
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _io.signalRenderComplete();
          });
        }

      case SetWindow(:final id):
        _debugLog('SetWindow: id=$id');
        _handleSetWindow(id);

      case SetCursor(:final line, :final column):
        _debugLog('SetCursor: line=$line, column=$column');
        _handleSetCursor(line, column);

      case ClearScreen(:final window):
        _debugLog('ClearScreen: window=$window');
        _handleClearScreen(window);

      case SetTextStyle(:final style):
        _debugLog('SetTextStyle: style=$style');
        _handleSetTextStyle(style);

      case Setcolor(:final foreground, :final background):
        _debugLog('SetColor: fg=$foreground, bg=$background');
        _handleSetColor(foreground, background);

      case StatusUpdate(:final location, :final formattedRight):
        _debugLog('StatusUpdate: location=$location, right=$formattedRight');
        _handleStatusUpdate(location, formattedRight);

      case EraseLine():
        _debugLog('EraseLine');
        _handleEraseLine();
    }
  }

  /// Normalizes text for matching Window 1 content to Window 0 duplicates.
  /// Strips brackets, quotes, extra whitespace.
  String _normalizeForMatching(String text) {
    return text
        .replaceAll(
          RegExp(
            r'[\[\]"'
            "'"
            r']+',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Apply any pending shrink (called when user inputs)
  void _applyPendingShrink() {
    if (_pendingShrinkHeight != null) {
      // Clear Window 0 when transitioning from title screen
      // This mimics the expected clear that happens after title screens
      setState(() {
        _window0History.clear();
        _window0CurrentLine.clear();
      });

      _handleSplitWindow(_pendingShrinkHeight!);
      _pendingShrinkHeight = null;
      _recentWindow1Text.clear();
    }
  }

  /// Split window (spec §8.6.1.1, §8.7.2.1)
  void _handleSplitWindow(int lines) {
    setState(() {
      final oldHeight = _window1Height;
      _window1Height = lines;

      // Ensure buffer has enough rows
      while (_window1Buffer.length < _window1Height) {
        _window1Buffer.add(List.filled(screenWidthChars, StyledChar.empty, growable: true));
      }

      // V3: When split occurs, upper window is cleared (spec §8.6.1.1.2)
      if (_zVersion == 3 && lines > 0 && oldHeight != lines) {
        for (var row in _window1Buffer) {
          row.fillRange(0, row.length, StyledChar.empty);
        }
      }

      // V5+: If cursor would be inside new upper window area, move it down
      // (spec §8.7.2.2)
      if (_zVersion >= 5 && _activeWindow == 0) {
        // Lower window cursor position check - just ensure it's below upper window
      }

      _window1Version++;
    });
  }

  /// Set active window (spec §8.6.1, §8.7.2)
  void _handleSetWindow(int id) {
    setState(() {
      _activeWindow = id;

      // Per spec §8.6.1 / §8.7.2: Selecting upper window resets cursor to (1,1)
      if (id == 1) {
        _window1CursorRow = 1;
        _window1CursorCol = 1;
      }

      _window1Version++;
    });
  }

  /// Set cursor position (spec §8.7.2.3)
  /// Only valid in upper window for V3-V5. Has no effect in lower window.
  void _handleSetCursor(int line, int column) {
    if (_activeWindow == 1) {
      setState(() {
        // Clamp to valid range (1-based)
        _window1CursorRow = line.clamp(1, _window1Height > 0 ? _window1Height : 1);
        _window1CursorCol = column.clamp(1, screenWidthChars);
      });
    }
    // Per spec: set_cursor has no effect when lower window is selected
  }

  /// Clear screen (spec §8.7.3.2, §8.7.3.3)
  void _handleClearScreen(int window) {
    setState(() {
      switch (window) {
        case -1:
          // Clear all, collapse upper, select lower, cursor to top-left (V5) or bottom-left (V4)
          _window0History.clear();
          _window0CurrentLine.clear();
          _window1Buffer.clear();
          _window1Height = 0;
          _activeWindow = 0;
          _window0CursorRow = 1;
          _window0CursorCol = 1;
          _window1CursorRow = 1;
          _window1CursorCol = 1;

        case 0:
          // Clear lower window
          _window0History.clear();
          _window0CurrentLine.clear();
          // V5: cursor to top-left; V4: cursor to bottom-left
          _window0CursorRow = 1;
          _window0CursorCol = 1;

        case 1:
          // Clear upper window, cursor to top-left
          for (var row in _window1Buffer) {
            row.fillRange(0, row.length, _createEmptyChar());
          }
          _window1CursorRow = 1;
          _window1CursorCol = 1;
      }

      _window1Version++;
    });
  }

  /// Set text style (spec §8.7.1)
  void _handleSetTextStyle(int style) {
    setState(() {
      if (style == 0) {
        // Roman = clear all styles
        _textStyle = 0;
      } else {
        // Combine styles (though spec doesn't require supporting combinations)
        _textStyle |= style;
      }
    });
  }

  /// Set colors (spec §8.3)
  void _handleSetColor(int foreground, int background) {
    setState(() {
      if (foreground > 0) _foregroundColor = foreground;
      if (background > 0) _backgroundColor = background;
    });
  }

  /// V3 status line update (spec §8.2)
  void _handleStatusUpdate(String location, String formattedRight) {
    if (_zVersion == 3) {
      setState(() {
        _statusLocation = location;
        _statusRight = formattedRight;
      });
    }
  }

  /// Erase from cursor to end of line in upper window (spec §8.7.3.4)
  void _handleEraseLine() {
    if (_activeWindow == 1 && _window1CursorRow <= _window1Buffer.length) {
      setState(() {
        final row = _window1Buffer[_window1CursorRow - 1];
        for (int i = _window1CursorCol - 1; i < row.length; i++) {
          row[i] = _createEmptyChar();
        }
        _window1Version++;
      });
    }
  }

  /// Create empty char with current background color
  StyledChar _createEmptyChar() {
    return StyledChar(' ', _backgroundColor, _backgroundColor, 0);
  }

  // ===== Printing =====

  /// Print to lower window (Window 0)
  void _printToWindow0(String text) {
    if (text == '\b') return; // Ignore backspace

    setState(() {
      int start = 0;
      for (int i = 0; i < text.length; i++) {
        if (text[i] == '\n') {
          if (i > start) {
            _addSpanToWindow0(text.substring(start, i));
          }
          _commitWindow0Line();
          start = i + 1;
        }
      }

      if (start < text.length) {
        _addSpanToWindow0(text.substring(start));
      }
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _addSpanToWindow0(String chunk) {
    if (chunk.isEmpty) return;

    // Resolve colors
    Color fgColor = _resolveColor(_foregroundColor, isBackground: false);
    Color bgColor = _resolveColor(_backgroundColor, isBackground: true);

    // Handle Reverse Video (spec §8.7.1)
    if (_textStyle & 1 != 0) {
      final temp = fgColor;
      fgColor = bgColor;
      bgColor = temp;
    }

    _window0CurrentLine.add(
      TextSpan(
        text: chunk,
        style: GoogleFonts.firaCode(
          color: fgColor,
          backgroundColor: bgColor,
          fontWeight: (_textStyle & 2 != 0) ? FontWeight.bold : FontWeight.normal,
          fontStyle: (_textStyle & 4 != 0) ? FontStyle.italic : FontStyle.normal,
          fontSize: 16,
          height: 1.4,
        ),
      ),
    );
  }

  void _commitWindow0Line() {
    final line = TextSpan(children: List.from(_window0CurrentLine));
    _window0History.add(line);
    _window0CurrentLine.clear();
  }

  /// Print to upper window (Window 1) - overlay at cursor position
  void _printToWindow1(String text) {
    setState(() {
      // Ensure row exists
      while (_window1Buffer.length < _window1CursorRow) {
        _window1Buffer.add(List.filled(screenWidthChars, StyledChar.empty, growable: true));
      }

      var row = _window1Buffer[_window1CursorRow - 1];

      // Ensure row is wide enough
      while (row.length < screenWidthChars) {
        row.add(StyledChar.empty);
      }

      int col = _window1CursorCol - 1; // Convert to 0-based

      for (int i = 0; i < text.length; i++) {
        if (text[i] == '\n') {
          // Newline: move to next row, column 1
          _window1CursorRow++;
          _window1CursorCol = 1;
          col = 0;

          // Ensure next row exists
          while (_window1Buffer.length < _window1CursorRow) {
            _window1Buffer.add(List.filled(screenWidthChars, StyledChar.empty, growable: true));
          }
          row = _window1Buffer[_window1CursorRow - 1];
          continue;
        }

        // Print character at cursor position (overlay)
        if (col < row.length) {
          row[col] = StyledChar(text[i], _foregroundColor, _backgroundColor, _textStyle);
        }
        col++;

        // Wrap at right edge? Per spec, upper window doesn't scroll,
        // and printing at bottom-right has undefined cursor behavior.
        // We'll just stay at the edge if we exceed.
        if (col >= screenWidthChars) {
          col = screenWidthChars - 1;
        }
      }

      _window1CursorCol = col + 1; // Back to 1-based
      _window1Version++;
    });
  }

  // ===== Color Resolution (spec §8.3.1) =====

  Color _resolveColor(int code, {required bool isBackground}) {
    switch (code) {
      case 0: // Current - no change (shouldn't reach here normally)
        return isBackground ? _defaultBgColor : _defaultFgColor;
      case 1: // Default
        return isBackground ? _defaultBgColor : _defaultFgColor;
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
        return const Color(0xFFD02090); // Magenta
      case 8:
        return Colors.cyanAccent;
      case 9:
        return Colors.white;
      default:
        return isBackground ? _defaultBgColor : _defaultFgColor;
    }
  }

  // ===== Input Handling =====

  Future<void> _handleUserInput(String input) async {
    if (input.isNotEmpty && (_inputHistory.isEmpty || _inputHistory.last != input)) {
      _inputHistory.add(input);
    }
    _historyIndex = -1;

    // Echo input for line input mode
    if (_engineState == ZMachineRunState.needsLineInput) {
      _printToWindow0("$input\n");
    }

    setState(() {
      _inputBuffer = "";
      _inputController.clear();
    });

    // Handle chained commands (e.g., "open mailbox. take leaflet")
    final commands = input.split('.').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

    if (commands.isEmpty) {
      await _submitInput("");
      return;
    }

    await _submitInput(commands[0]);

    for (int i = 1; i < commands.length; i++) {
      if (_engineState != ZMachineRunState.needsLineInput) break;

      final cmd = commands[i];
      _printToWindow0("$cmd\n");
      await Future.delayed(const Duration(milliseconds: 50));
      await _submitInput(cmd);
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // In needsCharInput mode, forward special keys immediately to the engine
    // using ZSCII codes (spec §3.8.5.4)
    if (_engineState == ZMachineRunState.needsCharInput) {
      String? zsciiChar;

      // ZSCII arrow key codes (spec §3.8.5.4)
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        zsciiChar = String.fromCharCode(129); // Cursor up
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        zsciiChar = String.fromCharCode(130); // Cursor down
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        zsciiChar = String.fromCharCode(131); // Cursor left
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        zsciiChar = String.fromCharCode(132); // Cursor right
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        zsciiChar = String.fromCharCode(27); // Escape
      } else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
        zsciiChar = String.fromCharCode(8); // Delete
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        zsciiChar = '\n'; // Enter/Return (ZSCII 13)
      }
      // Function keys F1-F12: ZSCII 133-144 (if needed later)

      if (zsciiChar != null) {
        _submitInput(zsciiChar);
        return KeyEventResult.handled;
      }
    }

    // Line input mode: arrow up/down for command history
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_inputHistory.isNotEmpty) {
        setState(() {
          if (_historyIndex == -1) {
            _historyIndex = _inputHistory.length - 1;
          } else if (_historyIndex > 0) {
            _historyIndex--;
          }
          _setInputText(_inputHistory[_historyIndex]);
        });
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex != -1) {
        setState(() {
          if (_historyIndex < _inputHistory.length - 1) {
            _historyIndex++;
            _setInputText(_inputHistory[_historyIndex]);
          } else {
            _historyIndex = -1;
            _setInputText("");
          }
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _setInputText(String text) {
    _inputBuffer = text;
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
  }

  void _onInputChanged(String value) {
    if (_engineState == ZMachineRunState.needsCharInput) {
      if (value.isNotEmpty) {
        final char = value.length == 1 ? value : value.substring(value.length - 1);
        _submitInput(char);
        _inputController.clear();
        return;
      }
    }

    setState(() {
      _inputBuffer = value;
    });
  }

  @override
  void dispose() {
    _io.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // ===== UI Build =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(widget.gameName, style: GoogleFonts.outfit()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _showHelpDialog),
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsDialog),
        ],
      ),
      body: Listener(
        onPointerDown: (_) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (context.mounted && !_inputFocusNode.hasFocus) {
              _inputFocusNode.requestFocus();
            }
          });
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  // Hidden input field for keyboard capture
                  Opacity(
                    opacity: 0,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        autofocus: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.transparent),
                        onChanged: _onInputChanged,
                        onSubmitted: _handleUserInput,
                      ),
                    ),
                  ),

                  // V3 Status Line (interpreter-rendered, spec §8.2)
                  if (_zVersion == 3) _buildV3StatusLine(),

                  // Main game area: Window 1 OVERLAYS Window 0 per spec §8.7.2.1
                  // "the upper window on the top n lines of the screen, overlaying
                  // any text which is already there"
                  Expanded(
                    child: Stack(
                      children: [
                        // Window 0 (Lower) - fills entire space, scrolling text
                        // Padding at top to account for Window 1 overlay
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.only(top: _window1Height * 20.0),
                            child: _buildWindow0(),
                          ),
                        ),

                        // Window 1 (Upper) - overlays top portion
                        if (_window1Height > 0)
                          Positioned(top: 0, left: 0, right: 0, height: _window1Height * 20.0, child: _buildWindow1()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// V3 Status Line (spec §8.2)
  Widget _buildV3StatusLine() {
    return Container(
      color: const Color(0xFFC0C0C0), // Softer grey background
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusLocation,
              style: GoogleFonts.firaCode(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _statusRight,
            style: GoogleFonts.firaCode(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Window 1 (Upper, spec §8.6.1 / §8.7.2)
  Widget _buildWindow1() {
    return Container(
      color: Colors.black,
      height: _window1Height * 20.0, // 20 pixels per line (cellHeight)
      width: double.infinity,
      child: ClipRect(
        child: MatrixDisplay(
          grid: _window1Buffer,
          cursorRow: _activeWindow == 1 ? _window1CursorRow - 1 : -1,
          cursorCol: _activeWindow == 1 ? _window1CursorCol - 1 : -1,
          showCursor: _activeWindow == 1,
          cellHeight: 20.0,
          cellWidth: 10.0,
          fontSize: 16.0,
          version: _window1Version,
        ),
      ),
    );
  }

  /// Window 0 (Lower, spec §8.6.2 / §8.7.3)
  Widget _buildWindow0() {
    return Container(
      color: Colors.black,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _window0History.length + 1,
          itemBuilder: (context, index) {
            if (index == _window0History.length) {
              // Current input line
              return RichText(
                text: TextSpan(
                  children: [
                    ..._window0CurrentLine,
                    TextSpan(
                      text: _inputBuffer,
                      style: GoogleFonts.firaCode(color: _defaultFgColor, fontSize: 16, height: 1.4),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _activeWindow == 0 ? const BlinkingCursor() : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            }
            return RichText(text: _window0History[index]);
          },
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: Text('About Zart Player', style: GoogleFonts.outfit(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Zart Player Uses:",
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  getPreamble().join('\n'),
                  style: GoogleFonts.inter(color: Colors.grey[300], fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tips for Saving & Restoring Games',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '• While playing the game, type "save" to save your game progress.\n'
                  '• Type "restore" to load a saved game.\n'
                  '• On web, saves usually default to your "Downloads" folder.\n',
                  style: GoogleFonts.inter(color: Colors.grey[300], fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: Text('Settings', style: GoogleFonts.outfit(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text Color:', style: GoogleFonts.inter(color: Colors.grey[400])),
              const SizedBox(height: 8),
              Center(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: List.generate(SettingsHelper.availableColors.length, (index) {
                    final isSelected = index == _selectedColorIndex;
                    return GestureDetector(
                      onTap: () async {
                        setState(() {
                          _selectedColorIndex = index;
                        });
                        Navigator.pop(context);
                        await _updateTheme(index);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: SettingsHelper.availableColors[index],
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        );
      },
    );
  }

  Future<void> _updateTheme(int index) async {
    await _settingsHelper.saveTextColorIndex(index);
    final newColor = _settingsHelper.getColor(index);

    setState(() {
      _defaultFgColor = newColor;

      // Update history spans to use new default color
      for (int i = 0; i < _window0History.length; i++) {
        _window0History[i] = _updateLineColor(_window0History[i], newColor);
      }

      for (int i = 0; i < _window0CurrentLine.length; i++) {
        _window0CurrentLine[i] = _updateSpanColor(_window0CurrentLine[i], newColor);
      }
    });
  }

  TextSpan _updateLineColor(TextSpan line, Color newColor) {
    if (line.children != null) {
      final newChildren = line.children!.map((span) {
        if (span is TextSpan) {
          return _updateSpanColor(span, newColor);
        }
        return span;
      }).toList();
      return TextSpan(children: newChildren);
    }
    return _updateSpanColor(line, newColor);
  }

  TextSpan _updateSpanColor(TextSpan span, Color newColor) {
    if (span.style?.color != null && SettingsHelper.availableColors.contains(span.style!.color)) {
      return TextSpan(
        text: span.text,
        style: span.style!.copyWith(color: newColor),
      );
    }
    return span;
  }
}

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
        child: Container(width: 2, height: 20, color: Colors.white),
      ),
    );
  }
}
