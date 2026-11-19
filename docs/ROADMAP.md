# Roadmap

Implemented features are described in the [README](../README.md). This file owns
remaining work and release evidence gaps.

## Open: App Store submission and public sign-in

- Supply and verify the production OAuth client website and redirect declaration
  for public browser sign-in. See [HA_API.md](HA_API.md#authentication).
- The existing direct-release CI has Developer ID signing and notarization
  inputs configured. Those do not establish App Store distribution readiness.
- The separate Store lane produced a signed package in
  [run 40836734856](https://github.com/YunaBraska/pearch_ha/actions/runs/40836734856)
  on 2026-10-29 at `5c6f06e`. Reverify the final submission revision. The upload
  workflow has not run, so App Store Connect acceptance remains unverified.
- The [public privacy policy](https://yunabraska.github.io/pearch_ha/privacy.html)
  returned HTTP 200 on 2026-10-29 and is linked from Settings About. Complete
  App Store privacy metadata and verify an isolated, reachable Home Assistant
  review account. Review access outside the repository remains unverified. Do
  not use a personal home installation.
- Verify Keychain continuity with the actual Store distribution identity and
  configuration migration on each supported macOS release before submission.

## In progress: runtime verification

- Extend the Settings responsiveness checks beyond the verified 500-entity
  fixture and the manually reviewed 1,154-entity installation.
- Extend closed-menu CPU/memory measurements to open history, Settings, standby,
  reconnects, stale-cache recovery, and long sessions.
- Verify the final Store archive's runtime before submission. A successful signed
  package build does not establish sandbox, migration or Keychain behavior.

## Planned

- Raise client coverage toward 95% without weakening the existing gates.
- Extend localization beyond the German/English **This Mac** source before claiming
  whole-app language support.
