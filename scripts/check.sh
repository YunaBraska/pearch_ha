#!/bin/sh
# The single check entrypoint used locally and by CI: strict build, full test
# suite with the coverage gate, smoke verification with exported snapshots,
# and the repository safety audit. Fails on the first broken step.
set -eux

export PERCHHA_TLS_DEBUG=1

swift run pearchha-xcode-doctor --json --strict
swift test --disable-swift-testing --enable-xctest list

swift build -Xswiftc -warnings-as-errors
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
coverage_path="$(swift test --disable-swift-testing --enable-xctest --enable-code-coverage --show-codecov-path | tail -n 1)"
coverage_directory="$(dirname "$coverage_path")"
# SwiftPM may export only the last XCTest bundle. Export all bundles against
# the merged profile so the gate includes every tested production target.
set --
for test_binary in "$coverage_directory"/../*.xctest/Contents/MacOS/*; do
    test -f "$test_binary"
    set -- "$@" -object "$test_binary"
done
xcrun llvm-cov export -instr-profile "$coverage_directory/default.profdata" "$@" > .build/pearchha-codecov.json
# Keep the client regression floor at 90% while the push to 95% continues.
swift run pearchha-coverage-check \
    --coverage-json .build/pearchha-codecov.json \
    --line-target PearchHACore=95 \
    --line-target PearchHAClient=90 \
    --branch-target PearchHACore=90
PEARCHHA_SMOKE_SNAPSHOT_DIR=.build/pearchha-snapshots swift run pearchha-smoke
swift run pearchha-repo-audit
