package dev.giann.before_i_leave;

/** Bounds native rows to one real orientation's widget size and the user's text scale. */
public final class WidgetResizePolicy {
    // These numeric values match android.content.res.Configuration without requiring Android in JVM policy checks.
    public static final int ORIENTATION_PORTRAIT = 1;
    public static final int ORIENTATION_LANDSCAPE = 2;

    private static final int MAX_CHECKLIST_ROWS = 5;
    private static final int MAX_QUICK_LIST_ROWS = 4;
    private static final int CHECKLIST_ROW_PITCH_DP = 50; // 48dp target plus its 2dp breathing room.
    private static final int QUICK_ROW_MIN_DP = 48;

    private WidgetResizePolicy() {}

    /** Widget options describe the portrait width and landscape width, not a rectangle. */
    public static int availableWidthDp(int minWidthDp, int maxWidthDp, int orientation) {
        if (orientation == ORIENTATION_PORTRAIT) return positiveOr(minWidthDp, maxWidthDp);
        if (orientation == ORIENTATION_LANDSCAPE) return positiveOr(maxWidthDp, minWidthDp);
        return positiveMin(minWidthDp, maxWidthDp);
    }

    /** Portrait pairs minWidth with maxHeight; landscape pairs maxWidth with minHeight. */
    public static int availableHeightDp(int minHeightDp, int maxHeightDp, int orientation) {
        if (orientation == ORIENTATION_PORTRAIT) return positiveOr(maxHeightDp, minHeightDp);
        if (orientation == ORIENTATION_LANDSCAPE) return positiveOr(minHeightDp, maxHeightDp);
        return positiveMin(minHeightDp, maxHeightDp);
    }

    /** Unknown-orientation fallback remains conservative for callers without configuration. */
    public static int availableWidthDp(int minWidthDp, int maxWidthDp) {
        return positiveMin(minWidthDp, maxWidthDp);
    }

    public static int availableHeightDp(int minHeightDp, int maxHeightDp) {
        return positiveMin(minHeightDp, maxHeightDp);
    }

    public static int pixelsToDpFloor(int pixels, float density) {
        if (pixels <= 0 || Float.isNaN(density) || Float.isInfinite(density) || density <= 0f) return 0;
        return (int) Math.floor(pixels / density);
    }

    public static boolean checklistUsesCompactLayout(int widthDp, int heightDp, float fontScale) {
        int fullRows = rowsThatFit(heightDp, checklistBaseHeightDp(widthDp, fontScale), checklistRowPitchDp(fontScale), MAX_CHECKLIST_ROWS);
        int compactRows = rowsThatFit(heightDp, checklistCompactRowsBaseHeightDp(fontScale), checklistRowPitchDp(fontScale), MAX_CHECKLIST_ROWS);
        return widthDp < 260 || fullRows == 0 || compactRows > fullRows;
    }

    public static int checklistRows(int widthDp, int heightDp, float fontScale) {
        int pitch = checklistRowPitchDp(fontScale);
        int fullRows = rowsThatFit(heightDp, checklistBaseHeightDp(widthDp, fontScale), pitch, MAX_CHECKLIST_ROWS);
        int compactRows = rowsThatFit(heightDp, checklistCompactRowsBaseHeightDp(fontScale), pitch, MAX_CHECKLIST_ROWS);
        return widthDp < 260 ? compactRows : Math.max(fullRows, compactRows);
    }

    public static int checklistRequiredHeight(int widthDp, int visibleRows, float fontScale, boolean compact) {
        int rows = Math.max(0, Math.min(MAX_CHECKLIST_ROWS, visibleRows));
        int base = rows == 0 ? checklistCompactSummaryHeightDp(fontScale)
                : compact ? checklistCompactRowsBaseHeightDp(fontScale) : checklistBaseHeightDp(widthDp, fontScale);
        return base + checklistRowPitchDp(fontScale) * rows;
    }

    public static boolean quickListsUsesCompactLayout(int widthDp, int heightDp, float fontScale) {
        int fullRows = rowsThatFit(heightDp, quickListBaseHeightDp(widthDp, fontScale), quickListRowPitchDp(fontScale), MAX_QUICK_LIST_ROWS);
        int compactRows = rowsThatFit(heightDp, quickListCompactBaseHeightDp(fontScale), quickListRowPitchDp(fontScale), MAX_QUICK_LIST_ROWS);
        return widthDp < 260 || fullRows == 0 || compactRows > fullRows;
    }

