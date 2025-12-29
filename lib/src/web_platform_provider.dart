import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/navigation_service.dart';
import 'package:zart_player/src/ui/dialogs/save_game_dialog.dart';
import 'package:zart_player/src/ui/screens/error_screen.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';

final _log = Logger.root;

/// A PlatformProvider implementation for Flutter web.
///
/// This provider bridges the Zart interpreter with the Flutter UI,
/// handling rendering, input, and save/restore operations.
class WebPlatformProvider implements PlatformProvider {
  /// Stream controller to emit screen frames to the UI.
  final StreamController<ScreenFrame> _frameController = StreamController<ScreenFrame>.broadcast();

  /// Exposes the frame stream for the UI to listen to.
  Stream<ScreenFrame> get frameStream => _frameController.stream;

  /// Completer for line input.
  Completer<String>? _lineCompleter;

  /// Completer for single-key input.
  Completer<InputEvent>? _inputCompleter;

  /// Queue for pending key inputs (for injecting strings as key events).
  final List<InputEvent> _pendingKeyInputs = [];

  /// In-memory quicksave data.
  Uint8List? _memorySaveData;

  /// Flags for quick save/restore operations.
  bool _quickSaveRequested = false;
  bool _quickRestoreRequested = false;

  /// The name of the currently loaded game.
  String _gameName = '';

  /// Debug mode flag.
  static const bool debugMode = true;

  void _debugLog(String message) {
    if (debugMode && kDebugMode) {
      _log.info('[WebPlatform] $message');
    }
  }

  /// Set the game name (called by the hosting game screen).
  void setGameName(String name) {
    _gameName = name;
  }

  // ===== PlatformProvider Implementation =====

  /// Dynamic screen dimensions (can be updated on resize)
  /// Default to 30 rows to ensure title screen "Press Any Key" text is visible.
  int _screenWidth = 80;
  int _screenHeight = 30;

  /// Update screen dimensions when viewport size changes
  void setScreenDimensions(int width, int height) {
    _screenWidth = width;
    _screenHeight = height;
  }

  @override
  PlatformCapabilities get capabilities => PlatformCapabilities(
    supportsColors: true,
    supportsBold: true,
    supportsItalic: true,
    supportsFixedPitch: true,
    supportsTimedInput: true,
    supportsMouse: true,
    supportsSound: false,
    supportsGraphics: false,
    screenWidth: _screenWidth,
    screenHeight: _screenHeight,
    defaultForeground: 0xFFFFFF,
    defaultBackground: 0x000000,
  );

  @override
  String get gameName => _gameName;

  @override
  void render(ScreenFrame frame) {
    _debugLog('render: ${frame.width}x${frame.height}, cursor at (${frame.cursorX}, ${frame.cursorY})');
    _frameController.add(frame);
  }

  @override
  void onInit(GameFileType fileType) {
    _debugLog('onInit: $fileType');
  }

  @override
  void onQuit() {
    _debugLog('onQuit');
    // Navigate back to home screen when game ends
    NavigationService.navigatorKey.currentState?.pop();
  }

