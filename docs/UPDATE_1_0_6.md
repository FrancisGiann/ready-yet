# Ready Yet? 1.0.6+7

The new Scheduled checklist Android widget follows the actual checklist occurrence due today. It shows the checklist name, packed progress and due time, with next-time metadata when nothing is scheduled today. It retains the existing manual checklist and Quick Lists widgets and their larger layouts.

Item taps set an explicit checked value through the canonical native store. Provider ownership, widget binding generation, storage epoch, current day, selected occurrence and item revision are validated. Replayed or stale actions cannot toggle a template, another daily occurrence or completed history. Packing every item does not automatically finish the outing. Quick-open targets the exact active or completed occurrence; setup and no-today states open Schedules.

Schedule wake, date/timezone changes and boot rescheduling refresh all widget kinds. Android may delay refresh under Doze or force-stop; displayed times are absolute rather than guaranteed live countdowns. Small cards show only rows that fit. At minimum size or extreme font scales, labels/time may ellipsize, while full descriptions and quick-open remain available.

## Validation

- 94 Flutter tests passed, including seven scheduled-widget launch cases; Flutter analysis found no issues.
- 227 focused Java widget-policy assertions passed, including 19 new selection/freshness assertions.
- Release APK compiled; release lint reported zero errors and 94 warnings.
- Six Robolectric API 35 tests used production release-compiled classes and packaged APK resources. Coverage includes actual private-receiver PendingIntent delivery, desired-value replay, stale epoch/binding/day rejection, exact open/reopen, installed provider refresh, timezone broadcast refresh, captured-day/DST selection and retained history.
- Fourteen native RemoteViews captures cover empty/no-today/no-schedules/completed/skipped/multiple schedules, long titles, light/dark configurations, 110/130/156dp compact layouts, larger/wide resizing and font scales 1/1.5/2/3. Visible row/footer targets remain at least 48dp and footers fit their bounds. The due line fits unellipsized at the standard 156dp compact size.
- APK signature and 16KiB alignment verified. Package `dev.giann.before_i_leave`, version name `1.0.6`, version code `7`, ARM64, Android API24+. Signing certificate SHA-256: `b33178ae6305c6776f3971fda246c7f4738200830e5ad1d1709983b3c855ab63`, matching previous releases.

Physical install/upgrade, OEM launcher/picker/pin, TalkBack, real reboot/Doze and real foreground/background Flutter engine timing were not tested. Host captures are synthetic renders, not device screenshots. The app has no automatic GitHub updater; Android package/signature/version-code compatibility was checked for manual upgrades.

## Published binary provenance

The existing verified signed candidate is reused without rebuilding or re-signing. It was built with version flags 1.0.6+7; source pubspec metadata now declares the same values. App implementation files match that candidate. The inherited About-screen display string remains 1.0.3 in both source and binary; Android installation metadata is 1.0.6+7. Updating that display text would require a separately tested rebuild.

APK: `Ready-Yet-1.0.6-arm64-v8a.apk`, 18,918,726 bytes.
SHA-256: `f37ab17e8643b1f02adab7275e8a8d98563abd8b1091da2ff17d4a060fd44ccd`.
