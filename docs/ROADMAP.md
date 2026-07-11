# Roadmap - PearchHA

This file is now the live backlog. Done work stays out unless it changes a release decision.

## Shipping now

- Native macOS menu bar app built with Swift, SwiftUI, and AppKit.
- Real Home Assistant connection with browser sign-in or bearer-token auth.
- Multi-address connection fallback, Keychain-backed session restore, and FakeHA-backed tests.
- Menu bar values, gauges, thresholds, custom actions, linked averages, entity settings, and cached history detail.
- CI on pull requests and a release workflow that publishes only from `main`, with manual dispatch available for dry runs or controlled releases.

## Release gates still open

### 1. Public release credentials

- Provide production OAuth client values if browser sign-in must ship against a public Home Assistant setup.
- Provide a real Developer ID signing identity and notarization profile when ad-hoc signing is no longer enough.

### 2. Verification hardening

- Raise `PearchHAClient` coverage from the low-90s toward the project target.
- Keep chasing the Settings entity-view freeze until we have repeatable evidence that the hot loop is gone.
- Add stronger evidence for long-range history cache behavior under standby, reconnects, and stale-cache recovery.

### 3. Performance hardening

- Keep reducing Settings entity-list work so large installs stay cheap while scrolling.
- Keep the panel and history detail strictly cache-first; background sync should stay asynchronous and bounded.
- Verify idle CPU and memory on a long-running real-HA session after the latest settings and history changes.

### 4. Product decisions

- Decide localization posture and record it in an ADR if v1 remains English-only.

## Next engineering slice

1. Finish the Settings freeze investigation with samples and regression coverage.
2. Tighten history cache maintenance for day/week/month so visible panel rows stay warm without repeated full-range fetches.
3. Re-run the full CI/release dry-run path after the repo cleanup lands.
