#!/usr/bin/env bash
set -euo pipefail

ROM_MANIFEST_BRANCH="sixteen-qpr2"

echo "==========================================="
echo "Initializing PixelOS ${ROM_MANIFEST_BRANCH}..."
echo "==========================================="
repo init \
    -u https://github.com/PixelOS-AOSP/android_manifest.git \
    -b "${ROM_MANIFEST_BRANCH}" \
    --git-lfs \
    --depth=1

echo "==========================================="
echo "Setting up local manifest..."
echo "==========================================="
rm -rf .repo/local_manifests/
git clone https://github.com/rony1duet/manifest_sweet2.git .repo/local_manifests -b main --depth=1

echo "==========================================="
echo "Syncing repositories on Crave..."
echo "==========================================="
/opt/crave/resync.sh

echo "==========================================="
echo "Setting up KernelSU-Next (sm6150)..."
echo "==========================================="
if [ -d "kernel/xiaomi/sm6150" ]; then
    (cd kernel/xiaomi/sm6150 && curl -LSs "https://raw.githubusercontent.com/manipvlator/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s main) || echo "KernelSU already applied or skipped"
fi

echo "==========================================="
echo "Fetching GCam prebuilts & libs..."
echo "==========================================="
bash vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh \
    vendor/GCam_sweet2/system/product/app/GoogleCameraEng

echo "==========================================="
echo "Exporting build environment variables..."
echo "==========================================="
export BUILD_USERNAME=rony1duet
export BUILD_HOSTNAME=crave
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true

echo "==========================================="
echo "Starting PixelOS sweet2 build..."
echo "==========================================="
source build/envsetup.sh
breakfast sweet2
m pixelos