    public static int quickListRows(int widthDp, int heightDp, float fontScale) {
        int pitch = quickListRowPitchDp(fontScale);
        int fullRows = rowsThatFit(heightDp, quickListBaseHeightDp(widthDp, fontScale), pitch, MAX_QUICK_LIST_ROWS);
        int compactRows = rowsThatFit(heightDp, quickListCompactBaseHeightDp(fontScale), pitch, MAX_QUICK_LIST_ROWS);
        return widthDp < 260 ? compactRows : Math.max(fullRows, compactRows);
    }

    public static int quickListsRequiredHeight(int widthDp, int visibleRows, float fontScale, boolean compact) {
        return (compact ? quickListCompactBaseHeightDp(fontScale) : quickListBaseHeightDp(widthDp, fontScale))
                + quickListRowPitchDp(fontScale) * Math.max(0, Math.min(MAX_QUICK_LIST_ROWS, visibleRows));
    }

    private static int checklistBaseHeightDp(int widthDp, float fontScale) {
        float scale = safeScale(fontScale);
        // Root padding, two-line brand, title/progress row, progress cue, row inset, and 48dp action.
        return 8 + Math.max(26, scaled(27, scale)) + 4 + Math.max(24, scaled(19, scale)) + 6 + 3 + 48 + 3;
    }

    private static int checklistCompactRowsBaseHeightDp(float fontScale) {
        float scale = safeScale(fontScale);
        // Compact omits tagline/progress cue but keeps title, 48dp action, and the first row inset.
        int brand = Math.max(24, scaled(14, scale));
        int title = Math.max(24, scaled(16, scale));
        return 4 + brand + 1 + title + 1 + 1 + 48;
    }

    private static int checklistCompactSummaryHeightDp(float fontScale) {
        float scale = safeScale(fontScale);
        int brand = Math.max(24, scaled(14, scale));
        // When no item row fits, the list title moves into the action; only brand + 48dp action remain.
        return 4 + brand + 1 + 48;
    }

    private static int quickListBaseHeightDp(int widthDp, float fontScale) {
        float scale = safeScale(fontScale);
        int verticalPadding = 12;
        int brandHeight = Math.max(26, scaled(27, scale));
        return verticalPadding + brandHeight + 2 + 1 + 48;
    }

    private static int quickListCompactBaseHeightDp(float fontScale) {
        float scale = safeScale(fontScale);
        int verticalPadding = scale >= 2.5f ? 4 : 8;
        int brandHeight = Math.max(24, scaled(12, scale));
        return verticalPadding + brandHeight + 1 + 1 + 48;
    }

    private static int quickListRowPitchDp(float fontScale) {
        // Two text lines plus the badge stay within the row at enlarged text scales.
        return Math.max(QUICK_ROW_MIN_DP, scaled(30, safeScale(fontScale)));
    }

    private static int checklistRowPitchDp(float fontScale) {
        return Math.max(CHECKLIST_ROW_PITCH_DP, scaled(18, safeScale(fontScale)) + 2);
    }

    private static int rowsThatFit(int heightDp, int baseHeightDp, int rowPitchDp, int maxRows) {
        return Math.max(0, Math.min(maxRows, (Math.max(0, heightDp) - baseHeightDp) / rowPitchDp));
    }

    private static int scaled(int dpAtDefaultScale, float scale) {
        return (int) Math.ceil(dpAtDefaultScale * scale);
    }

    private static float safeScale(float fontScale) {
        if (Float.isNaN(fontScale) || Float.isInfinite(fontScale)) return 1f;
        return Math.max(0.85f, Math.min(3f, fontScale));
    }

    private static int positiveOr(int preferred, int fallback) {
        return Math.max(0, preferred > 0 ? preferred : fallback);
    }

    private static int positiveMin(int first, int second) {
        if (first <= 0) return Math.max(0, second);
        if (second <= 0) return first;
        return Math.min(first, second);
    }
}
