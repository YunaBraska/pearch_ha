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
- [ ] Custom action editor review: the current narrow panel makes the nested service-data editor feel cramped below the fold; review whether the editor should open taller, scroll more clearly, or expose fewer stacked controls at once.
- [ ] Signed local app review: Finder/bundle icon is now present through ad-hoc signing, but a native launch screenshot of the signed app against a real HA session is still missing.

## Repo state at session end

- [x] `hamirror doctor --probe` now reports endpoint-specific remediation and suppresses misleading capture suggestions when both live endpoints are unusable.
- [x] Smoke screenshots and release-review baseline are currently stable in the local CLT path.
- [x] `perchha-xcode-doctor` now reports discovered Xcode developer directories, honors local `DEVELOPER_DIR`, and reports Xcode license blockage explicitly.
- [x] The checked-in macOS app icon is integrated into the Xcode wrapper and the local ad-hoc packaging path.
