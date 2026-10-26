
#!/usr/bin/env bash
# Pixeldrain upload script for Crave.io PixelOS builds
# Preserves the original ROM ZIP filename.

set -Eeuo pipefail

# ==================================================
# CONFIGURATION
# ==================================================

PIXELDRAIN_API_KEY="026168ac-08ec-4bdb-9dde-99c7635200b0"

ROM_DIR="out/target/product/sweet2"
PIXELDRAIN_API_URL="https://pixeldrain.com/api/file/"

# ==================================================
# COLORS AND LOGGING
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# ==================================================
# CHECK DEPENDENCIES
# ==================================================

command -v curl >/dev/null 2>&1 ||
    die "curl is not installed."

command -v python3 >/dev/null 2>&1 ||
    die "python3 is not installed."

[[ "$PIXELDRAIN_API_KEY" != "YOUR_PIXeldrain_API_KEY" ]] ||
    die "Set your Pixeldrain API key in the configuration section."

[[ -n "$PIXELDRAIN_API_KEY" ]] ||
    die "Pixeldrain API key is empty."

# ==================================================
# FIND ROM ZIP
# ==================================================

[[ -d "$ROM_DIR" ]] ||
    die "ROM directory not found: $ROM_DIR"

shopt -s nullglob

CANDIDATES=(
    "$ROM_DIR"/PixelOS_*.zip
    "$ROM_DIR"/aosp_*.zip
    "$ROM_DIR"/*sweet2*.zip
)

shopt -u nullglob

# Keep only files and remove duplicate paths.
declare -A SEEN=()
ZIP_FILES=()

for file in "${CANDIDATES[@]}"; do
    [[ -f "$file" ]] || continue

    if [[ -z "${SEEN["$file"]+yes}" ]]; then
        SEEN["$file"]=1
        ZIP_FILES+=("$file")
    fi
done

((${#ZIP_FILES[@]} > 0)) || {
    log_error "No matching ROM ZIP found in $ROM_DIR"
    ls -lah "$ROM_DIR" || true
    exit 1
}

# Select the newest ZIP by modification time.
ROM_ZIP=""

for file in "${ZIP_FILES[@]}"; do
    if [[ -z "$ROM_ZIP" ]] ||
       [[ "$file" -nt "$ROM_ZIP" ]]; then
        ROM_ZIP="$file"
    fi
done

[[ -f "$ROM_ZIP" ]] ||
    die "Unable to select a ROM ZIP."

# Preserve the original filename.
ORIGINAL_FILENAME="$(basename "$ROM_ZIP")"
FILE_SIZE="$(stat -c '%s' "$ROM_ZIP")"
HUMAN_SIZE="$(du -h "$ROM_ZIP" | cut -f1)"

log_info "Selected ROM: $ORIGINAL_FILENAME"
log_info "File size: $HUMAN_SIZE"
log_info "Starting Pixeldrain upload..."

# ==================================================
# UPLOAD TO PIXELDRAIN
# ==================================================

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

if ! HTTP_STATUS="$(
    curl --location \
        --silent \
        --show-error \
        --fail-with-body \
        --progress-bar \
        --connect-timeout 30 \
        --max-time 0 \
        --user ":${PIXELDRAIN_API_KEY}" \
        --form "file=@${ROM_ZIP};filename=${ORIGINAL_FILENAME}" \
        --output "$RESPONSE_FILE" \
        --write-out '%{http_code}' \
        "$PIXELDRAIN_API_URL"
)"; then
    log_error "Pixeldrain upload request failed."

    if [[ -s "$RESPONSE_FILE" ]]; then
        cat "$RESPONSE_FILE"
        printf '\n'
    fi

    exit 1
fi

log_info "HTTP Status: $HTTP_STATUS"

# ==================================================
# PARSE RESPONSE
# ==================================================

FILE_ID="$(
    python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        response = json.load(f)

    if response.get("success") is True:
        print(response.get("id", ""), end="")
    else:
        print("", end="")
except (OSError, json.JSONDecodeError):
    print("", end="")
PY
)"

if [[ -z "$FILE_ID" ]]; then
    log_error "Upload response did not contain a successful file ID."
    cat "$RESPONSE_FILE"
    printf '\n'
    exit 1
fi

# ==================================================
# GENERATE DOWNLOAD LINKS
# ==================================================

FILE_URL="https://pixeldrain.com/u/${FILE_ID}"
DIRECT_URL="https://pixeldrain.com/api/file/${FILE_ID}"

# ==================================================
# SAVE BUILD INFORMATION
# ==================================================

INFO_FILE="${ROM_DIR}/pixeldrain_info_$(date +%Y%m%d_%H%M%S).json"

python3 - "$INFO_FILE" "$ORIGINAL_FILENAME" "$FILE_SIZE" \
    "$FILE_ID" "$FILE_URL" "$DIRECT_URL" <<'PY'
import json
import sys
from datetime import datetime, timezone

(
    path,
    filename,
    size,
    file_id,
    page_url,
    direct_url,
) = sys.argv[1:]

info = {
    "rom": "PixelOS",
    "device": "sweet2",
    "build_date_utc": datetime.now(timezone.utc).strftime(
        "%Y-%m-%d %H:%M:%S UTC"
    ),
    "file_name": filename,
    "file_size_bytes": int(size),
    "pixeldrain_id": file_id,
    "download_url": page_url,
    "direct_url": direct_url,
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(info, f, indent=2)
    f.write("\n")
PY

# ==================================================
# FINAL SUMMARY
# ==================================================

printf '\n'
printf '%s\n' "============================================"
log_info "PIXELDRAIN UPLOAD SUCCESSFUL"
printf '%s\n' "============================================"

printf 'Original filename : %s\n' "$ORIGINAL_FILENAME"
printf 'File size         : %s\n' "$HUMAN_SIZE"
printf 'HTTP status       : %s\n' "$HTTP_STATUS"
printf 'Pixeldrain ID     : %s\n' "$FILE_ID"
printf 'Share URL         : %s\n' "$FILE_URL"
printf 'Direct download   : %s\n' "$DIRECT_URL"
printf 'Build info JSON   : %s\n' "$INFO_FILE"

printf '%s\n' "============================================"

# CI/CD output
printf 'PIXELDRAIN_FILE_ID=%s\n' "$FILE_ID"
printf 'PIXELDRAIN_URL=%s\n' "$FILE_URL"
printf 'PIXELDRAIN_DIRECT_URL=%s\n' "$DIRECT_URL"
printf 'PIXELDRAIN_FILENAME=%s\n' "$ORIGINAL_FILENAME"

log_info "Done!"
