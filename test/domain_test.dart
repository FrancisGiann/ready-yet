import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';

void main() {
  testWidgets('MethodChannel writes carry epoch-bound transaction arguments', (
    tester,
  ) async {
    const channel = MethodChannel(MethodChannelLeaveGateway.channelName);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'readState') return null;
      if (call.method != 'writeState') {
        throw StateError('Unexpected native call ${call.method}');
      }
      final arguments = Map<String, Object?>.from(call.arguments as Map);
      final target = Map<String, Object?>.from(
        jsonDecode(arguments['targetJson']! as String) as Map,
      );
      return jsonEncode({
        ...target,
        '_storageEpoch': 'channel-test-epoch',
        '_nativeRevision': calls
            .where((value) => value.method == 'writeState')
            .length,
      });
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    var nextId = 0;
    final controller = AppController(
      gateway: MethodChannelLeaveGateway(channel: channel),
      idFactory: () => 'channel-id-${nextId++}',
      now: () => DateTime(2026, 10, 11, 9),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.startOuting('school');
    await controller.updateSettings(
      controller.state.settings.copyWith(appearance: 'dark'),
    );

    final writeCalls = calls
        .where((call) => call.method == 'writeState')
        .toList();
    expect(writeCalls, hasLength(2));
    final firstArgs = Map<String, Object?>.from(
      writeCalls.first.arguments as Map,
    );
    final secondArgs = Map<String, Object?>.from(
      writeCalls.last.arguments as Map,
    );
    expect(
      Map<String, Object?>.from(
        jsonDecode(firstArgs['baseJson']! as String) as Map,
      )['_storageEpoch'],
      'legacy-v1',
    );
    expect(
      Map<String, Object?>.from(
        jsonDecode(secondArgs['baseJson']! as String) as Map,
      )['_storageEpoch'],
      'channel-test-epoch',
    );
    expect(
      firstArgs.keys,
      containsAll([
        'baseJson',
        'targetJson',
        'checkIntents',
        'lifecycleIntents',
      ]),
    );
    expect(secondArgs['checkIntents'], isEmpty);
    expect(secondArgs['lifecycleIntents'], isEmpty);
    expect(controller.saveError, isNull);
  });

  group('AppController', () {
    late FakeLeaveGateway gateway;
    late AppController controller;
    var nextId = 0;

    AppController createController(LeaveGateway storage) => AppController(
      gateway: storage,
      idFactory: () => 'generated-${nextId++}',
      now: () => DateTime(2026, 10, 11, 9, 30),
    );

    setUp(() async {
      nextId = 0;
      gateway = FakeLeaveGateway();
      controller = createController(gateway);
      await controller.initialize();
    });

    tearDown(() => controller.dispose());

    test('rapid repeated toggles serialize the latest state', () async {
      final outingId = await controller.startOuting('school');
      final itemId = controller.state.outings.single.items.first.id;

      final first = controller.toggleOutingItem(outingId, itemId);
      final second = controller.toggleOutingItem(outingId, itemId);
      final third = controller.toggleOutingItem(outingId, itemId);
      await Future.wait([first, second, third]);

      expect(controller.state.outings.single.items.first.checked, isTrue);
      expect(gateway.writes, hasLength(4));
      final persisted = AppState.fromJson(
        jsonDecode(gateway.storedJson!) as Map<String, Object?>,
      );
      expect(persisted.outings.single.items.first.checked, isTrue);
    });

    test('round-trips blueprints, outings, extras and settings', () async {
      final blueprintId = await controller.createBlueprint(
        name: 'Weekend',
        iconKey: 'bag',
        items: const [
          ChecklistItem(id: 'tent', label: 'Tent', iconKey: 'other'),
        ],
      );
      await controller.addDatedExtra(
        blueprintId,
        label: 'Train pass',
        date: '2026-10-12',
        iconKey: 'ticket',
      );
      final outingId = await controller.startOuting(
        blueprintId,
        date: '2026-10-12',
      );
      await controller.updateSettings(
        controller.state.settings.copyWith(
          appearance: 'dark',
          accent: 'sky',
          haptics: false,
          reducedMotion: true,
          onboarded: true,
          reminderEnabled: true,
          reminderHour: 7,
          reminderMinute: 15,
        ),
      );

      final restored = createController(
        FakeLeaveGateway(storedJson: gateway.storedJson),
      );
      addTearDown(restored.dispose);
      await restored.initialize();

      expect(restored.state.blueprints.last.name, 'Weekend');
      expect(restored.state.extras.single.date, '2026-10-12');
      expect(restored.state.outings.single.id, outingId);
      expect(restored.state.outings.single.items.map((item) => item.label), [
        'Tent',
        'Train pass',
      ]);
      expect(restored.state.settings.appearance, 'dark');
      expect(restored.state.settings.accent, 'sky');
      expect(restored.state.settings.haptics, isFalse);
      expect(restored.state.settings.reducedMotion, isTrue);
      expect(restored.state.settings.onboarded, isTrue);
      expect(restored.state.settings.reminderEnabled, isTrue);
      expect(restored.state.settings.reminderHour, 7);
      expect(restored.state.settings.reminderMinute, 15);
    });

    test('corrupt state falls back and can be saved again', () async {
      final brokenStorage = FakeLeaveGateway(storedJson: '{broken json');
      final recovered = createController(brokenStorage);
      addTearDown(recovered.dispose);

      await recovered.initialize();
      expect(recovered.isReady, isTrue);
      expect(recovered.loadError, isNotNull);
      expect(recovered.canEdit, isFalse);
      expect(
        () => recovered.retrySave(),
        throwsStateError,
        reason: 'A retry-save must not overwrite unreadable stored data',
      );
      expect(brokenStorage.storedJson, '{broken json');
      expect(recovered.state.blueprints.map((item) => item.id), [
        'school',
        'work',
        'gym',
        'trip',
      ]);

      await recovered.retryLoad();
      expect(recovered.loadError, isNotNull);
      brokenStorage.failWrites = true;
      final failedReset = recovered.resetCorruptState();
      expect(recovered.loadError, isNotNull);
      expect(recovered.canEdit, isFalse);
      expect(brokenStorage.storedJson, '{broken json');
      await expectLater(failedReset, throwsStateError);
      expect(recovered.loadError, isNotNull);
      expect(recovered.canEdit, isFalse);

      brokenStorage.failWrites = false;
      await recovered.resetCorruptState();
      expect(recovered.loadError, isNull);
      expect(recovered.saveError, isNull);
      expect(recovered.canEdit, isTrue);
      expect(brokenStorage.damagedJson, '{broken json');
      expect(
        AppState.fromJson(
          jsonDecode(brokenStorage.storedJson!) as Map<String, Object?>,
        ).blueprints,
        hasLength(4),
      );
      await recovered.updateSettings(
        recovered.state.settings.copyWith(appearance: 'dark'),
      );
      expect(recovered.saveError, isNull);
      expect(
        AppState.fromJson(
          jsonDecode(brokenStorage.storedJson!) as Map<String, Object?>,
        ).settings.appearance,
        'dark',
        reason: 'A post-reset write must use the newly committed native epoch',
      );
    });

    test(
      'first write metadata is reused by the next native transaction',
      () async {
        final freshStorage = FakeLeaveGateway();
        final fresh = createController(freshStorage);
        addTearDown(fresh.dispose);
        await fresh.initialize();

        await fresh.startOuting('school');
        final firstEpoch = fresh.storageEpoch;
        expect(firstEpoch, isNot('legacy-v1'));

        await fresh.updateSettings(
          fresh.state.settings.copyWith(appearance: 'dark'),
        );

        expect(freshStorage.writeTransactions, hasLength(2));
        final secondBase = jsonDecode(
          freshStorage.writeTransactions.last['baseJson']! as String,
        ) as Map<String, Object?>;
        expect(secondBase['_storageEpoch'], firstEpoch);
        expect(fresh.loadError, isNull);
        expect(fresh.saveError, isNull);
        expect(fresh.state.settings.appearance, 'dark');
      },
    );

    test(
      'write failures remain visible and retry writes the latest state',
      () async {
        gateway.failWrites = true;
        await controller.updateSettings(
          controller.state.settings.copyWith(appearance: 'dark'),
        );
        expect(controller.saveError, isNotNull);
        expect(controller.state.settings.appearance, 'dark');

        gateway.failWrites = false;
        await controller.retrySave();
        expect(controller.saveError, isNull);
        expect(
          AppState.fromJson(
            jsonDecode(gateway.storedJson!) as Map<String, Object?>,
          ).settings.appearance,
          'dark',
        );
      },
    );

    test('blueprint edits leave existing sessions intact', () async {
      final firstOutingId = await controller.startOuting('school');
      final firstSnapshot = controller.state.outings.single;
      await controller.updateBlueprint('school', name: 'Campus');
      await controller.updateBlueprintItem(
        'school',
        'school-bag',
        label: 'Backpack',
      );
      final secondOutingId = await controller.startOuting('school');

      expect(controller.state.outings, hasLength(2));
      final first = controller.state.outings.firstWhere(
        (outing) => outing.id == firstOutingId,
      );
      final second = controller.state.outings.firstWhere(
        (outing) => outing.id == secondOutingId,
      );
      expect(first.blueprintName, firstSnapshot.blueprintName);
      expect(first.items.first.label, 'Bag');
      expect(second.blueprintName, 'Campus');
      expect(second.items.first.label, 'Backpack');
      expect(first.items.every((item) => !item.checked), isTrue);
      expect(second.items.every((item) => !item.checked), isTrue);
    });

    test(
      'template and outing reorderings persist independently across reload',
      () async {
        final outingId = await controller.startOuting('school');

        await controller.reorderBlueprintItems('school', 0, 2);
        await controller.reorderOutingItems(outingId, 1, 3);

        expect(
          controller.state.blueprints
              .firstWhere((blueprint) => blueprint.id == 'school')
              .items
              .take(3)
              .map((item) => item.label),
          ['Book', 'Bag', 'Notebook'],
        );
        expect(
          controller.state.outings.single.items
              .take(3)
              .map((item) => item.label),
          ['Bag', 'Notebook', 'Book'],
        );

        final restored = createController(
          FakeLeaveGateway(storedJson: gateway.storedJson),
        );
        addTearDown(restored.dispose);
        await restored.initialize();

        expect(
          restored.state.blueprints
              .firstWhere((blueprint) => blueprint.id == 'school')
              .items
              .take(3)
              .map((item) => item.label),
          ['Book', 'Bag', 'Notebook'],
        );
        expect(
          restored.state.outings.single.items.take(3).map((item) => item.label),
          ['Bag', 'Notebook', 'Book'],
        );
      },
    );

    test(
      'only matching blueprint and local date extras enter a session',
      () async {
        await controller.addDatedExtra(
          'school',
          label: 'Field trip form',
          date: '2026-10-11',
        );
        await controller.addDatedExtra(
          'school',
          label: 'Tomorrow note',
          date: '2026-10-12',
        );
        await controller.addDatedExtra(
          'work',
          label: 'Work badge backup',
          date: '2026-10-11',
        );

        final todayId = await controller.startOuting(
          'school',
          date: '2026-10-11',
        );
        final tomorrowId = await controller.startOuting(
          'school',
          date: '2026-10-12',
        );
        final today = controller.state.outings.firstWhere(
          (outing) => outing.id == todayId,
        );
        final tomorrow = controller.state.outings.firstWhere(
          (outing) => outing.id == tomorrowId,
        );

        expect(
          today.items.map((item) => item.label),
          contains('Field trip form'),
        );
        expect(
          today.items.map((item) => item.label),
          isNot(contains('Tomorrow note')),
        );
        expect(
          today.items.map((item) => item.label),
          isNot(contains('Work badge backup')),
        );
        expect(
          tomorrow.items.map((item) => item.label),
          contains('Tomorrow note'),
        );
        expect(controller.state.extras, hasLength(3));
      },
    );

    test('finish requires every item; undo preserves checked items', () async {
      final outingId = await controller.startOuting('school');
      final items = controller.state.outings.single.items;
      expect(() => controller.finishOuting(outingId), throwsStateError);

      for (final item in items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }
      await controller.finishOuting(outingId);
      expect(controller.state.outings.single.isComplete, isTrue);
      expect(controller.state.outings.single.canFinish, isTrue);

      await controller.undoFinish(outingId);
      expect(controller.state.outings.single.isComplete, isFalse);
      expect(
        controller.state.outings.single.items.every((item) => item.checked),
        isTrue,
      );
    });

    test('failed finish rolls back to an editable unfinished outing', () async {
      final outingId = await controller.startOuting('school');
      final outing = controller.state.outings.single;
      for (final item in outing.items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }

      gateway.failWrites = true;
      await expectLater(controller.finishOuting(outingId), throwsStateError);
      expect(controller.state.outings.single.isComplete, isFalse);
      expect(controller.saveError, isNotNull);

      gateway.failWrites = false;
      await controller.retrySave();
      await controller.waitForSaves();
      expect(controller.state.outings.single.isComplete, isFalse);
      expect(controller.saveError, isNull);
      expect(
        AppState.fromJson(
          jsonDecode(gateway.storedJson!) as Map<String, Object?>,
        ).outings.single.isComplete,
        isFalse,
      );
    });

    test(
      'failed finish is retired before queued settings and rollback failure',
      () async {
        final outingId = await controller.startOuting('school');
        for (final item in controller.state.outings.single.items) {
          await controller.setOutingItemChecked(
            outingId,
            item.id,
            checked: true,
          );
        }
        final storage = _FailingFinishRollbackGateway(
          storedJson: gateway.storedJson,
        );
        final slow = createController(storage);
        addTearDown(slow.dispose);
        await slow.initialize();

        final finish = slow.finishOuting(outingId);
        await storage.firstWriteStarted.future;
        final settings = slow.updateSettings(
          slow.state.settings.copyWith(appearance: 'dark'),
        );
        storage.releaseFirstWrite.complete();

        await expectLater(finish, throwsStateError);
        await settings;
        await slow.waitForSaves();
        expect(storage.attempts, 3);
        expect(slow.state.outings.single.isActive, isTrue);
        expect(slow.state.outings.single.isComplete, isFalse);
        expect(slow.saveError, isNotNull);
        expect(
          AppState.fromJson(
            jsonDecode(storage.storedJson!) as Map<String, Object?>,
          ).outings.single.isActive,
          isTrue,
          reason: 'Queued settings must not replay the failed finish intent',
        );
      },
    );

    test('dismissing one unfinished session preserves siblings, templates and history', () async {
      final targetId = await controller.startOuting('school');
      final siblingId = await controller.startOuting('school');
      final completedId = await controller.startOuting('work');
      final templateBefore = controller.state.blueprints.firstWhere(
        (blueprint) => blueprint.id == 'school',
      );
      final targetBefore = controller.state.outings.firstWhere(
        (outing) => outing.id == targetId,
      );

      final completedBefore = controller.state.outings.firstWhere(
        (outing) => outing.id == completedId,
      );
      for (final item in completedBefore.items) {
        await controller.setOutingItemChecked(
          completedId,
          item.id,
          checked: true,
        );
      }
      await controller.finishOuting(completedId);

      await controller.setOutingItemChecked(
        targetId,
        targetBefore.items.first.id,
        checked: true,
      );
      final targetChecksBefore = controller.state.outings
          .firstWhere((outing) => outing.id == targetId)
          .items
          .map((item) => item.checked)
          .toList();
      await controller.dismissOuting(targetId);

      final target = controller.state.outings.firstWhere(
        (outing) => outing.id == targetId,
      );
      final sibling = controller.state.outings.firstWhere(
        (outing) => outing.id == siblingId,
      );
      final completed = controller.state.outings.firstWhere(
        (outing) => outing.id == completedId,
      );
      expect(target.isDismissed, isTrue);
      expect(target.isActive, isFalse);
      expect(target.items.map((item) => item.checked), targetChecksBefore);
      expect(sibling.isActive, isTrue);
      expect(sibling.isDismissed, isFalse);
      expect(completed.isComplete, isTrue);
      expect(completed.isDismissed, isFalse);
      expect(
        controller.state.blueprints.firstWhere(
          (blueprint) => blueprint.id == 'school',
        ),
        templateBefore,
      );
      expect(
        target.items.map((item) => item.label),
        targetBefore.items.map((item) => item.label),
      );
      expect(
        () => controller.toggleOutingItem(targetId, target.items.first.id),
        throwsStateError,
      );
      expect(() => controller.finishOuting(targetId), throwsStateError);
    });

    test('dismissal persists; restore and finish undo preserve exact checklist state', () async {
      final outingId = await controller.startOuting('school');
      final original = controller.state.outings.single;
      await controller.setOutingItemChecked(
        outingId,
        original.items[0].id,
        checked: true,
      );
      await controller.setOutingItemChecked(
        outingId,
        original.items[2].id,
        checked: true,
      );
      final expectedItems = controller.state.outings.single.items
          .map((item) => item.toJson())
          .toList();
      await controller.dismissOuting(outingId);

      final afterDismissStorage = FakeLeaveGateway(
        storedJson: gateway.storedJson,
      );
      final afterDismissReload = createController(afterDismissStorage);
      addTearDown(afterDismissReload.dispose);
      await afterDismissReload.initialize();
      final dismissed = afterDismissReload.state.outings.single;
      expect(dismissed.id, outingId);
      expect(dismissed.isDismissed, isTrue);
      expect(dismissed.dismissedAtUTC, isNotNull);
      expect(dismissed.dismissedAtUTC!.isUtc, isTrue);
      expect(
        dismissed.items.map((item) => item.toJson()).toList(),
        expectedItems,
      );

      await afterDismissReload.restoreOuting(outingId);
      final restored = afterDismissReload.state.outings.single;
      expect(restored.id, outingId);
      expect(restored.isActive, isTrue);
      expect(restored.dismissedAtUTC, isNull);
      expect(
        restored.items.map((item) => item.toJson()).toList(),
        expectedItems,
      );

      final afterRestoreStorage = FakeLeaveGateway(
        storedJson: afterDismissStorage.storedJson,
      );
      final afterRestoreReload = createController(afterRestoreStorage);
      addTearDown(afterRestoreReload.dispose);
      await afterRestoreReload.initialize();
      expect(afterRestoreReload.state.outings.single.id, outingId);
      expect(afterRestoreReload.state.outings.single.isActive, isTrue);
      expect(
        afterRestoreReload.state.outings.single.items
            .map((item) => item.toJson())
            .toList(),
        expectedItems,
      );

      for (final item in afterRestoreReload.state.outings.single.items) {
        await afterRestoreReload.setOutingItemChecked(
          outingId,
          item.id,
          checked: true,
        );
      }
      await afterRestoreReload.finishOuting(outingId);

      final finishedStorage = FakeLeaveGateway(
        storedJson: afterRestoreStorage.storedJson,
      );
      final finishedReload = createController(finishedStorage);
      addTearDown(finishedReload.dispose);
      await finishedReload.initialize();
      await finishedReload.undoFinish(outingId);
      final reopenedReload = createController(
        FakeLeaveGateway(storedJson: finishedStorage.storedJson),
      );
      addTearDown(reopenedReload.dispose);
      await reopenedReload.initialize();
      final reopened = reopenedReload.state.outings.single;
      expect(reopened.id, outingId);
      expect(reopened.isActive, isTrue);
      expect(reopened.items.every((item) => item.checked), isTrue);
    });

    test('dismiss and restore are idempotent', () async {
      final outingId = await controller.startOuting('school');
      final writeCount = gateway.writes.length;
      await controller.dismissOuting(outingId);
      final firstDismissal = controller.state.outings.single.dismissedAtUTC;
      final afterFirstDismiss = gateway.writes.length;

      await controller.dismissOuting(outingId);
      expect(gateway.writes.length, afterFirstDismiss);
      expect(controller.state.outings.single.dismissedAtUTC, firstDismissal);
      expect(afterFirstDismiss, writeCount + 1);

      await controller.restoreOuting(outingId);
      final afterFirstRestore = gateway.writes.length;
      await controller.restoreOuting(outingId);
      expect(gateway.writes.length, afterFirstRestore);
      expect(controller.state.outings.single.isActive, isTrue);
    });

    test('failed dismissal save remains visible and can be retried', () async {
      final outingId = await controller.startOuting('school');
      gateway.failWrites = true;
      await controller.dismissOuting(outingId);

      expect(controller.state.outings.single.isDismissed, isTrue);
      expect(controller.saveError, isNotNull);
      expect(
        AppState.fromJson(
          jsonDecode(gateway.storedJson!) as Map<String, Object?>,
        ).outings.single.isDismissed,
        isFalse,
      );

      gateway.failWrites = false;
      await controller.retrySave();
      expect(controller.saveError, isNull);
      expect(
        AppState.fromJson(
          jsonDecode(gateway.storedJson!) as Map<String, Object?>,
        ).outings.single.isDismissed,
        isTrue,
      );
    });

    test(
      'a new start creates a fresh session beside dismissed history',
      () async {
        final dismissedId = await controller.startOuting('school');
        final dismissedItems = controller.state.outings.single.items
            .map((item) => item.toJson())
            .toList();
        await controller.dismissOuting(dismissedId);

        final freshId = await controller.startOuting('school');
        expect(freshId, isNot(dismissedId));
        expect(controller.state.outings, hasLength(2));
        final dismissed = controller.state.outings.firstWhere(
          (outing) => outing.id == dismissedId,
        );
        final fresh = controller.state.outings.firstWhere(
          (outing) => outing.id == freshId,
        );
        expect(dismissed.isDismissed, isTrue);
        expect(
          dismissed.items.map((item) => item.toJson()).toList(),
          dismissedItems,
        );
        expect(fresh.isActive, isTrue);
        expect(fresh.items.every((item) => !item.checked), isTrue);
        expect(
          fresh.items
              .map((item) => item.id)
              .toSet()
              .intersection(dismissed.items.map((item) => item.id).toSet()),
          isEmpty,
        );
      },
    );

    test(
      'widget summary handles fresh and completed immutable session lists',
      () {
        final fresh = AppState.initial();
        expect(fresh.widgetSummary, {
          'title': null,
          'checked': 0,
          'total': 0,
          'completed': false,
        });

        final completed = Outing(
          id: 'done',
          blueprintId: 'school',
          blueprintName: 'School',
          date: '2026-10-11',
          startedAt: DateTime(2026, 10, 11, 8),
          completedAt: DateTime(2026, 10, 11, 8, 5),
          items: const [OutingItem(id: 'item', label: 'Bag', checked: true)],
        );
        final state = AppState(outings: [completed]);

        expect(state.widgetSummary, {
          'title': 'School',
          'checked': 1,
          'total': 1,
          'completed': true,
        });
        expect(state.outings, hasLength(1));
      },
    );

    test('widget summary skips dismissed sessions for active and fallback', () {
      final completed = Outing(
        id: 'done',
        blueprintId: 'school',
        blueprintName: 'School',
        date: '2026-10-11',
        startedAt: DateTime.utc(2026, 10, 11, 8),
        completedAt: DateTime.utc(2026, 10, 11, 8, 5),
        items: const [OutingItem(id: 'done-item', label: 'Bag', checked: true)],
      );
      final dismissed = Outing(
        id: 'dismissed',
        blueprintId: 'work',
        blueprintName: 'Work',
        date: '2026-10-11',
        startedAt: DateTime.utc(2026, 10, 11, 10),
        dismissedAtUTC: DateTime.utc(2026, 10, 11, 10, 1),
        items: const [OutingItem(id: 'dismissed-item', label: 'Laptop')],
      );
      final active = Outing(
        id: 'active',
        blueprintId: 'gym',
        blueprintName: 'Gym',
        date: '2026-10-11',
        startedAt: DateTime.utc(2026, 10, 11, 9),
        items: const [OutingItem(id: 'active-item', label: 'Shoes')],
      );

      expect(
        AppState(outings: [completed, dismissed, active])
            .widgetSummary['title'],
        'Gym',
      );
      expect(AppState(outings: [completed, dismissed]).widgetSummary, {
        'title': 'School',
        'checked': 1,
        'total': 1,
        'completed': true,
      });
      expect(AppState(outings: [dismissed]).widgetSummary, {
        'title': null,
        'checked': 0,
        'total': 0,
        'completed': false,
      });
    });

    test(
      'version-one outing JSON without dismissal timestamp remains valid',
      () {
        final legacyOuting = Outing(
          id: 'legacy',
          blueprintId: 'school',
          blueprintName: 'School',
          date: '2026-10-11',
          startedAt: DateTime.utc(2026, 10, 11, 8),
          items: const [OutingItem(id: 'legacy-item', label: 'Bag')],
        ).toJson()..remove('dismissedAtUTC');
        final legacyState = AppState.initial().toJson()
          ..['outings'] = [legacyOuting];

        final restored = AppState.fromJson(legacyState);
        expect(restored.outings.single.id, 'legacy');
        expect(restored.outings.single.dismissedAtUTC, isNull);
        expect(restored.outings.single.isActive, isTrue);
        expect(restored.outings.single.isDismissed, isFalse);
      },
    );

    test('outing timestamps preserve UTC instants and latest ordering', () {
      // These are equivalent to 10:00 in New York and 08:00 in Los Angeles
      // on this date. The later session must remain later after a timezone
      // change and a persisted-state round trip.
      final older = Outing(
        id: 'older',
        blueprintId: 'school',
        blueprintName: 'School',
        date: '2026-10-11',
        startedAt: DateTime.utc(2026, 10, 11, 14),
        completedAt: DateTime.utc(2026, 10, 11, 14, 30),
        items: const [
          OutingItem(id: 'older-item', label: 'Bag', checked: true),
        ],
      );
      final newer = Outing(
        id: 'newer',
        blueprintId: 'work',
        blueprintName: 'Work',
        date: '2026-10-11',
        startedAt: DateTime.utc(2026, 10, 11, 15),
        completedAt: DateTime.utc(2026, 10, 11, 15, 30),
        items: const [
          OutingItem(id: 'newer-item', label: 'Laptop', checked: true),
        ],
      );
      final saved = AppState(outings: [older, newer]).toJson();
      final savedOutings = saved['outings']! as List<Object?>;
      final savedOlder = savedOutings.first! as Map<String, Object?>;
      expect((savedOlder['startedAt']! as String).endsWith('Z'), isTrue);
      expect((savedOlder['completedAt']! as String).endsWith('Z'), isTrue);

      final restored = AppState.fromJson(saved);
      final restoredOlder = restored.outings.first;
      expect(restoredOlder.startedAt.isUtc, isTrue);
      expect(restoredOlder.startedAt.isAtSameMomentAs(older.startedAt), isTrue);
      expect(
        restoredOlder.completedAt!.isAtSameMomentAs(older.completedAt!),
        isTrue,
      );
      expect(restored.widgetSummary['title'], 'Work');
    });

    test(
      'queued writes finish in order and leave the newest snapshot durable',
      () async {
        final blocking = _BlockingGateway();
        final queuedController = createController(blocking);
        addTearDown(queuedController.dispose);
        await queuedController.initialize();

        final firstSave = queuedController.createBlueprint(name: 'First');
        expect(
          queuedController.state.blueprints.any((item) => item.name == 'First'),
          isTrue,
          reason: 'Mutations become visible before a slow disk write finishes',
        );
        await blocking.firstWriteStarted.future;
        final secondSave = queuedController.updateSettings(
          queuedController.state.settings.copyWith(appearance: 'dark'),
        );
        expect(blocking.attempts, hasLength(1));
        blocking.releaseFirstWrite.complete();
        await Future.wait([firstSave, secondSave]);

        expect(blocking.writes, hasLength(2));
        final first = AppState.fromJson(
          jsonDecode(blocking.writes.first) as Map<String, Object?>,
        );
        final last = AppState.fromJson(
          jsonDecode(blocking.writes.last) as Map<String, Object?>,
        );
        expect(first.blueprints.last.name, 'First');
        expect(first.settings.appearance, 'system');
        expect(last.settings.appearance, 'dark');
        expect(
          AppState.fromJson(
            jsonDecode(blocking.storedJson!) as Map<String, Object?>,
          ).toJson(),
          last.toJson(),
        );
      },
    );

    test(
      'notification denial leaves reminders off and core state editable',
      () async {
        gateway.notificationsGranted = false;

        final result = await controller.setReminder(
          hour: 7,
          minute: 15,
          enabled: true,
        );

        expect(result['permissionGranted'], isFalse);
        expect(result['enabled'], isFalse);
        expect(result['reason'], 'permission_required');
        expect(gateway.reminderSchedules, isEmpty);
        expect(controller.state.settings.reminderEnabled, isFalse);
        expect(controller.state.settings.reminderHour, 7);
        expect(controller.canEdit, isTrue);
        await controller.createBlueprint(name: 'Weekend');
      },
    );

    test('cold and warm launch actions reach the app layer', () async {
      gateway.pendingLaunchAction = 'pack_today';
      expect(await controller.getLaunchAction(), 'pack_today');
      expect(await controller.getLaunchAction(), isNull);

      final actions = <String>[];
      controller.setLaunchActionHandler(actions.add);
      gateway.emitLaunchAction('pack_today');
      expect(actions, ['pack_today']);
    });

    test(
      'widget checks survive app writes and explicit ABA values win',
      () async {
        final outingId = await controller.startOuting('school');
        final itemId = controller.state.outings.single.items.first.id;

        await gateway.setWidgetCheck(
          outingId: outingId,
          itemId: itemId,
          checked: true,
        );
        expect(controller.state.outings.single.items.first.checked, isTrue);

        // An explicit Flutter set-to-false must win even though it races from a
        // native checked snapshot; the intent is not inferred from a diff.
        await controller.setOutingItemChecked(outingId, itemId, checked: false);
        await controller.updateSettings(
          controller.state.settings.copyWith(appearance: 'dark'),
        );

        final restored = createController(
          FakeLeaveGateway(storedJson: gateway.storedJson),
        );
        addTearDown(restored.dispose);
        await restored.initialize();
        expect(restored.state.outings.single.items.first.checked, isFalse);
        expect(restored.state.settings.appearance, 'dark');
        expect(
          gateway.writeTransactions.any((transaction) {
            final intents = transaction['checkIntents']! as List;
            return intents.any(
              (intent) =>
                  intent['outingId'] == outingId &&
                  intent['itemId'] == itemId &&
                  intent['checked'] == false,
            );
          }),
          isTrue,
        );
      },
    );

    test(
      'newer check generation stays visible across an older write ack',
      () async {
        final outingId = await controller.startOuting('school');
        final itemId = controller.state.outings.single.items.first.id;
        final blocking = _BlockingGateway(storedJson: gateway.storedJson);
        final slow = createController(blocking);
        addTearDown(slow.dispose);
        await slow.initialize();

        final first = slow.setOutingItemChecked(
          outingId,
          itemId,
          checked: true,
        );
        await blocking.firstWriteStarted.future;
        final second = slow.setOutingItemChecked(
          outingId,
          itemId,
          checked: false,
        );
        expect(slow.state.outings.single.items.first.checked, isFalse);

        blocking.releaseFirstWrite.complete();
        await Future.wait([first, second]);
        expect(slow.state.outings.single.items.first.checked, isFalse);
        expect(
          AppState.fromJson(
            jsonDecode(blocking.storedJson!) as Map<String, Object?>,
          ).outings.single.items.first.checked,
          isFalse,
        );
        expect(
          blocking.writeTransactions
              .map((transaction) => transaction['checkIntents'])
              .toList(),
          [
            [
              {'outingId': outingId, 'itemId': itemId, 'checked': true},
            ],
            [
              {'outingId': outingId, 'itemId': itemId, 'checked': false},
            ],
          ],
        );
      },
    );

    test(
      'delayed post-commit acknowledgement rebases from the newer widget state',
      () async {
        final outingId = await controller.startOuting('school');
        final itemId = controller.state.outings.single.items.first.id;
        final blocking = _BlockingGateway(storedJson: gateway.storedJson)
          ..holdSecondWrite = true;
        final slow = createController(blocking);
        addTearDown(slow.dispose);
        await slow.initialize();
        final observedChecks = <bool>[];
        slow.addListener(() {
          observedChecks.add(slow.state.outings.single.items.first.checked);
        });

        final check = slow.setOutingItemChecked(
          outingId,
          itemId,
          checked: true,
        );
        await blocking.firstWriteStarted.future;
        final settings = slow.updateSettings(
          slow.state.settings.copyWith(appearance: 'dark'),
        );
        blocking.beforeWriteReply = (committedJson) async {
          expect(
            AppState.fromJson(jsonDecode(committedJson) as Map<String, Object?>)
                .outings
                .single
                .items
                .first
                .checked,
            isTrue,
          );
          await blocking.setWidgetCheck(
            outingId: outingId,
            itemId: itemId,
            checked: false,
          );
        };
        blocking.releaseFirstWrite.complete();
        await blocking.secondWriteStarted.future;
        expect(slow.canonicalState.outings.single.items.first.checked, isFalse);
        expect(slow.state.outings.single.items.first.checked, isFalse);
        expect(
          observedChecks.last,
          isFalse,
          reason: 'The old acknowledgement must notify after rebasing while settings wait',
        );
        expect(
          blocking.writeTransactions,
          hasLength(1),
          reason:
              'The second settings write is still blocked in this assertion',
        );
        expect(
          AppState.fromJson(
            jsonDecode(blocking.storedJson!) as Map<String, Object?>,
          ).outings.single.items.first.checked,
          isFalse,
        );
        blocking.releaseSecondWrite.complete();
        await Future.wait([check, settings]);

        expect(slow.state.outings.single.items.first.checked, isFalse);
        expect(
          AppState.fromJson(
            jsonDecode(blocking.storedJson!) as Map<String, Object?>,
          ).outings.single.items.first.checked,
          isFalse,
        );
      },
    );

    test('failed checklist writes retain explicit intent for retry', () async {
      final outingId = await controller.startOuting('school');
      final itemId = controller.state.outings.single.items.first.id;
      gateway.failWrites = true;

      await controller.setOutingItemChecked(outingId, itemId, checked: true);
      expect(controller.saveError, isNotNull);
      expect(
        AppState.fromJson(
          jsonDecode(gateway.storedJson!) as Map<String, Object?>,
        ).outings.single.items.first.checked,
        isFalse,
      );

      gateway.failWrites = false;
      await controller.retrySave();
      expect(controller.saveError, isNull);
      expect(
        AppState.fromJson(
          jsonDecode(gateway.storedJson!) as Map<String, Object?>,
        ).outings.single.items.first.checked,
        isTrue,
      );
      expect(gateway.writeTransactions.last['checkIntents'], [
        {'outingId': outingId, 'itemId': itemId, 'checked': true},
      ]);
    });

    test(
      'already acknowledged check is not replayed by a queued settings write',
      () async {
        final outingId = await controller.startOuting('school');
        final itemId = controller.state.outings.single.items.first.id;
        final blocking = _BlockingGateway(storedJson: gateway.storedJson);
        final slow = createController(blocking);
        addTearDown(slow.dispose);
        await slow.initialize();

        final check = slow.setOutingItemChecked(
          outingId,
          itemId,
          checked: true,
        );
        await blocking.firstWriteStarted.future;
        final settings = slow.updateSettings(
          slow.state.settings.copyWith(appearance: 'dark'),
        );
        blocking.beforeWriteReply = (_) async {
          await blocking.setWidgetCheck(
            outingId: outingId,
            itemId: itemId,
            checked: false,
          );
        };
        blocking.releaseFirstWrite.complete();
        await Future.wait([check, settings]);

        expect(slow.state.outings.single.items.first.checked, isFalse);
        expect(
          blocking.writeTransactions.map((tx) => tx['checkIntents']).toList(),
          [
            [
              {'outingId': outingId, 'itemId': itemId, 'checked': true},
            ],
            <Map<String, Object?>>[],
          ],
        );
        expect(
          AppState.fromJson(
            jsonDecode(blocking.storedJson!) as Map<String, Object?>,
          ).outings.single.items.first.checked,
          isFalse,
        );
      },
    );

    test(
      'stale legacy resume read cannot replace first persisted revision',
      () async {
        final legacy = AppState(
          outings: [
            Outing(
              id: 'legacy-outing',
              blueprintId: 'school',
              blueprintName: 'School',
              date: '2026-10-11',
              startedAt: DateTime(2026, 10, 11, 8),
              items: const [OutingItem(id: 'legacy-item', label: 'Book')],
            ),
          ],
        );
        final legacyJson = jsonEncode(legacy.toJson());
        final storage = FakeLeaveGateway(storedJson: legacyJson);
        final restored = createController(storage);
        addTearDown(restored.dispose);
        await restored.initialize();

        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        storage.readStateOverride = legacyJson;
        storage.beforeReadReply = () async {
          readStarted.complete();
          await releaseRead.future;
        };
        final refresh = restored.refreshExternalState();
        await readStarted.future;
        await restored.setOutingItemChecked(
          'legacy-outing',
          'legacy-item',
          checked: true,
        );
        final epochAfterWrite = restored.storageEpoch;
        releaseRead.complete();
        await refresh;

        expect(epochAfterWrite, 'legacy-v1');
        expect(restored.nativeRevision, 1);
        expect(restored.storageEpoch, epochAfterWrite);
        expect(restored.state.outings.single.items.single.checked, isTrue);
      },
    );

    test('late pre-reset widget event cannot leave the reset epoch', () async {
      final oldState = AppState.initial().copyWith(
        settings: const AppSettings(appearance: 'dark'),
      );
      final oldJson = jsonEncode({
        ...oldState.toJson(),
        '_storageEpoch': 'old-widget-epoch',
        '_nativeRevision': 18,
      });
      final storage = FakeLeaveGateway(storedJson: oldJson)..failReads = true;
      final recovery = createController(storage);
      addTearDown(recovery.dispose);
      await recovery.initialize();
      await recovery.resetCorruptState();
      final resetEpoch = recovery.storageEpoch;

      storage.emitExternalStateChange(oldJson);
      expect(recovery.storageEpoch, resetEpoch);
      expect(recovery.loadError, isNull);
      expect(recovery.state.settings.appearance, 'system');
      expect(recovery.state.blueprints.map((blueprint) => blueprint.id), [
        'school',
        'work',
        'gym',
        'trip',
      ]);
    });

    test(
      'widget uncheck racing finish demotes it without a ghost completion',
      () async {
        final outingId = await controller.startOuting('school');
        final outing = controller.state.outings.single;
        for (final item in outing.items) {
          await controller.setOutingItemChecked(
            outingId,
            item.id,
            checked: true,
          );
        }

        final blocking = _BlockingGateway(storedJson: gateway.storedJson);
        final slow = createController(blocking);
        addTearDown(slow.dispose);
        await slow.initialize();
        final pendingAppWrite = slow.updateSettings(
          slow.state.settings.copyWith(appearance: 'dark'),
        );
        await blocking.firstWriteStarted.future;

        final finish = slow.finishOuting(outingId);
        final itemId = slow.state.outings.single.items.first.id;
        await blocking.setWidgetCheck(
          outingId: outingId,
          itemId: itemId,
          checked: false,
        );
        blocking.releaseFirstWrite.complete();

        await pendingAppWrite;
        await expectLater(finish, throwsStateError);
        final latest = slow.state.outings.single;
        expect(latest.isComplete, isFalse);
        expect(latest.items.first.checked, isFalse);
        expect(slow.saveError, isNull);
        final lifecycleIntent =
            (blocking.writeTransactions.last['lifecycleIntents']! as List)
                    .single
                as Map<String, Object?>;
        expect(lifecycleIntent['outingId'], outingId);
        expect(lifecycleIntent['completedAt'], isA<String>());
        expect(lifecycleIntent['dismissedAtUTC'], isNull);
      },
    );

    test('rejected finish is not replayed after a widget recheck and queued setting', () async {
      final outingId = await controller.startOuting('school');
      for (final item in controller.state.outings.single.items) {
        await controller.setOutingItemChecked(outingId, item.id, checked: true);
      }

      final storage = _RejectingFinishRecheckGateway(
        storedJson: gateway.storedJson,
      );
      final slow = createController(storage);
      addTearDown(slow.dispose);
      await slow.initialize();
      final finish = slow.finishOuting(outingId);
      await storage.firstWriteStarted.future;
      final settings = slow.updateSettings(
        slow.state.settings.copyWith(appearance: 'dark'),
      );
      storage.beforeWriteReply = (_) async {
        await storage.setWidgetCheck(
          outingId: outingId,
          itemId: slow.state.outings.single.items.first.id,
          checked: true,
        );
      };
      storage.releaseFirstWrite.complete();

      await expectLater(finish, throwsStateError);
      await settings;
      expect(storage.writeTransactions, hasLength(2));
      expect(slow.state.outings.single.isActive, isTrue);
      expect(slow.state.outings.single.canFinish, isTrue);
      expect(slow.state.outings.single.isComplete, isFalse);
      expect(slow.saveError, isNull);
      final finishIntents =
          storage.writeTransactions.first['lifecycleIntents']! as List;
      expect(finishIntents, hasLength(1));
      final finishIntent = finishIntents.single as Map<String, Object?>;
      expect(finishIntent['outingId'], outingId);
      expect(finishIntent['completedAt'], isA<String>());
      expect(finishIntent['dismissedAtUTC'], isNull);
      expect(
        storage.writeTransactions.last['lifecycleIntents'],
        isEmpty,
        reason: 'The already resolved finish must not replay with settings',
      );
      expect(
        AppState.fromJson(
          jsonDecode(storage.storedJson!) as Map<String, Object?>,
        ).outings.single.isComplete,
        isFalse,
      );
    });

    test(
      'widget launch request is idempotent across reload and resumes latest',
      () async {
        await controller.addDatedExtra(
          'school',
          label: 'Field-trip form',
          date: '2026-10-11',
        );
        final action = jsonEncode({
          'type': 'widget_list',
          'blueprintId': 'school',
          'requestId': 'request-once',
        });
        final firstId = await controller.handleWidgetLaunchAction(action);
        final duplicateId = await controller.handleWidgetLaunchAction(action);
        expect(duplicateId, firstId);
        expect(controller.state.outings, hasLength(1));
        expect(
          controller.state.outings.single.items.map((item) => item.label),
          contains('Field-trip form'),
        );

        final restored = createController(
          FakeLeaveGateway(storedJson: gateway.storedJson),
        );
        addTearDown(restored.dispose);
        await restored.initialize();
        expect(await restored.handleWidgetLaunchAction(action), firstId);
        expect(restored.state.outings, hasLength(1));

        final resumeId = await restored.handleWidgetLaunchAction(
          jsonEncode({
            'type': 'widget_list',
            'blueprintId': 'school',
            'requestId': 'request-resume',
          }),
        );
        expect(resumeId, firstId);
        expect(restored.state.outings, hasLength(1));
      },
    );
  });
}

