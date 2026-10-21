import dev.giann.before_i_leave.ScheduledWidgetSelectionPolicy;
import java.util.Arrays;
import java.util.Collections;

public final class ScheduledWidgetSelectionPolicyCheck {
    private static int checks;

    public static void main(String[] args) {
        var later = active("b", "scheduled:b:2026-10-21", 900, false);
        var overdue = active("c", "scheduled:c:2026-10-21", 600, true);
        var earlierOverdue = active("a", "scheduled:a:2026-10-21", 600, true);
        expect(ScheduledWidgetSelectionPolicy.select(Arrays.asList(later, overdue, earlierOverdue)) == earlierOverdue,
                "overdue occurrences win, then departure minute and stable schedule id decide order");
        var normalizedGap = new ScheduledWidgetSelectionPolicy.Candidate("gap", "scheduled:gap:2026-10-21", 150,
                210 * 60_000L, false, true, false, false);
        var realThree = new ScheduledWidgetSelectionPolicy.Candidate("real", "scheduled:real:2026-10-21", 180,
                180 * 60_000L, false, true, false, false);
        expect(ScheduledWidgetSelectionPolicy.select(Arrays.asList(normalizedGap, realThree)) == realThree,
                "normalized spring-gap departure sorts by actual epoch, ahead of a normalized later time");

        var allCheckedButActive = active("a", "scheduled:a:2026-10-21", 600, true);
        expect(ScheduledWidgetSelectionPolicy.select(Arrays.asList(later, allCheckedButActive)) == allCheckedButActive,
                "an active packed occurrence remains selected until explicit Finish");

        var completed = new ScheduledWidgetSelectionPolicy.Candidate("a", "scheduled:a:2026-10-21", 600,
                true, false, true, false);
        var skipped = new ScheduledWidgetSelectionPolicy.Candidate("b", "scheduled:b:2026-10-21", 700,
                true, false, false, true);
        expect(ScheduledWidgetSelectionPolicy.select(Collections.singletonList(completed)) == completed,
                "completed occurrence remains available as a read-only projection");
        expect(!ScheduledWidgetSelectionPolicy.mayOpenOuting(true, true, true, true, true, false, false, true),
                "skipped occurrence cannot be reopened");
        expect(ScheduledWidgetSelectionPolicy.mayOpenOuting(true, true, true, true, true, false, true, false),
                "exact completed occurrence may open read-only");
        expect(ScheduledWidgetSelectionPolicy.mayOpenOuting(true, true, true, true, true, true, false, false),
                "exact active occurrence may open");
        expect(!ScheduledWidgetSelectionPolicy.mayOpenOuting(false, true, true, true, true, true, false, false),
                "another widget provider cannot open the scheduled occurrence");
        expect(!ScheduledWidgetSelectionPolicy.mayOpenOuting(true, false, true, true, true, true, false, false),
                "rebound widget rejects its old open action");
        expect(ScheduledWidgetSelectionPolicy.select(Collections.singletonList(skipped)) == skipped,
                "skipped occurrence remains available for a skipped status view");

        expect(ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, true, true, true,
                        5, 6, 4, 4, false, true),
                "current active occurrence accepts its desired check under item revision mask");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(false, true, true, true, true, true,
                        5, 6, 4, 4, false, true),
                "another provider cannot apply a scheduled check");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, false, true, true, true, true,
                        5, 6, 4, 4, false, true),
                "rebound widget rejects its old check action");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, true, true, true,
                        5, 6, 4, 4, true, true),
                "replayed desired value is idempotently rejected");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, true, false, true,
                        5, 6, 4, 4, false, true),
                "stale tap cannot modify another current projection");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, false, true, true, true,
                        5, 6, 4, 4, false, true),
                "state reset epoch rejects a rendered check");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, false, true, true,
                        5, 6, 4, 4, false, true),
                "yesterday occurrence cannot receive a scheduled widget check");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, true, true, false,
                        5, 6, 4, 4, false, true),
                "completed or skipped occurrence cannot receive a check");
        expect(!ScheduledWidgetSelectionPolicy.mayApplyCheck(true, true, true, true, true, true,
                        5, 6, 4, 5, false, true),
                "newer item revision rejects stale desired value");
        System.out.println("ScheduledWidgetSelectionPolicy: " + checks + " checks passed");
    }

    private static ScheduledWidgetSelectionPolicy.Candidate active(String scheduleId, String outingId,
                                                                    int departureMinute, boolean overdue) {
        return new ScheduledWidgetSelectionPolicy.Candidate(scheduleId, outingId, departureMinute,
                overdue, true, false, false);
    }

    private static void expect(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        checks++;
        System.out.println("PASS " + name);
    }
}
