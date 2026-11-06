#!/usr/bin/env bash

ROM_MANIFEST_BRANCH="seventeen"
DEVICE_BRANCH="PixelOS-17-base"

echo "==========================================="
echo "Cleaning unstaged modifications from prior builds..."
echo "==========================================="
git reset --hard HEAD 2>/dev/null || true
git clean -fdx 2>/dev/null || true
for gdir in .repo/manifests .repo/repo; do
    if [ -d "$gdir" ]; then
        git -C "$gdir" reset --hard HEAD 2>/dev/null || true
        git -C "$gdir" clean -fdx 2>/dev/null || true
    fi
done

echo "==========================================="
echo "Initializing PixelOS ${ROM_MANIFEST_BRANCH}..."
echo "==========================================="
repo init \
    -u https://github.com/PixelOS-AOSP/android_manifest.git \
    -b "${ROM_MANIFEST_BRANCH}" \
    --git-lfs \
    --depth=1

echo "==========================================="
echo "Setting up local manifest (${DEVICE_BRANCH})..."
echo "==========================================="
rm -rf .repo/local_manifests/
git clone https://github.com/rony1duet/manifest_sweet2.git .repo/local_manifests -b "${DEVICE_BRANCH}"

# Preserve any existing GCam prebuilt APK to cache before repository reset
if [ -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" ]; then
    mkdir -p /tmp/gcam_cache "${HOME:-/root}/.cache/gcam" 2>/dev/null || true
    cp -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" "/tmp/gcam_cache/GoogleCameraEng.apk" 2>/dev/null || true
    cp -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" "${HOME:-/root}/.cache/gcam/GoogleCameraEng.apk" 2>/dev/null || true
fi

repo forall -c "git reset --hard HEAD && git clean -fdx" 2>/dev/null || true
for repo_dir in kernel/xiaomi/sm6150 device/xiaomi/sweet2 device/xiaomi/sm6150-common vendor/xiaomi/sweet2 vendor/xiaomi/sm6150-common hardware/xiaomi hardware/dolby build/soong; do
    if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" reset --hard HEAD 2>/dev/null || true
        git -C "$repo_dir" clean -fdx 2>/dev/null || true
    fi
done

echo "==========================================="
echo "Syncing repositories on Crave..."
echo "==========================================="
if [ -x "/opt/crave/resync.sh" ]; then
    /opt/crave/resync.sh
else
    repo sync -c -j"$(nproc --all 2>/dev/null || echo 4)" --force-sync --no-clone-bundle --no-tags
fi

echo "==========================================="
echo "Ensuring latest commits on ${DEVICE_BRANCH}..."
echo "==========================================="
CUSTOM_REPOS=(
    "device/xiaomi/sm6150-common:${DEVICE_BRANCH}"
    "device/xiaomi/sweet2:${DEVICE_BRANCH}"
    "kernel/xiaomi/sm6150:${DEVICE_BRANCH}"
    "hardware/xiaomi:${DEVICE_BRANCH}"
    "hardware/dolby:${DEVICE_BRANCH}"
    "vendor/xiaomi/sm6150-common:${DEVICE_BRANCH}"
    "vendor/xiaomi/sweet2:${DEVICE_BRANCH}"
    "vendor/android_prebuilts_sweet2:${DEVICE_BRANCH}"
    "vendor/GCam_sweet2:${DEVICE_BRANCH}"
)

for entry in "${CUSTOM_REPOS[@]}"; do
    rdir="${entry%%:*}"
    rbranch="${entry##*:}"
    if [ -d "$rdir/.git" ]; then
        echo "Updating $rdir to latest origin/$rbranch..."
        git -C "$rdir" fetch origin "$rbranch" --depth=1 2>/dev/null || true
        git -C "$rdir" checkout -B "$rbranch" "origin/$rbranch" 2>/dev/null || git -C "$rdir" reset --hard "origin/$rbranch" 2>/dev/null || true
        COMMIT_INFO=$(git -C "$rdir" log -1 --oneline 2>/dev/null || true)
        echo " -> $rdir is at: $COMMIT_INFO"
    fi
done

echo "==========================================="
echo "Verifying Soong build system..."
echo "==========================================="
if [ ! -f "build/soong/soong_ui.bash" ]; then
    echo "Warning: build/soong/soong_ui.bash missing after resync. Forcing sync of build/soong..."
    repo sync -c -j4 --force-sync build/soong || true
fi

if [ ! -f "build/soong/soong_ui.bash" ]; then
    echo "[ERROR] Missing build/soong/soong_ui.bash! Build environment is broken."
    exit 1
fi

echo "==========================================="
echo "Ensuring Git LFS toolchains and binaries..."
echo "==========================================="
if ! command -v git-lfs >/dev/null 2>&1; then
    echo "git-lfs not found, installing..."
    (sudo apt-get update && sudo apt-get install -y git-lfs) 2>/dev/null || true
fi
git lfs install 2>/dev/null || true

# Pull Git LFS in prebuilt directories
for dir in prebuilts/clang/host/linux-x86 prebuilts/rust; do
    if [ -d "$dir" ]; then
        echo "Pulling Git LFS in $dir..."
        git -C "$dir" reset --hard HEAD 2>/dev/null || true
        git -C "$dir" lfs pull 2>/dev/null || true
    fi
done
repo forall -r "prebuilts/.*" -c "git lfs pull" 2>/dev/null || true

# Diagnostic & healing check for Clang compiler
echo "=== Checking Clang compiler ==="
CLANG_DIR="prebuilts/clang/host/linux-x86"
CLANG_BIN=$(find "${CLANG_DIR}" -type f -name "clang" 2>/dev/null | head -n 1)

if [ -n "$CLANG_BIN" ]; then
    echo "Inspecting $CLANG_BIN:"
    ls -l "$CLANG_BIN"
    file "$CLANG_BIN"
    # If Clang is still an ASCII text pointer file, force re-sync with LFS
    if file "$CLANG_BIN" | grep -q "ASCII text"; then
        echo "Clang is a Git LFS pointer text file! Re-syncing ${CLANG_DIR} with LFS..."
        rm -rf "${CLANG_DIR}"
        repo sync -c -j4 --force-sync "${CLANG_DIR}"
        (cd "${CLANG_DIR}" && git lfs pull) 2>/dev/null || true
        CLANG_BIN=$(find "${CLANG_DIR}" -type f -name "clang" 2>/dev/null | head -n 1)
    fi
fi

# Ensure all binaries in prebuilts are executable
find prebuilts/ -type f -name "clang*" -exec chmod +x {} + 2>/dev/null || true
find prebuilts/ -type f -name "lld*" -exec chmod +x {} + 2>/dev/null || true
find prebuilts/ -type f -name "llvm-*" -exec chmod +x {} + 2>/dev/null || true

if [ -n "$CLANG_BIN" ]; then
    chmod +x "$CLANG_BIN"
    "$CLANG_BIN" --version || echo "WARNING: Clang execution test returned non-zero"
fi

# Prune Git LFS local blob cache to reclaim 20-30GB of container disk space
echo "Pruning Git LFS object cache to free disk space..."
find prebuilts/ -type d -name "lfs" -path "*/.git/lfs" -exec rm -rf {} + 2>/dev/null || true
git lfs prune 2>/dev/null || true
echo "==============================="

echo "==========================================="
echo "Ensuring UNIX line endings on build configs and scripts..."
echo "==========================================="
find device/ hardware/ vendor/ system/ -type f \( -name "*.sh" -o -name "*.env" -o -name "*.bp" -o -name "*.mk" -o -name "*.xml" -o -name "*.rc" -o -path "*/sepolicy/*" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

echo "==========================================="
echo "Restoring native KernelSU in sm6150 kernel..."
echo "==========================================="
if [ -d "kernel/xiaomi/sm6150" ]; then
    rm -rf kernel/xiaomi/sm6150/KernelSU
    if [ -L "kernel/xiaomi/sm6150/drivers/kernelsu" ]; then
        rm -f kernel/xiaomi/sm6150/drivers/kernelsu
    fi
    git -C kernel/xiaomi/sm6150 checkout HEAD -- drivers/kernelsu drivers/Makefile drivers/Kconfig fs/ 2>/dev/null || true
    git -C kernel/xiaomi/sm6150 status -s
fi

# Clean up partial intermediate objects from previous aborted runs
echo "==========================================="
echo "Cleaning storage and preparing build environment..."
echo "==========================================="
# 1. Clean up any dead swapfile from previous runs to recover 16GB disk space immediately
if [ -f "/swapfile" ]; then
    echo "Removing unneeded /swapfile to recover root partition space..."
    sudo swapoff /swapfile 2>/dev/null || true
    sudo rm -f /swapfile 2>/dev/null || true
fi

# 2. Clean temporary build caches, sockets, and orphaned pipes
echo "Cleaning temporary build files..."
sudo rm -rf /tmp/* /tmp/.* 2>/dev/null || rm -rf /tmp/* 2>/dev/null || true
rm -rf out/soong/.temp 2>/dev/null || true

# 3. Partial cleanup for incremental builds: purge unneeded test, symbol, and conflicting intermediates
echo "Incremental mode: purging unneeded test and symbol intermediates..."
rm -rf out/target/product/sweet2/symbols 2>/dev/null || true
rm -rf out/target/product/sweet2/data 2>/dev/null || true
rm -rf out/target/product/sweet2/testcases 2>/dev/null || true
rm -rf out/host/linux-x86/testcases 2>/dev/null || true
rm -rf out/dist 2>/dev/null || true
rm -rf out/soong/.intermediates/art 2>/dev/null || true
rm -rf out/soong/.intermediates/bionic 2>/dev/null || true
rm -rf out/target/product/sweet2/obj/KERNEL_OBJ 2>/dev/null || true
rm -rf out/target/product/sweet2/obj/PACKAGING/check_vintf* 2>/dev/null || true
rm -rf out/target/product/sweet2/obj/PACKAGING/privapp_permissions* 2>/dev/null || true
rm -rf out/target/product/sweet2/*/etc/vintf 2>/dev/null || true
rm -rf out/target/product/sweet2/etc/vintf 2>/dev/null || true
rm -f out/target/product/sweet2/system/etc/vintf/compatibility_matrix.device.xml 2>/dev/null || true
rm -rf out/target/product/sweet2/system_ext/etc/permissions 2>/dev/null || true
rm -f out/soong/.intermediates/frameworks/base/core/jni/libandroid_runtime/*/obj/frameworks/base/core/jni/android_os_SELinux.o 2>/dev/null || true
rm -f out/soong/.intermediates/system/sepolicy/tools/version_policy/*/obj/system/sepolicy/tools/version_policy.o 2>/dev/null || true
rm -rf out/soong/.intermediates/hardware/qcom/wlan/legacy/qcwcn/wifi_hal 2>/dev/null || true
rm -rf out/soong/.intermediates/frameworks/av/services/camera/libcameraservice 2>/dev/null || true
rm -rf out/soong/.intermediates/device/xiaomi/sm6150-common/camera 2>/dev/null || true
rm -rf out/soong/.intermediates/device/xiaomi/sm6150-common/parts 2>/dev/null || true
rm -rf out/target/product/sweet2/system_ext/priv-app/XiaomiParts 2>/dev/null || true
rm -f out/target/product/sweet2/system/bin/cameraserver 2>/dev/null || true
rm -rf out/target/product/sweet2/system/app/Stk out/target/product/sweet2/system/priv-app/Stk 2>/dev/null || true
rm -rf out/target/product/sweet2/system_ext/app/Aperture* out/target/product/sweet2/product/app/SafetyHub* out/target/product/sweet2/product/priv-app/SafetyHub* 2>/dev/null || true
rm -rf out/target/product/sweet2/system/app/FMRadio out/target/product/sweet2/system/app/FM2 out/target/product/sweet2/product/priv-app/EmergencyInfo 2>/dev/null || true
rm -rf out/target/product/sweet2/system/priv-app/GooglePartnerSetup* out/target/product/sweet2/product/priv-app/GooglePartnerSetup* 2>/dev/null || true
rm -rf out/target/product/sweet2/system/app/PlayAutoInstall* out/target/product/sweet2/product/app/PlayAutoInstall* 2>/dev/null || true
rm -rf out/soong/.intermediates/system/sepolicy/recovery_sepolicy.* out/soong/.intermediates/system/sepolicy/vendor_sepolicy.* 2>/dev/null || true
rm -rf out/soong/.intermediates/vendor/GCam_sweet2 2>/dev/null || true
rm -rf out/target/product/sweet2/product/app/GoogleCameraEng 2>/dev/null || true

# 4. Prune Git LFS local blob cache across repositories (saves 20-30GB)
echo "Pruning Git LFS object cache..."
find . -type d -name "lfs" -path "*/.git/lfs" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "objects" -path "*/.git/lfs/objects" -exec rm -rf {} + 2>/dev/null || true

echo "==========================================="
echo "Exporting build environment variables..."
echo "==========================================="
export BUILD_USERNAME=rony1duet
export BUILD_HOSTNAME=crave
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
export DONT_INSTALL_DEXPREOPT_TESTS=true
export SKIP_BOOT_JARS_CHECK=true
export WITHOUT_CHECK_API=true

# Memory and GC tuning to prevent soong_build OOM kills in container
export GOGC=40
export GOMEMLIMIT=14GiB
export MALLOC_ARENA_MAX=2
export SOONG_GOGC=40
export SOONG_INCREMENTAL_ANALYSIS=false

echo "==========================================="
echo "Storage and memory status:"
echo "==========================================="
free -h 2>/dev/null || true
echo "Disk space status:"
df -h / /tmp 2>/dev/null || true

echo "==========================================="
echo "Ensuring GCam prebuilts..."
echo "==========================================="
if [ ! -d "vendor/GCam_sweet2" ]; then
    echo "Cloning vendor/GCam_sweet2..."
    git clone https://github.com/rony1duet/GCam_sweet2.git vendor/GCam_sweet2 -b "${DEVICE_BRANCH}" --depth=1
else
    echo "Updating vendor/GCam_sweet2..."
    git -C vendor/GCam_sweet2 fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
    git -C vendor/GCam_sweet2 reset --hard origin/"${DEVICE_BRANCH}" 2>/dev/null || true
fi
rm -f vendor/GCam_sweet2/Android.mk 2>/dev/null || true

if [ ! -d "vendor/android_prebuilts_sweet2" ]; then
    echo "Cloning vendor/android_prebuilts_sweet2..."
    git clone https://github.com/rony1duet/android_prebuilts_sweet2.git vendor/android_prebuilts_sweet2 -b "${DEVICE_BRANCH}" --depth=1
else
    echo "Updating vendor/android_prebuilts_sweet2..."
    git -C vendor/android_prebuilts_sweet2 fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
    git -C vendor/android_prebuilts_sweet2 reset --hard origin/"${DEVICE_BRANCH}" 2>/dev/null || true
fi

if [ -f "vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh" ]; then
    sed -i 's/\r$//' vendor/android_prebuilts_sweet2/gcam/*.sh vendor/android_prebuilts_sweet2/gcam/*.env 2>/dev/null || true
    bash vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh vendor/GCam_sweet2/system/product/app/GoogleCameraEng
fi

if [ ! -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" ]; then
    echo "[ERROR] GoogleCameraEng.apk missing! GCam prebuilt fetch failed."
    exit 1
fi

echo "==========================================="
echo "Starting PixelOS sweet2 build (A17)..."
echo "==========================================="
if ! source build/envsetup.sh; then
    echo "[ERROR] Failed to initialize Android build environment."
    exit 1
fi

if [ ! -f "build/soong/soong_ui.bash" ]; then
    echo "[ERROR] Missing build/soong/soong_ui.bash"
    exit 1
fi

if ! breakfast sweet2; then
    echo "[ERROR] Failed to configure sweet2 product."
    exit 1
fi

if ! m pixelos; then
    echo "[ERROR] PixelOS build failed."
    exit 1
fi

echo "==========================================="
echo "Build complete! Uploading to Pixeldrain..."
echo "==========================================="
curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh" -o /tmp/upload_to_pixeldrain.sh
bash /tmp/upload_to_pixeldrain.sh
