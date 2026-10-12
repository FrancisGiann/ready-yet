# Update 1.0.1 scope

The existing app styling is positively received and remains the design reference. The app name, package and signing identity remain unchanged pending a separate naming decision. This is a private sideload update; no publishing is authorized.

## Recoverable outing dismissal

Today resume cards expose **Dismiss outing**, with Undo. Dismissal saves a timestamp on the outing, hides it from active/resume views, and retains every item and check. History offers a separate dismissed section with Restore outing, so recovery remains possible after restart or an expired Snackbar. Reusable lists and completed history are unaffected. Starting that list again creates a fresh outing and never silently restores a dismissed one.

## Widgets

Two complementary widgets are authorized: an interactive checklist with packing progress and a compact multi-list quick-access widget. Each widget instance has its own list selection. Existing widget instances remain usable after the update. Refreshing or resizing cannot create an outing; only an explicit start action can. Resume actions must select the correct active outing and respect dismissals, deleted lists, local dates and dated extras.

Native item changes set an explicit checked value on an existing active outing. Completed and dismissed outings are protected. The shared persistence protocol must preserve widget changes when Flutter saves an unrelated edit, preserve explicit later app checks, reconcile a running app, and avoid claiming a finish if a concurrent uncheck makes the outing incomplete. Private storage remains atomic; no new sensitive permissions or server are needed.

Widget typography, color, corners, labeled actions and large touch targets follow the app. Android widgets use supported RemoteViews interactions and resize behavior; the app's spring animation is not promised in a launcher widget. Android 7+ remains supported, with fallbacks for newer APIs.

## Acceptance and delivery

Focused tests cover dismissal/Undo/restore/restart, sibling and completed history isolation, fresh starts, widget empty/deleted/dismissed states, per-instance selection, repeated/stale actions, concurrent check and app edits, storage failures and resize projections. Rendered previews cover small/large configurations, both themes and large text. Native tests and source review supplement compile checks where no device or launcher is available; previews are labeled accurately.

Deliver version 1.0.1/code 2 using the same package and certificate. Build a small ARM64 APK with complete assets, preserve the previous artifacts, and replace the existing ARM64 Library file to retain its version history. Update the source archive and relevant screenshots with confirmed Library results.
