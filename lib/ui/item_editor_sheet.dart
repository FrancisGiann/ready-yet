import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'components.dart';

Future<void> showItemEditor(
  BuildContext context, {
  required String title,
  String? initialLabel,
  String initialIcon = 'other',
  required FutureOr<void> Function(String label, String iconKey) onSave,
}) async {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => MediaQuery(
      data: MediaQuery.of(sheetContext).copyWith(
        disableAnimations:
            MediaQuery.disableAnimationsOf(sheetContext) || disableAnimations,
      ),
      child: _ItemEditorSheet(
        title: title,
        initialLabel: initialLabel,
        initialIcon: initialIcon,
        onSave: onSave,
      ),
    ),
  );
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({
    required this.title,
    required this.initialLabel,
    required this.initialIcon,
    required this.onSave,
  });
  final String title;
  final String? initialLabel;
  final String initialIcon;
  final FutureOr<void> Function(String, String) onSave;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.initialLabel ?? '',
  );
  late String _icon = widget.initialIcon;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Give this item a name.');
      return;
    }
    if (label.length > 60) {
      setState(() => _error = 'Keep the name under 60 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(label, _icon);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t save this item. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Keep legacy keys values on the model; only present their canonical
    // equivalent once in the picker unless the user explicitly chooses it.
    final selectedIcon = _icon == 'keys' ? 'key' : _icon;
    final iconKeys = [
      ...iconChoiceKeys,
      if (!iconChoiceKeys.contains(selectedIcon)) selectedIcon,
    ];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        11,
        22,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 19),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: 27),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _label,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'What should you bring?',
                hintText: 'e.g. Sunglasses',
                errorText: _error,
                filled: true,
                fillColor: colors.canvas,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide(color: colors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide(color: colors.line),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 17,
                ),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              'CHOOSE AN ICON',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.muted,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: iconKeys.map((key) {
                final selected = key == selectedIcon;
                final label = iconLabel(key);
                void selectIcon() => setState(() => _icon = key);
                return Semantics(
                  button: true,
                  enabled: !_saving,
                  selected: selected,
                  label: '$label icon',
                  onTap: _saving ? null : selectIcon,
                  child: ExcludeSemantics(
                    child: Tooltip(
                      message: label,
                      child: InkWell(
                        onTap: _saving ? null : selectIcon,
                        borderRadius: BorderRadius.circular(15),
                        child: AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.accent
                                : colors.surfaceRaised,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: selected ? colors.ink : Colors.transparent,
                              width: selected ? 1.5 : 0,
                            ),
                          ),
                          child: Center(
                            child: ItemGlyph(
                              iconKey: key,
                              color: selected ? colors.accentInk : colors.ink,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 21),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save item',
              icon: Icons.check_rounded,
              enabled: !_saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
