#!/usr/bin/env bash
# Downloads Eigen headers into third_party/eigen/.
# Eigen is header-only; the same headers work for macOS and iOS.
# third_party/eigen/ is .gitignored — run this before building with
# CAMERASUTRA_ENABLE_OPENVINS_RUNTIME=1.
set -euo pipefail

# Keep in sync with the Homebrew Eigen version used to compile the OpenVINS
# static library so template instantiations match at link time.
# (Homebrew formula: https://gitlab.com/libeigen/eigen/-/archive/5.0.1/eigen-5.0.1.tar.gz)
EIGEN_VERSION="${EIGEN_VERSION:-5.0.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/third_party/eigen"

if [ -d "$OUTPUT/Eigen" ]; then
  echo "Eigen headers already present at $OUTPUT — skipping download."
  exit 0
fi

ARCHIVE_URL="https://gitlab.com/libeigen/eigen/-/archive/${EIGEN_VERSION}/eigen-${EIGEN_VERSION}.tar.gz"
TMP_ARCHIVE="$ROOT_DIR/third_party/eigen-download.tar.gz"

mkdir -p "$ROOT_DIR/third_party"
echo "Downloading Eigen ${EIGEN_VERSION}..."
curl -L --progress-bar -o "$TMP_ARCHIVE" "$ARCHIVE_URL"

echo "Extracting..."
TMP_EXTRACT="$ROOT_DIR/third_party/_eigen_extract"
rm -rf "$TMP_EXTRACT"
mkdir -p "$TMP_EXTRACT"
tar -xzf "$TMP_ARCHIVE" -C "$TMP_EXTRACT"
rm -f "$TMP_ARCHIVE"

# The tarball extracts to eigen-<version>/
EXTRACTED_DIR=$(find "$TMP_EXTRACT" -maxdepth 1 -name "eigen-*" -type d | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
  echo "error: could not find extracted Eigen directory" >&2
  rm -rf "$TMP_EXTRACT"
  exit 1
fi

rm -rf "$OUTPUT"
mv "$EXTRACTED_DIR" "$OUTPUT"
rm -rf "$TMP_EXTRACT"

echo ""
echo "Eigen ${EIGEN_VERSION} headers ready at:"
echo "  $OUTPUT"
