#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ARCHIVE_MODE=0
if [[ "$MODE" == "--archive" || "$MODE" == "archive" ]]; then
  ARCHIVE_MODE=1
fi
PRODUCT_NAME="UsageDock"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
INSTALL_DIR="${USAGEDOCK_INSTALL_DIR:-$HOME/Applications}"
BROADCAST_BASE_URL="${TOKENREMAIN_BROADCAST_BASE_URL:-https://api.mytokenremain.jingsan.wang}"
# A stable signature lets macOS retain the user's "Always Allow" choice for
# the Claude Code keychain item across UsageDock rebuilds.
SIGNING_IDENTITY="${USAGEDOCK_SIGNING_IDENTITY:-}"

# `--archive` produces a release-configured, stripped, universal bundle for
# local packaging. Plain `run`/`--verify` builds keep their debug symbols so
# lldb works against them.
SIGNING_COMMON_NAME=""
ARCHIVE_DIR="${USAGEDOCK_ARCHIVE_DIR:-$ROOT_DIR/dist-release}"

# Fork note: this personal fork ships a single app identity — there is no Dev
# variant. Plain builds use the same name, executable and bundle id in one
# Keychain/UserDefaults namespace, so there is exactly one installed
# MyTokenRemain.
APP_NAME="MyTokenRemain"
EXECUTABLE_NAME="UsageDock"
BUNDLE_ID="com.jingsan0801.mytokenremain"
LEGACY_INSTALLED_APPS=(
  "$INSTALL_DIR/UsageDock.app"
  "$INSTALL_DIR/Token Remain.app"
  "$INSTALL_DIR/TokenRemain.app"
  "$INSTALL_DIR/MyTokenRemain Dev.app"
  "$INSTALL_DIR/UsageDock Dev.app"
  "$INSTALL_DIR/TokenRemain Dev.app"
)
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
# The shipped executable is stripped, so the only way to symbolicate a crash
# report is the archived companion dSYM. It sits beside the bundle rather than
# inside it: shipping 47 MB of DWARF to every user would defeat the strip.
APP_DSYM="$DIST_DIR/$APP_NAME.app.dSYM"

resolve_signing_common_name() {
  local selector="$1"
  local matches match_count
  matches="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -F -- "$selector" || true)"
  match_count="$(printf '%s\n' "$matches" | /usr/bin/sed '/^[[:space:]]*$/d' \
    | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
  if [[ "$match_count" != "1" ]]; then
    echo "Signing identity selector must match exactly one valid identity; use its SHA-1 when common names are duplicated." >&2
    return 1
  fi
  printf '%s\n' "$matches" | /usr/bin/sed -n 's/.*"\(.*\)".*/\1/p'
}

cleanup_build_artifacts() {
  # The staged bundle is only an intermediate. Keeping it under `dist/`
  # registers a second TokenRemain with LaunchServices and Developer Tools.
  # The signed installed copy under ~/Applications is the sole runnable app.
  if [[ -d "$APP_BUNDLE" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -u "$APP_BUNDLE" >/dev/null 2>&1 || true
    rm -rf "$APP_BUNDLE"
  fi
}
trap cleanup_build_artifacts EXIT

verify_bundle_identity() {
  local signed_app="$1"
  local entitlements
  # Fork note: with the Dev variant and CloudKit sync removed, every build
  # targets the single stable install path and must carry no iCloud or shared
  # sync-keychain entitlements.
  /usr/bin/codesign --verify --deep --strict "$signed_app"
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$signed_app/Contents/Info.plist")" != "$BUNDLE_ID" \
    || "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$signed_app/Contents/Info.plist")" != "$EXECUTABLE_NAME" ]]; then
    echo "Development bundle isolation metadata is invalid." >&2
    exit 1
  fi
  entitlements="$(/usr/bin/codesign -d --entitlements :- "$signed_app" 2>/dev/null || true)"
  if [[ "$entitlements" == *"com.apple.developer.icloud-container-identifiers"* \
    || "$entitlements" == *"com.apple.developer.icloud-services"* ]]; then
    echo "Bundle unexpectedly carries CloudKit entitlements." >&2
    exit 1
  fi
}

# Fork note: this machine's /usr/bin/lipo rejects every `-verify_arch` call
# with "requires exactly one input file" (macOS 27 toolchain regression), so
# the fork verifies the architecture list via `lipo -archs` instead.
verify_universal_binary() {
  local file="$1"
  local archs
  archs="$(/usr/bin/lipo -archs "$file" 2>/dev/null)" || return 1
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]
}


