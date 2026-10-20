import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/app/theme.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';
import 'package:before_i_leave/ui/schedules_screen.dart';

class _PermissionCountingGateway extends FakeLeaveGateway {
  int permissionRequests = 0;
  @override
  Future<bool> requestNotifications() async {
    permissionRequests++;
    return super.requestNotifications();
  }
}

void main() {
  ChecklistSchedule school({bool enabled = true}) => ChecklistSchedule(
    id: 'weekday-school',
    blueprintId: 'school',
    weekdays: [1, 2, 3, 4, 5],
    departureMinute: 7 * 60,
    leadMinutes: 15,
    enabled: enabled,
  );

  test(
    'v1 data without schedules upgrades additively and keeps outing identity',
    () {
      final json = AppState.initial().toJson()..remove('schedules');
      final restored = AppState.fromJson(json);
      expect(restored.schedules, isEmpty);
      expect(restored.blueprints.first.items.first.iconKey, 'bag');
      expect(restored.toJson()['version'], 1);
    },
  );

  test('schedule input rejects invalid weekdays, time and lead', () {
    for (final days in [
      <int>[],
      [0],
      [8],
    ]) {
      expect(
        () => ChecklistSchedule(
          id: 's',
          blueprintId: 'school',
          weekdays: days,
          departureMinute: 420,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => school().copyWith(departureMinute: 1440),
      throwsFormatException,
    );
    expect(() => school().copyWith(leadMinutes: -1), throwsFormatException);
    expect(
      ChecklistSchedule.fromJson(school().toJson()).toJson(),
      school().toJson(),
    );
  });

  test(
    'each scheduled date is idempotent and has independent checks',
    () async {
      var now = DateTime(2026, 10, 19, 6, 30);
      final gateway = FakeLeaveGateway();
      final controller = AppController(gateway: gateway, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      final monday = controller.state.outings.single;
      await controller.toggleOutingItem(monday.id, monday.items.first.id);
      await controller.ensureScheduledToday();
      await controller.refreshExternalState();
      expect(controller.state.outings, hasLength(1));
      now = DateTime(2026, 10, 20, 6, 30);
      await controller.ensureScheduledToday();
      expect(controller.state.outings, hasLength(2));
      expect(controller.state.outings.first.items.first.checked, isTrue);
      expect(
        controller.state.outings.last.items.every((item) => !item.checked),
        isTrue,
      );
      expect(
        controller.state.outings.last.id,
        school().occurrenceId('2026-10-20'),
      );
      final reopened = AppController(gateway: gateway, now: () => now);
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.state.outings, hasLength(2));
      now = DateTime(2026, 10, 24, 6, 30);
      await controller.ensureScheduledToday();
      expect(controller.state.outings, hasLength(2));
    },
  );

  test(
    'pause, edit and delete keep snapshots and the original checklist',
    () async {
      final controller = AppController(
        gateway: FakeLeaveGateway(),
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      final snapshot = controller.state.outings.single.toJson();
      await controller.saveSchedule(school(enabled: false));
      await controller.ensureScheduledToday();
      await controller.saveSchedule(school().copyWith(departureMinute: 8 * 60));
      expect(controller.state.outings.single.toJson(), snapshot);
      await controller.deleteSchedule(school().id);
      expect(controller.state.schedules, isEmpty);
      expect(
        controller.state.blueprints.any((list) => list.id == 'school'),
        isTrue,
      );
      expect(controller.state.outings.single.toJson(), snapshot);
    },
  );

  test('skipping or completing today never creates a second occurrence through widgets', () async {
    for (final complete in [false, true]) {
      final controller = AppController(
        gateway: FakeLeaveGateway(),
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      final outing = controller.state.outings.single;
      if (complete) {
        for (final item in outing.items) {
          await controller.setOutingItemChecked(
            outing.id,
            item.id,
            checked: true,
          );
        }
        await controller.finishOuting(outing.id);
      } else {
        await controller.dismissOuting(outing.id);
      }
      await controller.ensureScheduledToday();
      for (final request in ['first', 'second', 'second']) {
        expect(
          await controller.handleWidgetLaunchAction(
            jsonEncode({
              'type': 'widget_list',
              'blueprintId': 'school',
              'requestId': request,
            }),
          ),
          outing.id,
        );
      }
      expect(controller.state.outings, hasLength(1));
      expect(
        complete
            ? controller.state.outings.single.isComplete
            : controller.state.outings.single.isDismissed,
        isTrue,
      );
    }
  });

  test(
    'native-created occurrence survives a stale queued app snapshot',
    () async {
      final gateway = FakeLeaveGateway();
      final controller = AppController(
        gateway: gateway,
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.updateSettings(
        controller.state.settings.copyWith(onboarded: true),
      );
      final native = Outing(
        id: 'scheduled:s:2026-10-19',
        scheduleId: 's',
        blueprintId: 'school',
        blueprintName: 'School',
        date: '2026-10-19',
        startedAt: DateTime(2026, 10, 19),
        items: const [OutingItem(id: 'bag', label: 'Bag', checked: true)],
      );
      gateway.beforeWriteCommit = () async {
        final root = jsonDecode(gateway.storedJson!) as Map<String, dynamic>;
        root['outings'] = [native.toJson()];
        gateway.storedJson = jsonEncode(root);
      };
      await controller.updateSettings(
        controller.state.settings.copyWith(haptics: false),
      );
      expect(controller.state.outings.single.id, native.id);
      expect(controller.state.outings.single.checkedCount, 1);
      expect(
        AppState.fromJson(
          Map<String, Object?>.from(jsonDecode(gateway.storedJson!) as Map),
        ).outings.single.id,
        native.id,
      );
    },
  );

  test(
    'an unchanged widget request opens the next scheduled date after midnight',
    () async {
      var now = DateTime(2026, 10, 19, 6);
      final controller = AppController(
        gateway: FakeLeaveGateway(),
        now: () => now,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      final request = jsonEncode({
        'type': 'widget_list',
        'blueprintId': 'school',
        'requestId': 'same-pending-intent',
      });
      final monday = await controller.handleWidgetLaunchAction(request);
      now = DateTime(2026, 10, 20, 6);
      final tuesday = await controller.handleWidgetLaunchAction(request);
      expect(monday, isNot(tuesday));
      expect(tuesday, school().occurrenceId('2026-10-20'));
      expect(controller.state.outings, hasLength(2));
    },
  );

  test(
    'concurrent native creation keeps its snapshot for the same daily ID',
    () async {
      var now = DateTime(2026, 10, 18, 6);
      final gateway = FakeLeaveGateway();
      final controller = AppController(gateway: gateway, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      now = DateTime(2026, 10, 19, 6);
      final native = Outing(
        id: school().occurrenceId('2026-10-19'),
        scheduleId: school().id,
        blueprintId: 'school',
        blueprintName: 'Saved School',
        date: '2026-10-19',
        startedAt: DateTime(2026, 10, 19),
        items: const [
          OutingItem(
            id: 'native-bag',
            label: 'Saved native bag',
            checked: true,
          ),
        ],
      );
      gateway.beforeWriteCommit = () async {
        final root = jsonDecode(gateway.storedJson!) as Map<String, dynamic>;
        root['outings'] = [native.toJson()];
        gateway.storedJson = jsonEncode(root);
      };
      final materialize = controller.ensureScheduledToday();
      final queuedSettings = controller.updateSettings(
        controller.state.settings.copyWith(haptics: false),
      );
      await materialize;
      await queuedSettings;
      expect(controller.state.outings.single.toJson(), native.toJson());
      final saved = AppState.fromJson(
        Map<String, Object?>.from(jsonDecode(gateway.storedJson!) as Map),
      );
      expect(saved.outings.single.toJson(), native.toJson());
      await controller.addOutingItem(native.id, label: 'Extra book');
      final edited = AppState.fromJson(
        Map<String, Object?>.from(jsonDecode(gateway.storedJson!) as Map),
      );
      expect(edited.outings.single.items, hasLength(2));
      expect(edited.outings.single.items.first.checked, isTrue);
    },
  );

  test(
    'new widget list requests prefer an active schedule to a finished one',
    () async {
      final controller = AppController(
        gateway: FakeLeaveGateway(),
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(school());
      final first = controller.state.outings.single;
      await controller.dismissOuting(first.id);
      final later = ChecklistSchedule(
        id: 'later-school',
        blueprintId: 'school',
        weekdays: [1, 2, 3, 4, 5],
        departureMinute: 480,
        leadMinutes: 15,
        enabled: true,
      );
      await controller.saveSchedule(later);
      final result = await controller.handleWidgetLaunchAction(
        jsonEncode({
          'type': 'widget_list',
          'blueprintId': 'school',
          'requestId': 'active-schedule',
        }),
      );
      expect(result, later.occurrenceId('2026-10-19'));
    },
  );

  testWidgets('a failed editor save retries the same schedule identity', (
    tester,
  ) async {
    final gateway = _PermissionCountingGateway();
    final controller = AppController(
      gateway: gateway,
      now: () => DateTime(2026, 10, 19),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(dark: false, accentIndex: 0),
        home: SchedulesScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a schedule'));
    await tester.pumpAndSettle();
    gateway.failWrites = true;
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    final id = controller.state.schedules.single.id;
    gateway.failWrites = false;
    await tester.ensureVisible(find.text('Save schedule'));
    await tester.tap(find.text('Save schedule'));
    await tester.pumpAndSettle();
    expect(controller.state.schedules.single.id, id);
    expect(controller.state.outings, hasLength(1));
    expect(gateway.permissionRequests, 0);
  });

  testWidgets(
    'schedule editor remains scrollable at narrow widths in both themes and enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppController(
        gateway: FakeLeaveGateway(),
        now: () => DateTime(2026, 10, 19),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: createAppTheme(dark: dark, accentIndex: 0),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SchedulesScreen(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Create a schedule'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Create a schedule'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Save schedule'));
          expect(
            tester.takeException(),
            isNull,
            reason: 'dark=$dark scale=$scale',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'schedule editor uses school weekday defaults without requesting permissions',
    (tester) async {
      final gateway = FakeLeaveGateway();
      final controller = AppController(
        gateway: gateway,
        now: () => DateTime(2026, 10, 19),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: createAppTheme(dark: false, accentIndex: 0),
          home: SchedulesScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Make it a routine.'), findsOneWidget);
      final save = find.text('Save schedule');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final schedule = controller.state.schedules.single;
      expect(schedule.blueprintId, 'school');
      expect(schedule.weekdays, [1, 2, 3, 4, 5]);
      expect(schedule.departureMinute, 420);
      expect(schedule.leadMinutes, 15);
      expect(controller.state.outings, hasLength(1));
    },
  );
}
