# Roadmap

Implemented features are described in the [README](../README.md). This file owns
remaining work and release evidence gaps.

## Blocked: public release credentials

- Supply and verify the production OAuth client website and redirect declaration
  for public browser sign-in. See [HA_API.md](HA_API.md#authentication).
- Supply Developer ID signing and notarization credentials. Local test-signed
  universal packaging and evidence verification pass, but do not prove public trust.

## In progress: runtime verification

- Verify the Settings entity list stays responsive with a large real installation.
- Extend closed-menu CPU/memory measurements to open history, Settings, standby,
  reconnects, stale-cache recovery, and long sessions.
- Verify the credentialed release path before public release.

## Planned

- Raise client coverage toward 95% without weakening the existing gates.
- Decide localization scope before claiming broader language support.