sign_outer_bundle() {
  local entitlements_path="${1:-}"
  local signing_options=(--force --sign "$SIGNING_IDENTITY")

  # Developer ID distribution requires both Hardened Runtime and a secure
  # timestamp. Decide from the resolved certificate common name so an explicit
  # SHA-1 selector cannot silently fall back to development signing behavior.
  if [[ "$SIGNING_COMMON_NAME" == "Developer ID Application:"* ]]; then
    signing_options+=(--options runtime --timestamp)
  else
    signing_options+=(--timestamp=none)
  fi
  if [[ -n "$entitlements_path" ]]; then
    signing_options+=(--entitlements "$entitlements_path")
  fi
  /usr/bin/codesign "${signing_options[@]}" "$APP_BUNDLE"
}


# Guards the download-size contract. A regression here is invisible in QA —
# the app behaves identically, it is just megabytes larger — so assert it.
verify_bundle_payload() {
  local signed_app="$1"
  local stray_svg
  stray_svg="$(/usr/bin/find "$signed_app/Contents/Resources" -name '*.svg' -print -quit)"
  [[ -z "$stray_svg" ]] || {
    echo "Bundle ships SVG regeneration sources that nothing loads: $stray_svg" >&2
    exit 1
  }
  if [[ "$ARCHIVE_MODE" == "1" ]]; then
    # `strip -S` removes the debug stabs; their presence means the strip was
    # skipped and the executable carries ~7 MB of DWARF per architecture.
    local stabs
    stabs="$(/usr/bin/nm -arch arm64 -a "$signed_app/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null \
      | /usr/bin/grep -c ' OSO ' || true)"
    (( stabs == 0 )) || {
      echo "Release executable still carries $stabs debug symbol entries; the strip did not run." >&2
      exit 1
    }
  fi
}

verify_bundle_for_mode() {
  local signed_app="$1"
  verify_universal_binary "$signed_app/Contents/MacOS/$EXECUTABLE_NAME" || {
    echo "Signed application executable is not universal." >&2
    exit 1
  }
  verify_bundle_payload "$signed_app"
  verify_bundle_identity "$signed_app"
}

if [[ "$MODE" == "--print-install-contract" || "$MODE" == "print-install-contract" ]]; then
  printf 'archive=%s\napp_name=%s\nexecutable=%s\nbundle_id=%s\ninstalled_app=%s\n' \
    "$ARCHIVE_MODE" "$APP_NAME" "$EXECUTABLE_NAME" "$BUNDLE_ID" "$INSTALLED_APP"
  exit 0
fi

if [[ "$MODE" != "--archive" && "$MODE" != "archive" ]]; then
  pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
