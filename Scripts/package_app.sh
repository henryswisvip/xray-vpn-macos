#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/XrayVPN.xcodeproj"
SCHEME="XrayVPNApp"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"

TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ ! -x "${ROOT_DIR}/XrayVPNApp/Resources/xray" ]]; then
  echo "xray binary not found in app resources. Downloading it first..."
  "${ROOT_DIR}/Scripts/fetch_xray.sh"
fi

"${ROOT_DIR}/Scripts/generate_project.sh"

APP_PATH=""
EXPECTED_APP_NAME="${SCHEME}.app"

if [[ -n "${TEAM_ID}" ]]; then
  echo "Building signed archive with TEAM_ID=${TEAM_ID}"
  ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
  rm -rf "${ARCHIVE_PATH}"

  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    clean archive

  APP_PATH="${ARCHIVE_PATH}/Products/Applications/${EXPECTED_APP_NAME}"
  if [[ ! -d "${APP_PATH}" ]]; then
    APP_PATH="$(find "${ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
  fi
else
  echo "TEAM_ID is not set. Building unsigned app (users may need to bypass Gatekeeper)."
  DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
  rm -rf "${DERIVED_DATA_PATH}"

  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean build

  APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${EXPECTED_APP_NAME}"
  if [[ ! -d "${APP_PATH}" ]]; then
    APP_PATH="$(find "${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
  fi
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build succeeded but app was not found at ${APP_PATH}" >&2
  exit 1
fi

APP_BASENAME="$(basename "${APP_PATH}")"
APP_STEM="${APP_BASENAME%.app}"

OUTPUT_APP="${DIST_DIR}/${APP_BASENAME}"
OUTPUT_ZIP="${DIST_DIR}/${APP_STEM}-${STAMP}.zip"

rm -rf "${OUTPUT_APP}" "${OUTPUT_ZIP}"
cp -R "${APP_PATH}" "${OUTPUT_APP}"

ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_APP}" "${OUTPUT_ZIP}"

if [[ -n "${TEAM_ID}" && -n "${NOTARY_PROFILE}" ]]; then
  echo "Submitting zip for notarization using keychain profile '${NOTARY_PROFILE}'..."
  xcrun notarytool submit "${OUTPUT_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait

  echo "Stapling notarization ticket to app..."
  xcrun stapler staple "${OUTPUT_APP}"

  NOTARIZED_ZIP="${DIST_DIR}/${APP_STEM}-${STAMP}-notarized.zip"
  rm -f "${NOTARIZED_ZIP}"
  ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_APP}" "${NOTARIZED_ZIP}"
  OUTPUT_ZIP="${NOTARIZED_ZIP}"
fi

echo ""
echo "App bundle: ${OUTPUT_APP}"
echo "Shareable zip: ${OUTPUT_ZIP}"
echo ""
echo "Recipients do NOT need Xcode or a separate Xray install."
