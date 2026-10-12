# Widget assessment and update contract

## Previous release

The original widget is a read-only global snapshot: the latest unfinished outing's name and packed count, or the latest outing when none is unfinished. Tapping opens Today normally; the separate Pack for today launcher shortcut resumes the newest unfinished outing. Every widget instance shows the same summary. Minimum requested dimensions are 180×88dp, with horizontal/vertical resizing but one fixed layout. Refresh occurs after app saves, app resume, launcher update and size change; updatePeriodMillis is zero.

There is no item checking, list picker, per-instance selection or configuration activity in that release. App state is private JSON; the widget summary is embedded in its atomic commit and read asynchronously.

## Authorized enhancement

The user requested both an interactive checklist widget and compact quick access to multiple lists. Keep the existing widget provider identity for upgrades, add a second quick-list provider, and configure each instance independently using stable list IDs. Use fixed RemoteViews rows with clear access to overflow items: this supports Android 7+ and explicit immutable PendingIntents without adding a collection service. Compact layouts show progress and a clear resume/start action; larger sizes show more rows. Refresh/configuration/resizing never starts an outing.

List start/resume actions launch Dart, where current local dates, one-off extras and fresh-session rules already live. Direct widget actions set an explicit check value on an exact existing active outing/item. Completed, dismissed, missing and stale bindings are protected. No native widget command changes a reusable list or finishes/creates/dismisses an outing.

## Shared-state correctness

Native code owns only external item checks. Dart owns structure and lifecycle. Native application writes accept base/target JSON plus explicit check and lifecycle intent masks. Existing checks and the completion/dismissal tuple retain canonical values unless an eligible intent changes them. New nodes initialize from validated target data. One NativeStateStore lock covers read, merge, validation and atomic commit.

Dart retains unacknowledged intents across failures, tracks local check/lifecycle/membership generations, and filters already acknowledged generations at dispatch. It caches the newest canonical revision even when local changes temporarily obscure it; old acknowledgements resolve their intent generations without replacing newer canonical observations. The current UI is recomputed from canonical data plus remaining local intents. Rejected finishes resolve their intent and return an active outing, preventing queued snapshots from silently finishing it later.

Every progress projection comes from the committed canonical state. Sidecar or refresh errors after that authoritative commit cannot report the state write as failed. Reset establishes a new reconciliation baseline. Widget actions validate exact IDs, per-instance binding identity and active membership; they never retarget an old action to the newest outing.

## Platform evidence and limits

Android's official guidance supports configuration activities, responsive widget dimensions, and widget item actions. Collection views require fill-in intents and a mutable PendingIntent template; RemoteCollectionItems simplifies collections on API 31+, but does not remove that action requirement. Fixed rows avoid those API/version differences for this bounded checklist surface.

- https://developer.android.com/develop/ui/views/appwidgets/overview
- https://developer.android.com/develop/ui/views/appwidgets/configuration
- https://developer.android.com/develop/ui/views/appwidgets/collections
- https://developer.android.com/reference/android/widget/RemoteViews

A fresh read-only ADB inventory succeeded and found no connected Android devices and no configured AVDs. Native widget layouts, launcher resizing and host behavior therefore have compile/source evidence plus labeled Flutter previews; they cannot be described as phone-tested here.
