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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _ItemEditorSheet(
      title: title,
      initialLabel: initialLabel,
      initialIcon: initialIcon,
      onSave: onSave,
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
  static const _iconKeys = [
    'bag',
    'key',
    'phone',
    'wallet',
    'water',
    'book',
    'notebook',
    'pen',
    'laptop',
    'charger',
    'clothes',
    'medicine',
    'ticket',
    'umbrella',
    'other',
  ];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
    final iconKeys = [..._iconKeys, if (!_iconKeys.contains(_icon)) _icon];
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
                final selected = key == _icon;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '${key[0].toUpperCase()}${key.substring(1)} icon',
                  child: InkWell(
                    onTap: () => setState(() => _icon = key),
                    borderRadius: BorderRadius.circular(15),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected ? colors.accent : colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: selected ? colors.ink : Colors.transparent,
                          width: selected ? 1.5 : 0,
                        ),
                      ),
                      child: Icon(iconFor(key), color: colors.ink),
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
