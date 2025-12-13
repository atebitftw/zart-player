import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/navigation_service.dart';
import 'package:zart_player/src/ui/save_game_dialog.dart';
import 'package:logging/logging.dart';

final _log = Logger.root;

/// A custom IO Provider for the Zart interpreter that bridges
/// the game engine with the Flutter UI.
///
/// Supports chained commands separated by "." (e.g., "get up.take all.north"),
/// a common feature of Z-machine interpreters. Commands are split and fed
/// to the engine sequentially.
class ZartIOProvider implements IoProvider {
  /// Stream controller to send output commands to the UI.
  final StreamController<GameCommand> _outputController =
      StreamController<GameCommand>.broadcast();

  /// Exposes the output stream for the UI to listen to.
  Stream<GameCommand> get outputStream => _outputController.stream;

  /// Completer to handle user input.
  Completer<String>? _inputCompleter;

  /// Callback to retrieve the current cursor position from the UI.
  /// Returns [line, column].
  Future<Map<String, int>> Function()? getCursorCallback;

  /// Buffer for readChar inputs
  final List<String> _inputBuffer = [];

  /// Set to true to enable debug logging for IO commands
  static const bool debugMode = false;

  void _debugLog(String message) {
    if (debugMode && kDebugMode) {
      _log.info('[IO] $message');
    }
  }

  /// Completer for awaiting UI render completion.
  /// Visual commands wait on this before returning to the engine.
  Completer<void>? _renderCompleter;

  /// Signals that the UI has finished rendering the last command.
  /// Call this from the game screen after setState + frame callback.
  void signalRenderComplete() {
    if (_renderCompleter != null && !_renderCompleter!.isCompleted) {
      _renderCompleter!.complete();
      _renderCompleter = null;
    }
  }

  @override
  int getFlags1() {
    // Return flags matching CLI: Color(1) | Bold(4) | Italic(8) | Fixed(16) | Timed(128)
    // Note: Zart constants might not cover all, so we use raw values to ensure parity.
    return 1 | 4 | 8 | 16 | 128;
  }

