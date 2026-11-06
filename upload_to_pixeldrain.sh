#!/usr/bin/env bash
#
# Pixeldrain Uploader for PixelOS sweet2
#

set -eo pipefail

readonly PIXELDRAIN_API_KEY="026168ac-08ec-4bdb-9dde-99c7635200b0"
readonly ROM_DIR="out/target/product/sweet2"

ROM_ZIP=$(ls -t "${ROM_DIR}"/PixelOS_*.zip "${ROM_DIR}"/*sweet2*.zip 2>/dev/null | head -n 1)

if [[ -z "$ROM_ZIP" || ! -f "$ROM_ZIP" ]]; then
    echo "[!] No ROM zip found in ${ROM_DIR}"
    exit 1
fi

FILENAME=$(basename "$ROM_ZIP")
SIZE=$(du -h "$ROM_ZIP" | cut -f1)

echo "==> Target: ${FILENAME} (${SIZE})"
echo "==> Uploading to Pixeldrain..."

RESPONSE=$(curl -s --progress-bar --user ":${PIXELDRAIN_API_KEY}" \
    --form "file=@${ROM_ZIP};filename=${FILENAME}" \
    "https://pixeldrain.com/api/file/")

FILE_ID=$(python3 -c "import json, sys; print(json.loads(sys.argv[1]).get('id', ''))" "$RESPONSE" 2>/dev/null || \
          echo "$RESPONSE" | grep -oP '"id":\s*"\K[^"]+' || true)

if [[ -z "$FILE_ID" ]]; then
    echo "[!] Upload failed. Server response:"
    echo "$RESPONSE"
    exit 1
fi

URL="https://pixeldrain.com/u/${FILE_ID}"
DIRECT_URL="https://pixeldrain.com/api/file/${FILE_ID}"

echo ""
echo "========================================"
echo "  Upload Successful!"
echo "  File:   ${FILENAME} (${SIZE})"
echo "  Link:   ${URL}"
echo "  Direct: ${DIRECT_URL}"
echo "========================================"
