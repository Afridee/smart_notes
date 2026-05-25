#!/usr/bin/env bash
set -euo pipefail

# Run from repo root regardless of cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${SCRIPT_DIR}/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "config.json not found: $CONFIG" >&2
  exit 1
fi

# pubspec.yaml: version: 1.0.0+1 → afridees_note_v1.0.0_b1.apk
VERSION_FULL="$(grep -E '^version:' pubspec.yaml | head -n1 | awk '{ print $2 }')"
IFS='+' read -r SEMVER BUILD_NUM <<<"${VERSION_FULL}"
BUILD_NUM="${BUILD_NUM:-0}"
APK_NAME="afridees_note_v${SEMVER}_b${BUILD_NUM}.apk"

fvm flutter clean
fvm flutter pub get
fvm flutter build apk --release --dart-define-from-file="${CONFIG}"

RELEASE_APK="${SCRIPT_DIR}/build/app/outputs/flutter-apk/app-release.apk"
OUT_DIR="$(dirname "${RELEASE_APK}")"

if [[ ! -f "${RELEASE_APK}" ]]; then
  echo "Expected APK not found: ${RELEASE_APK}" >&2
  exit 1
fi

DEST="${OUT_DIR}/${APK_NAME}"
mv "${RELEASE_APK}" "${DEST}"
echo "Built: ${DEST}"
