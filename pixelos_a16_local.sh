#!/usr/bin/env bash
set -e

# ---------------- Config ----------------
ROM_MANIFEST_URL="https://github.com/PixelOS-AOSP/android_manifest.git"
ROM_MANIFEST_BRANCH="sixteen-qpr2"
SOURCE_DIR="/mnt/build_drive/pixelos"          # on /dev/sda2
DEVICE="sweet2"

BUILD_JOBS=1                                  # lower to 8 if the build gets OOM-killed
SYNC_JOBS=2
MAX_SYNC_RETRIES=10
MIN_FREE_GB=40                                 # min free on the source drive (sda2)
MIN_FREE_CACHE_GB=40                           # min free on sdb2 before building

# Everything below lives on /dev/sdb2 (mounted at /mnt/cache_drive)
CCACHE_DIR="/mnt/cache_drive/ccache"
CCACHE_SIZE="25G"
OUT_DIR_PATH="/mnt/cache_drive/pixelos_out"
SWAP_FILE="/swapfile"
SWAP_SIZE_GB=16

RUN_SYNC=false                                  # set false on later runs
RUN_GC=false                                    # one-time cleanup; set false afterwards

LOCAL_MANIFEST_FILE=".repo/local_manifests/sweet2.xml"

# ---------------- Helpers ----------------
free_gb() { df -BG --output=avail "${1:-.}" | tail -1 | tr -dc '0-9'; }

# ---------------- Pre-checks ----------------
cd "${SOURCE_DIR}" || { echo "ERROR: ${SOURCE_DIR} not found."; exit 1; }

git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000

echo "Source drive (sda2) free: $(free_gb .) GB"
if [ "$(free_gb .)" -lt "${MIN_FREE_GB}" ]; then
  echo "ERROR: less than ${MIN_FREE_GB} GB free on the source drive."
  exit 1
fi

CACHE_MOUNT="$(dirname "${CCACHE_DIR}")"
mkdir -p "${CCACHE_DIR}" "${OUT_DIR_PATH}"
if [ ! -w "${CCACHE_DIR}" ] || [ ! -w "${OUT_DIR_PATH}" ]; then
  echo "ERROR: ${CCACHE_DIR} or ${OUT_DIR_PATH} is not writable by $(whoami)."
  exit 1
fi
echo "sdb2 free: $(free_gb "${CACHE_MOUNT}") GB"

# ---------------- Swap (16 GB on sdb2) ----------------
if ! swapon --show=NAME --noheadings | grep -qx "${SWAP_FILE}"; then
  echo "Setting up ${SWAP_SIZE_GB} GB swap at ${SWAP_FILE}..."
  if [ ! -f "${SWAP_FILE}" ]; then
    sudo fallocate -l "${SWAP_SIZE_GB}G" "${SWAP_FILE}" \
      || sudo dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    sudo chmod 600 "${SWAP_FILE}"
    sudo mkswap "${SWAP_FILE}"
  fi
  sudo swapon "${SWAP_FILE}"
fi
swapon --show

# ---------------- Init + Sync ----------------
if [ "${RUN_SYNC}" = true ]; then
  if ! git ls-remote --exit-code --heads "${ROM_MANIFEST_URL}" "${ROM_MANIFEST_BRANCH}" >/dev/null 2>&1; then
    echo "ERROR: Branch '${ROM_MANIFEST_BRANCH}' not found in ${ROM_MANIFEST_URL}"
    exit 1
  fi

  echo "Initializing PixelOS ${ROM_MANIFEST_BRANCH}..."
  repo init -u "${ROM_MANIFEST_URL}" -b "${ROM_MANIFEST_BRANCH}" --git-lfs

  if [ ! -f "${LOCAL_MANIFEST_FILE}" ]; then
    echo "ERROR: ${LOCAL_MANIFEST_FILE} not found."
    exit 1
  fi

  echo "Syncing repositories..."
  attempt=1
  until repo sync -c -j"${SYNC_JOBS}" --force-sync --no-clone-bundle --no-tags \
        --optimized-fetch --retry-fetches=5; do
    if [ "${attempt}" -ge "${MAX_SYNC_RETRIES}" ]; then
      echo "ERROR: Sync failed after ${MAX_SYNC_RETRIES} attempts."
      exit 1
    fi
    echo "Sync failed (attempt ${attempt}/${MAX_SYNC_RETRIES}), retrying in 15s..."
    attempt=$((attempt + 1))
    sleep 15
  done
  echo "Sync completed. Free space: $(free_gb .) GB"
fi

# ---------------- Reclaim space from old-branch objects ----------------
if [ "${RUN_GC}" = true ]; then
  echo "Cleaning unreferenced git objects (slow, one-time)..."
  repo forall -j"${SYNC_JOBS}" -c 'git reflog expire --expire=now --all && git gc --prune=now --quiet' || true
  echo "Free space after cleanup: $(free_gb .) GB"
fi

# ---------------- KernelSU-Next ----------------
if [ -d "kernel/xiaomi/sm6150" ]; then
  rm -rf kernel/xiaomi/sm6150/KernelSU kernel/xiaomi/sm6150/drivers/kernelsu
  (cd kernel/xiaomi/sm6150 && \
    curl -LSs "https://raw.githubusercontent.com/manipvlator/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s main) \
    || echo "KernelSU already applied or skipped"
fi

# ---------------- GCam prebuilts ----------------
if [ -f "vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh" ]; then
  bash vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh \
    vendor/GCam_sweet2/system/product/app/GoogleCameraEng
fi


# ---------------- Bind-mount out/ onto the other drive ----------------
# Soong requires out/ inside the source tree, so OUT_DIR can't point elsewhere.
unset OUT_DIR
mkdir -p "${SOURCE_DIR}/out"
if ! mountpoint -q "${SOURCE_DIR}/out"; then
  sudo mount --bind "${OUT_DIR_PATH}" "${SOURCE_DIR}/out"
fi


# ---------------- Build env ----------------
export BUILD_USERNAME=rony1duet
export BUILD_HOSTNAME=Ubuntu
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true

export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR
export CCACHE_COMPRESS=1
ccache -M "${CCACHE_SIZE}" >/dev/null 2>&1 || true


if [ "$(free_gb "${CACHE_MOUNT}")" -lt "${MIN_FREE_CACHE_GB}" ]; then
  echo "ERROR: less than ${MIN_FREE_CACHE_GB} GB free on sdb2. Free space before building."
  exit 1
fi
echo "Free before build: sda2 $(free_gb .) GB | sdb2 $(free_gb "${CACHE_MOUNT}") GB"

# Ensure all sepolicy files have UNIX line endings
find device/ hardware/ vendor/ system/ -path "*/sepolicy/*" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true

# ---------------- Build ----------------
# envsetup.sh and breakfast are shell functions that may return non-zero
# internally, so disable 'set -e' here and check results explicitly.
set +e
# shellcheck disable=SC1091
source build/envsetup.sh

# Lunch
breakfast "${DEVICE}"
if [ $? -ne 0 ]; then
  echo "ERROR: 'breakfast ${DEVICE}' failed. Paste the error lines above for help."
  exit 1
fi

# Build
m pixelos -j"${BUILD_JOBS}"
BUILD_RC=$?
if [ "${BUILD_RC}" -ne 0 ]; then
  echo "ERROR: build failed (exit ${BUILD_RC}). Check ${SOURCE_DIR}/out/error.log"
  exit "${BUILD_RC}"
fi

echo "Build finished. Output: ${SOURCE_DIR}/out/target/product/${DEVICE}/"