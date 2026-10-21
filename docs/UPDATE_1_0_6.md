# Ready Yet? 1.0.6+7

The new Scheduled checklist Android widget follows the actual checklist occurrence due today. It shows the checklist name, packed progress and due time, with next-time metadata when nothing is scheduled today. It retains the existing manual checklist and Quick Lists widgets and their larger layouts.

Item taps set an explicit checked value through the canonical native store. Provider ownership, widget binding generation, storage epoch, current day, selected occurrence and item revision are validated. Replayed or stale actions cannot toggle a template, another daily occurrence or completed history. Packing every item does not automatically finish the outing. Quick-open targets the exact active or completed occurrence; setup and no-today states open Schedules.

Schedule wake, date/timezone changes and boot rescheduling refresh all widget kinds. Android may delay refresh under Doze or force-stop; displayed times are absolute rather than guaranteed live countdowns. Small cards show only rows that fit. At minimum size or extreme font scales, labels/time may ellipsize, while full descriptions and quick-open remain available.

## Validation

- The initial scheduled-widget candidate passed all 94 Flutter tests. The final About metadata correction passed 12 focused Flutter checks: four channel/controller/branding/fallback cases, seven scheduled-widget launch regressions and one actual-package-metadata render case covering light/dark. Flutter analysis found no issues. The full suite was not rerun after this minimal read-only metadata correction.
- 227 focused Java widget-policy assertions passed, including 19 new selection/freshness assertions.
- Release APK compiled; release lint reported zero errors and 94 warnings.
- Seven Robolectric API 35 tests used production release-compiled classes and packaged APK resources. Coverage includes actual private-receiver PendingIntent delivery, desired-value replay, stale epoch/binding/day rejection, exact open/reopen, installed provider refresh, timezone broadcast refresh, captured-day/DST selection, retained history and the production About helper reading actual installed APK package metadata.
- Fourteen native RemoteViews captures cover empty/no-today/no-schedules/completed/skipped/multiple schedules, long titles, light/dark configurations, 110/130/156dp compact layouts, larger/wide resizing and font scales 1/1.5/2/3. Visible row/footer targets remain at least 48dp and footers fit their bounds. The due line fits unellipsized at the standard 156dp compact size.
- APK signature and 16KiB alignment verified. Package `dev.giann.before_i_leave`, version name `1.0.6`, version code `7`, ARM64, Android API24+. Signing certificate SHA-256: `b33178ae6305c6776f3971fda246c7f4738200830e5ad1d1709983b3c855ab63`, matching previous releases.

Physical install/upgrade, OEM launcher/picker/pin, TalkBack, real reboot/Doze and real foreground/background Flutter engine timing were not tested. Host captures are synthetic renders, not device screenshots. The app has no automatic GitHub updater; Android package/signature/version-code compatibility was checked for manual upgrades.

## Published binary provenance

The final APK was rebuilt serially after replacing the inherited hardcoded About display with a read-only PackageManager version/build metadata path. It displays 1.0.6+7, with a brand-only fallback when metadata is unavailable. Source pubspec and native APK metadata both declare 1.0.6+7. Existing signing, package, schedules, history and storage are preserved. Host native metadata extraction and Flutter renders verified the displayed version; a physical-device install was not performed.

APK: `Ready-Yet-1.0.6-arm64-v8a.apk`, 18,918,726 bytes.
SHA-256: `32d6ff203192a8c97cf58567538411b56af7d01ec377ddc5a07b66633cbac929`.
