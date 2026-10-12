# Design direction

## Identity

Ready Yet? — Before I Leave is the quiet moment before stepping out. A tidy packing tray makes progress tangible. The bag is a product illustration, with an intentional silhouette and material detail, rather than a character assembled from geometric shapes. There are no mascot eyes, stock avatars, borrowed Tarsi art or logos.

## Reference inspection

Public screenshots 1 and 2 from https://www.tarsi.cloud/ were downloaded and visually inspected on 11 October 2026 UTC. The Google Play listing https://play.google.com/store/apps/details?id=com.tarsi.app was also read. Screenshot 1 shows a contextual illustrated header, bold section titles, compact quick-action icons, rounded cards and a bottom navigation capsule. Screenshot 2 shows clearly grouped cards, restrained supporting labels and prominent values. These observations informed hierarchy, density and contextual feedback only. Ready Yet? uses its own colors, illustration, checklist interaction and information architecture.

## Interaction rules

- A whole checklist row is a large check target; labels remain visible after packing.
- Tapping twice toggles twice. Motion never locks a target or queues an extra check.
- Bag progress supplements the written item count and check state.
- Completion is an explicit action after packing; undo restores the original session.
- Start always creates an independent outing. Resuming preserves current checks.
- Editing a reusable list affects future outings. Session edits are clearly temporary.
- Date extras use local calendar dates and attach only to the matching outing date.
- Reduced motion and system accessibility preference shorten or remove decorative transitions.
- Settings and dialogs offer cancellation without changing data.

## Visual acceptance

Review actual Flutter pixels at small and large Android-shaped viewports in light and dark modes, plus large text. Check contrast, text wrap, tap target clarity, clipped cards, keyboard-safe editors, semantic check state, and bag silhouette. A Flutter render is not physical-phone verification. Include sampled motion evidence if no Android runtime is available.
