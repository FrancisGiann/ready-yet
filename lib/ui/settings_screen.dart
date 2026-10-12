import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'components.dart';
import 'home_widget_guide.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  Map<String, Object?> _reminderStatus = const {};
  bool _checkingReminder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncReminderStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncReminderStatus();
  }

  Future<void> _syncReminderStatus() async {
    await _readReminderStatus();
    final nativeEnabled = _reminderStatus['enabled'];
    final current = widget.controller.state.settings;
    if (nativeEnabled == false && current.reminderEnabled) {
      try {
        await widget.controller.updateSettings(
          current.copyWith(reminderEnabled: false),
        );
      } catch (_) {
        // A status read should still complete if persistence is temporarily unavailable.
      }
    }
  }

  Future<void> _readReminderStatus() async {
    try {
      final value = await widget.controller.reminderStatus();
      if (mounted) setState(() => _reminderStatus = value);
    } catch (_) {
      if (mounted) {
        setState(() => _reminderStatus = const {'status': 'unavailable'});
      }
    }
  }

  void _update(AppSettings settings) =>
      unawaited(widget.controller.updateSettings(settings));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final settings = widget.controller.state.settings;
      return CustomScrollView(
        key: const PageStorageKey<String>('settings'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 25, 22, 35),
            sliver: SliverList.list(
              children: [
                const Eyebrow('Make it yours'),
                const SizedBox(height: 8),
                Text(
                  'Settings.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'A few small choices can make leaving easier.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 23),
                _SectionTitle(
                  title: 'Appearance',
                  icon: Icons.palette_outlined,
                ),
                const SizedBox(height: 9),
                SurfaceCard(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 11),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final largeText =
                              MediaQuery.textScalerOf(context).scale(14) > 17;
                          if (largeText) {
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in const [
                                  ('system', 'System'),
                                  ('light', 'Light'),
                                  ('dark', 'Dark'),
                                ])
                                  _AppearanceChoice(
                                    value: option.$1,
                                    label: option.$2,
                                    selected: settings.appearance == option.$1,
                                    onSelected: () => _update(
                                      settings.copyWith(appearance: option.$1),
                                    ),
                                  ),
                              ],
                            );
                          }
                          return SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: 'system',
                                label: const Text('System'),
                                icon: largeText
                                    ? null
                                    : const Icon(
                                        Icons.brightness_auto_outlined,
                                      ),
                              ),
                              ButtonSegment(
                                value: 'light',
                                label: const Text('Light'),
                                icon: largeText
                                    ? null
                                    : const Icon(Icons.light_mode_outlined),
                              ),
                              ButtonSegment(
                                value: 'dark',
                                label: const Text('Dark'),
                                icon: largeText
                                    ? null
                                    : const Icon(Icons.dark_mode_outlined),
                              ),
                            ],
                            selected: {settings.appearance},
                            onSelectionChanged: (values) => _update(
                              settings.copyWith(appearance: values.first),
                            ),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStateProperty.all(
                                const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 17),
                      Text(
                        'Accent',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 9,
                        runSpacing: 8,
                        children: [
                          _AccentChoice(
                            label: 'Lime',
                            name: 'lime',
                            color: const Color(0xFFD4F56A),
                            selected: settings.accent == 'lime',
                            onTap: () =>
                                _update(settings.copyWith(accent: 'lime')),
                          ),
                          _AccentChoice(
                            label: 'Sky',
                            name: 'sky',
                            color: const Color(0xFFA9D8E8),
                            selected: settings.accent == 'sky',
                            onTap: () =>
                                _update(settings.copyWith(accent: 'sky')),
                          ),
                          _AccentChoice(
                            label: 'Lilac',
                            name: 'lilac',
                            color: const Color(0xFFCAB9E7),
                            selected: settings.accent == 'lilac',
                            onTap: () =>
                                _update(settings.copyWith(accent: 'lilac')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                HomeWidgetGuide(controller: widget.controller),
                const SizedBox(height: 22),
                _SectionTitle(title: 'Feel', icon: Icons.vibration_rounded),
                const SizedBox(height: 9),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  child: Column(
                    children: [
                      _SettingSwitch(
                        title: 'Haptic feedback',
                        detail: 'A light touch when you check an item.',
                        icon: Icons.touch_app_outlined,
                        value: settings.haptics,
                        onChanged: (value) =>
                            _update(settings.copyWith(haptics: value)),
                      ),
                      Divider(height: 1, color: context.appColors.line),
                      _SettingSwitch(
                        title: 'Reduce motion',
                        detail:
                            'Also respects your device accessibility setting.',
                        icon: Icons.motion_photos_off_outlined,
                        value: settings.reducedMotion,
                        onChanged: (value) =>
                            _update(settings.copyWith(reducedMotion: value)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _SectionTitle(
                  title: 'A gentle nudge',
                  icon: Icons.notifications_none_rounded,
                ),
                const SizedBox(height: 9),
                SurfaceCard(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MergeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconTile(
                              icon: Icons.notifications_active_outlined,
                              color: context.appColors.peach,
                              size: 45,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.reminderEnabled
                                        ? 'Daily reminder on'
                                        : 'A reminder, if you want one',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _reminderMessage(settings),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: context.appColors.muted,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.reminderEnabled,
                              onChanged: _checkingReminder
                                  ? null
                                  : (value) => _toggleReminder(settings, value),
                            ),
                          ],
                        ),
                      ),
                      if (settings.reminderEnabled) ...[
                        const SizedBox(height: 9),
                        OutlinedButton.icon(
                          onPressed: _checkingReminder
                              ? null
                              : () => _chooseReminderTime(settings),
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(
                            'Every day at ${TimeOfDay(hour: settings.reminderHour, minute: settings.reminderMinute).format(context)}',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: context.appColors.ink,
                            side: BorderSide(color: context.appColors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ],
                      if (_checkingReminder) ...[
                        const SizedBox(height: 9),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      if (_needsNotificationAccess) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Notifications are turned off for this app. Your lists still work normally.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.appColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _SectionTitle(
                  title: 'Your space',
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 9),
                SurfaceCard(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    children: [
                      _SettingAction(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy, plainly',
                        detail: 'How your lists are stored',
                        onTap: () => _showPrivacy(context),
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: context.appColors.line,
                      ),
                      _SettingAction(
                        icon: Icons.replay_rounded,
                        title: 'Replay the welcome',
                        detail: 'See the quick practice again',
                        onTap: () => _replayWelcome(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: context.appColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        color: context.appColors.muted,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Ready Yet? is free and private. No account, ads, location tracking or online sync.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.appColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Center(
                  child: Column(
                    children: [
                      Text(
                        'READY YET?  ·  1.0.2',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.1,
                          color: context.appColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Before I Leave',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: context.appColors.muted),
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

  bool get _needsNotificationAccess =>
      _reminderStatus['permissionGranted'] == false ||
      _reminderStatus['reason'] == 'permission_required' ||
      _reminderStatus['reason'] == 'notifications_disabled';

  String _reminderMessage(AppSettings settings) {
    if (_needsNotificationAccess && !settings.reminderEnabled) {
      return 'Notification permission was not granted. You can try again whenever you like.';
    }
    return settings.reminderEnabled
        ? 'A quiet daily prompt to check your list.'
        : 'Choose a time that works for you. You can turn this off anytime.';
  }

  Future<void> _toggleReminder(AppSettings settings, bool enabled) async {
    setState(() => _checkingReminder = true);
    try {
      final result = await widget.controller.setReminder(
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
        enabled: enabled,
      );
      if (mounted) {
        setState(() => _reminderStatus = result);
        if (enabled && result['enabled'] != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder not enabled. You can allow notifications in Android settings and try again.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t update the reminder. Try again in a moment.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingReminder = false);
    }
  }

  Future<void> _chooseReminderTime(AppSettings settings) async {
    final choice = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
      ),
      helpText: 'Choose your daily reminder',
    );
    if (choice == null) return;
    await _toggleReminder(
      settings.copyWith(
        reminderHour: choice.hour,
        reminderMinute: choice.minute,
      ),
      true,
    );
  }

  Future<void> _replayWelcome() async {
    await widget.controller.updateSettings(
      widget.controller.state.settings.copyWith(onboarded: false),
    );
  }

  Future<void> _showPrivacy(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('The short version'),
          const SizedBox(height: 8),
          Text(
            'Your lists stay yours.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 13),
          Text(
            'Ready Yet? saves checklists and outing history privately on this device. It does not create an account, send data to a server, show ads or use your location.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 13),
          Text(
            'If you turn on a reminder, Android schedules an approximate local notification at the time you choose. You can switch it off here at any time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String value;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      label: 'Appearance: $label',
      button: true,
      selected: selected,
      onTap: onSelected,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? colors.accent : colors.surfaceRaised,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: onSelected,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: colors.line),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? colors.accentInk : colors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: context.appColors.muted),
      const SizedBox(width: 9),
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.detail,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String detail;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 70),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.appColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.appColors.muted),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _SettingAction extends StatelessWidget {
  const _SettingAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    minVerticalPadding: 8,
    leading: Icon(icon),
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(detail),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.label,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label accent',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? context.appColors.accentInk : Colors.transparent,
            width: selected ? 1.8 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 17,
                color: context.appColors.accentInk,
              )
            else
              const SizedBox(width: 17),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: context.appColors.accentInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
