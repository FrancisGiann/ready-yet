# Native widget redesign — Ready Yet? 1.0.2+3

## Goal

Replace the current oversized checklist and plain-text quick-list Android widgets with compact, branded native RemoteViews. Preserve the app package, widget providers, storage schema and revision guards, preferences, actions, and PendingIntent protections. Keep the praised Flutter app screen and bag icon intact.

## Design direction

- Brand the widgets as **Ready Yet?** with **Before I Leave** as a quiet context label.
- Use a compact header, a concise packing summary without raw ISO dates, a restrained accent progress cue, and well-spaced checklist rows.
- Keep each checklist row's interactive target at least 48dp, with a high-contrast illustrated checked/unchecked state.
- Show every item that fits the actual widget bounds, using width, available height, and font scale rather than a fixed two-row cap. Limit rendered rows to five and give a clear overflow action when more remain.
- Give quick lists individual visual tiles, a small original bag/list mark, and readable progress badges. Provide compact and wider arrangements.
- Check light and dark palettes, larger text, contrast, clipping, and density using rendered native layouts.

## Owned files

Native Android widget resources and code: the two app-widget provider XML files, checklist and quick-list RemoteViews layouts and drawables, widget colors/styles/strings, `NativeWidgetProjection`, `LeaveWidgetProvider`, `WidgetConfigurationActivity` where needed, and the Java resize policy/QA helpers. Any changes must keep the current `NativeStateStore` protocol and every intent/action contract unchanged.

## Rendering and validation

Inspect the supplied screenshot only around the widget itself. Do not reuse personal wallpaper or include it in assets or QA uploads. Determine whether this machine has a usable Android system image, emulator, or native layout renderer. Capture actual RemoteViews renders across useful sizes and themes if available; otherwise record the exact toolchain limitation and avoid presenting Flutter output as a native widget render. After the design is frozen by the parent task owner, build the release APK offline and verify package/version, ABI, signer, size, and permissions.

## Sizing and compact behavior

- Publish the independently budgeted landscape and portrait RemoteViews together, using the supported API16 constructor. Select each real widget option pair: portrait uses minimum width with maximum height; landscape uses maximum width with minimum height. Unknown orientation conservatively uses minimum bounds. `AppWidgetProviderInfo.minWidth/minHeight` pixel fallbacks are converted back to dp using display density.
- Checklist rows remain 48dp targets (50dp pitch with breathing room), with a maximum of five. Quick-list tiles remain 48dp targets and show up to four. Capacity accounts for font scale and may use the compact resource when it fits more rows.
- Compact layouts hide the tagline and progress cue before sacrificing the tappable footer. If no checklist row fits, the list title moves into the footer label; quick lists keep the “Manage quick lists” action. Every footer is at least 48dp.
- Checked marks use a rounded lime fill with a dark outline and tick; unchecked marks use matching rounded corners and a high-contrast outline. Row descriptions carry full item/list labels for accessibility when visible text is ellipsized.

## Environment and verification

- Android SDK platforms 35, 36, and 36.1 and the emulator executable are installed.
- `emulator -list-avds` currently returns no configured AVD.
- No Android system image is installed. Android Studio Panda is installed at `/home/francisgiann/.local/share/JetBrains/Toolbox/apps/android-studio`; its Layoutlib is the available native-rendering path.
- The original widget implementation used static `RemoteViews` with fixed-height switching and a two-row rendering cap.
- The pure-JVM widget merge/launch/resize policies pass, including portrait/landscape option pairing, density-3 fallback conversion, compact-footer capacity, and the three-item/four-list portrait target. Full offline Android resource processing, Flutter/native Kotlin/Java compilation, and `lintRelease` pass.
- Current pure-Java QA comprises 15 widget-merge, 8 widget-launch, 55 widget-resize, and 18 reminder assertions (96 total). The resize suite has 30 loop assertions and 25 standalone capacity/orientation/density assertions.
- See [native widget QA](../qa/native-widget-renders/README.md) for the rendering mechanism, captured cases and limits. Flutter widget-guide images remain app previews.
