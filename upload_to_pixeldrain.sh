#!/usr/bin/env bash
# Pixeldrain upload script for Crave builds
# Reads API key from PIXELDRAIN_API_KEY environment variable

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for API key
if [ -z "$PIXELDRAIN_API_KEY" ]; then
    log_error "PIXELDRAIN_API_KEY environment variable not set"
    log_info "Set it in Crave secrets or export before running"
    exit 1
fi

# Find the built ROM zip
# PixelOS typically outputs to out/target/product/sweet2/
ROM_DIR="out/target/product/sweet2"
if [ ! -d "$ROM_DIR" ]; then
    log_error "ROM directory not found: $ROM_DIR"
    exit 1
fi

# Find the latest PixelOS zip
ROM_ZIP=$(ls -t "$ROM_DIR"/PixelOS_*.zip 2>/dev/null | head -1)
if [ -z "$ROM_ZIP" ]; then
    log_error "No PixelOS zip found in $ROM_DIR"
    ls -la "$ROM_DIR"
    exit 1
fi

log_info "Found ROM: $ROM_ZIP"
log_info "File size: $(du -h "$ROM_ZIP" | cut -f1)"

# Upload to Pixeldrain
log_info "Uploading to Pixeldrain..."

UPLOAD_RESPONSE=$(curl -s -T "$ROM_ZIP" \
    -u ":$PIXELDRAIN_API_KEY" \
    "https://pixeldrain.com/api/file/" \
    -H "Accept: application/json")

# Check if upload was successful
FILE_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$FILE_ID" ]; then
    log_error "Upload failed. Response:"
    echo "$UPLOAD_RESPONSE"
    exit 1
fi

FILE_URL="https://pixeldrain.com/u/$FILE_ID"
log_info "Upload successful!"
log_info "File ID: $FILE_ID"
log_info "Download URL: $FILE_URL"

# Also create a direct download link
DIRECT_URL="https://pixeldrain.com/api/file/$FILE_ID"
log_info "Direct download: $DIRECT_URL"

# Output for CI/CD parsing
echo "PIXELDRAIN_FILE_ID=$FILE_ID"
echo "PIXELDRAIN_URL=$FILE_URL"
echo "PIXELDRAIN_DIRECT_URL=$DIRECT_URL"

# Optional: Upload JSON info file
INFO_FILE="/tmp/build_info_$(date +%Y%m%d_%H%M%S).json"
cat > "$INFO_FILE" << EOF
{
  "rom": "PixelOS",
  "device": "sweet2",
  "build_date": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "file_name": "$(basename "$ROM_ZIP")",
  "file_size": "$(stat -c%s "$ROM_ZIP")",
  "pixeldrain_id": "$FILE_ID",
  "download_url": "$FILE_URL",
  "direct_url": "$DIRECT_URL"
}
EOF

log_info "Build info saved to: $INFO_FILE"
cat "$INFO_FILE"

log_info "Done!"