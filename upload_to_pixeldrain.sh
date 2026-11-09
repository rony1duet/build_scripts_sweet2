#!/usr/bin/env bash
#
# Pixeldrain Uploader for PixelOS sweet2
#

set -eo pipefail

readonly PIXELDRAIN_API_KEY="026168ac-08ec-4bdb-9dde-99c7635200b0"
readonly ROM_DIR="out/target/product/sweet2"

if [[ -n "$1" && -f "$1" ]]; then
    ROM_ZIP="$1"
else
    ROM_ZIP=$(ls -t "${ROM_DIR}"/PixelOS_*.zip "${ROM_DIR}"/*sweet2*.zip 2>/dev/null | head -n 1)
fi

if [[ -z "$ROM_ZIP" || ! -f "$ROM_ZIP" ]]; then
    echo "[!] No ROM zip found in ${ROM_DIR}"
    exit 1
fi

FILENAME=$(basename "$ROM_ZIP")
SIZE=$(du -h "$ROM_ZIP" | cut -f1)

echo "==> Target: ${FILENAME} (${SIZE})"
echo "==> Uploading to Pixeldrain..."

TMP_RESP=$(mktemp /tmp/pixeldrain_resp.XXXXXX.json 2>/dev/null || echo "/tmp/pixeldrain_resp_$$.json")
trap 'rm -f "$TMP_RESP"' EXIT

# Pixeldrain streaming PUT to /api/file/{filename} (faster, no multipart boundary overhead)
HTTP_CODE=$(curl --progress-bar -L --retry 3 \
    --user ":${PIXELDRAIN_API_KEY}" \
    --upload-file "${ROM_ZIP}" \
    -w "%{http_code}" \
    -o "$TMP_RESP" \
    "https://pixeldrain.com/api/file/${FILENAME}" || true)

RESPONSE=$(cat "$TMP_RESP" 2>/dev/null || true)

FILE_ID=$(python3 -c "import json, sys; print(json.loads(sys.argv[1]).get('id', ''))" "$RESPONSE" 2>/dev/null || \
          echo "$RESPONSE" | grep -oP '"id":\s*"\K[^"]+' || true)

# If PUT did not return an ID, fallback to multipart POST /api/file (without trailing slash)
if [[ -z "$FILE_ID" ]]; then
    echo "[!] PUT upload returned HTTP ${HTTP_CODE}. Attempting POST fallback..."
    HTTP_CODE=$(curl --progress-bar -L --retry 3 \
        --user ":${PIXELDRAIN_API_KEY}" \
        --form "file=@${ROM_ZIP};filename=${FILENAME}" \
        -w "%{http_code}" \
        -o "$TMP_RESP" \
        "https://pixeldrain.com/api/file" || true)

    RESPONSE=$(cat "$TMP_RESP" 2>/dev/null || true)
    FILE_ID=$(python3 -c "import json, sys; print(json.loads(sys.argv[1]).get('id', ''))" "$RESPONSE" 2>/dev/null || \
              echo "$RESPONSE" | grep -oP '"id":\s*"\K[^"]+' || true)
fi

if [[ -z "$FILE_ID" ]]; then
    echo "[!] Upload failed. Server response (HTTP ${HTTP_CODE}):"
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
