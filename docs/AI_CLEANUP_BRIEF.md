# PerchHA AI Cleanup Brief

Use this brief when you work on PerchHA as a cleanup and simplification pass.

## Goal

Make the app feel lighter, simpler, and more predictable without removing any user-visible feature, workflow, setting, test surface, or Home Assistant capability.

This is not a redesign task.
This is not a feature-cut task.
This is not permission to replace working behavior with placeholders.

## Hard Constraints

- Keep all existing functionality and feature scope.
- Do not remove settings, controls, entity metadata, chart support, menu bar options, linked-entity averaging, threshold support, unit scaling, or update/release behavior.
- Prefer deletion of unnecessary glue, indirection, caches, observers, and interaction layers only when behavior stays the same or gets more reliable.
- Prefer boring native macOS behavior over clever SwiftUI/AppKit hybrids when the hybrid causes flakiness.
- Do not add AI references, provenance notes, or agent chatter to product docs, commits, or release artifacts.

## Primary Problems To Investigate

These user-reported issues are still unresolved and should be treated as live bugs:

1. History detail still behaves as if rows can pin it.
2. History detail still remains visible when the cursor is over the footer.
3. There is still a visible gap between the menu bar panel and the history panel.
4. Scrolling still does not reliably dismiss and suppress the history detail.
5. Opening the panel and opening Settings often still requires multiple clicks, suggesting stale focus or lingering popover ownership.

## Cleanup Priorities

1. Simplify interaction ownership around the menu panel and history detail.
2. Remove unnecessary smart behavior that tries to predict pointer intent if it makes the UI flaky.
3. Reduce background updates, hover churn, and view rebuilds while the panel is open.
4. Keep caching only where it measurably improves responsiveness.
5. Remove duplicate logic paths between SwiftUI and AppKit where one native path can own the behavior cleanly.

## Preferred Approach

- Start from user-visible behavior, not from internal abstractions.
- Trace click, hover, focus, scroll, and dismiss behavior at the actual window/view boundary.
- If the history detail mechanism is the source of complexity, replace it with a simpler native mechanism rather than layering more guards on top.
- If a cache, observer, debounce, suppression timer, or transient tracking layer is not essential, remove it.
- If a view model field exists only to support a fragile interaction workaround, challenge it.
- Keep implementation slices small and reversible.

## Things You May Simplify

- Popover/panel coordination
- Hover and dismissal state machines
- Scroll suppression logic
- View-local caching that duplicates model caching
- AppKit bridge helpers
- Repeated snapshot plumbing
- Overly defensive transient UI tracking

## Things You Must Not Simplify Away

- Menu bar entity configuration
- Entity detail metadata
- Thresholds and default thresholds
- Unit conversion and scaling
- Linked entity averaging
- Custom actions
- Cover controls
- Native settings flows
- Update checking and release info
- Real HA support and Fake HA test support

## Verification Expectations

At minimum, verify:

- Build succeeds with `swift build`
- Relevant targeted tests pass
- The five live bugs above are checked in the running app, not just in tests
- No feature disappears from Settings, the panel, or the menu bar
- No auth regression is introduced

## Working Style

- Favor smaller code with clearer ownership.
- Favor fewer moving parts.
- Favor explicit dismissal rules over inferred hover magic.
- Favor stable native behavior over “smart” interaction choreography.

If a simplification would remove behavior, stop and keep the behavior.
