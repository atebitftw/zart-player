import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/settings_helper.dart';
import 'package:zart_player/src/ui/widgets/blinking_cursor.dart';
import 'package:zart_player/src/ui/dialogs/help_dialog.dart';
import 'package:zart_player/src/ui/dialogs/settings_dialog.dart';
import 'package:zart_player/src/web_platform_provider.dart';

/// Simplified game screen that renders ScreenFrames from the Zart library.
///
/// The library now handles all screen model logic internally. This screen
/// simply renders the flat ScreenFrame grid and handles input.
class GameScreen extends StatefulWidget {
  final Uint8List gameData;
  final String gameName;

  const GameScreen({super.key, required this.gameData, required this.gameName});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final WebPlatformProvider _provider;
  StreamSubscription<ScreenFrame>? _frameSubscription;

  // Current screen frame from the library
  ScreenFrame? _currentFrame;

  // Input State
  late final FocusNode _inputFocusNode;
  final TextEditingController _inputController = TextEditingController();
  String _inputBuffer = "";
  final List<String> _inputHistory = [];
  int _historyIndex = -1;

  // Settings
  final SettingsHelper _settingsHelper = SettingsHelper();
  Color _defaultFgColor = SettingsHelper.availableColors[0];
  int _selectedColorIndex = 0;
  final _log = Logger.root;
  Map<String, String> _macroBinds = {};

  // Engine state
  GameRunner? _runner;

  static const bool debugMode = true;
  static const double _lineHeight = 1.2;

  void _debugLog(String message) {
    if (debugMode && kDebugMode) {
      debugPrint(message);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _provider = WebPlatformProvider();
    _provider.setGameName(widget.gameName);

    _inputFocusNode = FocusNode(onKeyEvent: (node, event) => _handleKeyEvent(event));

    // Listen to frame updates from the provider
    _frameSubscription = _provider.frameStream.listen(_handleFrame);

    _startGame();

    _log.level = Level.WARNING;
  }

  Future<void> _loadSettings() async {
    _selectedColorIndex = await _settingsHelper.loadTextColorIndex();
    final binds = await _settingsHelper.loadMacroBinds();
    setState(() {
      _defaultFgColor = _settingsHelper.getColor(_selectedColorIndex);
      _macroBinds = binds;
    });
  }

  void _startGame() async {
    try {
      // Create the game runner with our provider
      _runner = GameRunner(_provider);

      // Run the game (this is async and handles the game loop)
      _runner!
          .run(widget.gameData)
          .then((_) {
            if (mounted) {
              setState(() {});
            }
          })
          .catchError((e) {
            if (mounted) {
              setState(() {});
            }
            _debugLog('Game error: $e');
          });

      if (mounted) {
        _inputFocusNode.requestFocus();
      }
    } catch (e) {
      _debugLog('Failed to load game: $e');
    }
  }

  void _handleFrame(ScreenFrame frame) {
    if (!mounted) return;
    _debugLog('Frame received: ${frame.width}x${frame.height}');
    setState(() {
      _currentFrame = frame;
    });
  }

  // ===== Input Handling =====

  Future<void> _handleUserInput(String input) async {
    if (input.isNotEmpty && (_inputHistory.isEmpty || _inputHistory.last != input)) {
      _inputHistory.add(input);
    }
    _historyIndex = -1;

    // Clear input field immediately
    setState(() {
      _inputBuffer = "";
      _inputController.clear();
    });

    // Handle chained commands (e.g., "open mailbox. take leaflet")
    final commands = input.split('.').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

    if (commands.isEmpty) {
      // Just Enter key pressed with empty input
      _provider.submitLineInput("");
      return;
    }

    // Process each command sequentially
    for (final cmd in commands) {
      _provider.submitLineInput(cmd);
      // Small delay between chained commands
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Macro handling (Ctrl + Key)
    if (HardwareKeyboard.instance.isControlPressed) {
      final keyLabel = event.logicalKey.keyLabel.toLowerCase();
      if (_macroBinds.containsKey(keyLabel)) {
        final macro = _macroBinds[keyLabel]!;
        _handleUserInput(macro);
        return KeyEventResult.handled;
      }
    }

    // Arrow keys for navigation / char input
    InputEvent? inputEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Check if we should use history or send to game
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
      inputEvent = InputEvent.specialKey(SpecialKey.arrowUp);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
      inputEvent = InputEvent.specialKey(SpecialKey.arrowDown);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      inputEvent = InputEvent.specialKey(SpecialKey.arrowLeft);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      inputEvent = InputEvent.specialKey(SpecialKey.arrowRight);
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      inputEvent = InputEvent.specialKey(SpecialKey.escape);
    } else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      inputEvent = InputEvent.specialKey(SpecialKey.delete);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      inputEvent = InputEvent.specialKey(SpecialKey.enter);
    }

    if (inputEvent != null) {
      _provider.submitKeyInput(inputEvent);
      return KeyEventResult.handled;
    }

    // Quicksave (F5)
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _handleQuickSave();
      return KeyEventResult.handled;
    }