  @override
  void onError(String message) {
    _debugLog('onError: $message');
    // Navigate to error screen
    NavigationService.navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (context) => ErrorScreen(errorMessage: message)),
    );
  }

  @override
  void dispose() {
    _frameController.close();
    _lineCompleter?.completeError(Exception('Provider disposed'));
    _inputCompleter?.completeError(Exception('Provider disposed'));
  }

  @override
  void enterDisplayMode() {
    _debugLog('enterDisplayMode');
  }

  @override
  void exitDisplayMode() {
    _debugLog('exitDisplayMode');
  }

  // ===== Input Handling =====

  @override
  Future<String> readLine({int? maxLength, int? timeout}) async {
    _debugLog('readLine: waiting for line input');
    _lineCompleter = Completer<String>();

    if (timeout != null && timeout > 0) {
      return _lineCompleter!.future.timeout(Duration(milliseconds: timeout), onTimeout: () => '');
    }

    return _lineCompleter!.future;
  }

  @override
  Future<InputEvent> readInput({int? timeout}) async {
    _debugLog('readInput: waiting for key input');

    // Check if there's a pending key input queued up (e.g., from inject command)
    if (_pendingKeyInputs.isNotEmpty) {
      final event = _pendingKeyInputs.removeAt(0);
      _debugLog('readInput: returning queued key input: $event');
      return event;
    }

    _inputCompleter = Completer<InputEvent>();

    if (timeout != null && timeout > 0) {
      return _inputCompleter!.future.timeout(Duration(milliseconds: timeout), onTimeout: () => InputEvent.timeout());
    }

    return _inputCompleter!.future;
  }

  @override
  InputEvent? pollInput() {
    // Non-blocking poll - not typically used in Flutter
    return null;
  }

  /// Called by the UI when the user submits line input.
  void submitLineInput(String input) {
    if (_lineCompleter != null && !_lineCompleter!.isCompleted) {
      _lineCompleter!.complete(input);
      _lineCompleter = null;
    } else {
      _debugLog('submitLineInput: FAILED - no active line completer!');
    }
  }

  /// Called by the UI when the user presses a key.
  void submitKeyInput(InputEvent event) {
    if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
      _inputCompleter!.complete(event);
      _inputCompleter = null;
    }
  }

  /// Returns true if the game is waiting for single-key (character) input.
  /// Used by the UI to determine whether to clear input after each keypress.
  bool get isWaitingForCharInput => _inputCompleter != null && !_inputCompleter!.isCompleted;

  /// Returns true if the game is waiting for line input (typed commands).
  bool get isWaitingForLineInput => _lineCompleter != null && !_lineCompleter!.isCompleted;

  /// Injects a command string into the input stream.
  /// Works for both line input mode (completes immediately) and char input mode (queues characters).
  void injectCommand(String command) {
    // If in line input mode, complete directly
    if (_lineCompleter != null && !_lineCompleter!.isCompleted) {
      _lineCompleter!.complete(command);
      _lineCompleter = null;
      return;
    }

    // Otherwise, queue as character events for char input mode
    for (final char in command.split('')) {
      _pendingKeyInputs.add(InputEvent.character(char));
    }
    // Add Enter key at the end
    _pendingKeyInputs.add(InputEvent.specialKey(SpecialKey.enter));

    // If currently waiting for char input, complete with the first queued event
    if (_inputCompleter != null && !_inputCompleter!.isCompleted && _pendingKeyInputs.isNotEmpty) {
      final event = _pendingKeyInputs.removeAt(0);
      _debugLog('injectCommand: completing current char input with: $event');
      _inputCompleter!.complete(event);
      _inputCompleter = null;
    }
  }

  // ===== Save/Restore =====

  @override
  Future<String?> saveGame(List<int> data, {String? suggestedName}) async {
    // Handle quick save - save to memory instead of showing dialog
    if (_quickSaveRequested) {
      _quickSaveRequested = false;
      _memorySaveData = Uint8List.fromList(data);
      _debugLog('Quick save to memory successful');
      return 'quicksave'; // Return dummy filename so game thinks save succeeded
    }

    try {
      // Get context from NavigationService
      final context = NavigationService.navigatorKey.currentContext;
      if (context == null) {
        _debugLog('Save failed: No context available');
        return null;
      }

      // Show custom save dialog to get filename
      final filename = await SaveGameDialog.show(context);
      if (filename == null || filename.isEmpty) {
        _debugLog('Save cancelled');
        return null;
      }

      // Add to history for future saves
      await SaveGameDialog.addToHistory(filename);

      // Save file with .sav extension
      final fullFilename = '$filename.sav';

      // On web, saveFile() downloads directly to downloads folder
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Game',
        fileName: fullFilename,
        allowedExtensions: ['sav'],
        type: FileType.custom,
        bytes: Uint8List.fromList(data),
      );

      _debugLog('Game saved as "$fullFilename"');
      return fullFilename;
    } catch (e) {
      _debugLog('Save error: $e');
      return null;
    }
  }

  @override
  Future<List<int>?> restoreGame({String? suggestedName}) async {
    // Handle quick restore - restore from memory instead of showing dialog
    if (_quickRestoreRequested) {
      _quickRestoreRequested = false;
      if (_memorySaveData != null) {
        _debugLog('Quick restore from memory successful');
        return _memorySaveData!.toList();
      } else {
        _debugLog('Quick restore failed: No data in memory');
        return null;
      }
    }

    try {
      // Use FileType.any for mobile browser compatibility
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Restore Game',
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileBytes = file.bytes;

        if (file.name.isNotEmpty && !file.name.toLowerCase().endsWith('.sav')) {
          _debugLog('Warning: Selected file "${file.name}" is not a .sav file');
        }

        if (fileBytes != null && fileBytes.isNotEmpty) {
          _debugLog('Game restored from "${file.name}"');
          return fileBytes.toList();
        } else {
          _debugLog('Restore failed: Empty file');
          return null;
        }
      } else {
        _debugLog('Restore cancelled');
        return null;
      }
    } catch (e) {
      _debugLog('Restore error: $e');
      return null;
    }
  }

  // ===== Quick Save/Restore =====

  @override
  Future<String?> quickSave(List<int> data) async {
    _memorySaveData = Uint8List.fromList(data);
    _debugLog('Quicksave successful (in-memory)');
    _quickSaveRequested = false;
    return 'memory';
  }

  @override
  Future<List<int>?> quickRestore() async {
    _quickRestoreRequested = false;
    if (_memorySaveData != null) {
      _debugLog('Quickrestore successful (in-memory)');
      return _memorySaveData!.toList();
    } else {
      _debugLog('Quickrestore failed: No data in memory');
      return null;
    }
  }

  /// Request a quick save operation.
  @override
  void setQuickSaveFlag() {
    _quickSaveRequested = true;
  }

  /// Request a quick restore operation.
  @override
  void setQuickRestoreFlag() {
    _quickRestoreRequested = true;
  }

  /// Check if quick save was requested.
  bool get quickSaveRequested => _quickSaveRequested;

  /// Check if quick restore was requested.
  bool get quickRestoreRequested => _quickRestoreRequested;

  /// Check if there is quicksave data available.
  bool get hasQuickSaveData => _memorySaveData != null;

  // ===== Settings =====

  @override
  Future<void> openSettings(covariant terminal, {bool isGameStarted = false}) async {
    // Settings are handled by the Flutter UI directly
    _debugLog('openSettings called - handled by Flutter UI');
  }

  // ===== Utility =====

  /// Scroll callback for UI scroll events
  void Function(int scrollOffset)? _scrollCallback;

  @override
  void setScrollCallback(void Function(int scrollOffset)? callback) {
    _scrollCallback = callback;
  }

  /// Handle scroll events from the UI (e.g., mouse wheel)
  void handleScroll(int scrollOffset) {
    _scrollCallback?.call(scrollOffset);
  }

  @override
  void showTempMessage(String message, {int seconds = 3}) {
    _debugLog('showTempMessage: $message');
    // Could emit a separate stream for temp messages if needed
  }

  @override
  ({void Function() cleanup, Future<void> onKeyPressed, bool Function() wasPressed}) setupAsyncKeyWait() {
    _debugLog('setupAsyncKeyWait: setting up async key wait');
    bool pressed = false;
    final completer = Completer<void>();

    // Store cleanup to cancel wait
    void cleanup() {
      _debugLog('setupAsyncKeyWait: cleanup called');
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    // Listen for any input to complete the wait
    _debugLog('setupAsyncKeyWait: calling readInput()');
    readInput()
        .then((event) {
          _debugLog('setupAsyncKeyWait: readInput completed with event: $event');
          pressed = true;
          if (!completer.isCompleted) {
            _debugLog('setupAsyncKeyWait: completing onKeyPressed future');
            completer.complete();
          }
        })
        .catchError((e) {
          _debugLog('setupAsyncKeyWait: readInput error: $e');
        });

    return (cleanup: cleanup, onKeyPressed: completer.future, wasPressed: () => pressed);
  }

  @override
  void setTextColor(int colorCode) {
    // TODO: implement setTextColor
  }
}
