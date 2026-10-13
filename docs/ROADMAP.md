# Roadmap - PearchHA

This file is now the live backlog. Done work stays out unless it changes a release decision.

## Shipping now

- Native macOS menu bar app built with Swift, SwiftUI, and AppKit.
- Real Home Assistant connection with browser sign-in or bearer-token auth.
- Multi-address connection fallback, Keychain-backed session restore, and FakeHA-backed tests.
- Menu bar values, gauges, thresholds, capability-derived controls, custom actions, linked averages, entity settings, and history loaded on demand.
- Pull requests and merges build the universal app. The dispatched release workflow publishes stable GitHub releases from `main`.
- Local candidate 2026.10.13 passes all 960 tests, coverage gates, native smoke, repository audit, universal packaging, signature checks, and DMG/evidence verification. It is installed with the existing local signing identity. This is not a notarized public release.

## Release gates still open

### 1. Public release credentials

- Provide production OAuth client values if browser sign-in must ship against a public Home Assistant setup.
- Provide a real Developer ID signing certificate and notarization API key to enable the already-configured signed and notarized release path.

### 2. Verification hardening

- Raise `PearchHAClient` coverage from the low-90s toward the project target.
- Keep chasing the Settings entity-view freeze until we have repeatable evidence that the hot loop is gone.
- Add stronger evidence for long-range history cache behavior under standby, reconnects, and stale-cache recovery.

### 3. Performance hardening

- Keep reducing Settings entity-list work so large installs stay cheap while scrolling.
- Keep the panel and history detail strictly cache-first; background sync should stay asynchronous and bounded.
- Extend the real-HA runtime check beyond the five-minute closed-panel measurement on 2026.10.13: 0.31% average CPU, 96-107 MB RSS, and 43-54 MB physical footprint. Open-panel, Settings, standby, and long-session evidence remain separate checks.

### 4. Product decisions

- Decide localization posture and record it in an ADR if v1 remains English-only.

## Next engineering slice

1. Finish the Settings freeze investigation with samples and regression coverage.
2. Extend real-app performance evidence across open history, Settings, standby, and reconnects. Visible previews and the selected detail range already refresh only when due.
3. Run remote CI and the credentialed signing/notarization path before public release. The local check and packaging dry run pass after cleanup.
