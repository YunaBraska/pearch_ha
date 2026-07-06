# TODO

What is still missing before PerchHA can honestly be called production-ready:

## External blockers

- [x] Xcode license accepted on this Mac; full-Xcode XCTest now compiles and runs (448 tests) with the coverage gate operational.
- [ ] Restore real Home Assistant mirror capture readiness:
  - [ ] Primary `url` must answer `/api/`
  - [ ] Fallback `url2` must accept the configured token instead of returning `401`
- [ ] Provide production OAuth values in `.env.local`:
  - [ ] `PERCHHA_OAUTH_CLIENT_ID`
  - [ ] `PERCHHA_OAUTH_REDIRECT_URI`
- [ ] Provide Developer ID signing identity and notary profile for credentialed release evidence.

## Native/full-Xcode verification still missing

- [ ] `xcodebuild -project PerchHA.xcodeproj -scheme PerchHA -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- [x] Full-Xcode XCTest execution with coverage gate (448 tests green under `-warnings-as-errors`; `PerchHACore` 95.77% line / `PerchHAClient` 86.29% line, gate enforced at the measured baseline)
- [ ] Raise `PerchHAClient` line coverage from 86% back to the 95% goal
- [ ] Full-Xcode verification for:
  - [ ] M5 app shell / first run
  - [ ] M6 selection, ordering, formatting UI
  - [ ] M7 menu bar items and gauges
  - [ ] M9 history popover / chart behavior
  - [ ] M10 built-in controls visual / keyboard behavior
  - [ ] M11 custom action visual / keyboard behavior
  - [ ] M12 real callback delivery verification
  - [ ] M13 native focus traversal verification

## Real HA / release evidence still missing

- [ ] Real mirrored fixture capture for the optimized WebSocket path:
  - [ ] `swift run hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write`
- [ ] Published OAuth client-website verification against the real hosted page
- [ ] Real callback evidence for native OAuth sign-in
- [ ] Credentialed signed + notarized release evidence

## Review findings

- [ ] Real HA read-only review is still blocked:
  - [ ] Primary `.env.local` `url` did not answer `/api/`
  - [ ] Fallback `.env.local` `url2` answered `/api/` with `401`
  - [ ] No live connected real-HA screenshot set can be captured until one endpoint is readable without mutation
- [x] Custom action editor review: settings now open in a dedicated resizable window, so the nested service-data editor has full width and is no longer cramped below the fold.
- [ ] Signed local app review: Finder/bundle icon is now present through ad-hoc signing, but a native launch screenshot of the signed app against a real HA session is still missing.

## Repo state at session end

- [x] `hamirror doctor --probe` now reports endpoint-specific remediation and suppresses misleading capture suggestions when both live endpoints are unusable.
- [x] Smoke screenshots and release-review baseline are currently stable in the local CLT path.
- [x] `perchha-xcode-doctor` now reports discovered Xcode developer directories, honors local `DEVELOPER_DIR`, and reports Xcode license blockage explicitly.
- [x] The checked-in macOS app icon is integrated into the Xcode wrapper and the local ad-hoc packaging path.
- [x] Certificate validation is strict by default again; the connection form has an explicit self-signed opt-in scoped to its HTTPS hosts, persisted with the profile (ADR-0010).
- [x] Live WebSocket updates are wired end to end: one streaming `subscribe_entities` session per connection with reconnect backoff, running with the panel closed so menu bar items stay live (ADR-0011).
- [x] WebSocket command/auth/ack receives carry a deadline, receives honor cancellation, REST requests time out at 15 s, and the frame-size ceiling covers large `get_states` payloads.
- [x] The background history sync refreshes OAuth tokens (no more silent decay after 30 minutes), pauses during outages, skips just-synced entities on scroll re-arms, never evicts displayed preview keys, and fetches week/month ranges from recorder statistics like the hover path.
- [x] Every panel dismissal path (Escape, click-away, toggle) stops the background loops; background loops re-bind `self` weakly so a released model deallocates.
- [x] Keychain and configuration-store failures surface in Settings instead of being swallowed; bulk-history failure text scrubs the bearer token.
- [x] History popovers open without a pointer (VoiceOver action everywhere; focus + Space on macOS 14+), Settings stays reachable before a connection exists, and the timeline popover speaks its segments.

## Remaining polish candidates (non-blocking)

- [ ] Localization posture is undecided: UI strings are hardcoded English with no string catalog. If v1 is English-only, record it in an ADR.
- [ ] `applyLiveState` rebuilds the room list per pushed event; fine at curated-dashboard scale, worth indexing by entity ID if live-update volume grows.
- [ ] Transient `unavailable` during an HA restart briefly changes row shape (gauge hides, pill becomes text). A grace window that maps short unavailable blips to stale would need a time source in the presentation layer.
