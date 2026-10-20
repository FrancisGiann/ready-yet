import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'item_editor_sheet.dart';

class PackScreen extends StatefulWidget {
  const PackScreen({
    super.key,
    required this.controller,
    required this.outingId,
    this.onBackToHome,
  });
  final AppController controller;
  final String outingId;
  final VoidCallback? onBackToHome;

  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  AppController get controller => widget.controller;
  String get outingId => widget.outingId;

  bool _finishAttempted = false;
  bool _finishPending = false;
  bool _finishAccepted = false;
  bool _reopenPending = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final outings = controller.state.outings.where(
        (item) => item.id == outingId,
      );
      if (outings.isEmpty) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
            title: 'This outing is gone',
            message: 'It may have been removed from your history.',
          ),
        );
      }
      final outing = outings.first;
      // The controller publishes local mutations immediately. Keep the live
      // checklist visible until the awaited native merge confirms completion.
      final complete =
          _reopenPending ||
          outing.isComplete && (!_finishAttempted || _finishAccepted);
      final canEdit = !complete && !_finishPending;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            outing.blueprintName,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          centerTitle: false,
          actions: [
            if (canEdit)
              IconButton(
                tooltip: 'Add a packing item',
                onPressed: () => _addItem(context),
                icon: const Icon(Icons.add_rounded),
              ),
          ],
        ),
        body: Column(
          children: [
            if (controller.saveError != null)
              SaveErrorBanner(onRetry: () => unawaited(controller.retrySave())),
            Expanded(
              child: CustomScrollView(
                key: const PageStorageKey<String>('pack'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 23),
                    sliver: SliverList.list(
                      children: [
                        const Eyebrow('One outing · your own snapshot'),
                        const SizedBox(height: 6),
                        Text(
                          complete ? "You're ready." : 'Let’s pack.',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _dateLabel(outing.date),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: context.appColors.sky,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 19,
                            vertical: 4,
                          ),
                          child: Column(
                            children: [
                              BagTray(
                                checked: outing.checkedCount,
                                total: outing.items.length,
                                sealed: complete,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    complete
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.circle_outlined,
                                    size: 17,
                                    color: context.appColors.ink,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    complete
                                        ? 'Ready to go.'
                                        : '${outing.checkedCount} of ${outing.items.length} packed',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'The things to bring',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              '${outing.items.length}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: context.appColors.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (outing.items.isEmpty)
                          SurfaceCard(
                            child: Column(
                              children: [
                                const EmptyState(
                                  title: 'Nothing on this pack yet',
                                  message: 'Add a few things to remember before you go.',
                                  icon: Icons.add_task_rounded,
                                ),
                                PrimaryButton(
                                  label: 'Add an item',
                                  icon: Icons.add_rounded,
                                  onPressed: () => _addItem(context),
                                ),
                              ],
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: outing.items.length,
                            onReorderItem: (oldIndex, newIndex) {
                              if (!canEdit) return;
                              unawaited(
                                controller.reorderOutingItems(
                                  outingId,
                                  oldIndex,
                                  newIndex > oldIndex ? newIndex + 1 : newIndex,
                                ),
                              );
                            },
                            itemBuilder: (context, index) {
                              final item = outing.items[index];
                              return Padding(
                                key: ValueKey<String>(item.id),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ChecklistRow(
                                  label: item.label,
                                  icon: item.iconKey,
                                  checked: item.checked,
                                  onToggle: canEdit
                                      ? () => _toggle(item)
                                      : () {},
                                  onMore: !canEdit
                                      ? null
                                      : () => _itemActions(context, item),
                                  trailing: !canEdit
                                      ? null
                                      : ReorderableDragStartListener(
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
                                ),
                              );
                            },
                          ),
                        if (canEdit && outing.items.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: () => _addItem(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add something else'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              foregroundColor: context.appColors.ink,
                              side: BorderSide(color: context.appColors.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 17),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.appColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.content_copy_rounded,
                                size: 18,
                                color: context.appColors.muted,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'This outing is its own copy. Updates to “${outing.blueprintName}” won’t change it.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: context.appColors.muted,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            decoration: BoxDecoration(
              color: context.appColors.canvas,
              border: Border(
                top: BorderSide(
                  color: context.appColors.line.withValues(alpha: .7),
                ),
              ),
            ),
            child: complete
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrimaryButton(
                        label: 'Back to home',
                        icon: Icons.home_outlined,
                        onPressed: _backToHome,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _reopenPending || _finishPending
                              ? null
                              : _reopen,
                          icon: _reopenPending
                              ? const Icon(Icons.sync_rounded, size: 18)
                              : const Icon(Icons.replay_rounded, size: 18),
                          label: Text(
                            _reopenPending ? 'Reopening…' : 'Reopen outing',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.appColors.ink,
                            side: BorderSide(color: context.appColors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!outing.canFinish)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            outing.items.isEmpty
                                ? 'Add an item to finish this outing.'
                                : 'Check off every item to finish.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.appColors.muted),
                          ),
                        ),
                      PrimaryButton(
                        label: _finishPending ? 'Saving…' : 'Finish outing',
                        icon: _finishPending
                            ? Icons.sync_rounded
                            : Icons.done_all_rounded,
                        enabled: outing.canFinish && !_finishPending,
                        onPressed: _finish,
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );

  Future<void> _toggle(OutingItem item) async {
    if (_finishPending || _reopenPending) return;
    if (controller.state.settings.haptics) {
      unawaited(HapticFeedback.selectionClick());
    }
    await controller.toggleOutingItem(outingId, item.id);
  }

  Future<void> _addItem(BuildContext context) => showItemEditor(
    context,
    title: 'Add to this outing',
    onSave: (label, icon) =>
        controller.addOutingItem(outingId, label: label, iconKey: icon),
  );

  Future<void> _itemActions(BuildContext context, OutingItem item) =>
      showModalBottomSheet<void>(
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
                    iconKey: item.iconKey,
                    color: context.appColors.sky,
                    size: 45,
                  ),
                  title: Text(item.label),
                  subtitle: const Text('This outing only'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit item'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await showItemEditor(
                      context,
                      title: 'Edit this item',
                      initialLabel: item.label,
                      initialIcon: item.iconKey,
                      onSave: (label, icon) => controller.updateOutingItem(
                        outingId,
                        item.id,
                        label: label,
                        iconKey: icon,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Remove from outing'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(controller.removeOutingItem(outingId, item.id));
                  },
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _finish() async {
    if (_finishPending || _reopenPending) return;
    final currentOuting = controller.state.outings
        .where((outing) => outing.id == outingId)
        .firstOrNull;
    if (currentOuting == null ||
        currentOuting.isComplete ||
        !currentOuting.canFinish) {
      return;
    }
    setState(() {
      _finishAttempted = true;
      _finishPending = true;
      _finishAccepted = false;
    });
    try {
      await controller.finishOuting(outingId);
      final savedOuting = controller.state.outings
          .where((outing) => outing.id == outingId)
          .firstOrNull;
      if (!mounted) return;
      if (savedOuting?.isComplete == true && controller.saveError == null) {
        setState(() {
          _finishPending = false;
          _finishAccepted = true;
        });
        if (controller.state.settings.haptics) {
          unawaited(HapticFeedback.lightImpact());
        }
      } else {
        setState(() => _finishPending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This outing is still being packed.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _finishPending = false;
        _finishAccepted = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _backToHome() {
    final callback = widget.onBackToHome;
    if (callback != null) {
      callback();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _reopen() async {
    if (_reopenPending || _finishPending) return;
    final currentOuting = controller.state.outings
        .where((outing) => outing.id == outingId)
        .firstOrNull;
    if (currentOuting == null || !currentOuting.isComplete) return;
    setState(() => _reopenPending = true);
    try {
      await controller.undoFinish(outingId);
      final reopened = controller.state.outings
          .where((outing) => outing.id == outingId)
          .firstOrNull;
      if (reopened == null || !reopened.isActive) {
        throw StateError('This outing is still being saved.');
      }
      if (!mounted) return;
      setState(() {
        _reopenPending = false;
        _finishAttempted = false;
        _finishAccepted = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _reopenPending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t reopen this outing. Please try again.'),
          ),
        );
      }
    }
  }

  String _dateLabel(String key) {
    final parts = key.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1], parts[2]);
    final now = DateTime.now();
    const week = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today · ${months[date.month - 1]} ${date.day}';
    }
    return '${week[date.weekday - 1]} · ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
