import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dialog for saving games with filename selection and history.
/// Shows previous save names and allows entering a new one.
class SaveGameDialog extends StatefulWidget {
  const SaveGameDialog({super.key});

  static const String _saveNamesKey = 'zart_save_names';

  /// Shows the dialog and returns the chosen filename (without extension) or null if cancelled.
  static Future<String?> show(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => const SaveGameDialog(),
    );
  }

  /// Saves the filename to history (most recent first, max 10)
  static Future<void> addToHistory(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_saveNamesKey) ?? [];

    // Remove if already exists (will re-add at top)
    names.remove(filename);

    // Add to front
    names.insert(0, filename);

    // Keep max 10
    if (names.length > 10) {
      names.removeLast();
    }

    await prefs.setStringList(_saveNamesKey, names);
  }

  @override
  State<SaveGameDialog> createState() => _SaveGameDialogState();
}

class _SaveGameDialogState extends State<SaveGameDialog> {
  final TextEditingController _controller = TextEditingController(
    text: 'savegame',
  );
  List<String> _previousSaves = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaveNames();
  }

  Future<void> _loadSaveNames() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(SaveGameDialog._saveNamesKey) ?? [];
    setState(() {
      _previousSaves = names;
      _isLoading = false;
      // Pre-populate with most recent save name for convenience
      if (names.isNotEmpty) {
        _controller.text = names.first;
      }
    });
  }

  /// Normalizes filename: removes .sav extension if present
  String _normalizeFilename(String input) {
    var name = input.trim();
    if (name.toLowerCase().endsWith('.sav')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  Future<void> _onSave() async {
    final name = _normalizeFilename(_controller.text);
    if (name.isEmpty) return;

    // Check if this would overwrite an existing save
    if (_previousSaves.contains(name)) {
      final confirmed = await _showOverwriteConfirmation(name);
      if (!confirmed) return;
    }

    if (mounted) {
      Navigator.of(context).pop(name);
    }
  }

  /// Shows overwrite confirmation dialog unless user has disabled it
  Future<bool> _showOverwriteConfirmation(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    final skipConfirmation = prefs.getBool(_skipOverwriteConfirmKey) ?? false;

    if (skipConfirmation) return true;

    if (!mounted) return false;

    bool dontShowAgain = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'Overwrite Save?',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Based on your save history, it looks like a save file named "$filename.sav" may already exist. Do you want to overwrite it?',
                style: GoogleFonts.firaCode(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Note: Sometimes the browser will save the file like so "$filename (1).sav" when it sees that a file already exists with that same name.',
                style: GoogleFonts.firaCode(color: Colors.orange, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: dontShowAgain,
                    onChanged: (v) =>
                        setDialogState(() => dontShowAgain = v ?? false),
                    activeColor: Colors.tealAccent,
                  ),
                  Text(
                    "Don't ask me again",
                    style: GoogleFonts.firaCode(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (dontShowAgain) {
                  await prefs.setBool(_skipOverwriteConfirmKey, true);
                }
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              child: Text(
                'Overwrite',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  static const String _skipOverwriteConfirmKey = 'zart_skip_overwrite_confirm';

  void _selectPreviousSave(String name) {
    _controller.text = name;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: Text('Save Game', style: GoogleFonts.outfit(color: Colors.white)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info text
            Text(
              'On most browsers, the file will be saved to your "Downloads" folder.',
              style: GoogleFonts.firaCode(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            // Filename input
            TextField(
              controller: _controller,
              autofocus: true,
              style: GoogleFonts.firaCode(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Save name',
                labelStyle: GoogleFonts.firaCode(color: Colors.grey),
                suffixText: '.sav',
                suffixStyle: GoogleFonts.firaCode(color: Colors.grey),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.tealAccent),
                ),
              ),
              onSubmitted: (_) => _onSave(),
            ),

            // Previous saves
            if (!_isLoading && _previousSaves.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Previous saves:',
                style: GoogleFonts.firaCode(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _previousSaves.length,
                  itemBuilder: (context, index) {
                    final name = _previousSaves[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '$name.sav',
                        style: GoogleFonts.firaCode(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => _selectPreviousSave(name),
                      hoverColor: Colors.tealAccent.withValues(alpha: 0.1),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
          ),
          child: Text(
            'Save',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