class _BlockingGateway extends FakeLeaveGateway {
  _BlockingGateway({super.storedJson});

  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> releaseFirstWrite = Completer<void>();
  final Completer<void> secondWriteStarted = Completer<void>();
  final Completer<void> releaseSecondWrite = Completer<void>();
  final List<String> attempts = [];
  bool holdSecondWrite = false;

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    attempts.add(targetJson);
    if (attempts.length == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
    if (attempts.length == 2 && holdSecondWrite) {
      secondWriteStarted.complete();
      await releaseSecondWrite.future;
    }
    return super.writeState(
      baseJson: baseJson,
      targetJson: targetJson,
      checkIntents: checkIntents,
      lifecycleIntents: lifecycleIntents,
    );
  }
}

class _FailingFinishRollbackGateway extends FakeLeaveGateway {
  _FailingFinishRollbackGateway({required super.storedJson});

  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> releaseFirstWrite = Completer<void>();
  int attempts = 0;

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    attempts++;
    if (attempts == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
      throw StateError('Injected finish write failure');
    }
    if (attempts == 3) {
      throw StateError('Injected rollback write failure');
    }
    return super.writeState(
      baseJson: baseJson,
      targetJson: targetJson,
      checkIntents: checkIntents,
      lifecycleIntents: lifecycleIntents,
    );
  }
}

class _RejectingFinishRecheckGateway extends FakeLeaveGateway {
  _RejectingFinishRecheckGateway({super.storedJson});

  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> releaseFirstWrite = Completer<void>();
  int attempts = 0;

  @override
  Future<String> writeState({
    required String baseJson,
    required String targetJson,
    required List<Map<String, Object?>> checkIntents,
    required List<Map<String, Object?>> lifecycleIntents,
  }) async {
    attempts++;
    if (attempts == 1) {
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
      beforeWriteCommit = () async {
        final current = AppState.fromJson(
          jsonDecode(storedJson!) as Map<String, Object?>,
        );
        final outing = current.outings.single;
        await setWidgetCheck(
          outingId: outing.id,
          itemId: outing.items.first.id,
          checked: false,
        );
      };
    }
    return super.writeState(
      baseJson: baseJson,
      targetJson: targetJson,
      checkIntents: checkIntents,
      lifecycleIntents: lifecycleIntents,
    );
  }
}
