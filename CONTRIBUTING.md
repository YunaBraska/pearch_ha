# Contributing

Keep changes scoped to observable behavior. Prefer extending or simplifying the
existing implementation. Update its tests and owning document when behavior changes.

## Development

Use Swift 6 and full Xcode for native verification:

```sh
git clone https://github.com/YunaBraska/pearch_ha.git
cd pearch_ha
open PearchHA.xcodeproj
sh scripts/check.sh
```

[TESTING.md](docs/TESTING.md) defines the gates, focused checks, and evidence limits.
Use a branch from `main`, run the relevant checks, and include their results and any
remaining limitations in the pull request. Prefer terse present-tense commits.

To build and run a local app, set `MACOS_SIGNING_IDENTITY` to an existing signing
identity name or hash. Reuse it for subsequent builds:

```sh
swift build -c release --product PearchHA
bin_path=$(swift build -c release --product PearchHA --show-bin-path)
swift run pearchha-package-app --executable "$bin_path/PearchHA" \
  --output .build/PearchHA.app --callback-scheme pearchha --replace \
  --sign-identity "$MACOS_SIGNING_IDENTITY"
open .build/PearchHA.app
```

Keep the bundle identifier, signing identity, install path, and profile stable for
permission tests. Ad-hoc signing is suitable only for tests that do not depend on
persistent macOS permissions. Local signing does not replace notarized distribution.

The [documentation index](docs/README.md) identifies the canonical home for each
contract. Update that source instead of adding parallel notes or checklists.
