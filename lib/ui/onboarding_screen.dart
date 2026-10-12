import 'package:flutter/material.dart';

import 'components.dart';
import '../app/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;
  final Set<String> _practice = <String>{'keys'};
  static const _sample = <(String, String)>[
    ('Keys', 'keys'),
    ('Phone', 'phone'),
    ('Water bottle', 'water'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 18, 6),
              child: Row(
                children: [
                  const Icon(Icons.route_rounded, size: 21),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ready Yet?',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Before I Leave',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (_page < 2)
                    TextButton(
                      onPressed: widget.onDone,
                      child: const Text('Skip'),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                child: _buildPage(context, colors),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: index == _page ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: index == _page ? colors.ink : colors.line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: _page == 2 ? 'Let’s get ready' : 'Continue',
                    onPressed: () {
                      if (_page == 2) {
                        widget.onDone();
                      } else {
                        setState(() => _page++);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, AppColors colors) {
    return SingleChildScrollView(
      key: ValueKey<int>(_page),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: switch (_page) {
        0 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('A calmer way out the door'),
            const SizedBox(height: 12),
            Text(
              'Leave with\nwhat you need.',
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 12),
            Text(
              'A small, private checklist for the things you need before you go.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: colors.sky,
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: const BagTray(checked: 1, total: 4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 19, color: colors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your lists stay on this device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
        1 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Try a practice pack'),
            const SizedBox(height: 12),
            Text(
              'Tap what you’d\nbring along.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 7),
            Text(
              'This is only a demo. Your real lists are still waiting.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: _sample.map((item) {
                  final checked = _practice.contains(item.$2);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ChecklistRow(
                      label: item.$1,
                      icon: item.$2,
                      checked: checked,
                      onToggle: () => setState(
                        () => checked
                            ? _practice.remove(item.$2)
                            : _practice.add(item.$2),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${_practice.length} packed',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Your space, your pace'),
            const SizedBox(height: 12),
            Text(
              'No accounts.\nNo noise.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Your checklists and outing history stay on your device. Start with a ready-made list, then make it yours.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: 22),
            SurfaceCard(
              child: Column(
                children: [
                  _promise(
                    context,
                    Icons.offline_bolt_outlined,
                    'Works offline',
                    'No connection needed to check things off.',
                  ),
                  Divider(color: colors.line, height: 24),
                  _promise(
                    context,
                    Icons.tune_rounded,
                    'Made to fit your day',
                    'Separate lists for work, school, travel and more.',
                  ),
                  Divider(color: colors.line, height: 24),
                  _promise(
                    context,
                    Icons.notifications_none_rounded,
                    'Reminders are optional',
                    'You decide if and when a nudge helps.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can change these choices later in Settings.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.muted),
            ),
          ],
        ),
      },
    );
  }

  Widget _promise(
    BuildContext context,
    IconData icon,
    String title,
    String detail,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconTile(icon: icon, color: context.appColors.surfaceRaised, size: 42),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}
