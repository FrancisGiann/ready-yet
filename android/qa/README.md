# Android native QA

Run the dependency-free reminder clock checks with a local JDK 17 or newer:

```sh
android/qa/check_reminder_time.sh
```

Run the widget check merge and resize-budget checks with a local JDK 17 or newer:

```sh
android/qa/check_widget_policy.sh
```

The widget policy checks use the same pure-Java merge and layout-budget helpers as the Android implementation. At heights of 112/156/200/260/275/360/480dp, the tested checklist row budgets are 0/1/1/3/3/5/5. At quick-list heights of 88/112/156/200/260/275/360/480dp, the tested row budgets are 0/0/1/2/3/4/4/4. Visible rows retain a 48dp minimum target, and the footer action opens the remaining content. Static `RemoteViews` show at most five checklist rows and four quick-list tiles.

Widget interactions and storage are source-reviewed and Android-compiled, not exercised on a launcher. Each widget instance stores stable blueprint IDs and a binding generation. Activity intents bind the widget ID, kind, selection, generation, and unique string request ID in an immutable PendingIntent; MainActivity checks the provider, private generation/configuration, selected blueprint, and current outing/list before forwarding a launch. Invalid or stale widget launches safely return to Today without reopening an unrelated active outing. List-launch dates are resolved at action time by Flutter, so a list widget that was last rendered yesterday still opens its current selection. An existing outing may open only when it is still active and is the exact outing shown by that widget; an auto-selected active outing can remain openable when its reusable blueprint was deleted. Configuration activities confirm the appWidgetId belongs to the expected provider and reread list IDs before writing after an explicit Save. Checklist rows use API24-compatible image indicators and text; tapping a row sends an immutable desired-state action to a private receiver that only updates an active configured outing item. Revision/epoch and per-item revision checks reject stale renders and ABA taps. Native writes merge explicit app check/lifecycle masks under the same state lock; widget checks and app saves return canonical JSON with stable `_storageEpoch` and incrementing `_nativeRevision`. Summaries are derived from canonical JSON; no separate summary is authoritative. Pin requests require API 26+ host support and return whether the host accepted the request, not whether the widget was installed.

The resize checks verify row-budget math only, including that the configured minimum content height fits at each tested size. They do not measure OEM launcher insets, enlarged font rendering, real widget clicks, pinning, configuration lifecycle, or multiple instances on a device. No Android device or AVD was available for this run.

The script compiles the production `ReminderTimeCalculator.java` and `ReminderReschedulePolicy.java` and runs eighteen checks covering UTC scheduling, an Asia/Manila local-date boundary, New York's spring DST gap and repeated fall hour, the two-hour stale-delivery cutoff, and calendar-broadcast/reuse decisions. `Calendar` normalizes a nonexistent local time to the next valid clock time. During a repeated hour, it can choose the second occurrence when that occurrence is still in the future. A midnight `DATE_CHANGED` broadcast preserves a future or fresh scheduled instant; boot, wall-clock, and timezone changes recalculate local time.

The checks last passed with:

```text
PASS UTC next local occurrence today
PASS exact scheduled minute advances to tomorrow
PASS Asia/Manila uses its local date and clock
PASS New York spring gap normalizes 02:30 to 03:30 local
PASS New York repeated 01:30 uses the second future occurrence
PASS fall result is future and remains on the repeated local date
PASS delivery at the two-hour cutoff remains fresh
PASS delivery beyond two hours is dropped
PASS future delivery is not fresh
PASS DATE_CHANGED does not force recalculation
PASS BOOT_COMPLETED forces local-time recalculation
PASS TIME_SET forces local-time recalculation
PASS TIMEZONE_CHANGED forces local-time recalculation
PASS future stored alarm is reuse-eligible on startup
PASS midnight-due alarm is reuse-eligible inside delivery grace
PASS delayed due alarm is reuse-eligible before grace expires
PASS stale alarm is not reused after grace expires
PASS forced clock-change recalculation replaces stored alarm
PASS all 18 reminder time and reschedule policy checks
```

The widget policy script passed 15 merge-precedence/revision, 8 launch-authorization, and 55 resize-budget assertions (30 height/budget-fit loop assertions and 25 standalone capacity, orientation, and density assertions). The reminder script passed 18 clock/reschedule checks, for 96 pure-Java assertions total. Offline Android resource processing, Kotlin/Java compilation, and `:app:lintRelease` passed. Native render evidence and its limits are documented in `qa/native-widget-renders/README.md`; these policy and compile checks do not replace a launcher runtime test.

These checks exercise the production date/time and reschedule policy helpers. When Android delivers `DATE_CHANGED`, the receiver follows the non-forced reuse path so a future or still-fresh stored instant is retained; the OS does not guarantee that broadcast at precisely local midnight on every Android version or device. Boot, wall-clock, and timezone broadcasts force local-time recalculation. Startup reinstalls a persisted future/fresh alarm to recover after force-stop, and alarms older than the two-hour grace period are replaced by the next local occurrence.

Reminder configuration saves enabled state, local time, and its scheduled timestamp in one synchronous `SharedPreferences.commit()` before changing the OS alarm. If persistence, alarm installation/cancellation, or the final status read fails, the scheduler restores the prior preference snapshot and attempts to restore the prior pending alarm (or schedule the prior time's next occurrence if stale). Startup and broadcast handlers catch and log storage/scheduler failures. These transaction and recovery paths are source-reviewed, not exercised against Android's real `AlarmManager` or `SharedPreferences` here. The checks do not exercise notification permission prompts, widget rendering, or filesystem recovery. A release APK build validates Android resource and Kotlin integration, but is not a device runtime test.

## Compact 2×2 update

Both existing widget providers now advertise 2×2 placement with 110dp fallback width/height. They retain horizontal/vertical resizing and their existing larger source layouts. API 31+ exact launcher allocations select size-specific RemoteViews; older hosts use separate portrait and landscape views.

The additional `WidgetCompactAllocationCheck` runs 130 assertions across ten allocations and six font scales, including 110×110, 130×130, 130×220 and 269×117dp. At 110×110dp/default text, one checklist row or list shortcut fits alongside a separate 48dp action. At 2× text the smallest checklist shows its action only; at 130×130dp one checklist row fits. Larger widget capacity is preserved. Together with 15 merge, 8 launch, 55 resize and 18 reminder assertions, the scripts cover 226 pure-Java assertions.

See `qa/native-widget-renders/README.md` for the 31 synthetic native renders, text/bounds checks, and limitations. Flutter's existing deep-link tests cover selected-list/outings navigation and duplicate-request handling. These checks do not exercise a PendingIntent on a physical launcher.
