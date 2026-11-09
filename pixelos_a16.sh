#!/usr/bin/env bash
#
# PixelOS build script for sweet2 (Redmi Note 12 Pro)
# Target: Android 16 (sixteen-qpr2 / PixelOS-16-QPR2)
# Maintainer: rony1duet
#

set -eo pipefail

readonly ROM_MANIFEST_BRANCH="sixteen-qpr2"
readonly DEVICE_BRANCH="PixelOS-16-QPR2"
readonly DEVICE_CODENAME="sweet2"
readonly SCRIPT_VERSION="1.3.7"

# Ensure legacy check-api bypass is deactivated and source stubs are allowed
unset WITHOUT_CHECK_API
export WITHOUT_CHECK_API=false
export BUILD_FROM_SOURCE_STUB=true

info() { printf "\033[0;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[x]\033[0m %s\n" "$*" >&2; exit 1; }

clean_workspace() {
    info "Preparing workspace..."

    local gcam="vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk"
    if [[ -f "$gcam" ]]; then
        mkdir -p /tmp/gcam_cache
        cp -f "$gcam" /tmp/gcam_cache/GoogleCameraEng.apk
    fi

    git reset --hard HEAD 2>/dev/null || true
    git clean -fdx 2>/dev/null || true
    rm -rf .repo/local_manifests
}

setup_manifests() {
    info "Setting up manifests (${ROM_MANIFEST_BRANCH} / ${DEVICE_BRANCH})..."

    repo init \
        -u https://github.com/PixelOS-AOSP/android_manifest.git \
        -b "${ROM_MANIFEST_BRANCH}" \
        --git-lfs \
        --depth=1

    git clone https://github.com/rony1duet/manifest_sweet2.git .repo/local_manifests -b "${DEVICE_BRANCH}"
}

sync_sources() {
    info "Syncing sources..."

    if [[ -x "/opt/crave/resync.sh" ]]; then
        /opt/crave/resync.sh
    else
        repo sync -c -j"$(nproc --all)" --force-sync --no-clone-bundle --no-tags
    fi
}

sync_device_repos() {
    info "Updating device repositories to ${DEVICE_BRANCH}..."

    local repos=(
        device/xiaomi/sm6150-common
        device/xiaomi/sweet2
        kernel/xiaomi/sm6150
        hardware/xiaomi
        hardware/dolby
        vendor/xiaomi/sm6150-common
        vendor/xiaomi/sweet2
        vendor/android_prebuilts_sweet2
        vendor/GCam_sweet2
    )

    for repo in "${repos[@]}"; do
        if [[ -d "$repo/.git" ]]; then
            git -C "$repo" fetch origin "$DEVICE_BRANCH" --depth=1 2>/dev/null || true
            git -C "$repo" reset --hard "origin/$DEVICE_BRANCH" 2>/dev/null || true
            echo "  -> $repo: $(git -C "$repo" log -1 --oneline 2>/dev/null)"
        fi
    done
}

setup_toolchain() {
    info "Validating toolchains..."

    [[ -f "build/soong/soong_ui.bash" ]] || repo sync -c -j4 --force-sync build/soong
    [[ -f "build/soong/soong_ui.bash" ]] || die "Missing build/soong/soong_ui.bash"

    command -v git-lfs >/dev/null 2>&1 || (sudo apt-get update && sudo apt-get install -y git-lfs) 2>/dev/null || true
    git lfs install 2>/dev/null || true

    repo forall -r "prebuilts/.*" -c "git lfs pull" 2>/dev/null || true

    local clang_bin
    clang_bin=$(find prebuilts/clang/host/linux-x86 -type f -name "clang" 2>/dev/null | head -n 1)
    if [[ -n "$clang_bin" && "$(file "$clang_bin" 2>/dev/null)" == *"ASCII text"* ]]; then
        warn "Healing unexpanded Clang LFS pointer..."
        rm -rf prebuilts/clang/host/linux-x86
        repo sync -c -j4 --force-sync prebuilts/clang/host/linux-x86
        (cd prebuilts/clang/host/linux-x86 && git lfs pull) 2>/dev/null || true
    fi

    find prebuilts/ -type f \( -name "clang*" -o -name "lld*" -o -name "llvm-*" \) -exec chmod +x {} + 2>/dev/null || true
}

