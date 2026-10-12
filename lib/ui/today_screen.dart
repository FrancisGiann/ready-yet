import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/app_controller.dart';
import '../domain/models.dart';
import '../app/theme.dart';
import 'components.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.controller,
    required this.openOuting,
    required this.goToLists,
    this.now,
  });
  final AppController controller;
  final ValueChanged<String> openOuting;
  final VoidCallback goToLists;
  final DateTime Function()? now;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  Timer? _dayBoundaryTimer;
  DateTime _today = DateTime.now();

  DateTime get _clockNow => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _today = _clockNow;
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh(_today);
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now) _refreshDay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  void _refreshDay() {
    if (!mounted) return;
    _refreshTo(_clockNow);
  }

  void _refreshTo(DateTime current) {
    if (current.year != _today.year ||
        current.month != _today.month ||
        current.day != _today.day) {
      setState(() => _today = current);
    }
    _scheduleDayRefresh(current);
  }

  void _scheduleDayRefresh(DateTime current) {
    _dayBoundaryTimer?.cancel();
    final nextDay = DateTime(current.year, current.month, current.day + 1);
    final delay = nextDay.difference(current);
    _dayBoundaryTimer = Timer(
      delay <= Duration.zero ? const Duration(seconds: 1) : delay,
      _refreshDay,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final dateKey = localDateKey(_today);
      final active = state.outings.where((outing) => outing.isActive).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final date = _today;
      return CustomScrollView(
        key: const PageStorageKey<String>('today'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            sliver: SliverList.list(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 17;
                    final dateLabel = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          color: context.appColors.muted,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _dateLabel(date),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: context.appColors.muted),
                        ),
                      ],
                    );
                    return largeText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Eyebrow('A little more ready'),
                              const SizedBox(height: 6),
                              dateLabel,
                            ],
                          )
                        : Row(
                            children: [
                              const Eyebrow('A little more ready'),
                              const Spacer(),
                              dateLabel,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Before you\nhead out.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 19),
                _DailyPanel(
                  blueprintCount: state.blueprints.length,
                  activeCount: active.length,
                ),
                if (active.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final largeText =
                          MediaQuery.textScalerOf(context).scale(14) > 17;
                      return largeText
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pick up where you left off',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  '${active.length} unfinished',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: context.appColors.muted,
                                      ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pick up where you left off',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                                Text(
                                  '${active.length}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: context.appColors.muted,
                                      ),
                                ),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 12),
                  ...active.map(
                    (outing) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ResumeCard(
                        key: ValueKey<String>('resume-${outing.id}'),
                        outing: outing,
                        onTap: () => widget.openOuting(outing.id),
                        onDismiss: () => _dismissOuting(context, outing),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 17;
                    final heading = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Ready when you are'),
                        const SizedBox(height: 5),
                        Text(
                          'Your go-to lists',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    );
                    return largeText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              heading,
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: widget.goToLists,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('Edit'),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(child: heading),
                              TextButton.icon(
                                onPressed: widget.goToLists,
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                label: const Text('Edit'),
                              ),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 10),
                if (state.blueprints.isEmpty)
                  SurfaceCard(
                    child: Column(
                      children: [
                        const EmptyState(
                          title: 'A list for every kind of day',
                          message: 'Make your first checklist and keep the little essentials close.',
                        ),
                        PrimaryButton(
                          label: 'Create a list',
                          icon: Icons.add_rounded,
                          onPressed: widget.goToLists,
                        ),
                      ],
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      final columns = textScale > 1.18
                          ? 1
                          : constraints.maxWidth > 460
                          ? 3
                          : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: state.blueprints.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: textScale > 1.65
                              ? 180
                              : textScale > 1.18
                              ? 130
                              : columns == 3
                              ? 132
                              : 126,
                        ),
                        itemBuilder: (context, index) {
                          final blueprint = state.blueprints[index];
                          final extraCount = state.extras
                              .where(
                                (extra) =>
                                    extra.blueprintId == blueprint.id &&
                                    extra.date == dateKey,
                              )
                              .length;
                          return _BlueprintCard(
                            blueprint: blueprint,
                            extraCount: extraCount,
                            onTap: () => _start(context, blueprint),
                          );
                        },
                      );
                    },
                  ),
                const SizedBox(height: 17),
                Center(
                  child: Text(
                    'Made for the moments just before.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.appColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _start(BuildContext context, Blueprint blueprint) async {
    final actionTime = _clockNow;
    final dateKey = localDateKey(actionTime);
    _refreshTo(actionTime);
    final hasDatedItem = widget.controller.state.extras.any(
      (extra) => extra.blueprintId == blueprint.id && extra.date == dateKey,
    );
    if (blueprint.items.isEmpty && !hasDatedItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an item to this list before you start.'),
        ),
      );
      widget.goToLists();
      return;
    }
    try {
      final id = await widget.controller.startOuting(
        blueprint.id,
        date: dateKey,
      );
      if (context.mounted) widget.openOuting(id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _dismissOuting(BuildContext context, Outing outing) async {
    try {
      await widget.controller.dismissOuting(outing.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${outing.blueprintName} moved to Dismissed outings.'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_restoreOuting(context, outing)),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t dismiss this outing. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _restoreOuting(BuildContext context, Outing outing) async {
    try {
      await widget.controller.restoreOuting(outing.id);
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

  String _dateLabel(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

class _DailyPanel extends StatelessWidget {
  const _DailyPanel({required this.blueprintCount, required this.activeCount});
  final int blueprintCount;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 17;
    return Container(
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(25),
      ),
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: largeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeCount > 0
                          ? 'Your next step is waiting.'
                          : 'Start with the familiar things.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.accentInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      activeCount > 0
                          ? 'Pick up any unfinished outing below.'
                          : '$blueprintCount lists, ready for whenever.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.accentInk.withValues(alpha: .8),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 15,
                          color: colors.accentInk,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Private on this device',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.accentInk,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 145,
                    child: BagTray(
                      checked: activeCount,
                      total: activeCount + 2,
                      compact: true,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeCount > 0
                            ? 'Your next step is waiting.'
                            : 'Start with the familiar things.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.accentInk,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        activeCount > 0
                            ? 'Pick up any unfinished outing below.'
                            : '$blueprintCount lists, ready for whenever.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.accentInk.withValues(alpha: .8),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 15,
                            color: colors.accentInk,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Private on this device',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.accentInk,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 106,
                  child: BagTray(
                    checked: activeCount,
                    total: activeCount + 2,
                    compact: true,
                  ),
                ),
              ],
            ),
    );
  }
}

class _BlueprintCard extends StatefulWidget {
  const _BlueprintCard({
    required this.blueprint,
    required this.extraCount,
    required this.onTap,
  });
  final Blueprint blueprint;
  final int extraCount;
  final Future<void> Function() onTap;

  @override
  State<_BlueprintCard> createState() => _BlueprintCardState();
}

class _BlueprintCardState extends State<_BlueprintCard> {
  bool _starting = false;

  Future<void> _open() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Color _tileColor(BuildContext context) =>
      switch (widget.blueprint.colorIndex % 4) {
        0 => context.appColors.sky,
        1 => context.appColors.peach,
        2 => context.appColors.lilac,
        _ => context.appColors.surfaceRaised,
      };

  @override
  Widget build(BuildContext context) => Material(
    color: context.appColors.surface,
    borderRadius: BorderRadius.circular(23),
    child: InkWell(
      onTap: _starting ? null : _open,
      borderRadius: BorderRadius.circular(23),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconTile(
                  icon: iconFor(widget.blueprint.iconKey),
                  color: _tileColor(context),
                  size: 43,
                ),
                const Spacer(),
                _starting
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.arrow_outward_rounded,
                        size: 19,
                        color: context.appColors.muted,
                      ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.blueprint.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.blueprint.items.length} things${widget.extraCount > 0 ? '  ·  +${widget.extraCount} today' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.appColors.muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    super.key,
    required this.outing,
    required this.onTap,
    required this.onDismiss,
  });
  final Outing outing;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = outing.items.isEmpty
        ? 0.0
        : outing.checkedCount / outing.items.length;
    final label =
        'Resume ${outing.blueprintName}, ${outing.checkedCount} of ${outing.items.length} packed';
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                label: label,
                onTap: onTap,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          IconTile(
                            icon: Icons.backpack_outlined,
                            color: colors.accent,
                            size: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  outing.blueprintName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${outing.checkedCount} of ${outing.items.length} packed',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colors.muted),
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 5,
                                    backgroundColor: colors.surfaceRaised,
                                    color: colors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: colors.ink),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Outing options for ${outing.blueprintName}',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              requestFocus: false,
              color: colors.surface,
              surfaceTintColor: colors.surface,
              elevation: 3,
              shadowColor: colors.ink.withValues(alpha: .14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.line),
              ),
              menuPadding: const EdgeInsets.symmetric(vertical: 6),
              onSelected: (value) {
                if (value == 'dismiss') onDismiss();
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'dismiss',
                  child: Text('Dismiss outing'),
                ),
              ],
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.more_horiz_rounded, color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