    // Quickrestore (F6)
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      _handleQuickRestore();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setInputText(String text) {
    _inputBuffer = text;
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
  }

  void _onInputChanged(String value) {
    // For character input mode, send single chars
    if (value.isNotEmpty && value.length > _inputBuffer.length) {
      final char = value.substring(_inputBuffer.length);
      if (char.length == 1) {
        // Check if game is waiting for character input before sending
        final wasWaitingForChar = _provider.isWaitingForCharInput;
        _provider.submitKeyInput(InputEvent.character(char));

        // Only clear input if we were in character input mode (title screens, menus)
        // For line input mode, characters should accumulate until Enter is pressed
        if (wasWaitingForChar) {
          _inputController.clear();
          setState(() {
            _inputBuffer = "";
          });
          return;
        }
      }
    }

    setState(() {
      _inputBuffer = value;
    });
  }

  void _handleQuickSave() {
    _provider.setQuickSaveFlag();
    _provider.submitLineInput("save");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Quick-saved to memory. Type 'save' if you want to save to file.",
          style: TextStyle(fontFamily: 'Fira Code'),
        ),
      ),
    );
  }

  void _handleQuickRestore() {
    if (_provider.hasQuickSaveData) {
      _provider.setQuickRestoreFlag();
      _provider.submitLineInput("restore");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Restoring from memory...", style: TextStyle(fontFamily: 'Fira Code')),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No quicksave data found.", style: TextStyle(fontFamily: 'Fira Code')),
        ),
      );
    }
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _provider.dispose();
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
          IconButton(icon: const Icon(Icons.save), tooltip: "Quick Save (F5)", onPressed: _handleQuickSave),
          IconButton(icon: const Icon(Icons.restore), tooltip: "Quick Load (F6)", onPressed: _handleQuickRestore),
          IconButton(icon: const Icon(Icons.settings), tooltip: "Settings", onPressed: _showSettingsDialog),
          IconButton(icon: const Icon(Icons.help_outline), tooltip: "Help", onPressed: _showHelpDialog),
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
        onPointerSignal: (event) {
          // Handle mouse wheel scroll - trigger scroll offset, NOT keyboard events
          if (event is PointerScrollEvent) {
            // Scroll offset: positive = scroll up (back in history), negative = scroll down
            final int scrollLines = event.scrollDelta.dy < 0 ? 3 : -3;
            _provider.handleScroll(scrollLines);
          }
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

                  // Main game area - render the screen frame with dynamic sizing
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate screen dimensions based on available space
                        // Font size = 16, line height = 1.2
                        const double fontSize = 16;
                        const double charWidth = 9.6; // Approximate monospace char width
                        final int rows = (constraints.maxHeight / (fontSize * _lineHeight)).floor();
                        final int cols = (constraints.maxWidth / charWidth).floor().clamp(40, 120);

                        // Update provider dimensions if changed
                        if (_provider.capabilities.screenHeight != rows || _provider.capabilities.screenWidth != cols) {
                          _provider.setScreenDimensions(cols, rows);
                        }

                        return _buildScreenFrame();
                      },
                    ),
                  ),

                  const Text("Quick Save (To Memory) = F5, Quick Load = F6"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the screen frame from the current ScreenFrame data.
  Widget _buildScreenFrame() {
    if (_currentFrame == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Loading...', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final frame = _currentFrame!;

    return Container(
      color: Colors.black,
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int row = 0; row < frame.height; row++)
              _buildRow(
                frame.cells[row],
                showCursor: frame.cursorVisible && frame.cursorY == row,
                cursorX: frame.cursorX,
              ),
          ],
        ),
      ),
    );
  }

  /// Build a single row from cells.
  Widget _buildRow(List<dynamic> cells, {bool showCursor = false, int cursorX = -1}) {
    final spans = <InlineSpan>[];
    StringBuffer currentText = StringBuffer();
    int? currentFg;
    int? currentBg;
    bool? currentBold;
    bool? currentItalic;
    bool? currentReverse;
    int currentColumn = 0;
    bool cursorInserted = false;

    void flushSpan() {
      if (currentText.isNotEmpty) {
        Color fgColor = currentFg != null ? Color(currentFg | 0xFF000000) : _defaultFgColor;
        Color bgColor = currentBg != null ? Color(currentBg | 0xFF000000) : Colors.black;

        // Handle reverse video
        if (currentReverse == true) {
          final temp = fgColor;
          fgColor = bgColor;
          bgColor = temp;
        }

        // Use WidgetSpan with Container for proper background painting
        // TextSpan.backgroundColor doesn't reliably paint behind spaces
        if (bgColor != Colors.black) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Container(
                color: bgColor,
                child: Text(
                  currentText.toString(),
                  style: GoogleFonts.jetBrainsMono(
                    color: fgColor,
                    fontWeight: (currentBold == true) ? FontWeight.w600 : FontWeight.normal,
                    fontStyle: (currentItalic == true) ? FontStyle.italic : FontStyle.normal,
                    fontSize: 16,
                    height: _lineHeight,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          );
        } else {
          spans.add(
            TextSpan(
              text: currentText.toString(),
              style: GoogleFonts.jetBrainsMono(
                color: fgColor,
                fontWeight: (currentBold == true) ? FontWeight.w600 : FontWeight.normal,
                fontStyle: (currentItalic == true) ? FontStyle.italic : FontStyle.normal,
                fontSize: 16,
                height: _lineHeight,
                letterSpacing: 0,
              ),
            ),
          );
        }
        currentText = StringBuffer();
      }
    }

    for (int i = 0; i < cells.length; i++) {
      final cell = cells[i];

      // Check if cursor should be inserted at this position
      if (showCursor && !cursorInserted && currentColumn == cursorX) {
        flushSpan();
        // Add input buffer first, then cursor
        if (_inputBuffer.isNotEmpty) {
          spans.add(
            TextSpan(
              text: _inputBuffer,
              style: GoogleFonts.jetBrainsMono(
                color: _defaultFgColor,
                fontSize: 16,
                height: _lineHeight,
                letterSpacing: 0,
              ),
            ),
          );
        }
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: const BlinkingCursor(),
          ),
        );
        cursorInserted = true;
      }

      // Get effective styles - carry forward previous style if cell has null
      // This emulates ANSI terminal behavior where styles persist until changed
      final effectiveFg = cell.fgColor ?? currentFg;
      final effectiveBg = cell.bgColor ?? currentBg;
      final effectiveBold = cell.bold;
      final effectiveItalic = cell.italic;
      final effectiveReverse = cell.reverse;

      if (currentFg != effectiveFg ||
          currentBg != effectiveBg ||
          currentBold != effectiveBold ||
          currentItalic != effectiveItalic ||
          currentReverse != effectiveReverse) {
        flushSpan();
        currentFg = effectiveFg;
        currentBg = effectiveBg;
        currentBold = effectiveBold;
        currentItalic = effectiveItalic;
        currentReverse = effectiveReverse;
      }
      currentText.write(cell.char);
      currentColumn++;
    }
    flushSpan();

    // If cursor wasn't inserted yet (e.g., cursorX is at or past end of cells), add it now
    if (showCursor && !cursorInserted) {
      if (_inputBuffer.isNotEmpty) {
        spans.add(
          TextSpan(
            text: _inputBuffer,
            style: GoogleFonts.jetBrainsMono(
              color: _defaultFgColor,
              fontSize: 16,
              height: _lineHeight,
              letterSpacing: 0,
            ),
          ),
        );
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: const BlinkingCursor(),
        ),
      );
    }

    if (spans.isEmpty) {
      return const SizedBox(height: 22.4); // Empty line height
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _showHelpDialog() {
    HelpDialog.show(context);
  }

  void _showSettingsDialog() async {
    await SettingsDialog.show(
      context,
      selectedColorIndex: _selectedColorIndex,
      onColorSelected: (index) async {
        setState(() {
          _selectedColorIndex = index;
        });
        await _updateTheme(index);
      },
    );
    await _loadSettings(); // Reload macros after dialog closes
  }

  Future<void> _updateTheme(int index) async {
    await _settingsHelper.saveTextColorIndex(index);
    final newColor = _settingsHelper.getColor(index);
    setState(() {
      _defaultFgColor = newColor;
    });
  }
}
