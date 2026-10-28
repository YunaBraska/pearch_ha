#!/bin/sh
set -eu

test "$#" = 2

version=$1
build_number=$2
workspace_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/pearchha-app-store.XXXXXX")
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/pearchha-app-store-stage.XXXXXX")
dist_dir="${workspace_dir}/dist/app-store"
app_dir="${dist_dir}/PearchHA.app"

: "${APP_STORE_BUNDLE_ID:?}"
: "${APP_STORE_TEAM_ID:?}"
: "${MACOS_APP_STORE_APPLICATION_IDENTITY:?}"
: "${MACOS_APP_STORE_PROFILE_PATH:?}"

trap 'rm -rf "${build_dir}" "${stage_dir}"' EXIT HUP INT TERM
rm -rf "${dist_dir}"
mkdir -p "${dist_dir}"
rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.build-*' \
  --exclude 'dist' \
  "${workspace_dir}/" "${build_dir}/"
cd "${build_dir}"
export PEARCHHA_APP_STORE=1

swift build -c release --arch arm64 --product PearchHA --scratch-path .build-app-store-arm64
swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-app-store-x86_64
arm64_bin=$(swift build -c release --arch arm64 --product PearchHA --scratch-path .build-app-store-arm64 --show-bin-path)
x86_64_bin=$(swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-app-store-x86_64 --show-bin-path)
lipo -create \
  -output "${stage_dir}/PearchHA" \
  "${arm64_bin}/PearchHA" \
  "${x86_64_bin}/PearchHA"
lipo -info "${stage_dir}/PearchHA"

tool_bin=$(swift build -c release --product pearchha-package-app --scratch-path .build-app-store-tools --show-bin-path)
"${tool_bin}/pearchha-package-app" \
  --executable "${stage_dir}/PearchHA" \
  --output "${app_dir}" \
  --callback-scheme pearchha \
  --bundle-id "${APP_STORE_BUNDLE_ID}" \
  --version "${version}" \
  --build-version "${build_number}" \
  --replace

cp "${MACOS_APP_STORE_PROFILE_PATH}" "${app_dir}/Contents/embedded.provisionprofile"
entitlements="${stage_dir}/PearchHA-AppStore.entitlements"
cp "${workspace_dir}/scripts/PearchHA-AppStore.entitlements" "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${APP_STORE_TEAM_ID}.${APP_STORE_BUNDLE_ID}" "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${APP_STORE_TEAM_ID}" "${entitlements}"
/usr/libexec/PlistBuddy -c 'Add :keychain-access-groups array' "${entitlements}"
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string ${APP_STORE_TEAM_ID}.${APP_STORE_BUNDLE_ID}" "${entitlements}"
codesign --force --deep --entitlements "${entitlements}" --options runtime --timestamp --sign "${MACOS_APP_STORE_APPLICATION_IDENTITY}" "${app_dir}"
codesign --verify --deep --strict --verbose=2 "${app_dir}"
if strings "${app_dir}/Contents/MacOS/PearchHA" | grep -q 'Sparkle'; then
  echo 'App Store build must not contain Sparkle.' >&2
  exit 1
fi
