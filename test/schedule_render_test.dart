import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:before_i_leave/app/theme.dart';
import 'package:before_i_leave/domain/app_controller.dart';
import 'package:before_i_leave/domain/models.dart';
import 'package:before_i_leave/platform/leave_gateway.dart';
import 'package:before_i_leave/ui/schedules_screen.dart';

void main() {
  setUpAll(() async {
    var candidate = File(Platform.resolvedExecutable).absolute.parent;
    while (candidate.parent.path != candidate.path) {
      final fonts = Directory(
        '${candidate.path}/bin/cache/artifacts/material_fonts',
      );
      if (fonts.existsSync()) {
        for (final entry in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final bytes = await File('${fonts.path}/${entry.value}')
              .readAsBytes();
          await (FontLoader(
            entry.key,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
        return;
      }
      candidate = candidate.parent;
    }
  });
  testWidgets(
    'schedule overview and editor render long titles in both themes and enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = AppState.initial();
      final state = initial.copyWith(
        blueprints: initial.blueprints.map(
          (list) => list.id == 'school'
              ? list.copyWith(
                  name: 'School and extracurricular activities for a very busy weekday morning',
                )
              : list,
        ),
      );
      final controller = AppController(
        gateway: FakeLeaveGateway(storedJson: jsonEncode(state.toJson())),
        now: () => DateTime(2026, 10, 19, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.saveSchedule(
        ChecklistSchedule(
          id: 'render-school',
          blueprintId: 'school',
          weekdays: [1, 2, 3, 4, 5],
          departureMinute: 420,
          leadMinutes: 15,
          enabled: true,
        ),
      );
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${dark ? 'dark' : 'light'}_${scale == 1 ? 'normal' : 'large'}';
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('schedule-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: createAppTheme(dark: dark, accentIndex: 0),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: SchedulesScreen(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'overview $name');
          await capture(tester, 'schedule_overview_$name');
          await tester.scrollUntilVisible(
            find.text('Edit'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          for (
            var attempt = 0;
            attempt < 12 && find.text('Edit').hitTestable().evaluate().isEmpty;
            attempt++
          ) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -240),
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('Edit').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'editor $name');
          await capture(tester, 'schedule_editor_$name');
          await tester.ensureVisible(find.text('Save schedule'));
          expect(tester.takeException(), isNull, reason: 'editor scroll $name');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('schedule-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG encoding failed');
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
