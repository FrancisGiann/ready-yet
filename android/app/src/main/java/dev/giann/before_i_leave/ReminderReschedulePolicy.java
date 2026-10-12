package dev.giann.before_i_leave;

/** Pure policy for calendar-change broadcasts and preserving a pending daily alarm. */
public final class ReminderReschedulePolicy {
    private static final String ACTION_DATE_CHANGED = "android.intent.action.DATE_CHANGED";

    private ReminderReschedulePolicy() {}

    /** A midnight date rollover must not replace a due or still-fresh alarm. */
    public static boolean shouldForceForAction(String action) {
        return !ACTION_DATE_CHANGED.equals(action);
    }

    /** Reuse a future alarm or one that is still inside the existing delivery grace window. */
    public static boolean shouldReuseStoredAlarm(long scheduledAt, long nowMillis, boolean force) {
        return !force && scheduledAt > 0L &&
                (scheduledAt > nowMillis || ReminderTimeCalculator.isFreshDelivery(scheduledAt, nowMillis));
    }
}
