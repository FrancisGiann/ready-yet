import dev.giann.before_i_leave.WidgetResizePolicy;

public final class WidgetResizePolicyCheck {
    public static void main(String[] args) {
        int[] heights = {112, 156, 200, 260, 275, 360, 480};
        int[] checklistRows = {0, 1, 1, 3, 3, 5, 5};
        for (int i = 0; i < heights.length; i++) {
            int height = heights[i];
            int rows = WidgetResizePolicy.checklistRows(330, height, 1f);
            boolean compact = WidgetResizePolicy.checklistUsesCompactLayout(330, height, 1f);
            expect(checklistRows[i] == rows, "checklist row budget at " + height + "dp");
            expect(WidgetResizePolicy.checklistRequiredHeight(330, rows, 1f, compact) <= height,
                    "checklist content fits at " + height + "dp");
        }

        int[] quickHeights = {88, 112, 156, 200, 260, 275, 360, 480};
        int[] quickRows = {0, 0, 1, 2, 3, 4, 4, 4};
        for (int i = 0; i < quickHeights.length; i++) {
            int height = quickHeights[i];
            int rows = WidgetResizePolicy.quickListRows(330, height, 1f);
            boolean compact = WidgetResizePolicy.quickListsUsesCompactLayout(330, height, 1f);
            expect(quickRows[i] == rows, "quick-list row budget at " + height + "dp");
            expect(WidgetResizePolicy.quickListsRequiredHeight(330, rows, 1f, compact) <= height,
                    "quick-list content fits at " + height + "dp");
        }

        expect(WidgetResizePolicy.checklistRows(330, 275, 1f) == 3,
                "330x275dp checklist shows all three sample items");
        expect(WidgetResizePolicy.quickListRows(330, 275, 1f) == 4,
                "330x275dp quick list shows all four configured lists");
        expect(WidgetResizePolicy.checklistRows(330, 275, 1.2f) >= 2,
                "larger checklist text keeps a safe visible row budget");
        expect(WidgetResizePolicy.quickListRows(330, 275, 2f) == 3,
                "large quick-list text reduces visible rows safely");
        expect(WidgetResizePolicy.checklistUsesCompactLayout(180, 112, 1f),
                "minimum checklist uses compact summary layout");
        expect(!WidgetResizePolicy.checklistUsesCompactLayout(330, 275, 1f),
                "wide checklist uses full row layout");
        expect(WidgetResizePolicy.quickListsUsesCompactLayout(180, 275, 1f),
                "narrow quick list uses compact layout");

        // Pixel 5x3 option bounds: portrait is 349x337dp; landscape is 697x184dp.
        expect(WidgetResizePolicy.availableWidthDp(349, 697, WidgetResizePolicy.ORIENTATION_PORTRAIT) == 349,
                "portrait width uses its actual option bound");
        expect(WidgetResizePolicy.availableHeightDp(184, 337, WidgetResizePolicy.ORIENTATION_PORTRAIT) == 337,
                "portrait height uses its actual option bound");
        expect(WidgetResizePolicy.availableWidthDp(349, 697, WidgetResizePolicy.ORIENTATION_LANDSCAPE) == 697,
                "landscape width uses its actual option bound");
        expect(WidgetResizePolicy.availableHeightDp(184, 337, WidgetResizePolicy.ORIENTATION_LANDSCAPE) == 184,
                "landscape height uses its actual option bound");
        expect(WidgetResizePolicy.checklistRows(349, 337, 1f) >= 3,
                "portrait widget height shows the three-item checklist");
        expect(WidgetResizePolicy.quickListRows(349, 337, 1f) == 4,
                "portrait widget height shows four configured quick lists");
        int landscapeChecklistRows = WidgetResizePolicy.checklistRows(697, 184, 1f);
        int landscapeQuickRows = WidgetResizePolicy.quickListRows(697, 184, 1f);
        expect(landscapeChecklistRows == 1,
                "landscape checklist gets its own short-height row budget");
        expect(landscapeQuickRows == 2,
                "landscape quick lists get their own short-height row budget");
        expect(WidgetResizePolicy.checklistRequiredHeight(697, landscapeChecklistRows, 1f,
                        WidgetResizePolicy.checklistUsesCompactLayout(697, 184, 1f)) <= 184,
                "landscape checklist never exceeds its landscape height bound");
        expect(WidgetResizePolicy.quickListsRequiredHeight(697, landscapeQuickRows, 1f,
                        WidgetResizePolicy.quickListsUsesCompactLayout(697, 184, 1f)) <= 184,
                "landscape quick lists never exceed their landscape height bound");
        expect(WidgetResizePolicy.availableWidthDp(349, 697, 0) == 349,
                "unknown orientation uses conservative width bound");
        expect(WidgetResizePolicy.availableHeightDp(184, 337, 0) == 184,
                "unknown orientation uses conservative height bound");
        expect(WidgetResizePolicy.availableWidthDp(0, 180) == 180,
                "single valid width bound remains usable");
        expect(WidgetResizePolicy.availableHeightDp(0, 112) == 112,
                "single valid height bound remains usable");
        expect(WidgetResizePolicy.pixelsToDpFloor(540, 3f) == 180,
                "AppWidgetProviderInfo minWidth fallback converts pixels to dp");
        expect(WidgetResizePolicy.pixelsToDpFloor(336, 3f) == 112,
                "AppWidgetProviderInfo minHeight fallback converts pixels to dp");
        expect(WidgetResizePolicy.checklistRows(330, 112, 2f) == 0,
                "short large-text checklist keeps its action without clipping rows");
        expect(WidgetResizePolicy.quickListRows(180, 88, 2f) == 0,
                "minimum large-text quick widget preserves its action");
        System.out.println("WidgetResizePolicy: all size, orientation, font-scale, and capacity checks passed");
    }

    private static void expect(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
        System.out.println("PASS " + name);
    }
}
