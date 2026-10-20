package dev.giann.before_i_leave;

import java.util.Calendar;
import java.util.TimeZone;
import java.util.Locale;

/** Calendar-based local departures, available on API 24 without desugaring. */
public final class ScheduleTimePolicy {
    private ScheduleTimePolicy() {}

    public static long departureAt(int year, int month, int day, int minute, TimeZone zone) {
        if (minute < 0 || minute >= 1440) throw new IllegalArgumentException("Invalid departure time");
        Calendar calendar = Calendar.getInstance(zone, Locale.US);
        calendar.clear();
        // Lenient Calendar moves spring-gap times forward. Its deterministic
        // standard-time choice in the repeated autumn hour creates one event.
        calendar.set(year, month - 1, day, minute / 60, minute % 60, 0);
        return calendar.getTimeInMillis();
    }

    public static long reminderAt(long departureAt, int leadMinutes) {
        if (leadMinutes < 0 || leadMinutes > 1440) throw new IllegalArgumentException("Invalid lead time");
        return departureAt - leadMinutes * 60_000L;
    }

    public static boolean mayRemind(long now, long reminderAt, long departureAt,
            boolean active, int total, int checked) {
        return active && total > 0 && checked < total && now >= reminderAt && now <= departureAt;
    }

    public static long snoozeUntil(long now, long departureAt) {
        long snooze = now + 5 * 60_000L;
        return snooze <= departureAt ? snooze : 0L;
    }

    public static long deliveryDeadline(long departureAt, int leadMinutes) {
        // At-departure reminders need a small delivery grace: even exact
        // Android alarms are not guaranteed to arrive on a millisecond.
        return leadMinutes == 0 ? departureAt + 120_000L : departureAt;
    }

    public static int isoWeekday(Calendar calendar) {
        return (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1;
    }
}
