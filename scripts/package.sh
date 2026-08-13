#!/bin/sh
set -eu

test "$#" = 1

version=$1
identity=${MACOS_SIGNING_IDENTITY:--}
notary_profile=${MACOS_NOTARY_PROFILE:-}

rm -rf .build-release-arm64 .build-release-x86_64 dist
mkdir -p dist
swift build -c release --arch arm64 --product PearchHA --scratch-path .build-release-arm64
swift build -c release --arch x86_64 --product PearchHA --scratch-path .build-release-x86_64
lipo -create \
  -output dist/PearchHA \
  .build-release-arm64/arm64-apple-macosx/release/PearchHA \
  .build-release-x86_64/x86_64-apple-macosx/release/PearchHA
lipo -info dist/PearchHA

set -- \
  --executable dist/PearchHA \
  --output dist/PearchHA.app \
  --callback-scheme pearchha \
  --replace \
  --version "${version}" \
  --build-version "${version}" \
  --verify-signature \
  --package-dmg \
  --verify-dmg \
  --verify-dmg-contents \
  --release-manifest dist/pearchha-release-manifest.json \
  --bundle-release-evidence dist/pearchha-release-evidence \
  --snapshot-dir .build/pearchha-snapshots/current
if [ "${identity}" = '-' ]; then
  set -- "$@" --sign-ad-hoc
else
  set -- "$@" --sign-identity "${identity}"
fi
if [ -n "${notary_profile}" ]; then
  set -- "$@" --notary-profile "${notary_profile}"
fi
swift run pearchha-package-app "$@"
swift run pearchha-package-app --verify-release-manifest dist/pearchha-release-manifest.json
codesign --verify --deep --verbose=2 dist/PearchHA.app
ditto -c -k --sequesterRsrc --keepParent dist/PearchHA.app "dist/PearchHA-${version}.zip"
mv dist/PearchHA.dmg "dist/PearchHA-${version}.dmg"
