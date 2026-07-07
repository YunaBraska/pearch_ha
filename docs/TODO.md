# TODO

What is still missing before PerchHA can honestly be called production-ready:

## External prerequisites

- Provide production OAuth values in `.env.local`:
  - `PERCHHA_OAUTH_CLIENT_ID`
  - `PERCHHA_OAUTH_REDIRECT_URI`
- Provide a real Developer ID Application signing identity and a usable `notarytool` keychain profile

## Verification and evidence gaps

- Raise `PerchHAClient` line coverage from `91.56%` toward the `95%` target
- Verify the published OAuth client website against the real hosted page
- Capture real callback evidence for native OAuth sign-in
- Produce credentialed signed, notarized, and stapled release evidence
- Capture a native launch screenshot set of the signed app against a real Home Assistant session

## Product and repo decisions still open

- Decide localization posture and record it in an ADR if v1 remains English-only

## Non-blocking polish candidates

- `applyLiveState` still rebuilds the room list per pushed event; fine for current scale, worth indexing by entity ID if live-update volume grows
- Short `unavailable` blips during Home Assistant restarts still change row shape briefly; a stale-grace window would need time-aware presentation handling