  /// Sends input from the UI to the engine.
  void sendInput(String input) {
    if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
      _log.info('IO: sendInput completing with "$input"');
      _inputCompleter!.complete(input);
      _inputCompleter = null;
    } else {
      _log.info(
        'IO: sendInput called but no read is pending! Input discarded: "$input"',
      );
    }
  }

  @override
  Future<dynamic> command(Map<String, dynamic> command) async {
    final cmd = command['command'];

    switch (cmd) {
      case IoCommands.print:
        final text = command['buffer'] as String;
        // Window ID specifies which window this text should go to
        final window = command['window'] as int? ?? 0;
        _debugLog(
          'print: window=$window, text="${text.length > 30 ? text.substring(0, 30) : text}..."',
        );

        // Window 1 prints used to await, but this caused slow rendering.
        // Now treating as fire-and-forget to match Window 0 performance.
        _outputController.add(PrintText(text, window: window));
        return null;

      case IoCommands.printDebug:
        return null;

      case IoCommands.splitWindow:
        final lines = (command['lines'] as num?)?.toInt() ?? 0;
        _debugLog('splitWindow: lines=$lines');
        // Match CLI behavior: Fire and forget (don't await render).
        // This prevents the engine from pausing mid-update cycle.
        _outputController.add(SplitWindow(lines));
        return null;

      case IoCommands.setWindow:
        final window = (command['window'] as num?)?.toInt() ?? 0;

        _outputController.add(SetWindow(window));
        return null;

      case IoCommands.getCursor:
        if (getCursorCallback != null) {
          return await getCursorCallback!();
        }
        return {'row': 1, 'column': 1}; // Fallback if no callback registered

      case IoCommands.setCursor:
        final rawLine = command['line'];
        final rawColumn = command['column'];
        // Correct mapping: line is line, column is column.
        final line = (rawLine as num).toInt();
        final column = (rawColumn as num).toInt();
        _outputController.add(SetCursor(line, column));
        return null;

      case IoCommands.setTextStyle:
        final style = (command['style'] as num?)?.toInt() ?? 0;
        _outputController.add(SetTextStyle(style));
        return null;

      case IoCommands.setColour:
        final fg = (command['foreground'] as num?)?.toInt() ?? -1;
        final bg = (command['background'] as num?)?.toInt() ?? -1;
        _outputController.add(Setcolor(fg, bg));
        return null;

      case IoCommands.read:
        _debugLog('read: waiting for line input');
        _inputCompleter = Completer<String>();
        return _inputCompleter!.future;

      case IoCommands.readChar:
        _debugLog('readChar: waiting for char input');
        if (_inputBuffer.isNotEmpty) {
          final char = _inputBuffer.removeAt(0);
          return char;
        }

        _inputCompleter = Completer<String>();
        final input = await _inputCompleter!.future;

        if (input.isNotEmpty) {
          final chars = input.split('');
          final first = chars.first;
          if (chars.length > 1) {
            _inputBuffer.addAll(chars.sublist(1));
            _inputBuffer.add('\n');
          } else {
            _inputBuffer.add('\n');
          }
          return first;
        } else {
          return '\n';
        }

      case IoCommands.clearScreen:
        final window = (command['window_id'] as num?)?.toInt() ?? -1;
        _outputController.add(ClearScreen(window));
        return null;

      case IoCommands.quit:
        _outputController.add(const PrintText('\n*** GAME OVER ***\n'));
        return null;

      case IoCommands.status:
        // V3 Status Line (spec §8.2)
        // The zart library sends: location, score, turns (for score games)
        //                     or: location, hours, minutes (for time games)
        final location = command['room_name'] as String? ?? "";
        final isTimeGame = command['game_type'] == "TIME";

        String rightSide;
        if (isTimeGame) {
          final hours = (command['hours'] as num?)?.toInt() ?? 0;
          final minutes = (command['minutes'] as num?)?.toInt() ?? 0;
          // Format: "HH:MM AM/PM" per spec §8.2.3.2
          final h = hours % 12 == 0 ? 12 : hours % 12;
          final ampm = hours < 12 ? "AM" : "PM";
          rightSide = "$h:${minutes.toString().padLeft(2, '0')} $ampm";
        } else {
          final score = (command['score_one'] as String?) ?? "";
          final turns = (command['score_two'] as String?) ?? "";
          // Format: "Score/Turns" per spec §8.2.3.1
          rightSide = "$score/$turns";
        }

        _outputController.add(StatusUpdate(location, rightSide));
        return null;

      case IoCommands.save:
        // The file data sent by the Z-Machine engine (Quetzal format)
        final fileData = command['file_data'] as List<int>? ?? [];

        try {
          // Get context from NavigationService
          final context = NavigationService.navigatorKey.currentContext;
          if (context == null) {
            _debugLog('Save failed: No context available');
            return false;
          }

          // Show custom save dialog to get filename
          final filename = await SaveGameDialog.show(context);
          if (filename == null || filename.isEmpty) {
            _debugLog('Save cancelled');
            return false;
          }

          // Add to history for future saves
          await SaveGameDialog.addToHistory(filename);

          // Save file with .sav extension
          final fullFilename = '$filename.sav';

          // Note: On web, saveFile() downloads directly to downloads folder
          await FilePicker.platform.saveFile(
            dialogTitle: 'Save Game',
            fileName: fullFilename,
            allowedExtensions: ['sav'],
            type: FileType.custom,
            bytes: Uint8List.fromList(fileData),
          );

          _debugLog('Game saved as "$fullFilename"');
          return true;
        } catch (e) {
          _debugLog('Save error: $e');
          _debugLog('Save failed: $e');
          return false;
        }

      case IoCommands.restore:
        try {
          // Use FileType.any for mobile browser compatibility
          // (FileType.custom restricts mobile browsers to gallery only)
          final result = await FilePicker.platform.pickFiles(
            dialogTitle: 'Restore Game',
            type: FileType.any,
            withData: true,
          );

          if (result != null && result.files.isNotEmpty) {
            final file = result.files.first;
            final fileBytes = file.bytes;

            // Warn if not a .sav file (but still allow loading)
            if (file.name.isNotEmpty &&
                !file.name.toLowerCase().endsWith('.sav')) {
              _debugLog(
                'Warning: Selected file "${file.name}" is not a .sav file',
              );
            }

            if (fileBytes != null && fileBytes.isNotEmpty) {
              _debugLog('Game restored from "${file.name}"');
              // Return the file data as List<int> for the Z-Machine to restore
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
          _debugLog('Restore failed: $e');
          return null;
        }

      default:
        // Check for eraseLine if it exists in IoCommands
        if (cmd == IoCommands.eraseLine) {
          final value = (command['value'] as num?)?.toInt() ?? 1;
          if (value == 1) {
            _outputController.add(const EraseLine());
          }
          return null;
        }
        return null;
    }
  }

  /// Disposes of resources and clears any pending state.
  void dispose() {
    _outputController.close();
    // Z.softReset();
    // Z.isLoaded = false;

    // // Cancel any pending input
    // if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
    //   // Throwing inside the VM loop helps it exit
    //   // _inputCompleter!.completeError(GameException("Game disposed"));
    //   _inputCompleter = null;
    // }
  }
}

// --- Event Classes ---

sealed class GameCommand {
  const GameCommand();
}

class PrintText extends GameCommand {
  final String text;

  /// Window ID: 0 = lower, 1 = upper (per Z-Machine spec)
  final int window;
  const PrintText(this.text, {this.window = 0});
}

class SplitWindow extends GameCommand {
  final int lines;
  const SplitWindow(this.lines);
}

class SetWindow extends GameCommand {
  final int id;
  const SetWindow(this.id);
}

class SetCursor extends GameCommand {
  final int line;
  final int column;
  const SetCursor(this.line, this.column);
}

class SetTextStyle extends GameCommand {
  final int style;
  const SetTextStyle(this.style);
}

class Setcolor extends GameCommand {
  final int foreground;
  final int background;
  const Setcolor(this.foreground, this.background);
}

class ClearScreen extends GameCommand {
  final int window;
  const ClearScreen([this.window = -1]);
}

/// V3 Status Line update (spec §8.2)
class StatusUpdate extends GameCommand {
  final String location;
  final String formattedRight;
  const StatusUpdate(this.location, this.formattedRight);
}

/// Erase from cursor to end of line (spec §8.7.3.4)
class EraseLine extends GameCommand {
  const EraseLine();
}
