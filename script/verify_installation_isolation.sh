#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"

fail() {
  echo "installation isolation verification failed: $1" >&2
  exit 1
}

require_contract_value() {
  local output="$1"
  local expected="$2"
  /usr/bin/grep -Fqx -- "$expected" <<<"$output" \
    || fail "missing contract value '$expected'"
}

# Fork note: this fork ships a single app identity. Both plain and archive
# builds must agree on that identity; only the release configuration differs.
contract="$("$BUILD_SCRIPT" --print-install-contract)"

require_contract_value "$contract" "archive=0"
require_contract_value "$contract" "app_name=MyTokenRemain"
require_contract_value "$contract" "executable=UsageDock"
require_contract_value "$contract" "bundle_id=com.jingsan0801.mytokenremain"
/usr/bin/grep -Fq 'ARCHIVE_MODE=1' "$BUILD_SCRIPT" \
  || fail "archive mode is not derived from the build mode"

installed_app="$(/usr/bin/awk -F= '$1 == "installed_app" { print $2 }' <<<"$contract")"
[[ -n "$installed_app" ]] || fail "the contract does not name the installed app"
[[ "$installed_app" == */MyTokenRemain.app ]] \
  || fail "the installed app path is not the single stable bundle: $installed_app"

/usr/bin/grep -Fq 'verify_bundle_for_mode "$APP_BUNDLE"' "$BUILD_SCRIPT" \
  || fail "staged bundles are not verified before installation"
/usr/bin/grep -Fq 'verify_bundle_for_mode "$INCOMING_APP"' "$BUILD_SCRIPT" \
  || fail "incoming bundles are not verified before replacement"

echo "installation isolation verified: a single stable bundle with verified staging"
