package dev.giann.before_i_leave;

import java.time.Instant;
import java.time.ZoneId;
import java.util.TimeZone;

public final class ReminderTimeCalculatorCheck {
    private static int passed;

    private static void expect(String name, boolean condition) {
        if (!condition) throw new AssertionError(name);
        passed++;
        System.out.println("PASS " + name);
    }

    public static void main(String[] args) {
        TimeZone utc = TimeZone.getTimeZone("UTC");
        long before = Instant.parse("2026-10-11T08:30:00Z").toEpochMilli();
        long sameDay = Instant.parse("2026-10-11T09:00:00Z").toEpochMilli();
        long nextDay = Instant.parse("2026-10-12T09:00:00Z").toEpochMilli();
        expect("UTC next local occurrence today", ReminderTimeCalculator.nextTriggerAt(before, 9, 0, utc) == sameDay);
        expect("exact scheduled minute advances to tomorrow", ReminderTimeCalculator.nextTriggerAt(sameDay, 9, 0, utc) == nextDay);

        TimeZone manila = TimeZone.getTimeZone("Asia/Manila");
        long manilaMorning = Instant.parse("2026-10-11T23:00:00Z").toEpochMilli();
        long manilaNext = Instant.parse("2026-10-12T01:00:00Z").toEpochMilli();
        expect("Asia/Manila uses its local date and clock", ReminderTimeCalculator.nextTriggerAt(manilaMorning, 9, 0, manila) == manilaNext);

        TimeZone newYork = TimeZone.getTimeZone("America/New_York");
        long springBeforeGap = Instant.parse("2026-03-08T06:30:00Z").toEpochMilli();
        long springNormalized = Instant.parse("2026-03-08T07:30:00Z").toEpochMilli();
        expect("New York spring gap normalizes 02:30 to 03:30 local", ReminderTimeCalculator.nextTriggerAt(springBeforeGap, 2, 30, newYork) == springNormalized);

        long fallAfterFirstOccurrence = Instant.parse("2026-11-01T05:45:00Z").toEpochMilli();
        long fallSecondOccurrence = Instant.parse("2026-11-01T06:30:00Z").toEpochMilli();
        expect("New York repeated 01:30 uses the second future occurrence", ReminderTimeCalculator.nextTriggerAt(fallAfterFirstOccurrence, 1, 30, newYork) == fallSecondOccurrence);
        expect("fall result is future and remains on the repeated local date", fallSecondOccurrence > fallAfterFirstOccurrence &&
                Instant.ofEpochMilli(fallSecondOccurrence).atZone(ZoneId.of("America/New_York")).toLocalDate().toString().equals("2026-11-01"));

        expect("delivery at the two-hour cutoff remains fresh", ReminderTimeCalculator.isFreshDelivery(sameDay, sameDay + 2 * 60 * 60 * 1000L));
        expect("delivery beyond two hours is dropped", !ReminderTimeCalculator.isFreshDelivery(sameDay, sameDay + 2 * 60 * 60 * 1000L + 1));
        expect("future delivery is not fresh", !ReminderTimeCalculator.isFreshDelivery(sameDay, sameDay - 1));

        expect("DATE_CHANGED does not force recalculation", !ReminderReschedulePolicy.shouldForceForAction("android.intent.action.DATE_CHANGED"));
        expect("BOOT_COMPLETED forces local-time recalculation", ReminderReschedulePolicy.shouldForceForAction("android.intent.action.BOOT_COMPLETED"));
        expect("TIME_SET forces local-time recalculation", ReminderReschedulePolicy.shouldForceForAction("android.intent.action.TIME_SET"));
        expect("TIMEZONE_CHANGED forces local-time recalculation", ReminderReschedulePolicy.shouldForceForAction("android.intent.action.TIMEZONE_CHANGED"));
        expect("future stored alarm is reuse-eligible on startup", ReminderReschedulePolicy.shouldReuseStoredAlarm(nextDay, sameDay, false));
        expect("midnight-due alarm is reuse-eligible inside delivery grace", ReminderReschedulePolicy.shouldReuseStoredAlarm(sameDay, sameDay + 5 * 60 * 1000L, false));
        expect("delayed due alarm is reuse-eligible before grace expires", ReminderReschedulePolicy.shouldReuseStoredAlarm(sameDay, sameDay + 90 * 60 * 1000L, false));
        expect("stale alarm is not reused after grace expires", !ReminderReschedulePolicy.shouldReuseStoredAlarm(sameDay, sameDay + 2 * 60 * 60 * 1000L + 1, false));
        expect("forced clock-change recalculation replaces stored alarm", !ReminderReschedulePolicy.shouldReuseStoredAlarm(nextDay, sameDay, true));
        System.out.println("PASS all " + passed + " reminder time and reschedule policy checks");
    }
}
