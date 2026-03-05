#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v1.8.24}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${ROOT_DIR}/XrayVPNApp/Resources"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64)
    ARCHIVE="Xray-macos-arm64-v8a.zip"
    ;;
  x86_64)
    ARCHIVE="Xray-macos-64.zip"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

URL="https://github.com/XTLS/Xray-core/releases/download/${VERSION}/${ARCHIVE}"
ZIP_PATH="${TMP_DIR}/xray.zip"
UNPACK_DIR="${TMP_DIR}/unpacked"

mkdir -p "${DEST_DIR}" "${UNPACK_DIR}"

echo "Downloading ${URL}"
curl -fL "${URL}" -o "${ZIP_PATH}"

ditto -xk "${ZIP_PATH}" "${UNPACK_DIR}"

if [[ ! -f "${UNPACK_DIR}/xray" ]]; then
  echo "xray binary was not found in downloaded archive" >&2
  exit 1
fi

cp "${UNPACK_DIR}/xray" "${DEST_DIR}/xray"
chmod +x "${DEST_DIR}/xray"

for asset in geoip.dat geosite.dat; do
  if [[ -f "${UNPACK_DIR}/${asset}" ]]; then
    cp "${UNPACK_DIR}/${asset}" "${DEST_DIR}/${asset}"
  fi
done

echo "Installed xray artifacts into ${DEST_DIR}"
