package dev.giann.before_i_leave;

/** Pure check-state precedence used while merging Flutter and widget snapshots. */
public final class WidgetCheckMergePolicy {
    private WidgetCheckMergePolicy() {}

    /** An explicit app action wins; otherwise existing rows preserve canonical state. */
    public static Boolean mergeChecked(
            Boolean target,
            Boolean current,
            Boolean explicitAppIntent,
            boolean existing) {
        if (target == null) return null;
        if (explicitAppIntent != null) return explicitAppIntent;
        if (!existing) return target;
        return current != null ? current : target;
    }

    /**
     * App checks authorized while an outing was active remain valid when a
     * later queued lifecycle snapshot finishes or dismisses that same outing.
     */
    public static Boolean mergeAuthorizedAppCheck(
            Boolean target,
            Boolean current,
            Boolean explicitAppIntent,
            boolean existing,
            boolean hasLifecycleIntent) {
        // The lifecycle flag documents the ordering scenario; it must not
        // revoke an already-authorized item action from the same app session.
        return mergeChecked(target, current, explicitAppIntent, existing);
    }

    /** A merged unchecked item cannot remain in a completed outing. */
    public static boolean keepCompleted(boolean requestedCompleted, int total, int checked) {
        return requestedCompleted && total > 0 && checked == total;
    }

    /** Rejects stale same-row ABA actions while allowing unrelated row updates. */
    public static boolean shouldApplyWidgetCheck(
            long renderedItemRevision,
            long currentItemRevision,
            boolean currentChecked,
            boolean desiredChecked) {
        return currentChecked != desiredChecked && currentItemRevision <= renderedItemRevision;
    }

    /** Advances row generations for explicit app/lifecycle actions, including same-value writes. */
    public static boolean shouldAdvanceItemRevision(
            boolean hasExplicitAppIntent,
            boolean hasLifecycleIntent,
            boolean targetDiffersFromMerged,
            boolean currentDiffersFromMerged) {
        return hasExplicitAppIntent || hasLifecycleIntent || targetDiffersFromMerged || currentDiffersFromMerged;
    }
}
