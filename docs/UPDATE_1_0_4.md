# Ready Yet? 1.0.4 — compact widgets

Both native widget providers now request 2×2 home-screen placement. The existing larger checklist and Quick Lists layouts remain available on resize. Provider class names, per-widget selections, package `dev.giann.before_i_leave`, saved-data format and signing configuration are preserved. Version 1.0.4/code 5 follows the completed 1.0.3/code 4 app, including ID card/Perfume choices and the Back to home completion flow.

The small checklist shows the available item rows with check controls and a separate quick-open action with the selected outing title, packed/total count and overflow hint. Quick Lists shows the selected list, packed/total status and its existing destination, with configuration in a separate action. At 110×110dp/default text one 48dp row fits alongside a 48dp action. Content adjusts to each launcher allocation and text size. At very large font scales the smallest allocation prioritizes the readable action; long titles ellipsize while complete accessibility descriptions remain available.

Android 12+ receives exact-size RemoteViews from the launcher's supplied sizes. Earlier hosts retain portrait/landscape views and orientation-aware size fallback. Sizing follows the [Android widget layout guidance](https://developer.android.com/develop/ui/views/appwidgets/layouts).

Validation completed for this update:

- Flutter analysis: no issues.
- Full Flutter regression suite: 74 tests passed, including widget launch/deep-link selection, duplicate-request handling, current completed features and persistence checks.
- Native policy scripts: 226 assertions passed (15 merge, 8 launch, 55 resize, 130 compact allocation, 18 reminder).
- 31 synthetic native Layoutlib renders passed bounds, vertical text-fit and 48dp tap-target checks. They cover empty/unavailable data, completed/all-packed states, long labels/titles, 0.85–3× policy font scales, light/dark themes, compact allocations, wide/tall resizing and retained larger layouts.
- Signed release ARM64 APK built as 1.0.4/code 5; API 24 minimum, API 36 target. `apksigner verify` passed and the certificate matches 1.0.3 exactly.

The existing release signing certificate SHA-256 is `b33178ae6305c6776f3971fda246c7f4738200830e5ad1d1709983b3c855ab63`. This verifies upgrade identity and version ordering; actual upgrade installation and saved-data behavior on a physical device were not exercised. The available API 35 x86_64 Android Test Device has an empty home activity and no usable widget launcher. Native fixture captures are not launcher screenshots and do not execute PendingIntents or `RemoteViews.apply()`. Real pinning/configuration, resize gestures, checklist taps, quick-open PendingIntents and multiple instances remain physical-launcher checks.

No commits, pushes, publication or releases were performed. Existing prior APKs and source archives were retained.
