import dev.giann.before_i_leave.WidgetCheckMergePolicy;

public final class WidgetCheckMergePolicyCheck {
    public static void main(String[] args) {
        expect(true, WidgetCheckMergePolicy.mergeChecked(false, true, null, true), "maskless stale snapshot preserves current widget change");
        expect(false, WidgetCheckMergePolicy.mergeChecked(true, false, null, true), "maskless app snapshot cannot infer an intent");
        expect(false, WidgetCheckMergePolicy.mergeChecked(false, true, false, true), "explicit app toggle wins over a widget change");
        expect(true, WidgetCheckMergePolicy.mergeAuthorizedAppCheck(false, false, true, true, true), "pending app check survives a queued finish intent");
        expect(true, WidgetCheckMergePolicy.mergeAuthorizedAppCheck(false, false, true, true, true), "pending app check survives a queued dismiss intent");
        expect(true, WidgetCheckMergePolicy.shouldAdvanceItemRevision(true, false, false, false), "same-value explicit app choice invalidates older widget taps");
        expect(true, WidgetCheckMergePolicy.shouldAdvanceItemRevision(false, true, false, false), "outing lifecycle transition invalidates old item taps");
        expect(false, WidgetCheckMergePolicy.shouldAdvanceItemRevision(false, false, false, false), "unmasked unchanged row keeps its item generation");
        expect(false, WidgetCheckMergePolicy.mergeChecked(false, null, null, false), "new item initializes from target");
        expect(true, WidgetCheckMergePolicy.mergeChecked(true, null, null, false), "new checked item initializes from target");
        expect(null, WidgetCheckMergePolicy.mergeChecked(null, true, false, true), "deleted target item is not reintroduced");
        expect(true, WidgetCheckMergePolicy.keepCompleted(true, 3, 3), "completed outing remains complete only when all are checked");
        expect(false, WidgetCheckMergePolicy.keepCompleted(true, 3, 2), "unchecked merged item demotes completion");
        expect(false, WidgetCheckMergePolicy.keepCompleted(true, 0, 0), "empty outing is never completed through widget merge");
        expect(false, WidgetCheckMergePolicy.keepCompleted(false, 3, 3), "widget check never completes an outing");
        System.out.println("WidgetCheckMergePolicy: 15 checks passed");
    }

    private static void expect(Object expected, Object actual, String name) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(name + ": expected " + expected + ", got " + actual);
        }
    }
}
