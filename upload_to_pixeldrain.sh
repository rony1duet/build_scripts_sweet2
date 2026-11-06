#!/usr/bin/env bash
#
# Pixeldrain Release Uploader for Crave.io PixelOS builds
# Maintainer: rony1duet
#

set -Eeuo pipefail

readonly PIXELDRAIN_API_KEY="026168ac-08ec-4bdb-9dde-99c7635200b0"
readonly PIXELDRAIN_API_URL="https://pixeldrain.com/api/file/"
readonly ROM_DIR="out/target/product/sweet2"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log_info()  { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

check_dependencies() {
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v python3 >/dev/null 2>&1 || die "python3 is required"

    [[ -n "$PIXELDRAIN_API_KEY" ]] || die "Pixeldrain API key is empty"
    [[ -d "$ROM_DIR" ]] || die "ROM directory not found: $ROM_DIR"
}

find_rom_zip() {
    shopt -s nullglob
    local candidates=(
        "$ROM_DIR"/PixelOS_*.zip
        "$ROM_DIR"/aosp_*.zip
        "$ROM_DIR"/*sweet2*.zip
    )
    shopt -u nullglob

    declare -A seen=()
    local zip_files=()

    for file in "${candidates[@]}"; do
        [[ -f "$file" ]] || continue
        if [[ -z "${seen["$file"]+yes}" ]]; then
            seen["$file"]=1
            zip_files+=("$file")
        fi
    done

    ((${#zip_files[@]} > 0)) || {
        log_error "No matching ROM ZIP found in $ROM_DIR"
        ls -lah "$ROM_DIR" 2>/dev/null || true
        exit 1
    }

    local newest=""
    for file in "${zip_files[@]}"; do
        if [[ -z "$newest" ]] || [[ "$file" -nt "$newest" ]]; then
            newest="$file"
        fi
    done

    [[ -f "$newest" ]] || die "Target ROM zip resolution failed"
    printf "%s" "$newest"
}

upload_file() {
    local rom_zip="$1"
    local filename="$2"
    local response_file="$3"

    log_info "Uploading $filename to Pixeldrain..."

    local http_code
    if ! http_code="$(
        curl --location \
            --silent \
            --show-error \
            --fail-with-body \
            --progress-bar \
            --connect-timeout 30 \
            --max-time 0 \
            --user ":${PIXELDRAIN_API_KEY}" \
            --form "file=@${rom_zip};filename=${filename}" \
            --output "$response_file" \
            --write-out '%{http_code}' \
            "$PIXELDRAIN_API_URL"
    )"; then
        log_error "Pixeldrain upload request failed."
        [[ -s "$response_file" ]] && cat "$response_file" && printf '\n'
        exit 1
    fi

    printf "%s" "$http_code"
}

parse_file_id() {
    local response_file="$1"

    local file_id
    file_id="$(
        python3 - "$response_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    if data.get("success") is True:
        print(data.get("id", ""), end="")
except (OSError, json.JSONDecodeError):
    pass
PY
    )"

    [[ -n "$file_id" ]] || die "Upload response did not return a valid file ID"
    printf "%s" "$file_id"
}

save_build_metadata() {
    local filename="$1"
    local size="$2"
    local file_id="$3"
    local page_url="$4"
    local direct_url="$5"
    local info_path="${ROM_DIR}/pixeldrain_info_$(date +%Y%m%d_%H%M%S).json"

    python3 - "$info_path" "$filename" "$size" "$file_id" "$page_url" "$direct_url" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, filename, size, file_id, page_url, direct_url = sys.argv[1:]

info = {
    "rom": "PixelOS",
    "device": "sweet2",
    "build_date_utc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
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

    printf "%s" "$info_path"
}

main() {
    check_dependencies

    local rom_zip
    rom_zip="$(find_rom_zip)"

    local original_filename
    original_filename="$(basename "$rom_zip")"

    local file_size
    file_size="$(stat -c '%s' "$rom_zip")"

    local human_size
    human_size="$(du -h "$rom_zip" | cut -f1)"

    log_info "Target ROM : $original_filename"
    log_info "Size       : $human_size"

    local response_file
    response_file="$(mktemp)"
    trap 'rm -f "$response_file"' EXIT

    local http_status
    http_status="$(upload_file "$rom_zip" "$original_filename" "$response_file")"
    log_info "HTTP Status: $http_status"

    local file_id
    file_id="$(parse_file_id "$response_file")"

    local file_url="https://pixeldrain.com/u/${file_id}"
    local direct_url="https://pixeldrain.com/api/file/${file_id}"

    local info_file
    info_file="$(save_build_metadata "$original_filename" "$file_size" "$file_id" "$file_url" "$direct_url")"

    printf '\n'
    printf '%s\n' "============================================"
    log_info "PIXELDRAIN UPLOAD SUCCESSFUL"
    printf '%s\n' "============================================"
    printf 'Filename        : %s\n' "$original_filename"
    printf 'Size            : %s\n' "$human_size"
    printf 'HTTP Status     : %s\n' "$http_status"
    printf 'Pixeldrain ID   : %s\n' "$file_id"
    printf 'Share URL       : %s\n' "$file_url"
    printf 'Direct Download : %s\n' "$direct_url"
    printf 'Metadata JSON   : %s\n' "$info_file"
    printf '%s\n' "============================================"

    printf 'PIXELDRAIN_FILE_ID=%s\n' "$file_id"
    printf 'PIXELDRAIN_URL=%s\n' "$file_url"
    printf 'PIXELDRAIN_DIRECT_URL=%s\n' "$direct_url"
    printf 'PIXELDRAIN_FILENAME=%s\n' "$original_filename"

    log_info "Done."
}

main "$@"
