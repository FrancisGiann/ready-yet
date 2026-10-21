package dev.giann.before_i_leave;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Pure selection and freshness rules for the scheduled checklist widget. */
public final class ScheduledWidgetSelectionPolicy {
    private ScheduledWidgetSelectionPolicy() {}

    public static final class Candidate {
        public final String scheduleId;
        public final String outingId;
        public final int departureMinute;
        public final long departureAt;
        public final boolean overdue;
        public final boolean active;
        public final boolean completed;
        public final boolean skipped;

        public Candidate(String scheduleId, String outingId, int departureMinute,
                         boolean overdue, boolean active, boolean completed, boolean skipped) {
            this(scheduleId, outingId, departureMinute, departureMinute * 60_000L,
                    overdue, active, completed, skipped);
        }

        public Candidate(String scheduleId, String outingId, int departureMinute, long departureAt,
                         boolean overdue, boolean active, boolean completed, boolean skipped) {
            this.scheduleId = scheduleId;
            this.outingId = outingId;
            this.departureMinute = departureMinute;
            this.departureAt = departureAt;
            this.overdue = overdue;
            this.active = active;
            this.completed = completed;
            this.skipped = skipped;
        }
    }

    private static final Comparator<Candidate> ORDER = Comparator
            .comparing((Candidate value) -> !value.overdue)
            .thenComparingLong(value -> value.departureAt)
            .thenComparing(value -> value.scheduleId);

    /** Active outings always stay selected, including outings whose items are all checked. */
    public static Candidate select(List<Candidate> candidates) {
        List<Candidate> active = new ArrayList<>();
        for (Candidate candidate : candidates) if (candidate.active) active.add(candidate);
        if (!active.isEmpty()) return active.stream().min(ORDER).orElse(null);
        return candidates.stream().min(ORDER).orElse(null);
    }

    /** Check taps are allowed only while the exact current-day occurrence is active and projected. */
    public static boolean mayApplyCheck(
            boolean providerOwned,
            boolean bindingMatches,
            boolean epochMatches,
            boolean currentDay,
            boolean exactProjectionMatch,
            boolean active,
            long renderedRevision,
            long currentRevision,
            long renderedItemRevision,
            long currentItemRevision,
            boolean currentChecked,
            boolean desiredChecked) {
        return providerOwned && bindingMatches && epochMatches && currentDay && exactProjectionMatch && active
                && renderedRevision >= 0L && renderedRevision <= currentRevision
                && renderedItemRevision >= 0L
                && WidgetCheckMergePolicy.shouldApplyWidgetCheck(
                        renderedItemRevision, currentItemRevision, currentChecked, desiredChecked);
    }

    /** Completed occurrences may be opened read-only; skipped or stale occurrences may not be reopened. */
    public static boolean mayOpenOuting(
            boolean providerOwned,
            boolean bindingMatches,
            boolean epochMatches,
            boolean currentDay,
            boolean exactProjectionMatch,
            boolean active,
            boolean completed,
            boolean skipped) {
        return providerOwned && bindingMatches && epochMatches && currentDay && exactProjectionMatch
                && !skipped && (active || completed);
    }
}
