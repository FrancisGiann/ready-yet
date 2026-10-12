package dev.giann.before_i_leave;

/** Pure authorization policy for actions launched by a configured widget. */
public final class WidgetLaunchPolicy {
    private WidgetLaunchPolicy() {}

    /** Render dates are intentionally not part of this check; Dart chooses the action-time local date. */
    public static boolean canOpenList(
            boolean providerOwned,
            boolean bindingMatches,
            boolean selectionMatches,
            boolean blueprintExists) {
        return providerOwned && bindingMatches && selectionMatches && blueprintExists;
    }

    /** Existing outings open only when that exact active outing is still displayed by this widget. */
    public static boolean canOpenOuting(
            boolean providerOwned,
            boolean bindingMatches,
            boolean selectionMatches,
            boolean active,
            boolean exactProjectionMatch) {
        return providerOwned && bindingMatches && selectionMatches && active && exactProjectionMatch;
    }

    public static String invalidLaunchFallback() {
        return "widget_today";
    }
}
