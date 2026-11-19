#!/bin/sh
# UI automation owns a desktop. Never run it in a developer's working session.
set -eu

if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]; then
    printf '%s\n' 'Native UI tests require an isolated GitHub-hosted macOS runner.' >&2
    exit 1
fi

output_dir=${PEARCHHA_E2E_OUTPUT_DIR:-.build/ui-tests}
mkdir -p "$output_dir"

collect_startup_diagnostics() {
    test_result=$?
    trap - 0
    /usr/bin/log show --last 15m --style compact --predicate 'process == "PearchHA"' \
        > "$output_dir/startup.log" 2>&1 || :
    for report in "$HOME"/Library/Logs/DiagnosticReports/PearchHA*.ips; do
        if test -f "$report"; then cp "$report" "$output_dir/" || :; fi
    done
    exit "$test_result"
}
trap collect_startup_diagnostics 0

{
    git rev-parse HEAD
    sw_vers
    xcodebuild -version
} > "$output_dir/environment.log"

# Build the test runner and default app without the external updater. An explicit
# app path tests the unchanged published or packaged app instead.
export PEARCHHA_APP_STORE=1
export TEST_RUNNER_GITHUB_ACTIONS="$GITHUB_ACTIONS"
export TEST_RUNNER_RUNNER_ENVIRONMENT="$RUNNER_ENVIRONMENT"
export TEST_RUNNER_PEARCHHA_NATIVE_E2E=1
export TEST_RUNNER_PEARCHHA_E2E_APP_PATH="${PEARCHHA_E2E_APP_PATH:-$PWD/.build/ui-tests/DerivedData/Build/Products/Debug/PearchHA.app}"

if xcodebuild test \
    -project PearchHA.xcodeproj \
    -scheme PearchHAE2E \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .build/ui-tests/DerivedData \
    -resultBundlePath "$output_dir/NativeUI.xcresult" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 \
    -maximum-test-execution-time-allowance 180 \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    > "$output_dir/xcodebuild.log" 2>&1; then
    tail -30 "$output_dir/xcodebuild.log"
else
    result=$?
    tail -160 "$output_dir/xcodebuild.log"
    exit "$result"
fi
