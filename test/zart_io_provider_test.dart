import 'package:flutter_test/flutter_test.dart';
import 'package:zart/zart.dart';
import 'package:zart_player/src/zart_io_provider.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZartIOProvider Quicksave/Quickload', () {
    late ZartIOProvider io;

    setUp(() {
      io = ZartIOProvider();
    });

    tearDown(() {
      io.dispose();
    });

    test('Quicksave stores data in memory', () async {
      final savePayload = {
        'command': IoCommands.save,
        'file_data': [1, 2, 3, 4, 5],
      };

      // Enable quicksave mode
      io.quicksaveMode = true;

      // Execute save command
      final result = await io.command(savePayload);

      // Verify success
      expect(result, isTrue);
      // Verify data stored
      expect(io.memorySaveData, isNotNull);
      expect(io.memorySaveData, [1, 2, 3, 4, 5]);
      // Verify mode reset
      expect(io.quicksaveMode, isFalse);
    });

    test('Quickrestore retrieves data from memory', () async {
      // Pre-populate memory data
      io.memorySaveData = Uint8List.fromList([10, 20, 30]);

      // Enable quickrestore mode
      io.quickrestoreMode = true;

      final restorePayload = {'command': IoCommands.restore};

      // Execute restore command
      final result = await io.command(restorePayload);

      // Verify data retrieved
      expect(result, isNotNull);
      expect(result, [10, 20, 30]);
      // Verify mode reset
      expect(io.quickrestoreMode, isFalse);
    });

    test('Quickrestore returns null if no data', () async {
      // Ensure no memory data
      io.memorySaveData = null;

      // Enable quickrestore mode
      io.quickrestoreMode = true;

      final restorePayload = {'command': IoCommands.restore};

      // Execute restore command
      final result = await io.command(restorePayload);

      // Verify null result
      expect(result, isNull);
      // Verify mode reset
      expect(io.quickrestoreMode, isFalse);
    });
  });
}
