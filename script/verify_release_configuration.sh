#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./script/verify_version_consistency.sh
./script/verify_installation_isolation.sh
./script/verify_keychain_read_contract.sh

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)" == "com.jingsan0801.mytokenremain" ]]

/bin/bash -n script/build_and_run.sh
/bin/bash -n script/verify_launch_stability.sh
/bin/bash -n script/package_developer_id_release.sh
/usr/bin/grep -Fq 'SWIFT_BUILD_ARGS+=(--configuration release)' script/build_and_run.sh
/usr/bin/grep -Fq 'SIGNING_COMMON_NAME="$(resolve_signing_common_name "$SIGNING_IDENTITY")"' script/build_and_run.sh
/usr/bin/grep -Fq 'signing_options+=(--options runtime --timestamp)' script/build_and_run.sh
/usr/bin/grep -Fq 'sign_outer_bundle' script/build_and_run.sh
# Size contract: the shipped executable is stripped, its DWARF is archived
# beside the bundle first, and the two are UUID-matched before the strip runs.
/usr/bin/grep -Fq '/usr/bin/strip -S -x "$APP_BINARY"' script/build_and_run.sh
/usr/bin/grep -Fq '/usr/bin/ditto "$BUILD_DIR/$PRODUCT_NAME.dSYM" "$APP_DSYM"' script/build_and_run.sh
/usr/bin/grep -Fq 'refusing to strip' script/build_and_run.sh
# `-e` is required: grep would otherwise parse the leading `--exclude=` as its
# own option instead of as the pattern to search for.
/usr/bin/grep -Fq -e "--exclude='*.svg'" script/build_and_run.sh
/usr/bin/grep -Fq 'hdiutil convert "$rw_dmg" -format ULMO' script/package_developer_id_release.sh
/usr/bin/grep -Fq 'STAMP="${APP}.launch-stability-source"' script/verify_launch_stability.sh
/usr/bin/grep -Fq 'TokenRemain-$VERSION-$BUILD.dmg' script/package_developer_id_release.sh
/usr/bin/grep -Fq '/usr/bin/cmp -s "$DMG" "$VERSIONED_DMG"' script/package_developer_id_release.sh
/bin/bash -n script/verify_installation_isolation.sh
/bin/bash -n script/verify_keychain_read_contract.sh
/bin/bash -n script/verify_version_consistency.sh

echo "desktop release configuration verified: version, updater, packaging, privacy, and website contracts"
