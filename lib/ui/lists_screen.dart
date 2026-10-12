import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'item_editor_sheet.dart';

class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final blueprints = controller.state.blueprints;
      return CustomScrollView(
        key: const PageStorageKey<String>('lists'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
            sliver: SliverList.list(
              children: [
                const Eyebrow('Build your defaults'),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Your lists.',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _createBlueprint(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Reusable checklists for the things you do often.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 19),
                if (blueprints.isEmpty)
                  SurfaceCard(
                    child: Column(
                      children: [
                        const EmptyState(
                          title: 'Start with one list',
                          message: 'Give your next outing a few essentials, then reuse it whenever you like.',
                          icon: Icons.playlist_add_rounded,
                        ),
                        PrimaryButton(
                          label: 'Create your first list',
                          onPressed: () => _createBlueprint(context),
                          icon: Icons.add_rounded,
                        ),
                      ],
                    ),
                  )
                else
                  ...blueprints.map(
                    (blueprint) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BlueprintSummary(
                        blueprint: blueprint,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BlueprintEditorScreen(
                              controller: controller,
                              blueprintId: blueprint.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                SurfaceCard(
                  color: context.appColors.surfaceRaised,
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 19,
                        color: context.appColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Changes here shape future outings. A pack already in progress keeps its own copy.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.appColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _createBlueprint(BuildContext context) async {
    final name = await _NameSheet.show(context);
    if (name == null || !context.mounted) return;
    try {
      final id = await controller.createBlueprint(name: name);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                BlueprintEditorScreen(controller: controller, blueprintId: id),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t create this list. Please try again.'),
          ),
        );
      }
    }
  }
}

class _BlueprintSummary extends StatelessWidget {
  const _BlueprintSummary({required this.blueprint, required this.onTap});
  final Blueprint blueprint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final swatch = switch (blueprint.colorIndex % 4) {
      0 => colors.sky,
      1 => colors.peach,
      2 => colors.lilac,
      _ => colors.accent,
    };
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconTile(
                icon: iconFor(blueprint.iconKey),
                color: swatch,
                size: 52,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blueprint.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blueprint.items.isEmpty
                          ? 'Ready for its first item'
                          : blueprint.items
                                .take(3)
                                .map((item) => item.label)
                                .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: colors.canvas,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 19,
                  color: colors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BlueprintEditorScreen extends StatelessWidget {
  const BlueprintEditorScreen({
    super.key,
    required this.controller,
    required this.blueprintId,
  });
  final AppController controller;
  final String blueprintId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final matches = controller.state.blueprints.where(
        (item) => item.id == blueprintId,
      );
      if (matches.isEmpty) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
            title: 'This list is gone',
            message: 'It may have been deleted.',
          ),
        );
      }
      final blueprint = matches.first;
      final extras =
          controller.state.extras
              .where((extra) => extra.blueprintId == blueprintId)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to lists',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'List options',
              onSelected: (value) => _onListAction(context, value, blueprint),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename list')),
                PopupMenuItem(value: 'delete', child: Text('Delete list')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (controller.saveError != null)
              SaveErrorBanner(onRetry: () => unawaited(controller.retrySave())),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 7, 22, 28),
                    sliver: SliverList.list(
                      children: [
                        const Eyebrow('Reusable checklist'),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            IconTile(
                              icon: iconFor(blueprint.iconKey),
                              color: _blueprintColor(
                                context,
                                blueprint.colorIndex,
                              ),
                              size: 58,
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                blueprint.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'These items copy into each new outing.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 23),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Everyday items',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              '${blueprint.items.length}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: context.appColors.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (blueprint.items.isEmpty)
                          SurfaceCard(
                            child: Column(
                              children: [
                                const EmptyState(
                                  title: 'Begin with one essential',
                                  message: 'Add something you want to remember before heading out.',
                                  icon: Icons.add_task_rounded,
                                ),
                                PrimaryButton(
                                  label: 'Add an item',
                                  icon: Icons.add_rounded,
                                  onPressed: () => _addItem(context, blueprint),
                                ),
                              ],
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: blueprint.items.length,
                            onReorderItem: (oldIndex, newIndex) => unawaited(
                              controller.reorderBlueprintItems(
                                blueprintId,
                                oldIndex,
                                newIndex > oldIndex ? newIndex + 1 : newIndex,
                              ),
                            ),
                            itemBuilder: (context, index) {
                              final item = blueprint.items[index];
                              return Padding(
                                key: ValueKey<String>(item.id),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ChecklistRow(
                                  label: item.label,
                                  icon: item.iconKey,
                                  checked: false,
                                  onToggle: () =>
                                      _editItem(context, blueprint, item),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: IconButton(
                                          tooltip: 'Edit ${item.label}',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 19,
                                          ),
                                          onPressed: () => _editItem(
                                            context,
                                            blueprint,
                                            item,
                                          ),
                                        ),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: context.appColors.muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        if (blueprint.items.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: () => _addItem(context, blueprint),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add a reusable item'),
                            style: _outlineStyle(context),
                          ),
                        ],
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Just for a date',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add a dated item',
                              onPressed: () => _addExtra(context, blueprint),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A one-time item joins this list only on its chosen day.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 11),
                        if (extras.isEmpty)
                          Material(
                            color: context.appColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () => _addExtra(context, blueprint),
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_available_outlined,
                                      color: context.appColors.muted,
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Text(
                                        'Add an item for a specific day',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ),
                                    const Icon(Icons.add_rounded),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          ...extras.map(
                            (extra) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SurfaceCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    IconTile(
                                      icon: iconFor(extra.iconKey),
                                      color: context.appColors.peach,
                                      size: 42,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            extra.label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatDate(extra.date),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove ${extra.label}',
                                      onPressed: () => unawaited(
                                        controller.removeDatedExtra(extra.id),
                                      ),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _addExtra(context, blueprint),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Add a one-off item'),
                          style: _outlineStyle(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _addItem(BuildContext context, Blueprint blueprint) async {
    await showItemEditor(
      context,
      title: 'Add a list item',
      onSave: (label, icon) => controller.addBlueprintItem(
        blueprint.id,
        label: label,
        iconKey: icon,
      ),
    );
  }

  Future<void> _editItem(
    BuildContext context,
    Blueprint blueprint,
    ChecklistItem item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: IconTile(
                  icon: iconFor(item.iconKey),
                  color: context.appColors.sky,
                  size: 45,
                ),
                title: Text(item.label),
                subtitle: const Text('Reusable item'),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit item'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await showItemEditor(
                    context,
                    title: 'Edit item',
                    initialLabel: item.label,
                    initialIcon: item.iconKey,
                    onSave: (label, icon) => controller.updateBlueprintItem(
                      blueprint.id,
                      item.id,
                      label: label,
                      iconKey: icon,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: context.appColors.ink,
                ),
                title: const Text('Remove from list'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    controller.removeBlueprintItem(blueprint.id, item.id),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addExtra(BuildContext context, Blueprint blueprint) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Choose the day for this item',
    );
    if (!context.mounted || date == null) return;
    final key = localDateKey(date);
    await showItemEditor(
      context,
      title: 'Add for ${_formatDate(key)}',
      onSave: (label, icon) => controller.addDatedExtra(
        blueprint.id,
        date: key,
        label: label,
        iconKey: icon,
      ),
    );
  }

  Future<void> _onListAction(
    BuildContext context,
    String action,
    Blueprint blueprint,
  ) async {
    if (action == 'rename') {
      final name = await _NameSheet.show(
        context,
        initialName: blueprint.name,
        title: 'Rename this list',
      );
      if (name != null) {
        await controller.updateBlueprint(blueprint.id, name: name);
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('Delete ${blueprint.name}?'),
        content: const Text(
          'This removes the reusable list and its dated extras. Outings already in progress keep their own items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep list'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete list'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.deleteBlueprint(blueprint.id);
      if (context.mounted) Navigator.maybePop(context);
    }
  }
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initialName, required this.title});
  final String? initialName;
  final String title;

  static Future<String?> show(
    BuildContext context, {
    String? initialName,
    String title = 'Name your list',
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _NameSheet(initialName: initialName, title: title),
  );

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialName ?? '',
  );
  String? _error;
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _field.text.trim();
    if (value.isEmpty || value.length > 32) {
      setState(
        () => _error = value.isEmpty
            ? 'Add a short name.'
            : 'Use 32 characters or fewer.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      21,
      22,
      22 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 27),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _field,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'List name',
            hintText: 'e.g. Weekend away',
            errorText: _error,
            filled: true,
            fillColor: context.appColors.canvas,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
          ),
        ),
        const SizedBox(height: 15),
        PrimaryButton(
          label: widget.initialName == null ? 'Create list' : 'Save name',
          onPressed: _submit,
          icon: Icons.check_rounded,
        ),
      ],
    ),
  );
}

Color _blueprintColor(BuildContext context, int index) => switch (index % 4) {
  0 => context.appColors.sky,
  1 => context.appColors.peach,
  2 => context.appColors.lilac,
  _ => context.appColors.accent,
};

ButtonStyle _outlineStyle(BuildContext context) => OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  foregroundColor: context.appColors.ink,
  side: BorderSide(color: context.appColors.line),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

String _formatDate(String key) {
  final parts = key.split('-').map(int.parse).toList();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[parts[1] - 1]} ${parts[2]}, ${parts[0]}';
}