fi
cd "$ROOT_DIR"
SWIFT_BUILD_ARGS=(--product "$PRODUCT_NAME" --arch arm64 --arch x86_64)
if [[ "$ARCHIVE_MODE" == "1" ]]; then
  SWIFT_BUILD_ARGS+=(--configuration release)
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
# A release executable carries ~7 MB of symbol table per architecture, which is
# larger than its own __TEXT. Archive the DWARF first, verify it describes the
# binary we are about to ship, then strip. Development builds keep their
# symbols so lldb still works against a locally built app.
if [[ "$ARCHIVE_MODE" == "1" ]]; then
  [[ -d "$BUILD_DIR/$PRODUCT_NAME.dSYM" ]] || {
    echo "Release build produced no $PRODUCT_NAME.dSYM; refusing to ship an unsymbolicatable binary." >&2
    exit 1
  }
  rm -rf "$APP_DSYM"
  /usr/bin/ditto "$BUILD_DIR/$PRODUCT_NAME.dSYM" "$APP_DSYM"
  # A stale dSYM symbolicates to the wrong source lines, which is worse than no
  # dSYM at all. Match the Mach-O UUIDs before trusting the archive.
  binary_uuids="$(/usr/bin/dwarfdump --uuid "$APP_BINARY" | /usr/bin/awk '{ print $2 }' | /usr/bin/sort)"
  dsym_uuids="$(/usr/bin/dwarfdump --uuid "$APP_DSYM" | /usr/bin/awk '{ print $2 }' | /usr/bin/sort)"
  [[ "$binary_uuids" == "$dsym_uuids" ]] || {
    echo "Archived dSYM does not match the built executable; refusing to strip." >&2
    exit 1
  }
  /usr/bin/strip -S -x "$APP_BINARY"
  verify_universal_binary "$APP_BINARY" || {
    echo "Stripping produced a non-universal executable." >&2
    exit 1
  }
