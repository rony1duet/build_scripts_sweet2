#!/usr/bin/env bash

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
git clone https://github.com/rony1duet/manifest_sweet2.git .repo/local_manifests -b main

# Clean unstaged modifications from prior builds that prevent clean repo sync
repo forall -c "git reset --hard HEAD && git clean -fdx" 2>/dev/null || true
for repo_dir in kernel/xiaomi/sm6150 device/xiaomi/sweet2 device/xiaomi/sm6150-common vendor/xiaomi/sweet2 vendor/xiaomi/sm6150-common hardware/xiaomi hardware/dolby; do
    if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" reset --hard HEAD 2>/dev/null || true
        git -C "$repo_dir" clean -fdx 2>/dev/null || true
    fi
done

echo "==========================================="
echo "Syncing repositories on Crave..."
echo "==========================================="
/opt/crave/resync.sh

echo "==========================================="
echo "Ensuring UNIX line endings on policy files..."
echo "==========================================="
find device/ hardware/ vendor/ system/ -path "*/sepolicy/*" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true

echo "==========================================="
echo "Setting up KernelSU-Next (sm6150)..."
echo "==========================================="
if [ -d "kernel/xiaomi/sm6150" ]; then
    rm -rf kernel/xiaomi/sm6150/KernelSU kernel/xiaomi/sm6150/drivers/kernelsu
    (cd kernel/xiaomi/sm6150 && curl -LSs "https://raw.githubusercontent.com/manipvlator/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s main) || echo "KernelSU already applied or skipped"
fi


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

echo "==========================================="
echo "Build complete! Uploading to Pixeldrain..."
echo "==========================================="
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh -o /tmp/upload_to_pixeldrain.sh
bash /tmp/upload_to_pixeldrain.sh
