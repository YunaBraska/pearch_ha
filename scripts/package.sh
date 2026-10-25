#!/bin/sh
set -eu

test "$#" = 1

version=$1
identity=${MACOS_SIGNING_IDENTITY:--}
notary_profile=${MACOS_NOTARY_PROFILE:-}
update_private_key=${MACOS_UPDATE_PRIVATE_KEY:-}
update_public_key=${MACOS_UPDATE_PUBLIC_KEY:-}

if [ -n "${update_public_key}" ] || [ -n "${update_private_key}" ]; then
  test -n "${update_public_key}"
  test -n "${update_private_key}"
fi

rm -rf .build-release-arm64 .build-release-x86_64 dist
mkdir -p dist
swift build -c release --arch arm64 --product PearchHA --scratch-path .build-release-arm64
swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-release-x86_64
arm64_bin=$(swift build -c release --arch arm64 --product PearchHA --scratch-path .build-release-arm64 --show-bin-path)
x86_64_bin=$(swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-release-x86_64 --show-bin-path)
lipo -create \
  -output dist/PearchHA \
  "$arm64_bin/PearchHA" \
  "$x86_64_bin/PearchHA"
lipo -info dist/PearchHA
install_name_tool -add_rpath '@executable_path/../Frameworks' dist/PearchHA
sparkle_framework=$(find .build-release-arm64 -type d -name 'Sparkle.framework' -print -quit)
test -n "${sparkle_framework}"

set -- \
  --executable dist/PearchHA \
  --output dist/PearchHA.app \
  --callback-scheme pearchha \
  --replace \
  --version "${version}" \
  --build-version "${version}" \
  --verify-signature \
  --package-dmg \
  --dmg-output "dist/PearchHA-${version}.dmg" \
  --zip-output "dist/PearchHA-${version}.zip" \
  --verify-dmg \
  --verify-dmg-contents \
  --release-manifest dist/pearchha-release-manifest.json \
  --bundle-release-evidence dist/pearchha-release-evidence \
  --snapshot-dir .build/pearchha-snapshots/current \
  --framework "${sparkle_framework}"
if [ -n "${update_public_key}" ]; then
  set -- "$@" \
    --update-feed-url 'https://github.com/YunaBraska/pearch_ha/releases/latest/download/appcast.xml' \
    --update-public-key "${update_public_key}"
fi
if [ "${identity}" = '-' ]; then
  set -- "$@" --sign-ad-hoc
else
  set -- "$@" --sign-identity "${identity}"
fi
if [ -n "${notary_profile}" ]; then
  set -- "$@" --notary-profile "${notary_profile}" --notary-timeout 90m
fi
swift run pearchha-package-app "$@"
swift run pearchha-package-app --verify-release-manifest dist/pearchha-release-manifest.json
codesign --verify --deep --verbose=2 dist/PearchHA.app
if [ -n "${update_public_key}" ]; then
  update_stage=$(mktemp -d)
  update_key="${update_stage}/private-key"
  trap 'rm -rf "${update_stage}"' 0 HUP INT TERM
  (umask 077; printf '%s' "${update_private_key}" > "${update_key}")
  generate_appcast=$(find .build-release-arm64 -type f -name generate_appcast -print -quit)
  sign_update=$(find .build-release-arm64 -type f -name sign_update -print -quit)
  test -n "${generate_appcast}"
  test -n "${sign_update}"
  cp "dist/PearchHA-${version}.dmg" "${update_stage}/"
  "${generate_appcast}" --ed-key-file "${update_key}" --download-url-prefix "https://github.com/YunaBraska/pearch_ha/releases/download/${version}/" --maximum-versions 1 --disable-signing-warning -o dist/appcast.xml "${update_stage}"
  "${sign_update}" --ed-key-file "${update_key}" dist/appcast.xml --disable-signing-warning
  "${sign_update}" --ed-key-file "${update_key}" --verify dist/appcast.xml
fi
