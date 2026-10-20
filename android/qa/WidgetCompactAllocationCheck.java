import dev.giann.before_i_leave.WidgetResizePolicy;

/** Representative 2×2 allocations and enlarged text, plus larger-widget regression guarantees. */
public final class WidgetCompactAllocationCheck {
    public static void main(String[] args) {
        expect(WidgetResizePolicy.checklistRows(110, 110, 1f) == 1, "110×110dp keeps one checkable item");
        expect(WidgetResizePolicy.checklistRows(130, 130, 1f) == 1, "130×130dp keeps one checkable item");
        expect(WidgetResizePolicy.quickListRows(110, 110, 1f) == 1, "110×110dp keeps one list shortcut");
        expect(WidgetResizePolicy.checklistRows(130, 220, 1f) == 3, "tall 2×2 checklist expands to three items");
        expect(WidgetResizePolicy.quickListRows(130, 220, 1f) == 3, "tall 2×2 quick list expands to three shortcuts");
        expect(!WidgetResizePolicy.usesTwoByTwoLayout(349, 337), "existing large portrait layout preserved");
        expect(WidgetResizePolicy.checklistRows(349, 337, 1f) == 4, "large checklist capacity preserved");
        expect(WidgetResizePolicy.quickListRows(349, 337, 1f) == 4, "large quick-list capacity preserved");
        expect(WidgetResizePolicy.checklistRows(110, 110, 2f) == 0, "2× text prioritizes readable footer at minimum size");
        expect(WidgetResizePolicy.checklistRows(130, 130, 2f) == 1, "2× text keeps a checkable row when it fits");
        int[][] sizes = {{110,110},{130,117},{130,130},{156,156},{180,180},{130,220},{269,117},{330,275},{349,337},{697,184}};
        float[] scales = {0.85f,1f,1.3f,1.5f,2f,3f};
        for (int[] size : sizes) for (float scale : scales) {
            int checks = WidgetResizePolicy.checklistRows(size[0],size[1],scale);
            int lists = WidgetResizePolicy.quickListRows(size[0],size[1],scale);
            expect(WidgetResizePolicy.checklistRequiredHeight(size[0],size[1],checks,scale,
                    WidgetResizePolicy.checklistUsesCompactLayout(size[0],size[1],scale)) <= size[1],
                    "checklist fits " + size[0] + "×" + size[1] + " at " + scale + "× text");
            expect(WidgetResizePolicy.quickListsRequiredHeight(size[0],size[1],lists,scale,
                    WidgetResizePolicy.quickListsUsesCompactLayout(size[0],size[1],scale)) <= size[1],
                    "quick lists fit " + size[0] + "×" + size[1] + " at " + scale + "× text");
        }
        System.out.println("WidgetCompactAllocation: all 130 compact and larger-widget assertions passed");
    }
    private static void expect(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        System.out.println("PASS " + message);
    }
}
