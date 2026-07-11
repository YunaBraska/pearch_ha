# Contributing to PerchHA

Thanks for helping. Keep changes small, tested, and documented.

## Development setup

```sh
git clone https://github.com/YunaBraska/pearch_ha.git
cd pearch_ha

swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
swift run perchha-repo-audit
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke
```

Full native verification needs full Xcode selected:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift run perchha-xcode-doctor --json --strict
swift test --disable-swift-testing --enable-xctest list
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
```

## Pull requests

1. Branch from `main`.
2. Keep scope tight.
3. Add or update tests for behavior changes.
4. Update the relevant doc in [`docs/README.md`](docs/README.md) when behavior, release steps, or verification changes.
5. Run the relevant local checks before opening the PR.

## Required checks for most changes

```sh
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
swift run perchha-repo-audit
```

Also run these when the touched area needs them:

- `PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke`
- `swift run hamirror verify --fixtures Fixtures/public/m2-minimal`
- `swift build -c release`
- `swift run perchha-package-app --help`

## Documentation rule

README is the fast entrypoint. The real contract lives in `docs/`.

- Build order: `docs/ROADMAP.md`
- Architecture: `docs/ARCHITECTURE.md`
- Home Assistant integration: `docs/HA_API.md`
- Testing and traceability: `docs/TESTING.md`
- Decision records: `docs/ADRs.md`

## Commit style

Prefer terse present-tense commits, for example:

- `feat: add release evidence bundler`
- `fix: rewrite bundled manifest paths`
- `test: cover nested release manifest relocation`
