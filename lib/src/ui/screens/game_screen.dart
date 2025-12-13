import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/settings_helper.dart';
import 'package:zart_player/src/ui/widgets/blinking_cursor.dart';
import 'package:zart_player/src/ui/dialogs/help_dialog.dart';
import 'package:zart_player/src/ui/dialogs/settings_dialog.dart';
import 'package:zart_player/src/ui/widgets/window1_painter.dart';
import 'package:zart_player/src/zart_io_provider.dart';

/// Z-Machine Screen Model compliant game screen.
/// Uses the ScreenModel API from zart for window management.
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

  // Screen Model from zart - handles all window/buffer management
  final ScreenModel _screen = ScreenModel(cols: 80, rows: 25);

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

  // Z-Machine version (3, 4, 5, 7, 8) - read from header byte 0
  int _zVersion = 5;

  // V3 Status Line (spec §8.2)
  String _statusLocation = "";
  String _statusRight = "";

  // Active window (0 = lower, 1 = upper)
  int _activeWindow = 0;

  // Render version counter to force repaints
  int _renderVersion = 0;

  // Settings
  final SettingsHelper _settingsHelper = SettingsHelper();
  Color _defaultFgColor = SettingsHelper.availableColors[0];
  int _selectedColorIndex = 0;
  final _log = Logger.root;

  ZMachineRunState? _engineState;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _io = ZartIOProvider();

    _inputFocusNode = FocusNode(onKeyEvent: (node, event) => _handleKeyEvent(event));

    _startGame();
    _io.outputStream.listen(_handleGameCommand);

    _log.level = Level.WARNING;
    // _log.onRecord.listen((record) {
    //   debugPrint(record.toString());
    // });
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

    // Wire up getCursor callback so the engine can check position
    _io.getCursorCallback = () async {
      // Return 1-based coordinates
      return {'row': _screen.cursorRow, 'column': _screen.cursorCol};
    };

    try {
      var blorbData = Blorb.getZData(widget.gameData);
      Z.io = _io;
      Z.load(blorbData);

      // Detect Z-Machine version from header byte 0
      _zVersion = Z.engine.mem.loadb(0);

      // Clear screen at game start
      _screen.clearAll();

      // Initialize Screen Size in Header (Standard 1.0, 8.4)
      // This is crucial for V5+ games (like Beyond Zork) to calculate layout correctly.
      // Without this, they may assume 255 rows/cols or 0, leading to garbled output.
      Z.engine.mem.storeb(0x20, 25); // Rows
      Z.engine.mem.storeb(0x21, 80); // Columns
      if (_zVersion >= 4) {
        Z.engine.mem.storew(0x22, 80); // Screen width in units
        Z.engine.mem.storew(0x24, 25); // Screen height in units
        Z.engine.mem.storeb(0x26, 1); // Font height in units
        Z.engine.mem.storeb(0x27, 1); // Font width in units
      }

      _renderVersion++;

      await _pumpEngine();
    } catch (e) {
      _screen.appendToWindow0("Failed to load game: $e\n");
      _renderVersion++;
    }
  }

  Future<void> _pumpEngine() async {
    _engineState = await Z.runUntilInput();

    if (_engineState == ZMachineRunState.quit) {
      _screen.appendToWindow0("\n*** GAME OVER ***\n");
      _renderVersion++;
    }

    if (mounted) {
      _inputFocusNode.requestFocus();
      setState(() {});
    }
  }

  Future<void> _submitInput(String input) async {
    _debugLog('submitInput: input="$input"');

    // Apply any pending window shrink now that user has provided input
    _screen.applyPendingWindowShrink();
    _renderVersion++;

    if (_engineState == ZMachineRunState.needsLineInput) {
      _engineState = await Z.submitLineInput(input);
    } else if (_engineState == ZMachineRunState.needsCharInput) {
      final char = input.isEmpty ? '\n' : input;
      _engineState = await Z.submitCharInput(char);
    }

    if (_engineState == ZMachineRunState.quit) {
      _screen.appendToWindow0("\n*** GAME OVER ***\n");
      _renderVersion++;
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
          _screen.appendToWindow0(text);
        } else {
          _screen.writeToWindow1(text);
          // Signal render complete for awaited Window 1 prints
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _io.signalRenderComplete();
          });
        }
        setState(() => _renderVersion++);

      case SplitWindow(:final lines):
        _debugLog('SplitWindow: lines=$lines');
        _screen.splitWindow(lines);
        setState(() => _renderVersion++);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _io.signalRenderComplete();
        });

      case SetWindow(:final id):
        _debugLog('SetWindow: id=$id');
        setState(() {
          _activeWindow = id;
          // Note: Do NOT reset cursor to (1,1) here.
          // Z-Machine spec requires keeping independent window cursor logic.
          // Resetting it breaks games like Beyond Zork that switch windows frequently.
        });

      case SetCursor(:final line, :final column):
        _debugLog('SetCursor: line=$line, column=$column');
        _screen.setCursor(line, column);
        setState(() => _renderVersion++);

      case ClearScreen(:final window):
        _debugLog('ClearScreen: window=$window');
        if (window == -1 || window == -2) {
          _screen.clearAll();
        } else if (window == 0) {
          _screen.clearWindow0();
        } else if (window == 1) {
          _screen.clearWindow1();
        }
        setState(() => _renderVersion++);

      case SetTextStyle(:final style):
        _debugLog('SetTextStyle: style=$style');
        _screen.setStyle(style);

      case Setcolor(:final foreground, :final background):
        _debugLog('SetColor: fg=$foreground, bg=$background');
        _screen.setColors(foreground, background);

      case StatusUpdate(:final location, :final formattedRight):
        _debugLog('StatusUpdate: location=$location, right=$formattedRight');
        if (_zVersion == 3) {
          setState(() {
            _statusLocation = location;
            _statusRight = formattedRight;
          });
        }

      case EraseLine():
        _debugLog('EraseLine');
      // Emulate erase line by printing spaces to end of width
      // CLI leaves this ignored so we will too.
      // if (_activeWindow == 1) {
      //   // Assume 80 column width for Window 1
      //   int charsToErase = 80 - _screen.cursorCol + 1;
      //   if (charsToErase > 0) {
      //     _screen.write(" " * charsToErase);
      //     setState(() => _renderVersion++);
      //   }
      // }
    }

    // Scroll to bottom after updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ===== Input Handling =====

  Future<void> _handleUserInput(String input) async {
    if (input.isNotEmpty && (_inputHistory.isEmpty || _inputHistory.last != input)) {
      _inputHistory.add(input);
    }
    _historyIndex = -1;

    // Echo input for line input mode
    if (_engineState == ZMachineRunState.needsLineInput) {
      _screen.appendToWindow0("$input\n");
      _renderVersion++;
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
      _screen.appendToWindow0("$cmd\n");
      _renderVersion++;
      await Future.delayed(const Duration(milliseconds: 50));
      await _submitInput(cmd);
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // In needsCharInput mode, forward special keys immediately
    if (_engineState == ZMachineRunState.needsCharInput) {
      String? zsciiChar;

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        zsciiChar = String.fromCharCode(129);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        zsciiChar = String.fromCharCode(130);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        zsciiChar = String.fromCharCode(131);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        zsciiChar = String.fromCharCode(132);
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        zsciiChar = String.fromCharCode(27);
      } else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
        zsciiChar = String.fromCharCode(8);
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        zsciiChar = '\n';
      }

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

  // ===== Color Resolution =====

  Color _resolveColor(int code, {required bool isBackground}) {
    switch (code) {
      case 0:
      case 1:
        return isBackground ? Colors.black : _defaultFgColor;
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
        return isBackground ? Colors.black : _defaultFgColor;
    }
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

                  // Main game area: Window 1 overlays Window 0
                  Expanded(
                    child: Stack(
                      children: [
                        // Window 0 (Lower) - scrolling text
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.only(top: _screen.window1Height * 20.0),
                            child: _buildWindow0(),
                          ),
                        ),

                        // Window 1 (Upper) - overlays top portion
                        if (_screen.window1Height > 0)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: _screen.window1Height * 20.0,
                            child: _buildWindow1(),
                          ),
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
      color: const Color(0xFFC0C0C0),
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

  /// Window 1 (Upper) - renders from ScreenModel.window1Grid using CustomPainter
  /// CustomPainter gives precise control over cell backgrounds and text rendering
  Widget _buildWindow1() {
    final grid = _screen.window1Grid;
    if (grid.isEmpty) return const SizedBox.shrink();

    // Calculate size: 80 columns × font width, rows × line height
    // Dynamic char width measurement to fix padding issues
    final textPainter = TextPainter(
      text: TextSpan(text: '0', style: GoogleFonts.firaCode(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    final double charWidth = textPainter.width;

    const double lineHeight = 20.0;
    const double targetCols = 80;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: CustomPaint(
        size: Size(charWidth * targetCols, lineHeight * grid.length),
        painter: Window1Painter(
          grid: grid,
          targetCols: targetCols.toInt(),
          charWidth: charWidth,
          lineHeight: lineHeight,
          resolveColor: _resolveWindow1Color,
        ),
      ),
    );
  }

  /// Standard Z-Machine color resolution for Window 1
  /// Uses white as default foreground (not user theme color)
  Color _resolveWindow1Color(int code, {required bool isBackground}) {
    switch (code) {
      case 0:
      case 1:
        return isBackground ? Colors.black : Colors.white;
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
        return isBackground ? Colors.black : Colors.white;
    }
  }

  /// Window 0 (Lower) - renders from ScreenModel.window0Grid
  Widget _buildWindow0() {
    final grid = _screen.window0Grid;

    return Container(
      color: Colors.black,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: grid.length,
          itemBuilder: (context, index) {
            final isLastLine = index == grid.length - 1;

            // Build grid line, and if this is the last line, append input + cursor
            return _buildGridLine(grid[index], appendInput: isLastLine);
          },
        ),
      ),
    );
  }

  /// Builds a RichText widget from a list of Cells
  /// If appendInput is true, appends the input buffer and blinking cursor
  Widget _buildGridLine(List<Cell> cells, {bool appendInput = false}) {
    final spans = <InlineSpan>[];
    StringBuffer currentText = StringBuffer();
    int? currentFg;
    int? currentBg;
    int? currentStyle;

    void flushSpan() {
      if (currentText.isNotEmpty) {
        Color fgColor = _resolveColor(currentFg ?? 1, isBackground: false);
        Color bgColor = _resolveColor(currentBg ?? 1, isBackground: true);

        // Handle reverse video
        if ((currentStyle ?? 0) & 1 != 0) {
          final temp = fgColor;
          fgColor = bgColor;
          bgColor = temp;
        }

        spans.add(
          TextSpan(
            text: currentText.toString(),
            style: GoogleFonts.firaCode(
              color: fgColor,
              backgroundColor: bgColor == Colors.black ? null : bgColor,
              fontWeight: ((currentStyle ?? 0) & 2 != 0) ? FontWeight.bold : FontWeight.normal,
              fontStyle: ((currentStyle ?? 0) & 4 != 0) ? FontStyle.italic : FontStyle.normal,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        );
        currentText = StringBuffer();
      }
    }

    for (final cell in cells) {
      if (currentFg != cell.fg || currentBg != cell.bg || currentStyle != cell.style) {
        flushSpan();
        currentFg = cell.fg;
        currentBg = cell.bg;
        currentStyle = cell.style;
      }
      currentText.write(cell.char);
    }
    flushSpan();

    // If this is the input line, append input buffer and cursor
    if (appendInput) {
      if (_inputBuffer.isNotEmpty) {
        spans.add(
          TextSpan(
            text: _inputBuffer,
            style: GoogleFonts.firaCode(color: _defaultFgColor, fontSize: 16, height: 1.4),
          ),
        );
      }
      if (_activeWindow == 0) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: const BlinkingCursor(),
          ),
        );
      }
    }

    if (spans.isEmpty) {
      return const SizedBox(height: 22.4); // Empty line height
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _showHelpDialog() {
    HelpDialog.show(context);
  }

  void _showSettingsDialog() {
    SettingsDialog.show(
      context,
      selectedColorIndex: _selectedColorIndex,
      onColorSelected: (index) async {
        setState(() {
          _selectedColorIndex = index;
        });
        await _updateTheme(index);
      },
    );
  }

  Future<void> _updateTheme(int index) async {
    await _settingsHelper.saveTextColorIndex(index);
    final newColor = _settingsHelper.getColor(index);
    setState(() {
      _defaultFgColor = newColor;
    });
  }
}
