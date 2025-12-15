import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zart_player/src/settings_helper.dart';

class SettingsDialog extends StatefulWidget {
  final int selectedColorIndex;
  final ValueChanged<int> onColorSelected;

  const SettingsDialog({super.key, required this.selectedColorIndex, required this.onColorSelected});

  static Future<void> show(
    BuildContext context, {
    required int selectedColorIndex,
    required ValueChanged<int> onColorSelected,
  }) async {
    await showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(selectedColorIndex: selectedColorIndex, onColorSelected: onColorSelected);
      },
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final SettingsHelper _settingsHelper = SettingsHelper();
  Map<String, String> _macroBinds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMacros();
  }

  Future<void> _loadMacros() async {
    final binds = await _settingsHelper.loadMacroBinds();
    if (mounted) {
      setState(() {
        _macroBinds = binds;
        _isLoading = false;
      });
    }
  }

  Future<void> _addMacro() async {
    String keyChart = '';
    String macroText = '';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: Text('Add Macro', style: GoogleFonts.outfit(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                style: GoogleFonts.firaCode(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Key (e.g. "a")',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
                maxLength: 1,
                onChanged: (value) => keyChart = value.toLowerCase(),
              ),
              const SizedBox(height: 8),
              TextField(
                style: GoogleFonts.firaCode(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Text to insert',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
                onChanged: (value) => macroText = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                if (keyChart.isNotEmpty && macroText.isNotEmpty) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (keyChart.isNotEmpty && macroText.isNotEmpty) {
      final newBinds = Map<String, String>.from(_macroBinds);
      newBinds[keyChart] = macroText;
      await _settingsHelper.saveMacroBinds(newBinds);
      await _loadMacros();
    }
  }

  Future<void> _deleteMacro(String key) async {
    final newBinds = Map<String, String>.from(_macroBinds);
    newBinds.remove(key);
    await _settingsHelper.saveMacroBinds(newBinds);
    await _loadMacros();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: Text('Settings', style: GoogleFonts.outfit(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
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
                  final isSelected = index == widget.selectedColorIndex;
                  return GestureDetector(
                    onTap: () {
                      widget.onColorSelected(index);
                      // Don't close dialog on color select to allow macro editing
                      setState(() {});
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
            const Divider(height: 32, color: Colors.grey),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Macro Binds (Ctrl + Key):', style: GoogleFonts.inter(color: Colors.grey[400])),
                IconButton(
                  onPressed: _addMacro,
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  tooltip: "Add Macro",
                ),
              ],
            ),
            const SizedBox(height: 8),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _macroBinds.isEmpty
                ? Text(
                    'No macros set.',
                    style: GoogleFonts.firaCode(color: Colors.grey, fontStyle: FontStyle.italic),
                  )
                : Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _macroBinds.length,
                      itemBuilder: (context, index) {
                        final key = _macroBinds.keys.elementAt(index);
                        final value = _macroBinds[key]!;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          title: RichText(
                            text: TextSpan(
                              children: [
                                const TextSpan(
                                  text: "Ctrl + ",
                                  style: TextStyle(color: Colors.grey),
                                ),
                                TextSpan(
                                  text: key.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Fira Code',
                                  ),
                                ),
                                const TextSpan(
                                  text: "  →  ",
                                  style: TextStyle(color: Colors.grey),
                                ),
                                TextSpan(
                                  text: value,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                            onPressed: () => _deleteMacro(key),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