sanitize_configs() {
    info "Normalizing configs and kernel..."

    find device/ hardware/ vendor/ -type f \( -name "*.sh" -o -name "*.env" -o -name "*.bp" -o -name "*.mk" -o -name "*.xml" \) \
        -exec sed -i 's/\r$//' {} + 2>/dev/null || true

    if [[ -d "kernel/xiaomi/sm6150" ]]; then
        rm -rf kernel/xiaomi/sm6150/KernelSU kernel/xiaomi/sm6150/drivers/kernelsu
        git -C kernel/xiaomi/sm6150 checkout HEAD -- drivers/kernelsu drivers/Makefile drivers/Kconfig fs/ 2>/dev/null || true
    fi

    # Fix GoogleCameraEng check_prebuilt_presigned_apk failure (contains compressed dex files and is privileged)
    if [[ -f "vendor/GCam_sweet2/Android.bp" ]] && ! grep -q "skip_preprocessed_apk_checks" vendor/GCam_sweet2/Android.bp; then
        sed -i '/preprocessed: true,/a \    skip_preprocessed_apk_checks: true,' vendor/GCam_sweet2/Android.bp
    fi
}

cleanup_storage() {
    info "Purging stale intermediates and recovering disk..."

    [[ -f "/swapfile" ]] && sudo rm -f /swapfile 2>/dev/null || true
    sudo rm -rf /tmp/* /tmp/.* out/soong/.temp 2>/dev/null || true

    rm -rf \
        out/target/product/${DEVICE_CODENAME}/symbols \
        out/target/product/${DEVICE_CODENAME}/data \
        out/target/product/${DEVICE_CODENAME}/testcases \
        out/host/linux-x86/testcases \
        out/dist \
        out/soong/.intermediates/art \
        out/soong/.intermediates/bionic \
        out/target/product/${DEVICE_CODENAME}/obj/KERNEL_OBJ \
        out/target/product/${DEVICE_CODENAME}/obj/PACKAGING \
        out/target/product/${DEVICE_CODENAME}/etc/vintf \
        out/target/product/${DEVICE_CODENAME}/system/etc/vintf \
        out/soong/.intermediates/vendor/GCam_sweet2 \
        out/target/product/${DEVICE_CODENAME}/product/app/GoogleCameraEng \
        out/soong/.bootstrap \
        out/soong/build.*.ninja \
        out/soong/soong.*.variables 2>/dev/null || true

    find . -type d -name "objects" -path "*/.git/lfs/objects" -exec rm -rf {} + 2>/dev/null || true
}

setup_environment() {
    info "Exporting build environment..."

    export BUILD_USERNAME="rony1duet"
    export BUILD_HOSTNAME="crave"
    export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
    export DONT_INSTALL_DEXPREOPT_TESTS=true
    export SKIP_BOOT_JARS_CHECK=true
    unset WITHOUT_CHECK_API
    export WITHOUT_CHECK_API=false
    export BUILD_FROM_SOURCE_STUB=true
    export DONT_UNCOMPRESS_PRIV_APPS_DEXS=true

    export GOGC=40
    export GOMEMLIMIT="14GiB"
    export MALLOC_ARENA_MAX=2
    export SOONG_GOGC=40
    export SOONG_INCREMENTAL_ANALYSIS=false
}

setup_gcam() {
    info "Preparing GCam prebuilt..."

    local fetcher="vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh"
    if [[ -f "$fetcher" ]]; then
        bash "$fetcher" vendor/GCam_sweet2/system/product/app/GoogleCameraEng
    fi

    [[ -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" ]] || die "GoogleCameraEng.apk not found"

    # Invalidate stale GCam prebuilt check stamps so Soong re-evaluates check_prebuilt_presigned_apk
    rm -rf out/soong/.intermediates/vendor/GCam_sweet2 2>/dev/null || true

    # Ensure GCam Android.bp skips preprocessed compressed dex validation for presigned APK
    if [[ -f "vendor/GCam_sweet2/Android.bp" ]] && ! grep -q "skip_preprocessed_apk_checks" vendor/GCam_sweet2/Android.bp; then
        sed -i '/preprocessed: true,/a \    skip_preprocessed_apk_checks: true,' vendor/GCam_sweet2/Android.bp
    fi
}

build_target() {
    info "Compiling PixelOS ${DEVICE_CODENAME}..."

    # Deactivate WITHOUT_CHECK_API and allow building stubs from source
    unset WITHOUT_CHECK_API
    export WITHOUT_CHECK_API=false
    export BUILD_FROM_SOURCE_STUB=true

    # shellcheck source=/dev/null
    source build/envsetup.sh
    breakfast "${DEVICE_CODENAME}" || die "breakfast failed"

    unset WITHOUT_CHECK_API
    export WITHOUT_CHECK_API=false
    export BUILD_FROM_SOURCE_STUB=true

    m pixelos || die "Build failed"
}

upload_artifacts() {
    info "Uploading build artifact..."
    curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/${DEVICE_BRANCH}/upload_to_pixeldrain.sh" | bash
}

main() {
    clean_workspace
    setup_manifests
    sync_sources
    sync_device_repos
    setup_toolchain
    sanitize_configs
    cleanup_storage
    setup_environment
    setup_gcam
    build_target
    upload_artifacts
}

main "$@"
