# Roadmap

Implemented features are described in the [README](../README.md). This file owns
remaining work and release evidence gaps.

## Open: App Store submission and public sign-in

- Supply and verify the production OAuth client website and redirect declaration
  for public browser sign-in. See [HA_API.md](HA_API.md#authentication).
- The existing direct-release CI has Developer ID signing and notarization
  inputs configured. Those do not establish App Store distribution readiness.
- Connect App Store distribution signing, provisioning and App Store Connect
  access to a separate CI lane. The local `AppStore` Xcode configuration and
  archive/export script are present, but a Store-signed upload is not verified.
- Publish and verify the privacy-policy URL from `Page/privacy.md`, complete App
  Store privacy metadata, and provide an isolated, reachable Home Assistant
  review account. The public privacy URL returned HTTP 404 on 2026-10-27, and
  review access outside the repository remains unverified. Use an isolated
  review installation instead of a personal home installation.
- Verify Keychain continuity with the actual Store distribution identity and
  configuration migration on each supported macOS release before submission.

## In progress: runtime verification

- Extend the Settings responsiveness checks beyond the verified 500-entity
  fixture and the manually reviewed 1,154-entity installation.
- Extend closed-menu CPU/memory measurements to open history, Settings, standby,
  reconnects, stale-cache recovery, and long sessions.
- Verify the credentialed Store archive, export and runtime before submission.

## Planned

- Raise client coverage toward 95% without weakening the existing gates.
- Decide localization scope before claiming broader language support.
