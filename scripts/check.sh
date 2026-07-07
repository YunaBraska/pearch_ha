#!/bin/sh
# The single check entrypoint used locally and by CI: strict build, full test
# suite with the coverage gate, smoke verification with exported snapshots,
# and the repository safety audit. Fails on the first broken step.
set -eu

swift build -Xswiftc -warnings-as-errors
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
coverage_path="$(swift test --disable-swift-testing --enable-xctest --enable-code-coverage --show-codecov-path | tail -n 1)"
test -f "$coverage_path"
cp "$coverage_path" .build/perchha-codecov.json
# PerchHAClient line target tracks the current measured baseline (~91.5%) to
# guard against regression while the push to 95% continues.
swift run perchha-coverage-check \
    --coverage-json .build/perchha-codecov.json \
    --line-target PerchHACore=95 \
    --line-target PerchHAClient=90 \
    --branch-target PerchHACore=90
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke
swift run perchha-repo-audit
