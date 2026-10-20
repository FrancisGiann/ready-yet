import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';

String _time(BuildContext context, int minutes) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

void openSchedules(BuildContext context, AppController controller) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SchedulesScreen(controller: controller),
    ),
  );
}

/// Today stays one tap away from its own occurrence, including skipped history.
class TodaySchedules extends StatelessWidget {
  const TodaySchedules({
    super.key,
    required this.controller,
    required this.today,
    required this.openOuting,
  });
  final AppController controller;
  final DateTime today;
  final ValueChanged<String> openOuting;

  @override
  Widget build(BuildContext context) {
    final date = localDateKey(today);
    final schedules =
        controller.state.schedules.where((s) => s.runsOn(today)).toList()
          ..sort((a, b) => a.departureMinute.compareTo(b.departureMinute));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: Eyebrow('Your rhythm')),
            TextButton.icon(
              onPressed: () => openSchedules(context, controller),
              icon: const Icon(Icons.event_repeat_rounded),
              label: const Text('Schedules'),
            ),
          ],
        ),
        if (schedules.isEmpty)
          Text(
            'School mornings, workdays, whatever your week looks like.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...schedules.map((schedule) {
            final outing = controller.state.outings
                .where((o) => o.id == schedule.occurrenceId(date))
                .firstOrNull;
            final blueprint = controller.state.blueprints
                .where((b) => b.id == schedule.blueprintId)
                .firstOrNull;
            if (blueprint == null && outing == null) {
              return const SizedBox.shrink();
            }
            final status = outing?.isComplete == true
                ? 'Ready to go'
                : outing?.isDismissed == true
                ? 'Skipped today'
                : '${outing?.checkedCount ?? 0}/${outing?.items.length ?? blueprint?.items.length ?? 0} packed';
            return Padding(
              padding: const EdgeInsets.only(top: 9),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _time(context, schedule.departureMinute),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          outing?.blueprintName ??
                              blueprint?.name ??
                              'Checklist removed',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Align(
                        key: ValueKey(status),
                        alignment: Alignment.centerLeft,
                        child: Text(status),
                      ),
                    ),
                    if (outing != null && outing.isActive)
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () => openOuting(outing.id),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('Open checklist'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await controller.dismissOuting(outing.id);
                            },
                            child: const Text('Skip today'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen>
    with WidgetsBindingObserver {
  Map<String, Object?> _status = const {};
  bool _permissionBusy = false;

  Future<void> _allowReminders() async {
    setState(() => _permissionBusy = true);
    try {
      await widget.controller.requestNotifications();
      await _refreshStatus();
      if (mounted) await widget.controller.refreshExternalState();
    } catch (_) {
      if (mounted) {
        _message(context, 'Couldn’t update reminder access. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _permissionBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await widget.controller.reminderStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _status = const {'unavailable': true});
    }
  }

  Future<void> _edit([ChecklistSchedule? schedule]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ScheduleEditor(controller: widget.controller, schedule: schedule),
    );
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final native = _status['checklistSchedules'];
      final precise = native is Map && native['precise'] == true;
      return Scaffold(
        appBar: AppBar(title: const Text('Schedules')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
          children: [
            if (widget.controller.saveError != null)
              SaveErrorBanner(
                onRetry: () => unawaited(widget.controller.retrySave()),
              ),
            const Eyebrow('One less thing to remember'),
            const SizedBox(height: 12),
            Text(
              'A little rhythm.\nA calmer morning.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose a checklist, your days and when you leave. Each day gets a fresh copy. Your history stays yours.',
            ),
            const SizedBox(height: 22),
            ...state.schedules.map((schedule) {
              final blueprint = state.blueprints
                  .where((b) => b.id == schedule.blueprintId)
                  .firstOrNull;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              blueprint?.name ?? 'Checklist removed',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Semantics(
                            label:
                                '${schedule.enabled ? 'Pause' : 'Resume'} ${blueprint?.name ?? 'schedule'}',
                            child: Switch(
                              value: schedule.enabled && blueprint != null,
                              onChanged: blueprint == null
                                  ? null
                                  : (enabled) async {
                                      try {
                                        await widget.controller.saveSchedule(
                                          schedule.copyWith(enabled: enabled),
                                        );
                                      } catch (_) {
                                        if (context.mounted) {
                                          _message(
                                            context,
                                            'Couldn’t save the schedule. Try again.',
                                          );
                                        }
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${_time(context, schedule.departureMinute)} departure',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${schedule.weekdays.map((day) => _days[day - 1]).join(' · ')}\n${schedule.leadMinutes == 0 ? 'Remind at departure' : 'Remind ${schedule.leadMinutes} min before'}',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: blueprint == null
                                ? null
                                : () => _edit(schedule),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final remove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete this schedule?'),
                                  content: const Text(
                                    'Your checklist and past outings will stay. Future reminders will stop.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Keep'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete schedule'),
                                    ),
                                  ],
                                ),
                              );
                              if (remove == true) {
                                try {
                                  await widget.controller.deleteSchedule(
                                    schedule.id,
                                  );
                                } catch (_) {
                                  if (context.mounted) {
                                    _message(
                                      context,
                                      'Couldn’t delete the schedule. Try again.',
                                    );
                                  }
                                }
                              }
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            PrimaryButton(
              label: state.schedules.isEmpty
                  ? 'Create a schedule'
                  : 'Add schedule',
              icon: Icons.add_rounded,
              enabled: state.blueprints.isNotEmpty,
              onPressed: () => _edit(),
            ),
            if (state.blueprints.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Create a checklist in Your lists first.'),
              ),
            const SizedBox(height: 18),
            SurfaceCard(
              color: context.appColors.surfaceRaised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminders, on your terms',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status['permissionGranted'] == true
                        ? precise
                              ? 'Precise alarm access is enabled. Delivery can still depend on your phone’s settings.'
                              : 'Android may delay reminders. You can allow more precise alarms in system settings.'
                        : 'Schedules work without notifications. Allow reminders when you’re ready.',
                  ),
                  if (_status['permissionGranted'] != true)
                    TextButton(
                      onPressed: _permissionBusy ? null : _allowReminders,
                      child: const Text('Allow reminders'),
                    ),
                  if (_status['permissionGranted'] != true)
                    TextButton(
                      onPressed: () async {
                        final opened = await widget.controller
                            .openNotificationSettings();
                        if (!opened && context.mounted) {
                          _message(
                            context,
                            'Notification settings are unavailable on this device.',
                          );
                        }
                      },
                      child: const Text('Open notification settings'),
                    ),
                  if (!precise && _status['permissionGranted'] == true)
                    TextButton(
                      onPressed: () async {
                        final opened = await widget.controller
                            .openPreciseReminderSettings();
                        if (!opened && context.mounted) {
                          _message(
                            context,
                            'Precise reminder settings are unavailable on this device.',
                          );
                        }
                      },
                      child: const Text('Improve reminder timing'),
                    ),
                  if (native is Map && native['error'] is String)
                    Text(
                      native['error'] as String,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_status['unavailable'] == true)
                    const Text(
                      'Reminder status is unavailable. Your schedules are still saved.',
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({required this.controller, this.schedule});
  final AppController controller;
  final ChecklistSchedule? schedule;
  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late final String _scheduleId;
  late String _blueprintId;
  late Set<int> _weekdays;
  late int _departure;
  late int _lead;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _scheduleId = schedule?.id ?? widget.controller.newScheduleId();
    _blueprintId =
        schedule?.blueprintId ?? widget.controller.state.blueprints.first.id;
    _weekdays = schedule?.weekdays.toSet() ?? {1, 2, 3, 4, 5};
    _departure = schedule?.departureMinute ?? 7 * 60;
    _lead = schedule?.leadMinutes ?? 15;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      22,
      22,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.schedule == null ? 'Make it a routine.' : 'Your routine.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _blueprintId,
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          decoration: const InputDecoration(labelText: 'Checklist'),
          items: widget.controller.state.blueprints
              .map(
                (b) => DropdownMenuItem(
                  value: b.id,
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) setState(() => _blueprintId = value);
                },
        ),
        const SizedBox(height: 18),
        const Eyebrow('Repeat on'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: List.generate(
            7,
            (index) => FilterChip(
              label: Text(_days[index]),
              selected: _weekdays.contains(index + 1),
              onSelected: _saving
                  ? null
                  : (selected) => setState(() {
                      if (selected) {
                        _weekdays.add(index + 1);
                      } else {
                        _weekdays.remove(index + 1);
                      }
                    }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Departure time'),
            const Text('Uses your phone’s local time'),
            TextButton.icon(
              icon: const Icon(Icons.schedule_rounded),
              onPressed: _saving
                  ? null
                  : () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: _departure ~/ 60,
                          minute: _departure % 60,
                        ),
                      );
                      if (time != null && mounted) {
                        setState(
                          () => _departure = time.hour * 60 + time.minute,
                        );
                      }
                    },
              label: Text(_time(context, _departure)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _lead,
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          decoration: const InputDecoration(labelText: 'Remind me'),
          items: ({0, 5, 10, 15, 30, 60, 120, _lead}.toList()..sort())
              .map(
                (lead) => DropdownMenuItem(
                  value: lead,
                  child: Text(
                    lead == 0 ? 'At departure' : '$lead minutes before',
                  ),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) setState(() => _lead = value);
                },
        ),
        const SizedBox(height: 16),
        const Text(
          'A fresh checklist on each scheduled day. No location tracking.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: _saving ? 'Saving…' : 'Save schedule',
          enabled: !_saving && _weekdays.isNotEmpty,
          icon: Icons.check_rounded,
          onPressed: () async {
            setState(() {
              _saving = true;
              _error = null;
            });
            try {
              await widget.controller.saveSchedule(
                ChecklistSchedule(
                  id: _scheduleId,
                  blueprintId: _blueprintId,
                  weekdays: _weekdays,
                  departureMinute: _departure,
                  leadMinutes: _lead,
                  enabled: widget.schedule?.enabled ?? true,
                ),
              );
              if (context.mounted) Navigator.pop(context);
            } catch (_) {
              if (mounted) {
                setState(() {
                  _saving = false;
                  _error = 'Couldn’t save this schedule. Please try again.';
                });
              }
            }
          },
        ),
      ],
    ),
  );
}
