import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/app_controller.dart';
import '../domain/models.dart';
import '../platform/leave_gateway.dart';
import '../ui/history_screen.dart';
import '../ui/lists_screen.dart';
import '../ui/onboarding_screen.dart';
import '../ui/pack_screen.dart';
import '../ui/settings_screen.dart';
import '../ui/today_screen.dart';
import '../ui/components.dart';
import 'theme.dart';

class BeforeILeaveApp extends StatefulWidget {
  const BeforeILeaveApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<BeforeILeaveApp> createState() => _BeforeILeaveAppState();
}

class _BeforeILeaveAppState extends State<BeforeILeaveApp> {
  late final AppController _controller;
  bool _ownsController = false;
  String? _pendingLaunchAction;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        AppController(gateway: MethodChannelLeaveGateway());
    _controller.setLaunchActionHandler(_receiveLaunchAction);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    try {
      final action = await _controller.getLaunchAction();
      if (action != null) _receiveLaunchAction(action);
    } catch (_) {
      // Launch affordances are optional; the normal Today screen remains usable.
    }
  }

  void _receiveLaunchAction(String action) {
    if (!mounted) return;
    setState(() => _pendingLaunchAction = action);
  }

  void _clearLaunchAction() {
    if (mounted) setState(() => _pendingLaunchAction = null);
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final state = _controller.state;
      final settings = state.settings;
      final accentIndex = switch (settings.accent) {
        'sky' => 1,
        'lilac' => 2,
        _ => 0,
      };
      return MaterialApp(
        title: 'Ready Yet?',
        debugShowCheckedModeBanner: false,
        theme: createAppTheme(dark: false, accentIndex: accentIndex),
        darkTheme: createAppTheme(dark: true, accentIndex: accentIndex),
        themeMode: settings.appearance == 'dark'
            ? ThemeMode.dark
            : settings.appearance == 'light'
            ? ThemeMode.light
            : ThemeMode.system,
        home: !_controller.isReady
            ? const _LoadingScreen()
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations:
                      MediaQuery.disableAnimationsOf(context) ||
                      settings.reducedMotion,
                ),
                child: !_controller.canEdit
                    ? _RecoveryScreen(controller: _controller)
                    : !settings.onboarded
                    ? OnboardingScreen(
                        onDone: () => unawaited(
                          _controller.updateSettings(
                            settings.copyWith(onboarded: true),
                          ),
                        ),
                      )
                    : HomeShell(
                        controller: _controller,
                        launchAction: _pendingLaunchAction,
                        onLaunchActionHandled: _clearLaunchAction,
                      ),
              ),
      );
    },
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    this.launchAction,
    required this.onLaunchActionHandled,
  });
  final AppController controller;
  final String? launchAction;
  final VoidCallback onLaunchActionHandled;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  String? _scheduledLaunchAction;
  final Set<String> _handledLaunchRequests = <String>{};
  int _navigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final action = widget.launchAction;
    if (action != null) _scheduleLaunchAction(action);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refreshExternalState());
    }
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.launchAction != null &&
        widget.launchAction != oldWidget.launchAction) {
      _scheduleLaunchAction(widget.launchAction!);
    }
  }

  void _scheduleLaunchAction(String action) {
    if (_scheduledLaunchAction == action) return;
    _scheduledLaunchAction = action;
    final navigationGeneration = ++_navigationGeneration;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _runLaunchAction(action, navigationGeneration),
    );
  }

  Future<void> _runLaunchAction(String action, int navigationGeneration) async {
    if (!mounted) return;
    _scheduledLaunchAction = null;
    widget.onLaunchActionHandled();
    if (action == 'pack_today') {
      _returnToToday();
      final active = _latestActiveOuting();
      if (active != null) _replacePackRoute(active.id);
      return;
    }

    String requestKey = action;
    Map<String, Object?>? payload;
    try {
      final decoded = jsonDecode(action);
      if (decoded is Map) payload = Map<String, Object?>.from(decoded);
      if (decoded is Map && decoded['requestId'] is String) {
        requestKey = decoded['requestId'] as String;
      }
    } on FormatException {
      // Invalid or legacy action payloads are handled by the controller as a
      // graceful Today fallback rather than treated as a resumable outing.
    }
    if (_handledLaunchRequests.contains(requestKey)) return;
    if (action == 'widget_today' || payload?['type'] == 'widget_today') {
      _rememberLaunchRequest(requestKey);
      _returnToToday();
      return;
    }

    final navigator = Navigator.of(context);
    final hadChildRoute = navigator.canPop();

    try {
      final outingId = await widget.controller.handleWidgetLaunchAction(action);
      if (!mounted) return;
      if (_navigationGeneration != navigationGeneration ||
          navigator.canPop() != hadChildRoute) {
        return;
      }
      final outing = widget.controller.state.outings
          .where((value) => value.id == outingId)
          .firstOrNull;
      if (outing == null || !outing.isActive) {
        _showLaunchMessage('That outing is no longer available.');
        return;
      }
      _rememberLaunchRequest(requestKey);
      _replacePackRoute(outingId);
    } catch (_) {
      if (mounted) {
        _showLaunchMessage(
          'Couldn’t open that checklist. Try again in the app.',
        );
      }
    }
  }

  Outing? _latestActiveOuting() {
    final active =
        widget.controller.state.outings
            .where((outing) => outing.isActive)
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return active.firstOrNull;
  }

  void _rememberLaunchRequest(String requestKey) {
    _handledLaunchRequests.add(requestKey);
    if (_handledLaunchRequests.length > 32) {
      _handledLaunchRequests.remove(_handledLaunchRequests.first);
    }
  }

  void _returnToToday() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_tab != 0 && mounted) setState(() => _tab = 0);
  }

  void _showLaunchMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openOuting(String id) {
    _navigationGeneration++;
    _replacePackRoute(id);
  }

  void _replacePackRoute(String id) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => PackScreen(controller: widget.controller, outingId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pages = [
      TodayScreen(
        controller: widget.controller,
        openOuting: _openOuting,
        goToLists: () => setState(() => _tab = 1),
      ),
      ListsScreen(controller: widget.controller),
      HistoryScreen(
        controller: widget.controller,
        openOuting: _openOuting,
        goToToday: () => setState(() => _tab = 0),
      ),
      SettingsScreen(controller: widget.controller),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (widget.controller.saveError != null)
              SaveErrorBanner(
                onRetry: () => unawaited(widget.controller.retrySave()),
              ),
            Expanded(
              child: IndexedStack(index: _tab, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colors.accentInk
                  : colors.muted,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? colors.ink
                  : colors.muted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            if (index != _tab) _navigationGeneration++;
            setState(() => _tab = index);
          },
          height: 72,
          backgroundColor: colors.surface,
          indicatorColor: colors.accent,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined),
              selectedIcon: Icon(Icons.wb_sunny_rounded),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist_rounded),
              label: 'Lists',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 22),
          Text(
            'Getting your lists ready',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen({required this.controller});
  final AppController controller;

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  bool _working = false;
  String? _message;

  Future<void> _retry() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.controller.retryLoad();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Your saved lists still can’t be read. You can retry again or begin with a new set.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startFresh() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Start with fresh lists?'),
        content: const Text(
          'This replaces the unreadable saved data on this device. Your previous lists may not be recoverable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep trying'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.controller.resetCorruptState();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Couldn’t create a fresh set yet. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(
                  icon: Icons.inventory_2_outlined,
                  color: context.appColors.peach,
                  size: 62,
                ),
                const SizedBox(height: 22),
                const Eyebrow('A saved file needs attention'),
                const SizedBox(height: 9),
                Text(
                  'Your lists couldn’t be opened.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 11),
                Text(
                  'The app keeps your checklists on this device. It can try reading them again, or you can start a new set.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: context.appColors.muted),
                ),
                const SizedBox(height: 19),
                SurfaceCard(
                  color: context.appColors.surfaceRaised,
                  child: Text(
                    'Starting fresh replaces the unreadable saved data. The old lists may not be recoverable.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.appColors.ink),
                  ),
                ),
                const SizedBox(height: 18),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                PrimaryButton(
                  label: _working ? 'Trying…' : 'Try reading again',
                  icon: Icons.refresh_rounded,
                  enabled: !_working,
                  onPressed: _retry,
                ),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _working ? null : _startFresh,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.appColors.ink,
                      side: BorderSide(color: context.appColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Start with fresh lists'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
