import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.openOuting,
    required this.goToToday,
    required this.navigationGeneration,
  });
  final AppController controller;
  final ValueChanged<String> openOuting;
  final VoidCallback goToToday;
  final int navigationGeneration;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Map<String, Outing> _reopeningOutings = <String, Outing>{};

  AppController get controller => widget.controller;
  ValueChanged<String> get openOuting => widget.openOuting;
  VoidCallback get goToToday => widget.goToToday;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final completed =
          controller.state.outings
              .where(
                (outing) =>
                    outing.isComplete ||
                    _reopeningOutings.containsKey(outing.id),
              )
              .map((outing) => _reopeningOutings[outing.id] ?? outing)
              .toList()
            ..sort(
              (a, b) => (b.completedAt ?? b.startedAt).compareTo(
                a.completedAt ?? a.startedAt,
              ),
            );
      final dismissed =
          controller.state.outings
              .where((outing) => outing.isDismissed)
              .toList()
            ..sort(
              (a, b) => (b.dismissedAtUTC ?? b.startedAt).compareTo(
                a.dismissedAtUTC ?? a.startedAt,
              ),
            );
      return CustomScrollView(
        key: const PageStorageKey<String>('history'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 25, 22, 34),
            sliver: SliverList.list(
              children: [
                const Eyebrow('A small record of done'),
                const SizedBox(height: 8),
                Text(
                  'Good to go.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Reopen an outing to keep its checkmarks, or start a fresh one from Today.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 19),
                if (completed.isEmpty)
                  SurfaceCard(
                    child: const EmptyState(
                      title: 'Nothing to look back on yet',
                      message: 'When you finish an outing, its packed list will appear here.',
                      icon: Icons.done_all_rounded,
                    ),
                  )
                else
                  ...completed.map(
                    (outing) => Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _HistoryCard(
                        key: ValueKey<String>('history-${outing.id}'),
                        outing: outing,
                        onOpen: () => openOuting(outing.id),
                        onReopen: () => _reopen(context, outing),
                        reopening: _reopeningOutings.containsKey(outing.id),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (completed.isNotEmpty)
                  Center(
                    child: Text(
                      '${completed.length} ${completed.length == 1 ? 'outing' : 'outings'} finished',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.appColors.muted),
                    ),
                  ),
                if (dismissed.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const Eyebrow('Set aside for later'),
                  const SizedBox(height: 7),
                  Text(
                    'Dismissed outings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'These are still in progress. Restore one to pick it up again.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  ...dismissed.map(
                    (outing) => Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _DismissedOutingCard(
                        outing: outing,
                        onRestore: () => _restoreDismissed(context, outing),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _reopen(BuildContext context, Outing outing) async {
    if (_reopeningOutings.containsKey(outing.id)) return;
    final navigationGeneration = widget.navigationGeneration;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    _reopeningOutings[outing.id] = outing;
    setState(() {});
    try {
      await controller.undoFinish(outing.id);
      final reopened = controller.state.outings
          .where((value) => value.id == outing.id)
          .firstOrNull;
      if (reopened?.isActive != true) {
        throw StateError('This outing could not be reopened.');
      }
      if (context.mounted &&
          widget.navigationGeneration == navigationGeneration &&
          !navigator.canPop() &&
          ModalRoute.of(context) == route) {
        openOuting(outing.id);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t reopen this outing. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _reopeningOutings.remove(outing.id));
      }
    }
  }

  Future<void> _restoreDismissed(BuildContext context, Outing outing) async {
    try {
      await controller.restoreOuting(outing.id);
      if (context.mounted) {
        goToToday();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${outing.blueprintName} is back in Today.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t restore this outing. Please try again.'),
          ),
        );
      }
    }
  }
}

class _DismissedOutingCard extends StatelessWidget {
  const _DismissedOutingCard({required this.outing, required this.onRestore});

  final Outing outing;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(23),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(
                  icon: Icons.inventory_2_outlined,
                  color: colors.sky,
                  size: 47,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outing.blueprintName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDate(outing.date)}  ·  ${outing.checkedCount} of ${outing.items.length} packed',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Restore outing'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.ink,
                  side: BorderSide(color: colors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    super.key,
    required this.outing,
    required this.onOpen,
    required this.onReopen,
    required this.reopening,
  });
  final Outing outing;
  final VoidCallback onOpen;
  final VoidCallback onReopen;
  final bool reopening;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: reopening ? null : onOpen,
        borderRadius: BorderRadius.circular(23),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(
                    icon: Icons.done_rounded,
                    color: colors.accent,
                    size: 47,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          outing.blueprintName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(outing.date),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.muted),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: outing.items
                    .take(4)
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ItemGlyph(
                              iconKey: item.iconKey,
                              size: 14,
                              color: colors.muted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              item.label,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.muted),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              if (outing.items.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+${outing.items.length - 4} more',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.muted),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: reopening ? null : onReopen,
                  icon: reopening
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: Icon(Icons.sync_rounded, size: 18),
                        )
                      : const Icon(Icons.replay_rounded, size: 18),
                  label: Text(reopening ? 'Reopening…' : 'Reopen outing'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.ink,
                    side: BorderSide(color: colors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
