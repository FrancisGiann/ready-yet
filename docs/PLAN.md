# Ready Yet? — implementation plan

Ready Yet? (tagline: Before I Leave) is an original, free, private Android outing checklist. No account, server, ads, location, payments or tracking. Source is staged in the delegated workspace and copied into the newly created sibling project before delivery. The accepted 1.0.1 enhancement scope is recorded in [UPDATE_1_0_1.md](UPDATE_1_0_1.md).

## Product contract

Reusable School, Work, Gym, Trip and custom checklists are blueprints. Starting an outing copies items into a fresh session; unfinished sessions remain resumable. Blueprint edits never silently change an existing outing. Check/uncheck is immediate. Finish is explicit, requires every item checked, and can be undone. Empty lists invite an item before starting. Sessions carry a local calendar date; dated extras attach only to that date and checklist. A dated extra is not consumed by preview or by a cancelled start.

## Design system

Warm porcelain background, deep ink text, acid-lime signature, desaturated lilac/sky/peach secondary accents. Dark mode uses soft charcoal and luminous lime. Three cohesive accent themes. Editorial large headings, compact uppercase eyebrows, readable body copy. Rounded tray surfaces and crisp line icons. Minimum 48dp tap targets, visible labels, text scaling, accessible checked semantics. The original bag/tray illustration is drawn in Flutter so it scales sharply and requires no network assets. Checking tucks a small essential toward the bag; after a successfully saved explicit Finish, a short seal confirms completion. Reduced motion follows system preference or app override.

## Core screens

1. Practice onboarding, with an interactive sample that does not alter real lists.
2. Today: resume unfinished outings, choose a reusable checklist, date-specific extras.
3. Pack: large check rows, tray progress, add session-only items, edit, remove, reorder, finish/undo.
4. Lists: edit, reorder, create/rename/delete with clear confirmation; reusable items and dated extras.
5. History: completed outings with reopen/undo and dismissed outings with persistent Restore.
6. Settings: system/light/dark, accent, haptics, reduced motion, optional local reminder, tutorial replay and privacy explanation.

## Technical decisions

Installed Flutter/Dart, minimal dependency surface. Immutable serialized domain objects and ChangeNotifier controller. Native Android MethodChannel for atomic private JSON persistence, backup recovery, inexact AlarmManager reminders, Android 13 notification consent requested only from the reminder flow, reboot rescheduling, two independently configured home-screen widgets and a launcher shortcut. Explicit check/lifecycle transaction masks reconcile app and widget state safely. No exact alarm permission. Android reminder times are approximate and may be delayed by the OS. Denial leaves core usable and informs the user. No changes to device settings.

## Milestones and acceptance

Write this plan before implementing. Parallel owners: domain/controller + tests; Android gateway/storage/reminders/widget + icon; onboarding/illustration; root owns design and complete screen integration. Then analyze and domain/widget tests; rendered screens at 360×800 and 430×932 in both themes plus scaled text; repeated toggles, modal cancellation/back, durable reload, multiple outings, dated extras, reminder denial/overdue/timezone logic. Build release APK, inspect package/version/permissions/icon, sign and verify using local debug signing for private sideload distribution. Preserve a source snapshot and concise feature/QA guides. Upload the final APK and a few actual rendered screens to Library, returning confirmed IDs. No public publishing.
