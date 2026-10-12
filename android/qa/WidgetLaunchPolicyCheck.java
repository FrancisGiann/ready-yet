import dev.giann.before_i_leave.WidgetLaunchPolicy;

public final class WidgetLaunchPolicyCheck {
    public static void main(String[] args) {
        expect(WidgetLaunchPolicy.canOpenList(true, true, true, true),
                "yesterday-rendered list action remains valid when its current selection still exists");
        expect(!WidgetLaunchPolicy.canOpenList(true, true, true, false),
                "deleted list cannot create an outing from a stale widget action");
        expect(!WidgetLaunchPolicy.canOpenList(true, false, true, true),
                "reconfigured widget rejects a stale binding generation");
        expect(!WidgetLaunchPolicy.canOpenList(false, true, true, true),
                "foreign widget provider cannot launch a list action");
        expect(WidgetLaunchPolicy.canOpenOuting(true, true, true, true, true),
                "exact active outing still displayed by widget may open");
        expect(!WidgetLaunchPolicy.canOpenOuting(true, true, true, true, false),
                "widget cannot redirect to a different active outing");
        expect(!WidgetLaunchPolicy.canOpenOuting(true, true, true, false, true),
                "completed or dismissed outing cannot reopen from a stale widget action");
        expect("widget_today".equals(WidgetLaunchPolicy.invalidLaunchFallback()),
                "invalid widget launch safely falls back to Today");
        System.out.println("WidgetLaunchPolicy: 8 checks passed");
    }

    private static void expect(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        System.out.println("PASS " + name);
    }
}
