# Checklist schedules — 1.0.5 validation

Time-based scheduling is implemented, built and validated as Ready Yet? 1.0.5+6. The signed arm64 APK and preview evidence are saved locally. The shared heavy slot was released after validation. GitHub source publication is authorized; release/asset upload needs an authenticated interface not currently exposed. No Library upload was attempted because its previously denied route remains blocked.

## Behavior

- Home → Schedules opens a compact editor for checklist, recurring weekdays, local departure time and reminder lead. The first schedule defaults to School / Mon–Fri / 07:00 / 15 minutes before. Settings provides the same entry point. Editing, pausing and deleting schedules retain the checklist and existing outing history.
- Each occurrence has stable identity `scheduled:<scheduleId>:<YYYY-MM-DD>`. Native reads and Flutter reconcile today's occurrences without resetting existing checks. Each occurrence snapshots checklist items and that date's extras. A tomorrow occurrence can be created when its reminder lead crosses midnight. Missed past days are not backfilled.
- Home and both existing native widget providers surface today's scheduled checklist. Completed/skipped states remain visible, and repeated widget launches do not create another occurrence. Existing 2×2 and larger layouts remain in place.
- Reminder actions are Open checklist, Snooze 5 min and Skip today. Snooze is offered only when five minutes fit before departure. A late tap on an older Snooze action keeps the current reminder and explains that departure is close. Replayed actions and actions from prior storage epochs cannot change the current occurrence or dismiss a newer reminder.
- Completion, skip and an entirely packed checklist suppress remaining reminders. Pause/delete suppress future reminders and cancel visible notifications. Occurrence history is preserved. Ordinary advance reminders expire at departure; the optional zero-lead setting has a two-minute latency grace.
- A single next-event alarm handles reminders, departure expiry and daily materialization. Reads/writes run on the existing storage/worker lanes; there is no polling service. Boot, date/time/timezone changes and alarm-access changes recalculate against local calendar dates. Spring-gap departures normalize forward; the repeated autumn hour has one deterministic standard-time event. Daily IDs and durable delivery records prevent repeat delivery after reopening.

## Permissions and delivery

Schedules remain enabled and usable when notifications are denied. Permission requests occur only after an explicit Allow reminders tap. A separate notification-settings button supports denied/channel-disabled cases. The app declares `SCHEDULE_EXACT_ALARM` and exposes an explicit system-settings action; it uses exact alarms only when access already exists, otherwise an inexact allow-while-idle fallback. No permissions were requested or granted on a device during this work.

Notification timing has not been tested on a device and is not guaranteed. Doze, OEM restrictions, force-stop and permission revocation can delay/cancel alarms; reopening restores from persisted state. See the current official [Android alarm guidance](https://developer.android.com/develop/background-work/services/alarms) and [notification permission guidance](https://developer.android.com/develop/ui/compose/notifications/notification-permission). No location permission, geofence, tracking dependency or location service was added. Location backup remains deferred until the time-based feature is built and validated.

## Storage and compatibility

The package/signing configuration, v1 storage format, storage filenames, epoch/check revision protocol, old user settings, existing manual outings and ID card/Perfume/completion features are preserved. `schedules` and optional outing `scheduleId` fields are additive. Native-owned reminder delivery metadata and newly materialized occurrences survive stale Flutter structural snapshots under the same state lock. The existing general daily reminder remains available independently.

## Completed lightweight checks

- Dart syntax/format checks on changed Dart source.
- 12 dependency-free Dart schedule checks.
- Existing native widget/reminder policies: 226 assertions passed.
- 27 pure-Java clock/action checks, including DST gap/fold, timezone changes, midnight leads, delivery cutoff/grace, stale epochs/tokens, duplicate Snooze and terminal suppression.
- Bounded standalone compilation (256 MB heap, two CPU threads) of pure native schedule state and widget projection against local API signatures. This is not an Android app build or runtime test.
- Twelve Flutter regression cases prepared in `test/schedule_test.dart`: additive migration, validation, per-day independence/reload, pause/edit/delete, completed/skipped idempotency, native-created occurrence merge, same widget request across midnight, concurrent creation with queued settings, active schedule widget selection, editor retry identity, explicit permission behavior and a light/dark 360dp text-scale matrix. These have **not** run yet.

Run the small clock/action checks with a local JDK:

```sh
sh android/qa/check_schedule_time.sh
```

## October 20 lightweight continuation

A parallel read-only native review identified concurrent occurrence creation and a reminder-threshold clock gap. Native materialization and event selection now share a clock sample. The first committed scheduled checklist snapshot survives concurrent creation and an unchanged queued settings snapshot; explicit structural edits and check/lifecycle intent masks remain supported. A second locked eligibility check prevents a completion, pause or reset from committing between notification eligibility and posting. New widget-list requests prefer an active scheduled occurrence to a terminal one, matching native projection order. Two settings-action Dart interface type errors found by the host compile were corrected.

Seventeen assertions passed using the actual production controller, models and fake gateway on the Dart VM with minimal isolated Flutter foundation/services stubs. They cover migration, daily independence, reload, weekends, edit/pause/delete, terminal widget replay, midnight advancement, concurrent native creation plus queued settings, deliberate item edits retaining checks, and active schedule selection. This validates domain behavior only, not Flutter rendering or platform channels. The 12 pure Dart and 27 Java schedule checks and 226 existing native assertions were rerun successfully. Full Flutter analysis/tests, Android application compile/lint, notification runtime and physical-device checks remain unrun. No scheduling APK or new Library upload exists.

The preserved source originals are in `task-9/schedule-source-before-20261020`; the machine-readable handoff is `task-9/schedule-readiness.json`, and lightweight harness/logs are in `task-9/schedule-oct20-host`. Source hash checks verified that only the five implementation/test files and this document changed during this continuation. Package, signing and version configuration were not changed.

## Completed full validation (October 20)

- Flutter analysis: no issues. Full Flutter suite: 87 tests passed, including existing ID card/Perfume and completion flows. The initial full run exposed Home placement and lazy-list test issues; both were corrected before the final passing run.
- Android signed arm64 release build: passed. Release lint: passed with zero errors and 89 warnings (resource/layout recommendations, API guards and existing icon/resource warnings); warnings were not suppressed.
- Existing widget/reminder Java checks: 226 assertions; schedule/action Java checks: 27 assertions; pure Dart policy: 12 assertions; isolated actual controller host: 17 assertions. All passed.
- Four synthetic Robolectric API 35 tests using compiled production classes passed: daily occurrence persistence, concurrent native creation plus queued settings and explicit item edits, Open/Snooze/replay/Skip including old reset epoch rejection, and notification suppression for pause/packed/permission-denied states. The offline host harness uses cached dependencies and synthetic app data, not an emulator or physical device.
- All 31 native Layoutlib widget captures passed; eight new real Flutter schedule overview/editor previews passed with long titles, light/dark and 1×/2× text.
- APK package/version, zip alignment and signing verification passed. Version code 6 is greater than prior 5 and the signing certificate matches 1.0.4. Physical in-place upgrade installation/data verification remains unperformed.
- No available AVD/system image or attached device. OEM launcher PendingIntent/resize behavior, pinning/configuration, boot/timezone receiver delivery, Doze/force-stop/background alarm timing and real system permission transitions remain unperformed. The pure policy checks cover DST and clock boundaries; synthetic runtime coverage does not establish device delivery guarantees.
- Heavy build/test processes were stopped and a host process recheck found none remaining when the slot was released. No further heavy work is planned during source publication.
