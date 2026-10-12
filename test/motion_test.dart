import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:before_i_leave/app/theme.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';
import 'package:before_i_leave/ui/components.dart';
import 'package:before_i_leave/ui/pack_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey<String>('motion_capture');
const _bagCaptureKey = ValueKey<String>('bag_only_capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRenderFonts);

  testWidgets(
    'checked items settle before explicit finish seals the bag and confirms',
    (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments is String) {
            haptics.add((call.arguments as String).split('.').last);
          }
          return null;
        },
      );

      const cases = <(String, Size, bool, bool, bool)>[
        ('360_light', Size(360, 800), false, true, true),
        ('430_dark', Size(430, 932), true, false, false),
      ];
      for (final (name, size, dark, hapticsEnabled, waitForSettle) in cases) {
        final session = await _makeSession(haptics: hapticsEnabled);
        final reduceMotion = ValueNotifier(false);
        await _openPack(tester, session, size, dark, reduceMotion);
        await tester.pumpAndSettle();

        expect(find.text('5 of 6 packed'), findsOneWidget);
        expect(find.text("You're ready."), findsNothing);
        await _captureFrame(tester, 'motion_pack_near_complete_$name');
        if (waitForSettle) {
          await _captureFrame(
            tester,
            'motion_sequence_360_light_00_near_complete',
          );
        }

        await tester.tap(find.text('Bag'));
        await tester.pump(const Duration(milliseconds: 50));
        if (waitForSettle) {
          await _captureFrame(tester, 'motion_sequence_360_light_01_pack_050');
        }
        await tester.pump(const Duration(milliseconds: 50));
        if (waitForSettle) {
          await _captureFrame(tester, 'motion_sequence_360_light_02_pack_100');
        }
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('6 of 6 packed'), findsOneWidget);
        expect(find.text("You're ready."), findsNothing);
        final allChecked = session.controller.state.outings.single;
        expect(allChecked.checkedCount, allChecked.items.length);
        expect(allChecked.completedAt, isNull);
        expect(allChecked.isComplete, isFalse);
        expect(
          session.controller.state.outings.where((outing) => outing.isComplete),
          isEmpty,
          reason: 'Checking every item must not create completed history.',
        );
        await _captureFrame(tester, 'motion_pack_settling_$name');

        await tester.pumpAndSettle();
        await _captureFrame(tester, 'motion_pack_settled_open_$name');
        if (waitForSettle) {
          await _captureFrame(
            tester,
            'motion_sequence_360_light_03_ready_open',
          );
        }

        await tester.tap(find.text('Finish outing'));
        // A second tap during the same pending frame must not enqueue a
        // duplicate finish transaction or a second success haptic.
        if (waitForSettle) {
          await tester.tap(find.text('Finish outing'));
        }
        await session.controller.waitForSaves();
        await tester.pump();
        expect(session.controller.state.outings.single.isComplete, isTrue);
        expect(find.text("You're ready."), findsOneWidget);
        expect(find.text('Ready to go.'), findsOneWidget);
        await _captureFrame(tester, 'motion_finish_confirmed_$name');
        if (waitForSettle) {
          await _captureFrame(
            tester,
            'motion_sequence_360_light_04_finish_open',
          );
        }

        await tester.pump(const Duration(milliseconds: 60));
        if (waitForSettle) {
          await _captureFrame(tester, 'motion_sequence_360_light_05_seal_060');
          await tester.pump(const Duration(milliseconds: 60));
          await _captureFrame(tester, 'motion_sequence_360_light_06_seal_120');
          await tester.pump(const Duration(milliseconds: 60));
          await _captureFrame(tester, 'motion_sequence_360_light_07_seal_180');
          await tester.pump(const Duration(milliseconds: 60));
          await _captureFrame(tester, 'motion_sequence_360_light_08_seal_240');
          await tester.pump(const Duration(milliseconds: 60));
          await _captureFrame(tester, 'motion_sequence_360_light_09_seal_300');
          await tester.pump(const Duration(milliseconds: 60));
          await _captureFrame(tester, 'motion_sequence_360_light_10_seal_360');
        } else {
          await tester.pump(const Duration(milliseconds: 120));
        }
        await _captureFrame(tester, 'motion_bag_closing_$name');
        await tester.pumpAndSettle();
        await _captureFrame(tester, 'motion_bag_sealed_$name');
        if (waitForSettle) {
          await _captureFrame(tester, 'motion_sequence_360_light_11_sealed');
        }
        expect(tester.takeException(), isNull, reason: name);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        reduceMotion.dispose();
        session.controller.dispose();
      }

      expect(haptics, contains('selectionClick'));
      expect(haptics, contains('lightImpact'));
      expect(haptics.where((type) => type == 'lightImpact'), hasLength(1));
      expect(haptics, isNot(contains('mediumImpact')));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'a concurrent uncheck keeps finish unconfirmed until the latest state is saved',
    (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments is String) {
            haptics.add((call.arguments as String).split('.').last);
          }
          return null;
        },
      );
      final initial = _initialState();
      final gateway = _GatedGateway(storedJson: jsonEncode(initial.toJson()));
      final session = await _makeSession(gateway: gateway);
      final reduceMotion = ValueNotifier(false);
      await _openPack(
        tester,
        session,
        const Size(360, 800),
        false,
        reduceMotion,
      );
      await tester.tap(find.text('Bag'));
      await tester.pumpAndSettle();

      gateway.holdNextWrite();
      await tester.tap(find.text('Finish outing'));
      await tester.pump();
      await gateway.writeStarted!.future;
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text("You're ready."), findsNothing);

      final undo = session.controller.undoFinish(session.outingId);
      expect(session.controller.state.outings.single.isComplete, isFalse);
      final uncheck = session.controller.setOutingItemChecked(
        session.outingId,
        session.firstItemId,
        checked: false,
      );
      expect(session.controller.state.outings.single.canFinish, isFalse);
      gateway.releaseWrite();
      await Future.wait([undo, uncheck, session.controller.waitForSaves()]);
      await tester.pumpAndSettle();

      expect(session.controller.state.outings.single.isComplete, isFalse);
      expect(session.controller.state.outings.single.checkedCount, 5);
      expect(find.text("You're ready."), findsNothing);
      expect(find.text('5 of 6 packed'), findsOneWidget);
      expect(find.text('Finish outing'), findsOneWidget);
      expect(haptics, isNot(contains('lightImpact')));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      reduceMotion.dispose();
      session.controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'failed finish keeps the save banner and haptics respect the setting',
    (tester) async {
      final session = await _makeSession(haptics: false);
      final reduceMotion = ValueNotifier(false);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments is String) {
            haptics.add((call.arguments as String).split('.').last);
          }
          return null;
        },
      );
      await _openPack(
        tester,
        session,
        const Size(360, 800),
        false,
        reduceMotion,
      );
      await tester.tap(find.text('Bag'));
      await tester.pumpAndSettle();

      (session.gateway as FakeLeaveGateway).failWrites = true;
      await tester.tap(find.text('Finish outing'));
      await session.controller.waitForSaves();
      await tester.pumpAndSettle();

      expect(find.text("You're ready."), findsNothing);
      expect(find.text('Couldn’t save changes. Tap to retry.'), findsOneWidget);
      expect(haptics, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      reduceMotion.dispose();
      session.controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'reduced motion makes the bag update immediately and statically',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      var checked = 0;
      var sealed = false;
      late StateSetter updateBag;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: createAppTheme(dark: false, accentIndex: 0),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    updateBag = setState;
                    return RepaintBoundary(
                      key: _bagCaptureKey,
                      child: BagTray(
                        checked: checked,
                        total: 1,
                        sealed: sealed,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      updateBag(() => checked = 1);
      await tester.pump();
      final packedOpen = await _captureBag(tester);
      await tester.runAsync(() async {
        await File('qa/screenshots/motion_reduced_static_packed_open.png')
            .writeAsBytes(packedOpen);
      });
      await tester.pump(const Duration(milliseconds: 120));
      expect(await _captureBag(tester), orderedEquals(packedOpen));

      updateBag(() => sealed = true);
      await tester.pump();
      final sealedStatic = await _captureBag(tester);
      await tester.runAsync(() async {
        await File('qa/screenshots/motion_reduced_static_sealed.png')
            .writeAsBytes(sealedStatic);
      });
      await tester.pump(const Duration(milliseconds: 120));
      expect(await _captureBag(tester), orderedEquals(sealedStatic));

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('rapid reverse taps and back navigation safely cancel motion', (
    tester,
  ) async {
    final session = await _makeSession(haptics: false);
    final reduceMotion = ValueNotifier(false);
    await _openPack(tester, session, const Size(360, 800), false, reduceMotion);
    await tester.tap(find.text('Bag'));
    await tester.pump(const Duration(milliseconds: 35));
    await _captureFrame(tester, 'motion_pack_reversal_start_360_light');
    await tester.tap(find.text('Bag'));
    await tester.pump(const Duration(milliseconds: 35));
    await _captureFrame(tester, 'motion_pack_reversal_360_light');
    expect(session.controller.state.outings.single.checkedCount, 5);
    expect(session.controller.state.outings.single.isComplete, isFalse);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open pack'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    reduceMotion.dispose();
    session.controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

AppState _initialState({bool haptics = true}) => AppState.initial().copyWith(
  settings: AppSettings(onboarded: true, haptics: haptics),
);

Future<_Session> _makeSession({
  bool haptics = true,
  FakeLeaveGateway? gateway,
}) async {
  final storage =
      gateway ??
      FakeLeaveGateway(
        storedJson: jsonEncode(_initialState(haptics: haptics).toJson()),
      );
  final controller = AppController(gateway: storage);
  await controller.initialize();
  final outingId = await controller.startOuting('school');
  final outing = controller.state.outings.single;
  for (final item in outing.items.skip(1)) {
    await controller.setOutingItemChecked(outingId, item.id, checked: true);
  }
  await controller.waitForSaves();
  return _Session(controller, storage, outingId, outing.items.first.id);
}

Future<void> _openPack(
  WidgetTester tester,
  _Session session,
  Size size,
  bool dark,
  ValueNotifier<bool> reduceMotion,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: createAppTheme(dark: dark, accentIndex: 0),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (routeContext) => ValueListenableBuilder<bool>(
                      valueListenable: reduceMotion,
                      builder: (context, reduced, _) => MediaQuery(
                        data: MediaQuery.of(routeContext)
                            .copyWith(disableAnimations: reduced),
                        child: PackScreen(
                          controller: session.controller,
                          outingId: session.outingId,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open pack'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open pack'));
  await tester.pumpAndSettle();
}

Future<void> _captureFrame(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode $name');
      final file = File('qa/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<Uint8List> _captureBag(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_bagCaptureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not capture the bag');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

Directory? _findFlutterRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    return Directory(configuredRoot);
  }

  var candidate = File(Platform.resolvedExecutable).absolute.parent;
  while (true) {
    final fonts = Directory(
      [
        candidate.path,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
      ].join(Platform.pathSeparator),
    );
    if (fonts.existsSync()) return candidate;
    final parent = candidate.parent;
    if (parent.path == candidate.path) return null;
    candidate = parent;
  }
}

Future<void> _loadRenderFonts() async {
  final flutterRoot = _findFlutterRoot();
  if (flutterRoot == null) return;
  final directory = Directory(
    [
      flutterRoot.path,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    ].join(Platform.pathSeparator),
  );
  final roboto = File('${directory.path}/Roboto-Regular.ttf');
  final materialIcons = File('${directory.path}/MaterialIcons-Regular.otf');
  if (await roboto.exists()) {
    final bytes = await roboto.readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
  }
  if (await materialIcons.exists()) {
    final bytes = await materialIcons.readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
  }
}

class _Session {
  const _Session(
    this.controller,
    this.gateway,
    this.outingId,
    this.firstItemId,
  );

  final AppController controller;
  final LeaveGateway gateway;
  final String outingId;
  final String firstItemId;
}

class _GatedGateway extends FakeLeaveGateway {
  _GatedGateway({required super.storedJson});

  Completer<void>? writeStarted;
  Completer<void>? _release;
  bool _holdNext = false;

  void holdNextWrite() {
    _holdNext = true;
    writeStarted = Completer<void>();
    _release = Completer<void>();
  }

  void releaseWrite() => _release!.complete();

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    if (_holdNext) {
      _holdNext = false;
      writeStarted!.complete();
      await _release!.future;
    }
    return super.writeState(
      baseJson: baseJson,
      targetJson: targetJson,
      checkIntents: checkIntents,
      lifecycleIntents: lifecycleIntents,
    );
  }
}
