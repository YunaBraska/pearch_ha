# Architecture - PearchHA

## Stack

- Swift package as the source of truth.
- SwiftUI for view code, hosted inside AppKit windows and panels.
- `NSStatusItem` for menu bar presence.
- `NSPanel` for the drop-down surface and `NSWindow` for Settings.
- Foundation networking plus Home Assistant REST and WebSocket calls.
- JSON config for non-secrets, Keychain for secrets.

## Modules

```text
PerchHAApp -> PerchHAUI -> PerchHACore <- PerchHAClient -> PerchHASupport
                                 ^                         ^
                                 `---- PerchHAPersistence --'
```

- `PerchHACore`: pure formatting, units, thresholds, selection, ordering, and presentation rules.
- `PerchHAClient`: Home Assistant auth, discovery, history, live updates, and service calls.
- `PerchHAPersistence`: config store and secret storage.
- `PerchHAUI`: panel, settings, controls, charts, and local view helpers.
- `PerchHAApp`: lifecycle, status items, windows, panel placement, and release/update wiring.
- `PerchHASupport`: clocks, rate limiting, backoff, request coalescing, redaction, and command-line support.

## State and flow

`PerchHAPanelModel` is the main UI state owner.

Flow:

```text
Home Assistant or user input
-> client/service result
-> panel model mutation
-> immutable snapshot
-> SwiftUI/AppKit render
```

UI surfaces do not talk to Home Assistant directly.

## Runtime rules

- Menu bar and history detail always read from cache first.
- Background sync updates cache asynchronously; UI does not block on it.
- Live WebSocket updates keep menu bar items fresh even while the panel is closed.
- Settings is intentionally cheaper than the panel: it works from cached discovery/config data and should not behave like a live dashboard.
- History caching is bounded by capacity and TTL, not by unbounded growth.
- Secrets stay in Keychain, never in tracked config, fixtures, or docs.

## Focus and lifetime

- The panel is a transient surface. Closing it stops panel-only refresh loops.
- Settings is a real window, but it should not keep expensive live-update behavior alive on its own.
- Unfocused transient surfaces are allowed to close themselves after a long idle period to keep the app from lingering forever in the background.

## Failure boundaries

The app keeps separate user-facing states for:

- auth failure
- unreachable host / TLS failure
- unsupported HA capability
- history unavailable
- service-call failure
- persistence failure

Those failures must stay explicit and testable.

## What does not belong here

- Product promises belong in the UI itself and in tests.
- Binding technical choices belong in [ADRs.md](ADRs.md).
- Release procedure belongs in CI and packaging tests, not a separate checklist doc.
