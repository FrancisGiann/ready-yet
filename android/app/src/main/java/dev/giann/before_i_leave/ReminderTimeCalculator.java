package dev.giann.before_i_leave;

import java.util.Calendar;
import java.util.TimeZone;

/** Pure local-time calculation shared by scheduling and JVM logic checks. */
public final class ReminderTimeCalculator {
    public static final long MAX_DELIVERY_AGE_MS = 2 * 60 * 60 * 1000L;

    private ReminderTimeCalculator() {}

    public static long nextTriggerAt(long nowMillis, int hour, int minute) {
        return nextTriggerAt(nowMillis, hour, minute, TimeZone.getDefault());
    }

    public static long nextTriggerAt(long nowMillis, int hour, int minute, TimeZone timeZone) {
        if (hour < 0 || hour > 23) throw new IllegalArgumentException("hour must be between 0 and 23");
        if (minute < 0 || minute > 59) throw new IllegalArgumentException("minute must be between 0 and 59");
        Calendar next = Calendar.getInstance(timeZone);
        next.setTimeInMillis(nowMillis);
        next.set(Calendar.HOUR_OF_DAY, hour);
        next.set(Calendar.MINUTE, minute);
        next.set(Calendar.SECOND, 0);
        next.set(Calendar.MILLISECOND, 0);
        if (next.getTimeInMillis() <= nowMillis) next.add(Calendar.DAY_OF_YEAR, 1);
        return next.getTimeInMillis();
    }

    public static boolean isFreshDelivery(long scheduledAt, long nowMillis) {
        return nowMillis >= scheduledAt && nowMillis - scheduledAt <= MAX_DELIVERY_AGE_MS;
    }
}