fi
cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP_CONTENTS/Info.plist"
if [[ -n "$BROADCAST_BASE_URL" ]]; then
  if [[ "$BROADCAST_BASE_URL" != https://* && "$BROADCAST_BASE_URL" != http://localhost* \
    && "$BROADCAST_BASE_URL" != http://127.0.0.1* ]]; then
    echo "TOKENREMAIN_BROADCAST_BASE_URL must use HTTPS (localhost HTTP is allowed for development)." >&2
    exit 2
  fi
  /usr/libexec/PlistBuddy \
    -c "Add :TokenRemainBroadcastBaseURL string $BROADCAST_BASE_URL" \
    "$APP_CONTENTS/Info.plist"
fi
cp "$ROOT_DIR/Sources/UsageDock/Resources/claude.png" "$APP_RESOURCES/claude.png"
# BrandIcon only ever resolves `withExtension: "png"`. The SVGs beside them are
# the regeneration sources described in ProviderIcons/README.md and stay in the
# repository, but shipping them to users is dead weight.
# `--delete-excluded` rather than plain `--delete`: rsync treats an excluded
# file as protected on the receiver, so `--delete` alone would leave stale SVGs
# behind in any destination that already had them.
mkdir -p "$APP_RESOURCES/ProviderIcons"
/usr/bin/rsync -a --delete --delete-excluded --exclude='*.svg' --exclude='README.md' \
  "$ROOT_DIR/Sources/UsageDock/Resources/ProviderIcons/" "$APP_RESOURCES/ProviderIcons/"
cp "$ROOT_DIR/Sources/UsageDock/Resources/MyTokenRemain.icns" "$APP_RESOURCES/MyTokenRemain.icns"
# macOS 26+ draws the Icon Composer icon; a release must never ship without it.
if [[ "$ARCHIVE_MODE" == "1" ]]; then
  "$ROOT_DIR/script/compile_app_icon.sh" "$APP_RESOURCES" --required
else
  "$ROOT_DIR/script/compile_app_icon.sh" "$APP_RESOURCES"
fi
# Localized strings live in the app bundle so SwiftUI and NSLocalizedString
# automatically follow the system language or the per-app macOS language.
for localization in "$ROOT_DIR/Sources/UsageDock/Localization/"*.lproj; do
  cp -R "$localization" "$APP_RESOURCES/"
done
chmod +x "$APP_BINARY"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
    | head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "${USAGEDOCK_ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
    # Machines without an Apple Development certificate (CI, a secondary
    # Mac used only for verification) can opt into an ad-hoc signature.
    # Keychain items created by this build trust the ad-hoc CDHash, so they
    # survive relaunches but not rebuilds; production installs should still
    # use a stable Apple Development identity.
    SIGNING_IDENTITY="-"
    SIGNING_COMMON_NAME="Ad Hoc"
  else
    echo "TokenRemain needs an Apple Development signing identity to preserve Keychain approval." >&2
    exit 1
  fi
else
  SIGNING_COMMON_NAME="$(resolve_signing_common_name "$SIGNING_IDENTITY")"
  if [[ -z "$SIGNING_COMMON_NAME" ]]; then
    echo "Could not resolve the requested signing identity." >&2
    exit 1
  fi
fi
# Finder/File Provider metadata can be copied onto a local bundle and invalidate
# its resource seal. These are metadata only; the signed app never relies on them.
for attribute in com.apple.FinderInfo com.apple.fileprovider.fpfs#P com.apple.macl com.apple.provenance com.apple.quarantine; do
  /usr/bin/xattr -dr "$attribute" "$APP_BUNDLE" 2>/dev/null || true
done
sign_outer_bundle
# On File Provider-backed workspaces, codesign itself can cause provenance
# metadata to be re-applied to newly written signature files. Removing it after
# signing does not change the code signature and prevents dyld launch stalls.
/usr/bin/xattr -dr com.apple.provenance "$APP_BUNDLE" 2>/dev/null || true

verify_bundle_for_mode "$APP_BUNDLE"

if [[ "$MODE" == "--archive" || "$MODE" == "archive" ]]; then
  mkdir -p "$ARCHIVE_DIR"
  ARCHIVED_APP="$ARCHIVE_DIR/$APP_NAME.app"
  rm -rf "$ARCHIVED_APP"
  /usr/bin/ditto "$APP_BUNDLE" "$ARCHIVED_APP"
  /usr/bin/codesign --verify --deep --strict "$ARCHIVED_APP"
  verify_bundle_identity "$ARCHIVED_APP"
  # Keep the DWARF with the release it describes. Crash reports arrive months
  # later and the build tree is long gone by then.
  if [[ -d "$APP_DSYM" ]]; then
    rm -rf "$ARCHIVE_DIR/$APP_NAME.app.dSYM"
    /usr/bin/ditto "$APP_DSYM" "$ARCHIVE_DIR/$APP_NAME.app.dSYM"
  fi
  printf '%s\n' "$ARCHIVED_APP"
  exit 0
fi

# Run from the stable installed location. LaunchServices can refuse or stall on
# app bundles inside File Provider-backed development folders, while the
# installed path also gives Keychain and notification permissions a stable home.
mkdir -p "$INSTALL_DIR"
INCOMING_APP="$INSTALL_DIR/.${APP_NAME}.incoming.$$"
PREVIOUS_APP="$INSTALL_DIR/.${APP_NAME}.previous.$$"
rm -rf "$INCOMING_APP" "$PREVIOUS_APP"
/usr/bin/ditto "$APP_BUNDLE" "$INCOMING_APP"
for attribute in com.apple.FinderInfo com.apple.fileprovider.fpfs#P com.apple.macl com.apple.provenance com.apple.quarantine; do
  /usr/bin/xattr -dr "$attribute" "$INCOMING_APP" 2>/dev/null || true
done
verify_bundle_for_mode "$INCOMING_APP"
if [[ -e "$INSTALLED_APP" ]]; then
  /bin/mv "$INSTALLED_APP" "$PREVIOUS_APP"
fi
if ! /bin/mv "$INCOMING_APP" "$INSTALLED_APP"; then
  if [[ -e "$PREVIOUS_APP" ]]; then
    /bin/mv "$PREVIOUS_APP" "$INSTALLED_APP"
  fi
  echo "Could not install the verified app; the previous app was restored." >&2
  exit 1
fi
rm -rf "$PREVIOUS_APP"
verify_bundle_for_mode "$INSTALLED_APP"
for legacy_app in "${LEGACY_INSTALLED_APPS[@]}"; do
  rm -rf "$legacy_app"
done

open_app() {
  # LaunchServices may have already restored the login item after the pre-build
  # stop. Reuse that instance so a verified rebuild never leaves two copies
  # competing for the same status item.
  /usr/bin/open "$INSTALLED_APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == '$EXECUTABLE_NAME'"
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'"
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      # Match the executable name exactly. A full-command-line search can match
      # the build shell itself because its arguments contain the app path,
      # producing a false-positive launch verification.
      if pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.5
    done
    echo "$APP_NAME did not remain running after launch." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--archive]" >&2
    exit 2
    ;;
esac
