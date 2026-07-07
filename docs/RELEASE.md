# How is a release cut?

This checklist turns a build into release evidence. It does not replace the roadmap; it is the operational gate for `M15 - Release packaging`.

## Local release candidate

```sh
swift build -c release
xcrun --find xctest
swift test --disable-swift-testing --enable-xctest list
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
xcodebuild -project PerchHA.xcodeproj -scheme PerchHA -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke --repeat 5
swift run perchha-package-app \
  --executable .build/release/PerchHA \
  --output .build/PerchHA.app \
  --callback-scheme perchha \
  --replace \
  --verify-launch-services \
  --sign-ad-hoc \
  --verify-signature \
  --package-dmg \
  --verify-dmg \
  --verify-dmg-contents \
  --release-manifest .build/perchha-release-manifest.json \
  --bundle-release-evidence .build/perchha-release-evidence \
  --oauth-site .build/perchha-oauth-site/index.html \
  --snapshot-dir .build/perchha-snapshots/current

swift run perchha-package-app \
  --verify-release-manifest .build/perchha-release-manifest.json
```

`--bundle-release-evidence .build/perchha-release-evidence` copies the manifest and all referenced artifacts into one portable evidence directory, then re-verifies the bundled manifest in place. Keep either that bundle or the generated `.build/PerchHA.app/`, `.build/PerchHA.dmg`, `.build/perchha-release-manifest.json`, `.build/perchha-oauth-site/`, and `.build/perchha-snapshots/current/` layout together as local evidence. The manifest records artifact paths relative to its own location when possible, so the evidence remains verifiable after relocation as long as that internal layout stays intact. Release manifest generation requires `--snapshot-dir` so screenshot evidence cannot be omitted accidentally, and `--oauth-site` lets the retained bundle re-verify the exact OAuth declaration page that was intended for deployment.
The verification command re-reads the manifest and fails if the app metadata, recorded app signature, recorded stapled DMG validation, DMG hash, retained OAuth site artifact hash, screenshot hashes, recorded review baseline hash, or canonical required screenshot names no longer match the current artifacts.

Required smoke screenshots:

- `built-in-controls-light.png`
- `connected-dark-increased-contrast.png`
- `connected-dark.png`
- `connected-light-reduced-motion.png`
- `connected-light.png`
- `connecting-light.png`
- `empty-light.png`
- `error-dark.png`
- `first-run-light.png`
- `history-loaded-light.png`
- `history-loaded-light-increased-contrast.png`
- `reconnecting-light.png`
- `review-contact-sheet.png`
- `settings-about-update-light.png`
- `settings-selection-light.png`
- `signing-in-light.png`

The checked-in review baseline lives at `docs/release-review-baseline.json`. When an intentional UI change is approved, refresh it with:

```sh
swift run perchha-smoke --update-review-baseline
```

Use `swift run perchha-smoke --repeat <count>` when you need repeated public-entrypoint smoke evidence for snapshot drift or flake diagnosis; it runs fresh smoke invocations and the final exported screenshots still come from the last run.

The release manifest records the smoke-exported `review-baseline-expected.json` from `.build/perchha-snapshots/current/`, which is a retained copy of the checked-in review contract that smoke compared against. `review-baseline-current.json` is still exported for local diagnosis when current rendering drifts.

## Credentialed release

Run this on the release machine after `notarytool` credentials are stored in Keychain:

```sh
swift run perchha-package-app \
  --release-preflight \
  --sign-identity "Developer ID Application: Example (TEAMID)" \
  --notary-profile perchha-release

swift run perchha-package-app \
  --release-preflight \
  --json \
  --sign-identity "Developer ID Application: Example (TEAMID)" \
  --notary-profile perchha-release

swift run perchha-package-app \
  --executable .build/release/PerchHA \
  --output .build/PerchHA.app \
  --callback-scheme perchha \
  --replace \
  --verify-launch-services \
  --sign-identity "Developer ID Application: Example (TEAMID)" \
  --verify-signature \
  --package-dmg \
  --verify-dmg \
  --verify-dmg-contents \
  --notary-profile perchha-release \
  --release-manifest .build/perchha-release-manifest.json \
  --bundle-release-evidence .build/perchha-release-evidence \
  --oauth-site .build/perchha-oauth-site/index.html \
  --snapshot-dir .build/perchha-snapshots/current

swift run perchha-package-app \
  --verify-release-manifest .build/perchha-release-manifest.json
```

`--notary-profile` is valid for `--release-preflight` on its own. For an actual notarization submission, use it with `--package-dmg` and a Developer ID `--sign-identity` so the submitted artifact is produced and signed by the same command.
`--release-preflight` now reports redacted next steps and suggested commands in both human output and `--json`, so release scripts and humans get the same readiness guidance without echoing the configured identity or profile values.

## GitHub Actions workflows

- `.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual dispatch: one job that runs `scripts/check.sh` (strict build, tests with the coverage gate, smoke with exported snapshots, repo audit) on the latest stable Xcode and fails if the checks dirty the working tree.
- `.github/workflows/release.yml` runs automatically on pushes to `main`, so a real merge to `main` cuts a release. It also supports manual dispatch with an optional `version` override and a branch-safe `dry_run` mode that builds, packages, verifies, and uploads the release evidence as a workflow artifact without publishing a GitHub release.
- The release workflow runs the same `scripts/check.sh`, builds a universal (`arm64` + `x86_64`) release binary, packages the ad-hoc-signed app bundle and DMG with the release manifest and evidence bundle, verifies the manifest, bundle metadata, universal slices, and signature, uploads the retained evidence artifact, and publishes a GitHub release with the zip and DMG only when the run is a `main` push or a non-dry-run manual dispatch from `main`.
- When the optional `RELEASE_TOKEN` repository secret is set, the release publication step uses it instead of the default workflow token; this is the escape hatch for repositories whose release/tag policy needs a user token.
- When the optional `HOMEBREW_TAP_TOKEN` repository secret is set, the release workflow also updates the `perchha` cask in `YunaBraska/homebrew-tap`; without the secret those steps are skipped.

The published app is ad-hoc signed and not notarized: install by unzipping and right-click → **Open** on first launch. The Developer ID + notarization path below remains the local, credentialed route.

## Release gate

- Full Xcode-selected XCTest and app verification passed.
- Smoke screenshots are current and attached to the milestone report.
- DMG verifies by bytes and mounted content.
- Release manifest exists and records app metadata, DMG hash, screenshot hashes, signing status, and notarization status.
- Release manifest records the retained OAuth client-website artifact when one is part of the release bundle.
- Release manifest verification passes against the retained app, DMG, screenshot artifacts, and canonical required screenshot names.
- Retained CI evidence is bundled with the manifest, app, DMG, OAuth site artifact, and `perchha-snapshots/current/` tree in the same relative layout so `--verify-release-manifest` still works after download.
- Release preflight passes for the Developer ID identity and `notarytool` Keychain profile.
- Release preflight JSON reports `credentialedRelease=ready` on the release machine.
- Credentialed build uses a Developer ID identity, not `--sign-ad-hoc`.
- Notary submission completes and the artifact is stapled.
- Automatic updates are deferred by ADR-0009 until after the direct release path is stable.
- No `.env.local`, credentials, private fixtures, or temporary mount directories are present in tracked files.
- `swift run perchha-repo-audit` passes, including the no-telemetry-by-default source audit.
- Throwaway LaunchServices registrations are removed with `lsregister -u <path-to-app>`.
