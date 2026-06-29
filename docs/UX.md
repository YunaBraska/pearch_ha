# UX - PearchHA

## 1. North star

PerchHA should feel like a quiet macOS utility: quick to scan, hard to misclick, and never louder than the home state it is showing.

Visual references:

- iStat Menus density and menu bar utility.
- Netatmo-style room grouping.
- Native macOS materials, typography, and focus behavior.

## 2. Surfaces

- Menu bar items.
- Drop-down panel.
- History popover.
- Settings window.
- Inline toasts and errors.

## 3. Drop-down panel

The panel is a custom `NSPanel` hosted by AppKit and rendered with SwiftUI.

Layout:

1. Header: app name, connection state, last update.
2. Room sections: collapsible room groups.
3. Entity rows: name, optional gauge, value, unit, freshness.
4. Control rows: toggles, cover controls, or custom action buttons.
5. Footer: settings, refresh, quit.

Rules:

- Values align in a stable right column.
- Rows do not resize on value changes.
- Section separators are quiet.
- Errors appear inline.
- No modal-heavy workflow.

## 4. Menu bar items

Each bar item can show:

- Text value.
- Bar gauge.
- Battery gauge.
- Ring gauge.

Click opens the panel. Right-click opens a compact context menu for hide, style, and settings.

## 5. Settings

Settings open in a dedicated resizable window (separate from the menu-bar panel), organized as tabs:

- Connection: Home Assistant address, fallback address, access token, and sign-in. Shares the same field stack as first-run.
- Entities: searchable room -> entity tree. Selecting an entity reveals its display and action configuration inline (menu-bar promotion, gauge style, label/unit/decimals, thresholds, history range, and custom actions).
- Advanced: self-signed certificate allowance and other rarely-used options.
- About: app identity and version.

Entity selection uses a searchable room -> entity tree. Dragging changes PerchHA display order only; it does not rewrite Home Assistant areas. Per-entity display and action editing live in the Entities tab rather than separate Display/Actions tabs, so a single entity's configuration stays in one place.

## 6. Custom actions

Custom actions are icon-and-title buttons attached to entity rows. A sensor can have actions, but the UI must make clear that the button runs a service call and does not edit the sensor's state.

Settings lets each entity add, edit, delete, confirm, and reorder actions. Core service fields and scalar service-data fields edit inline so a simple action does not require leaving the row. When Home Assistant service metadata is available, domain and service fields become pickers and missing scalar fields can be prefilled from metadata examples. Actions attached to entities that are no longer discovered remain visible in settings for deletion.

Actions support optional confirmation. Failure rolls back optimistic UI when a visible value was changed; sensor-attached actions keep the sensor value unchanged and show a short inline message under the row.

## 7. History popover

Hovering a value opens a compact chart with:

- Hour.
- Day.
- Week.
- Month.
- Current value.
- Min, average, max when available.

Loading states are skeletons. Unsupported history shows a clear empty state.

## 8. First-run and empty states

First run asks for:

- Home Assistant URL.
- Long-lived access token, or sign-in flow when implemented.
- Optional fallback URL.
- Connection test.

No selected entities: show a short empty state and a button to open settings.

Disconnected: keep last-known values visible, mark them stale, and show reconnect state.

## 9. Accessibility

Required:

- Keyboard navigation for panel and settings.
- Visible focus.
- VoiceOver labels for values, gauges, controls, and connection state.
- Reduced Motion support.
- Increase Contrast support.
- Dynamic Type within practical menu bar constraints.

## 10. Theming

Use system colors and a small semantic token set:

- accent
- surface
- surfaceRaised
- separator
- textPrimary
- textSecondary
- ok
- warn
- critical

Every gauge and chart supports light and dark mode.
