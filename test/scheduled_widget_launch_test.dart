import 'dart:convert';

import 'package:before_i_leave/app/app.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';
import 'package:before_i_leave/ui/schedules_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSchedule routine(String id) => ChecklistSchedule(
  id: id,
  blueprintId: 'school',
  weekdays: [1, 2, 3, 4, 5],
  departureMinute: 420,
  leadMinutes: 15,
  enabled: true,
);
String request(
  FakeLeaveGateway gateway,
  ChecklistSchedule schedule,
  String id, {
  String date = '2026-10-19',
  String? epoch,
}) => jsonEncode({
  'type': 'scheduled_widget_outing',
  'outingId': schedule.occurrenceId(date),
  'scheduleId': schedule.id,
  'requestId': id,
  'storageEpoch':
      epoch ?? (jsonDecode(gateway.storedJson!) as Map)['_storageEpoch'],
});
void main() {
  test('scheduled widget opens the exact occurrence without starting another outing', () async {
    final gateway = FakeLeaveGateway();
    final controller = AppController(
      gateway: gateway,
      now: () => DateTime(2026, 10, 19, 6),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.saveSchedule(routine('school-am'));
    final action = request(gateway, routine('school-am'), 'open');
    final before = controller.state.outings.single.toJson();
    expect(
      await controller.handleWidgetLaunchAction(action),
      routine('school-am').occurrenceId('2026-10-19'),
    );
    expect(
      await controller.handleWidgetLaunchAction(action),
      routine('school-am').occurrenceId('2026-10-19'),
    );
    expect(controller.state.outings, hasLength(1));
    expect(controller.state.outings.single.toJson(), before);
  });
  test(
    'completed scheduled widget opens read-only without repeating completion',
    () async {
      final gateway = FakeLeaveGateway();
      final controller = AppController(
        gateway: gateway,
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(routine('school-am'));
      final outing = controller.state.outings.single;
      for (final item in outing.items) {
        await controller.setOutingItemChecked(
          outing.id,
          item.id,
          checked: true,
        );
      }
      await controller.finishOuting(outing.id);
      final completed = controller.state.outings.single.toJson();
      await controller.handleWidgetLaunchAction(
        request(gateway, routine('school-am'), 'complete'),
      );
      expect(controller.state.outings.single.toJson(), completed);
      expect(controller.state.outings.single.isComplete, isTrue);
    },
  );
  test(
    'cached scheduled widget request is revalidated after midnight',
    () async {
      var now = DateTime(2026, 10, 19, 6);
      final gateway = FakeLeaveGateway();
      final controller = AppController(gateway: gateway, now: () => now);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(routine('school-am'));
      final action = request(gateway, routine('school-am'), 'cached');
      await controller.handleWidgetLaunchAction(action);
      now = DateTime(2026, 10, 20, 6);
      await expectLater(
        controller.handleWidgetLaunchAction(action),
        throwsFormatException,
      );
      expect(controller.state.outings, hasLength(2));
      expect(controller.state.outings.first.checkedCount, 0);
      expect(controller.state.outings.last.checkedCount, 0);
    },
  );
  test('paused skipped and stale-epoch requests cannot open or mutate an occurrence', () async {
    for (final kind in ['paused', 'skipped', 'epoch']) {
      final gateway = FakeLeaveGateway();
      final controller = AppController(
        gateway: gateway,
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(routine('school-am'));
      final action = request(
        gateway,
        routine('school-am'),
        'stale',
        epoch: kind == 'epoch' ? 'retired-storage' : null,
      );
      if (kind == 'paused') {
        await controller.saveSchedule(
          routine('school-am').copyWith(enabled: false),
        );
      }
      if (kind == 'skipped') {
        await controller.dismissOuting(controller.state.outings.single.id);
      }
      final before = controller.state.outings.single.toJson();
      await expectLater(
        controller.handleWidgetLaunchAction(action),
        throwsFormatException,
      );
      expect(controller.state.outings.single.toJson(), before);
    }
  });
  test(
    'request replay cannot retarget another schedule with the same checklist',
    () async {
      final gateway = FakeLeaveGateway();
      final controller = AppController(
        gateway: gateway,
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(routine('school-am'));
      await controller.saveSchedule(routine('school-later'));
      await controller.handleWidgetLaunchAction(
        request(gateway, routine('school-am'), 'same'),
      );
      await expectLater(
        controller.handleWidgetLaunchAction(
          request(gateway, routine('school-later'), 'same'),
        ),
        throwsFormatException,
      );
      expect(controller.state.outings, hasLength(2));
      expect(
        controller.state.outings.every((outing) => outing.checkedCount == 0),
        isTrue,
      );
    },
  );
  testWidgets(
    'scheduled widget management destination can be opened again after returning Home',
    (tester) async {
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
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        gateway.emitLaunchAction('widget_schedules');
        await tester.pumpAndSettle();
        expect(find.byType(SchedulesScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(SchedulesScreen))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(SchedulesScreen), findsNothing);
      }
      expect(controller.state.outings, isEmpty);
    },
  );
  testWidgets(
    'duplicate scheduled management request keeps the current route',
    (tester) async {
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
      await tester.pumpWidget(BeforeILeaveApp(controller: controller));
      await tester.pumpAndSettle();
      final action = jsonEncode({
        'type': 'widget_schedules',
        'requestId': 'management-one',
      });
      gateway.emitLaunchAction(action);
      await tester.pumpAndSettle();
      final original = tester.state(find.byType(SchedulesScreen));
      gateway.emitLaunchAction(action);
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(SchedulesScreen)), original),
        isTrue,
      );
    },
  );
}
