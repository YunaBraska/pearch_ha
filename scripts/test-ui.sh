#!/bin/sh
# UI automation owns a desktop. Never run it in a developer's working session.
set -eu

if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]; then
    printf '%s\n' 'Native UI tests require an isolated GitHub-hosted macOS runner.' >&2
    exit 1
fi

mkdir -p .build/ui-tests
{
    git rev-parse HEAD
    sw_vers
    xcodebuild -version
} > .build/ui-tests/environment.log

# The menu/focus behavior is shared by both channels. Omit the external updater
# for this UI test build, without importing release certificates or credentials.
export PEARCHHA_APP_STORE=1
export TEST_RUNNER_GITHUB_ACTIONS="$GITHUB_ACTIONS"
export TEST_RUNNER_RUNNER_ENVIRONMENT="$RUNNER_ENVIRONMENT"
export TEST_RUNNER_PEARCHHA_NATIVE_E2E=1
export TEST_RUNNER_PEARCHHA_E2E_APP_PATH="$PWD/.build/ui-tests/DerivedData/Build/Products/Debug/PearchHA.app"

if xcodebuild test \
    -project PearchHA.xcodeproj \
    -scheme PearchHAE2E \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .build/ui-tests/DerivedData \
    -resultBundlePath .build/ui-tests/NativeUI.xcresult \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 180 \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    > .build/ui-tests/xcodebuild.log 2>&1; then
    tail -30 .build/ui-tests/xcodebuild.log
else
    result=$?
    tail -160 .build/ui-tests/xcodebuild.log
    exit "$result"
fi
