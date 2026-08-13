#!/bin/sh
# The single check entrypoint used locally and by CI: strict build, full test
# suite with the coverage gate, smoke verification with exported snapshots,
# and the repository safety audit. Fails on the first broken step.
set -eu

export PERCHHA_TLS_DEBUG=1

swift run pearchha-xcode-doctor --json --strict
swift test --disable-swift-testing --enable-xctest list

swift build -Xswiftc -warnings-as-errors
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
coverage_path="$(swift test --disable-swift-testing --enable-xctest --enable-code-coverage --show-codecov-path | tail -n 1)"
test -f "$coverage_path"
cp "$coverage_path" .build/pearchha-codecov.json
# PearchHAClient line target tracks the current measured baseline (~91.5%) to
# guard against regression while the push to 95% continues.
swift run pearchha-coverage-check \
    --coverage-json .build/pearchha-codecov.json \
    --line-target PearchHACore=95 \
    --line-target PearchHAClient=90 \
    --branch-target PearchHACore=90
PEARCHHA_SMOKE_SNAPSHOT_DIR=.build/pearchha-snapshots swift run pearchha-smoke
swift run pearchha-repo-audit
