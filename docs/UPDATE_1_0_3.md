# Ready Yet? 1.0.3

Version 1.0.3 adds clearer carry-item pictograms and safer outing recovery while keeping existing lists and outing history readable.

## Carry-item pictograms

The item picker now offers 26 distinct choices, including an ID card and a custom perfume-bottle drawing. It also exposes useful existing carry symbols for notebooks, towels, medicine, glasses, passports, and travel, plus hand sanitizer and soap. Existing saved keys and their glyphs remain supported, including legacy `keys`, `shoes`, `spark`, and unknown saved keys. Editing an existing `keys` item keeps its value unless a different choice is selected.

The item choices have spoken labels and selectable semantics. Saving disables duplicate submissions, and item editing remains usable with a keyboard, large text, dark mode, and reduced-motion settings.

## Outing completion and recovery

After saving a finish, the primary action now returns to Today. A separate **Reopen outing** action intentionally resumes that completed outing with its checkmarks. The system Back action only navigates; it does not finish, reopen, or dismiss an outing. Reopening stays disabled until its durable save succeeds, and a failed save keeps the finished History entry available for retry. Starting the same reusable list from Today creates a fresh outing.

History explains the difference between resuming a completed outing and starting a new one. It does not open an optimistic outing after a failed save or after the user navigates away while a reopen is pending.

## Compatibility and validation

Package `dev.giann.before_i_leave`, minimum Android API 24, and signing certificate remain unchanged. This local ARM64 release is version `1.0.3` / code `4`.

The Android resource merger previously rejected two definitions of `launcher_background`: the same `#F5F2EA` color appeared in `res/color/launcher_background.xml` and `res/values/colors.xml`. The redundant color resource was removed; the values resource and launcher icon references remain.

Flutter tests, Java widget/reminder policy checks, Android resource processing, Kotlin compilation, release lint, and Layoutlib label renders passed. No Android handset or emulator was available, so these checks do not claim launcher/device runtime coverage. See the 1.0.3 QA notes and APK verification report for details.
