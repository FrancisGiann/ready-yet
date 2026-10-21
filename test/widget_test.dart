import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:before_i_leave/app/app.dart';
import 'package:before_i_leave/app/theme.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';
import 'package:before_i_leave/ui/components.dart';
import 'package:before_i_leave/ui/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRenderFonts);

  testWidgets(
    'practice onboarding is interactive and leaves real lists alone',
    (tester) async {
      final controller = await _controller(onboarded: false);
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('Leave with'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('1 packed'), findsOneWidget);
      await tester.tap(find.text('Water bottle'));
      await tester.pumpAndSettle();
      expect(find.text('2 packed'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Let’s get ready'));
      await tester.pumpAndSettle();

      expect(controller.state.outings, isEmpty);
      expect(controller.state.blueprints.length, 4);
      expect(controller.state.settings.onboarded, isTrue);
      controller.dispose();
    },
  );

  testWidgets('Ready Yet? keeps Before I Leave as its tagline', (tester) async {
    final initial = AppState.initial().copyWith(
      settings: AppSettings(onboarded: false),
    );
    final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
      ..currentAppVersion = const {'versionName': '9.8.7', 'buildNumber': '42'};
    final controller = await _controller(onboarded: false, gateway: gateway);
    await tester.pumpWidget(BeforeILeaveApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Ready Yet?',
    );
    expect(find.text('Ready Yet?'), findsOneWidget);
    expect(find.text('Before I Leave'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final settingsScrollable = find
        .descendant(
          of: find.byKey(const PageStorageKey<String>('settings')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('READY YET?  ·  9.8.7+42'),
      320,
      scrollable: settingsScrollable,
    );
    expect(find.text('READY YET?  ·  9.8.7+42'), findsOneWidget);
    expect(find.text('Before I Leave'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('About stays brand-only for missing or failed metadata', (
    tester,
  ) async {
    Future<void> check({required bool failAppVersion}) async {
      final initial = AppState.initial().copyWith(
        settings: AppSettings(onboarded: false),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..failAppVersion = failAppVersion;
      final controller = await _controller(onboarded: false, gateway: gateway);
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      gateway.writes.clear();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('settings')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('READY YET?'),
        320,
        scrollable: scrollable,
      );
      expect(find.text('READY YET?'), findsOneWidget);
      expect(find.textContaining('READY YET?  · '), findsNothing);
      expect(gateway.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    }

    await check(failAppVersion: false);
    await check(failAppVersion: true);
  });

  testWidgets(
    'home starts an outing, checking updates the session, and history can reopen it',
    (tester) async {
      final controller = await _controller(onboarded: true);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey<String>('screen_capture'),
          child: BeforeILeaveApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      expect(controller.state.outings, hasLength(1));
      expect(find.text('Let’s pack.'), findsOneWidget);
      final outing = controller.state.outings.single;
      final firstItem = outing.items.first;
      await tester.tap(find.text(firstItem.label));
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.items.first.checked, isTrue);

      for (final item in controller.state.outings.single.items.where(
        (item) => !item.checked,
      )) {
        await controller.toggleOutingItem(outing.id, item.id);
      }
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish outing'));
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(find.text('Ready to go.'), findsOneWidget);
      expect(find.text('Back to home'), findsOneWidget);
      expect(find.text('Reopen outing'), findsOneWidget);
      await _saveScreenshot(tester, 'completion_360_light');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'completion_360_large_text');
      expect(tester.takeException(), isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Good to go.'), findsOneWidget);
      await tester.tap(find.text('Reopen outing'));
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isFalse);
      expect(find.text('Let’s pack.'), findsOneWidget);
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.textScaleFactorTestValue = 1;
    },
  );

  testWidgets(
    'ID card and Perfume choices stay accessible and save to the outing snapshot',
    (tester) async {
      final gateway = _GatedGateway(
        storedJson: jsonEncode(
          AppState.initial()
              .copyWith(
                settings: const AppSettings(
                  onboarded: true,
                  reducedMotion: true,
                ),
              )
              .toJson(),
        ),
      );
      final controller = await _controller(onboarded: true, gateway: gateway);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        controller.dispose();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey<String>('screen_capture'),
          child: BeforeILeaveApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      final outingId = controller.state.outings.single.id;
      await tester.tap(find.byTooltip('Add a packing item'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();

      expect(iconChoiceKeys, hasLength(26));
      expect(iconLabel('badge'), 'ID card');
      expect(iconLabel(''), 'Other');
      final semantics = tester.ensureSemantics();
      await tester.ensureVisible(find.byTooltip('ID card'));
      await tester.ensureVisible(find.byTooltip('Perfume'));
      final idCardNode = tester.getSemantics(
        find.bySemanticsLabel('ID card icon'),
      );
      final perfumeNode = tester.getSemantics(
        find.bySemanticsLabel('Perfume icon'),
      );
      expect(
        idCardNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        perfumeNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(find.byTooltip('Perfume'), findsOneWidget);
      await tester.tap(find.byTooltip('ID card'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'ID card');
      await tester.ensureVisible(find.text('Save item'));
      gateway.holdNextWrite();
      await tester.tap(find.text('Save item'));
      await tester.pump();
      await gateway.writeStarted!.future;
      await tester.pump();
      gateway.releaseWrite();
      await controller.waitForSaves();
      await tester.pumpAndSettle();

      final outing = controller.state.outings.singleWhere(
        (value) => value.id == outingId,
      );
      expect(
        outing.items.singleWhere((item) => item.label == 'ID card').iconKey,
        'badge',
      );

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a packing item'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Perfume'));
      await tester.tap(find.byTooltip('Perfume'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byTooltip('Perfume'),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Perfume icon'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      await _saveScreenshot(tester, 'icons_picker_360_large_text_keyboard');

      await tester.enterText(find.byType(TextField).first, 'Perfume');
      await tester.ensureVisible(find.text('Save item'));
      gateway.holdNextWrite();
      await tester.tap(find.text('Save item'));
      await tester.pump();
      await gateway.writeStarted!.future;
      await tester.pump();

      final pendingPerfumeNode = tester.getSemantics(
        find.bySemanticsLabel('Perfume icon'),
      );
      expect(
        pendingPerfumeNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(
        pendingPerfumeNode.getSemanticsData().flagsCollection.isEnabled,
        ui.Tristate.isFalse,
      );
      expect(
        controller.state.outings
            .singleWhere((outing) => outing.id == outingId)
            .items
            .where((item) => item.label == 'Perfume'),
        hasLength(1),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        controller.state.outings
            .singleWhere((outing) => outing.id == outingId)
            .items
            .where((item) => item.label == 'Perfume'),
        hasLength(1),
      );

      gateway.releaseWrite();
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      final perfume = controller.state.outings
          .singleWhere((outing) => outing.id == outingId)
          .items
          .singleWhere((item) => item.label == 'Perfume');
      expect(perfume.iconKey, 'perfume');
      final saved = AppState.fromJson(
        jsonDecode(gateway.storedJson!) as Map<String, Object?>,
      ).outings.singleWhere((outing) => outing.id == outingId);
      expect(
        saved.items.singleWhere((item) => item.label == 'Perfume').iconKey,
        'perfume',
      );
      expect(
        saved.items.singleWhere((item) => item.label == 'ID card').iconKey,
        'badge',
      );

      tester.view.physicalSize = const Size(430, 900);
      await tester.pumpAndSettle();
      final packScrollable = find.descendant(
        of: find.byKey(const PageStorageKey<String>('pack')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Perfume'),
        220,
        scrollable: packScrollable.first,
      );
      await tester.scrollUntilVisible(
        find.text('ID card'),
        220,
        scrollable: packScrollable.first,
      );
      final perfumeRow = find.ancestor(
        of: find.text('Perfume'),
        matching: find.byType(ChecklistRow),
      );
      expect(
        find.descendant(of: perfumeRow, matching: find.byType(ItemGlyph)),
        findsOneWidget,
      );
      final perfumeGlyph = find.descendant(
        of: perfumeRow,
        matching: find.byType(ItemGlyph),
      );
      final perfumePaint = find.descendant(
        of: perfumeGlyph,
        matching: find.byType(CustomPaint),
      );
      expect(tester.getSize(perfumePaint).width, closeTo(44 * .48, .01));
      expect(tester.getSize(perfumePaint).height, closeTo(44 * .48, .01));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'carry_icon_rows_430_large_text');
      final idCardRow = find.ancestor(
        of: find.text('ID card'),
        matching: find.byType(ChecklistRow),
      );
      expect(
        find.descendant(of: idCardRow, matching: find.byType(ItemGlyph)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(360, 800);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a packing item'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Perfume'));
      await tester.tap(find.byTooltip('Perfume'));
      await tester.pumpAndSettle();
      await _saveScreenshot(
        tester,
        'icons_picker_360_dark_large_text_keyboard',
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('editing a legacy keys item keeps its persisted icon key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    final controller = await _controller(onboarded: true);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
    });
    await controller.addBlueprintItem(
      'school',
      label: 'Keys backup',
      iconKey: 'keys',
    );
    await controller.waitForSaves();
    await tester.pumpWidget(BeforeILeaveApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('School').first);
    await tester.pumpAndSettle();
    final itemLabel = find.text('Keys backup');
    await tester.scrollUntilVisible(
      itemLabel,
      220,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(itemLabel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Key'), findsOneWidget);
    expect(find.byTooltip('Keys'), findsNothing);
    final semantics = tester.ensureSemantics();
    final keyNode = tester.getSemantics(find.bySemanticsLabel('Key icon'));
    expect(
      keyNode.getSemanticsData().flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(
      controller.state.blueprints
          .singleWhere((blueprint) => blueprint.id == 'school')
          .items
          .singleWhere((item) => item.label == 'Keys backup')
          .iconKey,
      'keys',
    );
    semantics.dispose();
  });

  testWidgets(
    'completed outing Home returns to Today and reopening retains checkmarks',
    (tester) async {
      final gateway = _GatedGateway(
        storedJson: jsonEncode(
          AppState.initial()
              .copyWith(
                settings: const AppSettings(
                  onboarded: true,
                  reducedMotion: true,
                ),
              )
              .toJson(),
        ),
      );
      final controller = await _controller(onboarded: true, gateway: gateway);
      final outingId = await controller.startOuting('school');
      for (final item in controller.state.outings.single.items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }
      await controller.finishOuting(outingId);
      await controller.waitForSaves();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );

      final cardTitle = find.descendant(
        of: find.byKey(ValueKey<String>('history-$outingId')),
        matching: find.text('School'),
      );
      await tester.tap(cardTitle);
      await tester.pumpAndSettle();
      expect(find.text("You're ready."), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );

      await tester.tap(cardTitle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      final reopenedCardTitle = find.descendant(
        of: find.byKey(ValueKey<String>('history-$outingId')),
        matching: find.text('School'),
      );
      await tester.tap(reopenedCardTitle);
      await tester.pumpAndSettle();
      gateway.holdNextWrite();
      await tester.tap(find.text('Reopen outing'));
      await tester.pump();
      await gateway.writeStarted!.future;
      await tester.pump();
      expect(find.text('Reopening…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("You're ready."), findsOneWidget);
      expect(find.byTooltip('Add a packing item'), findsNothing);
      expect(controller.canonicalState.outings.single.isComplete, isTrue);
      gateway.releaseWrite();
      await controller.waitForSaves();
      await tester.pumpAndSettle();

      final reopened = controller.state.outings.single;
      expect(reopened.id, outingId);
      expect(reopened.isComplete, isFalse);
      expect(reopened.items.every((item) => item.checked), isTrue);
      expect(find.text('Let’s pack.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isFalse);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'failed pack and history reopens keep the canonical completed outing',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      );
      final controller = await _controller(onboarded: true, gateway: gateway);
      final outingId = await controller.startOuting('school');
      for (final item in controller.state.outings.single.items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }
      await controller.finishOuting(outingId);
      await controller.waitForSaves();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey<String>('history-$outingId')),
          matching: find.text('School'),
        ),
      );
      await tester.pumpAndSettle();

      gateway.failWrites = true;
      await tester.tap(find.text('Reopen outing'));
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(
        controller.state.outings.single.items.every((item) => item.checked),
        isTrue,
      );
      expect(find.text("You're ready."), findsOneWidget);
      expect(find.text('Reopen outing'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Good to go.'), findsOneWidget);
      await tester.tap(find.text('Reopen outing'));
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(
        controller.state.outings.single.items.every((item) => item.checked),
        isTrue,
      );
      expect(find.text('Good to go.'), findsOneWidget);
      expect(find.byKey(ValueKey<String>('history-$outingId')), findsOneWidget);

      final restored = AppState.fromJson(
        jsonDecode(gateway.storedJson!) as Map<String, Object?>,
      ).outings.single;
      expect(restored.isComplete, isTrue);
      expect(restored.items.every((item) => item.checked), isTrue);

      gateway.failWrites = false;
      await controller.retrySave();
      await controller.waitForSaves();
      expect(controller.state.outings.single.isComplete, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'pending History reopen cannot open the card or navigate after leaving History',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = _GatedGateway(storedJson: jsonEncode(initial.toJson()));
      final controller = await _controller(onboarded: true, gateway: gateway);
      final outingId = await controller.startOuting('school');
      for (final item in controller.state.outings.single.items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }
      await controller.finishOuting(outingId);
      await controller.waitForSaves();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        controller.dispose();
      });
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      gateway.holdNextWrite();
      await tester.tap(find.text('Reopen outing'));
      await gateway.writeStarted!.future;
      await tester.pump();
      final card = find.byKey(ValueKey<String>('history-$outingId'));
      final cardTap = find
          .descendant(of: card, matching: find.byType(InkWell))
          .first;
      expect(tester.widget<InkWell>(cardTap).onTap, isNull);
      await tester.tap(
        find.descendant(of: card, matching: find.text('School')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsNothing);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      gateway.releaseWrite();
      await controller.waitForSaves();
      await tester.pumpAndSettle();

      expect(controller.state.outings, hasLength(1));
      expect(controller.state.outings.single.isActive, isTrue);
      expect(find.text('Let’s pack.'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets(
    'Today can dismiss one outing, undo it, and start a fresh copy without changing its list',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final controller = await _controller(onboarded: true);
      final schoolId = await controller.startOuting('school');
      final schoolItem = controller.state.outings
          .firstWhere((outing) => outing.id == schoolId)
          .items
          .first;
      await controller.toggleOutingItem(schoolId, schoolItem.id);
      final workId = await controller.startOuting('work');
      final completedId = await controller.startOuting('trip');
      for (final item
          in controller.state.outings
              .firstWhere((outing) => outing.id == completedId)
              .items) {
        await controller.setOutingItemChecked(
          completedId,
          item.id,
          checked: true,
        );
      }
      await controller.finishOuting(completedId);
      await controller.waitForSaves();
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();

      final schoolMenu = find.byTooltip('Outing options for School');
      await tester.ensureVisible(schoolMenu);
      final menuSemantics = tester.ensureSemantics();
      final resumeSemantics = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Resume School')))
          .getSemanticsData();
      expect(resumeSemantics.label, contains('1 of 6 packed'));
      expect(resumeSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester
            .getSemantics(schoolMenu)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      menuSemantics.dispose();
      await tester.tap(schoolMenu);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == schoolId)
            .isDismissed,
        isFalse,
      );

      await tester.tap(schoolMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss outing'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey<String>('resume-$schoolId')), findsNothing);
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == schoolId)
            .isDismissed,
        isTrue,
      );
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == workId)
            .isActive,
        isTrue,
      );
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == completedId)
            .isComplete,
        isTrue,
      );
      expect(
        controller.state.blueprints
            .firstWhere((list) => list.id == 'school')
            .items
            .first
            .label,
        schoolItem.label,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final restored = controller.state.outings.firstWhere(
        (outing) => outing.id == schoolId,
      );
      expect(restored.isActive, isTrue);
      expect(restored.items.first.checked, isTrue);

      await tester.ensureVisible(schoolMenu);
      await tester.tap(schoolMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss outing'));
      await tester.pumpAndSettle();
      final freshSchoolId = await controller.startOuting('school');
      final freshSchool = controller.state.outings.firstWhere(
        (outing) => outing.id == freshSchoolId,
      );
      expect(freshSchoolId, isNot(schoolId));
      expect(freshSchool.items.every((item) => !item.checked), isTrue);
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == workId)
            .isActive,
        isTrue,
      );
      expect(
        controller.state.outings
            .firstWhere((outing) => outing.id == completedId)
            .isComplete,
        isTrue,
      );
      expect(
        controller.state.blueprints
            .firstWhere((list) => list.id == 'school')
            .items
            .first
            .label,
        schoolItem.label,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'dismissed outings remain separate after reload and restore with their checked state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      );
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      final outingId = await controller.startOuting('trip');
      final firstItem = controller.state.outings.single.items.first;
      await controller.toggleOutingItem(outingId, firstItem.id);
      await controller.dismissOuting(outingId);
      await controller.waitForSaves();

      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dismissed outings'));
      expect(find.text('Dismissed outings'), findsOneWidget);
      expect(find.text('Restore outing'), findsOneWidget);
      expect(find.text('Reopen outing'), findsNothing);
      await tester.tap(find.text('Restore outing'));
      await tester.pumpAndSettle();
      final restored = controller.state.outings.single;
      expect(restored.id, outingId);
      expect(restored.isActive, isTrue);
      expect(restored.items.first.checked, isTrue);
      expect(find.text('Let’s pack.'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await controller.waitForSaves();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      final restarted = AppController(gateway: gateway);
      await restarted.initialize();
      expect(restarted.state.outings.single.id, outingId);
      expect(restarted.state.outings.single.isActive, isTrue);
      expect(restarted.state.outings.single.items.first.checked, isTrue);
      expect(restarted.state.outings.single.isComplete, isFalse);
      restarted.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'a second outing is a fresh snapshot and saved progress survives an app restart',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      );
      final firstRun = AppController(gateway: gateway);
      await firstRun.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: firstRun));
      await tester.pumpAndSettle();
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();

      final firstOutingId = firstRun.state.outings.single.id;
      final firstItemId = firstRun.state.outings.single.items.first.id;
      await tester.tap(find.text('Bag'));
      await tester.pumpAndSettle();
      await firstRun.startOuting('school');

      expect(firstRun.state.outings, hasLength(2));
      expect(firstRun.state.outings.first.id, firstOutingId);
      expect(firstRun.state.outings.first.items.first.checked, isTrue);
      final secondOuting = firstRun.state.outings.last;
      expect(secondOuting.id, isNot(firstOutingId));
      expect(secondOuting.items.first.checked, isFalse);
      await firstRun.waitForSaves();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      firstRun.dispose();

      final restarted = AppController(gateway: gateway);
      await restarted.initialize();
      expect(restarted.state.outings, hasLength(2));
      expect(restarted.state.outings.first.items.first.id, firstItemId);
      expect(restarted.state.outings.first.items.first.checked, isTrue);
      expect(restarted.state.outings.last.items.first.checked, isFalse);
      restarted.dispose();
    },
  );

  testWidgets('lists editor adds a reusable item through the UI', (
    tester,
  ) async {
    final controller = await _controller(onboarded: true);
    await tester.pumpWidget(BeforeILeaveApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lists'));
    await tester.pumpAndSettle();
    expect(find.text('Your lists.'), findsOneWidget);
    await tester.ensureVisible(find.text('School'));
    await tester.tap(find.text('School'));
    await tester.pumpAndSettle();
    expect(find.text('REUSABLE CHECKLIST'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add a reusable item'));
    await tester.tap(find.text('Add a reusable item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Library card');
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();
    final school = controller.state.blueprints.firstWhere(
      (blueprint) => blueprint.id == 'school',
    );
    expect(school.items.any((item) => item.label == 'Library card'), isTrue);
    controller.dispose();
  });

  testWidgets(
    'dated-only checklists start only on the matching local day and Today refreshes on resume',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      var now = DateTime(2026, 10, 11, 23, 58);
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final controller = AppController(
        gateway: FakeLeaveGateway(storedJson: jsonEncode(initial.toJson())),
        now: () => now,
      );
      await controller.initialize();
      final todayList = await controller.createBlueprint(name: 'Today only');
      final tomorrowList = await controller.createBlueprint(
        name: 'Tomorrow only',
      );
      final noResumeList = await controller.createBlueprint(
        name: 'Clock changed',
      );
      await controller.addDatedExtra(
        todayList,
        date: '2026-10-11',
        label: 'Library card',
        iconKey: 'badge',
      );
      await controller.addDatedExtra(
        tomorrowList,
        date: '2026-10-12',
        label: 'Train ticket',
        iconKey: 'ticket',
      );
      await controller.addDatedExtra(
        noResumeList,
        date: '2026-10-13',
        label: 'Gallery ticket',
        iconKey: 'ticket',
      );
      await controller.waitForSaves();
      String? openedOutingId;
      var wentToLists = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: createAppTheme(dark: false, accentIndex: 0),
          home: Scaffold(
            body: TodayScreen(
              controller: controller,
              now: () => now,
              openOuting: (id) => openedOutingId = id,
              goToLists: () => wentToLists = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sun, Oct 11'), findsOneWidget);
      expect(find.text('Library card'), findsNothing);
      expect(find.textContaining('+1 today'), findsOneWidget);

      await tester.tap(find.text('Today only'));
      await tester.pumpAndSettle();
      expect(openedOutingId, isNotNull);
      expect(controller.state.outings.single.date, '2026-10-11');
      expect(controller.state.outings.single.items.map((item) => item.label), [
        'Library card',
      ]);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('today')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tomorrow only'));
      await tester.tap(find.text('Tomorrow only'));
      await tester.pumpAndSettle();
      expect(wentToLists, isTrue);
      expect(controller.state.outings, hasLength(1));
      expect(
        find.text('Add an item to this list before you start.'),
        findsOneWidget,
      );

      now = DateTime(2026, 10, 12, 0, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('today')),
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mon, Oct 12'), findsOneWidget);
      expect(find.textContaining('+1 today'), findsOneWidget);
      await tester.drag(
        find.byKey(const PageStorageKey<String>('today')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tomorrow only'));
      await tester.tap(find.text('Tomorrow only'));
      await tester.pumpAndSettle();
      expect(controller.state.outings, hasLength(2));
      expect(controller.state.outings.last.date, '2026-10-12');
      expect(controller.state.outings.last.items.single.label, 'Train ticket');
      expect(openedOutingId, controller.state.outings.last.id);

      // The date changes while Today remains in the foreground: no lifecycle
      // callback fires before the user starts this dated-only checklist.
      now = DateTime(2026, 10, 13, 0, 3);
      await tester.drag(
        find.byKey(const PageStorageKey<String>('today')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Clock changed'));
      await tester.tap(find.text('Clock changed'));
      await tester.pumpAndSettle();
      expect(controller.state.outings, hasLength(3));
      expect(controller.state.outings.last.date, '2026-10-13');
      expect(
        controller.state.outings.last.items.single.label,
        'Gallery ticket',
      );
      expect(openedOutingId, controller.state.outings.last.id);
      await tester.drag(
        find.byKey(const PageStorageKey<String>('today')),
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tue, Oct 13'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'save failure stays visible on Pack and retry writes its latest checked state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..failWrites = true;
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      final item = controller.state.outings.single.items.first;
      await tester.tap(find.text(item.label));
      await tester.pumpAndSettle();
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      expect(controller.saveError, isNotNull);
      expect(find.text('Couldn’t save changes. Tap to retry.'), findsOneWidget);

      gateway.failWrites = false;
      await tester.tap(find.text('Couldn’t save changes. Tap to retry.'));
      await tester.pumpAndSettle();
      await controller.waitForSaves();
      final persisted = AppState.fromJson(
        Map<String, Object?>.from(jsonDecode(gateway.storedJson!) as Map),
      );
      expect(controller.saveError, isNull);
      expect(persisted.outings.single.items.first.checked, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'save failure stays visible in list detail and retry persists the renamed list',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..failWrites = true;
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('List options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename list'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'School revised');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();
      await controller.waitForSaves();
      await tester.pumpAndSettle();
      expect(controller.saveError, isNotNull);
      expect(find.text('Couldn’t save changes. Tap to retry.'), findsOneWidget);

      gateway.failWrites = false;
      await tester.tap(find.text('Couldn’t save changes. Tap to retry.'));
      await tester.pumpAndSettle();
      await controller.waitForSaves();
      final persisted = AppState.fromJson(
        Map<String, Object?>.from(jsonDecode(gateway.storedJson!) as Map),
      );
      expect(controller.saveError, isNull);
      expect(
        persisted.blueprints
            .firstWhere((blueprint) => blueprint.id == 'school')
            .name,
        'School revised',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'revoked reminder permission is reconciled at cold start and switches have one labeled action',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true, reminderEnabled: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..currentReminderStatus = const {
          'enabled': false,
          'permissionGranted': false,
          'reason': 'notifications_disabled',
        };
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await controller.waitForSaves();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(controller.state.settings.reminderEnabled, isFalse);
      final settingsScrollable = find.descendant(
        of: find.byKey(const PageStorageKey<String>('settings')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('A reminder, if you want one'),
        180,
        scrollable: settingsScrollable,
      );
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);

      final semantics = tester.ensureSemantics();
      for (final label in [
        'Haptic feedback',
        'Reduce motion',
        'A reminder, if you want one',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: settingsScrollable,
        );
        final finder = find.bySemanticsLabel(RegExp(label));
        expect(finder, findsOneWidget, reason: label);
        expect(
          tester
              .getSemantics(finder)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
          reason: label,
        );
      }
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('Haptic feedback')))
            .getSemanticsData()
            .label,
        contains('A light touch when you check an item'),
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'canceling an outing item sheet and repeating a check preserves the expected state',
    (tester) async {
      final controller = await _controller(onboarded: true);
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      final outing = controller.state.outings.single;

      await tester.tap(find.byTooltip('Add a packing item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A test item');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        controller.state.outings.single.items,
        hasLength(outing.items.length),
      );

      final item = outing.items.first;
      await tester.tap(find.text(item.label));
      await tester.tap(find.text(item.label));
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.items.first.checked, isFalse);
      controller.dispose();
    },
  );

  testWidgets(
    'checklist item exposes one labeled checked action to assistive technology',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await _controller(onboarded: true);
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();

      final label = controller.state.outings.single.items.first.label;
      final finder = find.bySemanticsLabel(label);
      final node = tester.getSemantics(finder);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        node.getSemanticsData().flagsCollection.isChecked,
        ui.CheckedState.isFalse,
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(controller.state.outings.single.items.first.checked, isTrue);

      semantics.dispose();
      controller.dispose();
    },
  );

  testWidgets('denied reminder consent leaves Today and lists available', (
    tester,
  ) async {
    final initial = AppState.initial().copyWith(
      settings: const AppSettings(onboarded: true),
    );
    final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
      ..notificationsGranted = false;
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    await tester.pumpWidget(BeforeILeaveApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('A reminder, if you want one'),
      260,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey<String>('settings')),
        matching: find.byType(Scrollable),
      ),
    );
    final switches = find.byType(Switch);
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(controller.state.settings.reminderEnabled, isFalse);
    expect(find.textContaining('Notification permission'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'cold and warm pack shortcuts resume the latest unfinished outing',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final coldGateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      )..pendingLaunchAction = 'pack_today';
      final coldController = AppController(gateway: coldGateway);
      await coldController.initialize();
      await coldController.startOuting('school');
      await tester.pumpWidget(BeforeILeaveApp(controller: coldController));
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      coldController.dispose();

      final warmGateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      );
      final warmController = AppController(gateway: warmGateway);
      await warmController.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: warmController));
      await tester.pumpAndSettle();
      final outingId = await warmController.startOuting('work');
      await tester.pumpAndSettle();
      warmGateway.emitLaunchAction('pack_today');
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(warmController.state.outings.single.id, outingId);
      warmController.dispose();
    },
  );

  testWidgets(
    'widget launch deep links open one outing and duplicate request IDs do not push again',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(
        storedJson: jsonEncode(initial.toJson()),
      );
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();

      final listAction = jsonEncode({
        'type': 'widget_list',
        'blueprintId': 'school',
        'requestId': 'widget-list-1',
      });
      gateway.emitLaunchAction(listAction);
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsOneWidget);
      expect(
        controller.state.outings.where((item) => item.isActive),
        hasLength(1),
      );
      final outingId = controller.state.outings.single.id;

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      gateway.emitLaunchAction(listAction);
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsNothing);
      expect(controller.state.outings, hasLength(1));

      gateway.emitLaunchAction(
        jsonEncode({
          'type': 'widget_outing',
          'blueprintId': 'school',
          'outingId': outingId,
          'requestId': 'widget-outing-1',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsOneWidget);
      expect(controller.state.outings.single.id, outingId);

      final workOutingId = await controller.startOuting('work');
      await controller.waitForSaves();
      gateway.emitLaunchAction(
        jsonEncode({
          'type': 'widget_outing',
          'blueprintId': 'work',
          'outingId': workOutingId,
          'requestId': 'widget-outing-work',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Book'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Let’s pack.'), findsNothing);
      expect(controller.state.outings, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets(
    'widget_today fallback returns to Today without retargeting an active outing',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..pendingLaunchAction = 'widget_today';
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      final outingId = await controller.startOuting('work');
      await controller.waitForSaves();
      final writeCount = gateway.writes.length;

      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Before you\nhead out.'), findsOneWidget);
      expect(find.text('Let’s pack.'), findsNothing);
      expect(controller.state.outings, hasLength(1));
      expect(controller.state.outings.single.id, outingId);
      expect(controller.state.outings.single.isActive, isTrue);
      expect(gateway.writes, hasLength(writeCount));

      gateway.emitLaunchAction(
        jsonEncode({'type': 'widget_today', 'requestId': 'widget-today-1'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Before you\nhead out.'), findsOneWidget);
      expect(find.text('Let’s pack.'), findsNothing);
      expect(controller.state.outings, hasLength(1));
      expect(controller.state.outings.single.id, outingId);
      expect(controller.state.outings.single.isActive, isTrue);
      expect(gateway.writes, hasLength(writeCount));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets('home resumes and reconciles a native checklist check', (
    tester,
  ) async {
    final initial = AppState.initial().copyWith(
      settings: const AppSettings(onboarded: true),
    );
    final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()));
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    final outingId = await controller.startOuting('school');
    final item = controller.state.outings.single.items.first;
    await tester.pumpWidget(BeforeILeaveApp(controller: controller));
    await tester.pumpAndSettle();

    gateway.setExternalStateChangedHandler(null);
    await gateway.setWidgetCheck(
      outingId: outingId,
      itemId: item.id,
      checked: true,
    );
    expect(controller.state.outings.single.items.first.checked, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.state.outings.single.items.first.checked, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets(
    'pack shortcut falls back to Today when its only outing was dismissed',
    (tester) async {
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..pendingLaunchAction = 'pack_today';
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      final outingId = await controller.startOuting('school');
      await controller.dismissOuting(outingId);
      await controller.waitForSaves();

      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Before you\nhead out.'), findsOneWidget);
      expect(find.text('Let’s pack.'), findsNothing);
      expect(controller.state.outings.single.isDismissed, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  testWidgets(
    'unreadable saved data requires explicit confirmation before starting fresh',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      final gateway = FakeLeaveGateway(storedJson: '{not valid');
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey<String>('screen_capture'),
          child: BeforeILeaveApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'recovery_360_light');
      expect(find.text('Your lists couldn’t be opened.'), findsOneWidget);
      await tester.tap(find.text('Start with fresh lists'));
      await tester.pumpAndSettle();
      expect(find.text('Start with fresh lists?'), findsOneWidget);
      await tester.tap(find.text('Start fresh'));
      await tester.pumpAndSettle();
      expect(controller.loadError, isNull);
      expect(find.textContaining('Leave with'), findsOneWidget);
      expect(gateway.storedJson, isNot(contains('not valid')));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'real Flutter renders cover both themes, both target sizes, scaled text, and a packing session',
    (tester) async {
      const cases = <(String, Size, Brightness, double)>[
        ('today_360_light', Size(360, 800), Brightness.light, 1),
        ('today_430_light', Size(430, 932), Brightness.light, 1),
        ('today_360_dark', Size(360, 800), Brightness.dark, 1),
        ('today_430_dark', Size(430, 932), Brightness.dark, 1),
        ('today_360_large_text', Size(360, 800), Brightness.light, 2),
      ];
      for (final entry in cases) {
        final controller = await _controller(onboarded: true);
        await _capture(
          tester,
          controller,
          name: entry.$1,
          size: entry.$2,
          brightness: entry.$3,
          textScale: entry.$4,
        );
        expect(tester.takeException(), isNull, reason: entry.$1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        controller.dispose();
      }

      final controller = await _controller(onboarded: true);
      await _capture(
        tester,
        controller,
        name: 'pack_360_light',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'pack_360_light');
      expect(tester.takeException(), isNull, reason: 'pack_360_light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    },
  );

  testWidgets(
    'screen render matrix covers onboarding, pack motion, lists, settings, history, and empty states',
    (tester) async {
      final intro = await _controller(onboarded: false);
      await _capture(
        tester,
        intro,
        name: 'onboarding_intro_360_light',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _capture(
        tester,
        intro,
        name: 'onboarding_brand_360_large_text',
        size: const Size(360, 800),
        brightness: Brightness.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: 'scaled onboarding brand');
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'onboarding_practice_360_light');
      expect(tester.takeException(), isNull, reason: 'onboarding practice');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      intro.dispose();

      final pack = await _controller(onboarded: true);
      await _capture(
        tester,
        pack,
        name: 'pack_home_360_light',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'pack_360_light');
      await tester.tap(find.text('Bag'));
      await tester.pump(const Duration(milliseconds: 45));
      await _saveScreenshot(tester, 'motion_pack_045');
      await tester.pump(const Duration(milliseconds: 110));
      await _saveScreenshot(tester, 'motion_pack_155');
      await tester.pump(const Duration(milliseconds: 180));
      await _saveScreenshot(tester, 'motion_pack_335');
      tester.view.physicalSize = const Size(430, 932);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'pack_430_dark');
      tester.view.physicalSize = const Size(360, 800);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'pack_360_large_text');
      expect(tester.takeException(), isNull, reason: 'large text pack');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      pack.dispose();

      final lists = await _controller(onboarded: true);
      await _capture(
        tester,
        lists,
        name: 'home_for_lists_360_light',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.tap(find.text('Lists'));
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'lists_360_light');
      await tester.tap(find.text('School'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(430, 932);
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'list_editor_430_light');
      await tester.scrollUntilVisible(
        find.text('Add a reusable item'),
        260,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Add a reusable item'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'item_editor_keyboard_inset_430_light');
      expect(
        tester.takeException(),
        isNull,
        reason: 'item editor keyboard inset',
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      lists.dispose();

      final history = await _controller(onboarded: true);
      final outingId = await history.startOuting('trip');
      final firstHistoryItem = history.state.outings.single.items.first;
      await history.updateOutingItem(
        outingId,
        firstHistoryItem.id,
        label: 'Perfume',
        iconKey: 'perfume',
      );
      for (final item in history.state.outings.single.items) {
        await history.setOutingItemChecked(outingId, item.id, checked: true);
      }
      await history.finishOuting(outingId);
      await _capture(
        tester,
        history,
        name: 'history_home_430_light',
        size: const Size(430, 932),
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      final historyCard = find.byKey(ValueKey<String>('history-$outingId'));
      final historyPerfume = find.descendant(
        of: historyCard,
        matching: find.byWidgetPredicate(
          (widget) => widget is ItemGlyph && widget.iconKey == 'perfume',
        ),
      );
      expect(historyPerfume, findsOneWidget);
      final historyPerfumePaint = find.descendant(
        of: historyPerfume,
        matching: find.byType(CustomPaint),
      );
      expect(tester.getSize(historyPerfumePaint).width, closeTo(14, .01));
      expect(tester.getSize(historyPerfumePaint).height, closeTo(14, .01));
      await _saveScreenshot(tester, 'history_completed_430_light');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'history_completed_430_dark');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'settings_430_dark');
      expect(tester.takeException(), isNull, reason: 'history and settings');
      tester.view.physicalSize = const Size(360, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      final settingsScrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('settings')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('READY YET?'),
        220,
        scrollable: settingsScrollable,
      );
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'settings_brand_footer_360_large_text');
      expect(
        tester.takeException(),
        isNull,
        reason: 'scaled Settings brand footer',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      history.dispose();

      final empty = await _controller(onboarded: true);
      for (final blueprint in [...empty.state.blueprints]) {
        await empty.deleteBlueprint(blueprint.id);
      }
      await _capture(
        tester,
        empty,
        name: 'today_empty_430_light',
        size: const Size(430, 932),
        brightness: Brightness.light,
        textScale: 1,
      );
      expect(tester.takeException(), isNull, reason: 'empty home');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      empty.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );

  testWidgets(
    'dismissal and restore screens render in light, dark, and scaled text',
    (tester) async {
      Future<AppController> activeController() async {
        final controller = await _controller(onboarded: true);
        final outingId = await controller.startOuting('school');
        final firstItem = controller.state.outings.single.items.first;
        await controller.toggleOutingItem(outingId, firstItem.id);
        await controller.waitForSaves();
        return controller;
      }

      final light = await activeController();
      await _capture(
        tester,
        light,
        name: 'dismiss_today_360_light',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 1,
      );
      final options = find.byTooltip('Outing options for School');
      await tester.tap(options);
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'dismiss_menu_360_light');
      expect(tester.takeException(), isNull, reason: 'dismiss menu light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      light.dispose();

      final dark = await activeController();
      await _capture(
        tester,
        dark,
        name: 'dismiss_today_430_dark',
        size: const Size(430, 932),
        brightness: Brightness.dark,
        textScale: 1,
      );
      expect(tester.takeException(), isNull, reason: 'dismiss home dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      dark.dispose();

      final large = await activeController();
      await _capture(
        tester,
        large,
        name: 'dismiss_today_360_large_text',
        size: const Size(360, 800),
        brightness: Brightness.light,
        textScale: 2,
      );
      final largeResumeCard = find.byKey(
        ValueKey<String>('resume-${large.state.outings.single.id}'),
      );
      await tester.scrollUntilVisible(
        largeResumeCard,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey<String>('today')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(largeResumeCard);
      await tester.pumpAndSettle();
      await _saveScreenshot(tester, 'dismiss_today_360_large_text');
      expect(tester.takeException(), isNull, reason: 'dismiss home large text');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      large.dispose();

      Future<AppController> dismissedController() async {
        final controller = await _controller(onboarded: true);
        final outingId = await controller.startOuting('trip');
        final firstItem = controller.state.outings.single.items.first;
        await controller.toggleOutingItem(outingId, firstItem.id);
        await controller.dismissOuting(outingId);
        await controller.waitForSaves();
        return controller;
      }

      for (final entry in const <(String, Size, Brightness, double)>[
        ('dismiss_history_430_light', Size(430, 932), Brightness.light, 1),
        ('dismiss_history_360_dark', Size(360, 800), Brightness.dark, 1),
        ('dismiss_history_360_large_text', Size(360, 800), Brightness.light, 2),
      ]) {
        final history = await dismissedController();
        await _capture(
          tester,
          history,
          name: entry.$1,
          size: entry.$2,
          brightness: entry.$3,
          textScale: entry.$4,
        );
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Restore outing'),
          220,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey<String>('history')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        if (entry.$4 > 1) {
          await tester.drag(
            find.byKey(const PageStorageKey<String>('history')),
            const Offset(0, -260),
          );
        }
        await tester.pumpAndSettle();
        await _saveScreenshot(tester, entry.$1);
        expect(tester.takeException(), isNull, reason: entry.$1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        history.dispose();
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );

  testWidgets(
    'launcher widget guide previews are labeled, noninteractive, and scale cleanly',
    (tester) async {
      for (final entry in const <(String, Size, Brightness, double)>[
        ('widget_guide_430_dark', Size(430, 932), Brightness.dark, 1),
        ('widget_guide_360_large_text', Size(360, 800), Brightness.light, 2),
      ]) {
        final controller = await _controller(onboarded: true);
        final outingId = await controller.startOuting('school');
        final item = controller.state.outings.single.items.first;
        await controller.toggleOutingItem(outingId, item.id);
        await controller.waitForSaves();
        await _capture(
          tester,
          controller,
          name: entry.$1,
          size: entry.$2,
          brightness: entry.$3,
          textScale: entry.$4,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.$1}: initial home',
        );
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.$1}: settings top',
        );
        final settingsScrollable = find
            .descendant(
              of: find.byKey(const PageStorageKey<String>('settings')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Home-screen widgets'),
          220,
          scrollable: settingsScrollable,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.$1}: widget section',
        );
        final checklistHeading = find.text('CHECKLIST WIDGET');
        await tester.scrollUntilVisible(
          checklistHeading,
          180,
          scrollable: settingsScrollable,
        );
        await tester.ensureVisible(checklistHeading);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(checklistHeading).overlaps(Offset.zero & entry.$2),
          isTrue,
          reason: '${entry.$1}: checklist preview is visible before capture',
        );
        expect(tester.takeException(), isNull, reason: '${entry.$1}: preview');
        final semantics = tester.ensureSemantics();
        for (final label in [
          'Flutter preview of the checklist widget, not interactive',
          'Flutter preview of the quick lists widget, not interactive',
        ]) {
          final preview = tester.getSemantics(find.bySemanticsLabel(label));
          expect(
            preview.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
            reason: label,
          );
        }
        semantics.dispose();
        expect(find.textContaining('Add a Ready Yet? widget'), findsOneWidget);
        await _saveScreenshot(tester, entry.$1);
        expect(tester.takeException(), isNull, reason: entry.$1);
        if (entry.$4 > 1) {
          final quickListsHeading = find.text('QUICK LISTS WIDGET');
          await tester.scrollUntilVisible(
            quickListsHeading,
            180,
            scrollable: settingsScrollable,
          );
          await tester.ensureVisible(quickListsHeading);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(quickListsHeading).overlaps(Offset.zero & entry.$2),
            isTrue,
          );
          await _saveScreenshot(
            tester,
            'widget_guide_quick_lists_360_large_text',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'widget_guide_quick_lists_360_large_text',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        controller.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );

  testWidgets(
    'Android widget guide uses the native preview snapshot and pin flow',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final initial = AppState.initial().copyWith(
        settings: const AppSettings(onboarded: true),
      );
      final gateway = FakeLeaveGateway(storedJson: jsonEncode(initial.toJson()))
        ..currentWidgetSnapshot = {
          'pinSupported': true,
          'checklist': {
            'title': 'School',
            'subtitle': '1 of 6 packed',
            'checked': 1,
            'total': 6,
            'primaryLabel': 'Open full checklist',
            'items': [
              {'id': 'book', 'label': 'Notebook', 'checked': true},
              {'id': 'water', 'label': 'Water bottle', 'checked': false},
              {'id': 'keys', 'label': 'Keys', 'checked': false},
              {'id': 'lunch', 'label': 'Lunchbox', 'checked': false},
              {'id': 'badge', 'label': 'ID card', 'checked': false},
            ],
          },
          'quickLists': {
            'title': 'Your lists',
            'lists': [
              {
                'id': 'school',
                'title': 'School',
                'subtitle': '1 of 6 packed',
                'checked': 1,
                'total': 6,
                'hasActive': true,
              },
              {
                'id': 'work',
                'title': 'Work',
                'subtitle': '5 items ready',
                'checked': 0,
                'total': 5,
                'hasActive': false,
              },
              {
                'id': 'gym',
                'title': 'Gym',
                'subtitle': '4 items ready',
                'checked': 0,
                'total': 4,
                'hasActive': false,
              },
              {
                'id': 'trip',
                'title': 'Trip',
                'subtitle': '6 items ready',
                'checked': 0,
                'total': 6,
                'hasActive': false,
              },
            ],
          },
        };
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      final outingId = await controller.startOuting('school');
      final firstItem = controller.state.outings.single.items.first;
      await controller.toggleOutingItem(outingId, firstItem.id);

      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey<String>('screen_capture'),
          child: BeforeILeaveApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('CHECKLIST WIDGET'),
        220,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey<String>('settings')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('CHECKLIST WIDGET'));
      await tester.pumpAndSettle();
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('1 of 6 packed'), findsWidgets);
      expect(find.text('1 of 6 packed · Oct 12'), findsNothing);
      expect(find.text('Open full checklist · +3 more'), findsOneWidget);
      expect(find.text('1/6'), findsOneWidget);
      expect(find.text('READY'), findsWidgets);
      expect(find.text('Manage quick lists'), findsOneWidget);
      expect(find.text('Before I Leave'), findsWidgets);
      expect(find.text('Add checklist widget'), findsOneWidget);
      expect(find.text('Add quick lists widget'), findsOneWidget);
      await _saveScreenshot(tester, 'widget_guide_pin_supported_430_light');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Add checklist widget'));
      await tester.pumpAndSettle();
      expect(
        find.text('Android opened a pin request. Follow the prompt to add it.'),
        findsOneWidget,
      );
      expect(gateway.pinWidgetRequests, ['checklist']);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    },
  );
}

Future<AppController> _controller({
  required bool onboarded,
  FakeLeaveGateway? gateway,
}) async {
  final initial = AppState.initial().copyWith(
    settings: AppSettings(onboarded: onboarded),
  );
  final controller = AppController(
    gateway:
        gateway ?? FakeLeaveGateway(storedJson: jsonEncode(initial.toJson())),
  );
  await controller.initialize();
  return controller;
}

Future<void> _capture(
  WidgetTester tester,
  AppController controller, {
  required String name,
  required Size size,
  required Brightness brightness,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey<String>('screen_capture'),
      child: BeforeILeaveApp(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  await _saveScreenshot(tester, name);
}

Future<void> _saveScreenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('screen_capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode render $name');
      final directory =
          Platform.environment['READY_YET_QA_CAPTURE_DIR'] ?? 'qa/screenshots';
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
