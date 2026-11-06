#!/usr/bin/env bash
#
# PixelOS sweet2 automated build script
# Target: Android 16 (sixteen-qpr2 / PixelOS-16-QPR2)
# Maintainer: rony1duet
#

set -eo pipefail

readonly ROM_MANIFEST_URL="https://github.com/PixelOS-AOSP/android_manifest.git"
readonly ROM_MANIFEST_BRANCH="sixteen-qpr2"
readonly LOCAL_MANIFEST_URL="https://github.com/rony1duet/manifest_sweet2.git"
readonly DEVICE_BRANCH="PixelOS-16-QPR2"
readonly DEVICE_CODENAME="sweet2"
readonly BUILD_TARGET="pixelos"

readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'
readonly C_BLUE='\033[0;34m'

log_section() { printf "\n${C_BLUE}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
log_info()    { printf "  ${C_GREEN}->${C_RESET} %s\n" "$*"; }
log_warn()    { printf "  ${C_YELLOW}[!]${C_RESET} %s\n" "$*"; }
log_error()   { printf "  ${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
die()         { log_error "$*"; exit 1; }

clean_workspace() {
    log_section "Preparing workspace..."

    local gcam_existing="vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk"
    if [[ -f "$gcam_existing" ]]; then
        mkdir -p /tmp/gcam_cache "${HOME:-/root}/.cache/gcam" 2>/dev/null || true
        cp -f "$gcam_existing" /tmp/gcam_cache/GoogleCameraEng.apk 2>/dev/null || true
        cp -f "$gcam_existing" "${HOME:-/root}/.cache/gcam/GoogleCameraEng.apk" 2>/dev/null || true
    fi

    git reset --hard HEAD 2>/dev/null || true
    git clean -fdx 2>/dev/null || true

    for gdir in .repo/manifests .repo/repo; do
        if [[ -d "$gdir" ]]; then
            git -C "$gdir" reset --hard HEAD 2>/dev/null || true
            git -C "$gdir" clean -fdx 2>/dev/null || true
        fi
    done
}

setup_manifests() {
    log_section "Initializing ROM manifest (${ROM_MANIFEST_BRANCH})..."
    repo init -u "${ROM_MANIFEST_URL}" -b "${ROM_MANIFEST_BRANCH}" --git-lfs --depth=1

    log_section "Configuring local device manifest (${DEVICE_BRANCH})..."
    rm -rf .repo/local_manifests
    git clone "${LOCAL_MANIFEST_URL}" .repo/local_manifests -b "${DEVICE_BRANCH}"
}

sync_sources() {
    log_section "Syncing source repositories..."
    if [[ -x "/opt/crave/resync.sh" ]]; then
        /opt/crave/resync.sh
    else
        repo sync -c -j"$(nproc --all 2>/dev/null || echo 4)" --force-sync --no-clone-bundle --no-tags
    fi
}

sync_device_repos() {
    log_section "Checking out device repositories on ${DEVICE_BRANCH}..."

    local custom_repos=(
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

    for entry in "${custom_repos[@]}"; do
        local rdir="${entry%%:*}"
        local rbranch="${entry##*:}"
        if [[ -d "$rdir/.git" ]]; then
            git -C "$rdir" fetch origin "$rbranch" --depth=1 2>/dev/null || true
            git -C "$rdir" checkout -B "$rbranch" "origin/$rbranch" 2>/dev/null || \
                git -C "$rdir" reset --hard "origin/$rbranch" 2>/dev/null || true
            log_info "$rdir -> $(git -C "$rdir" log -1 --oneline 2>/dev/null || true)"
        fi
    done
}

setup_toolchain() {
    log_section "Validating toolchains and Git LFS..."

    if [[ ! -f "build/soong/soong_ui.bash" ]]; then
        log_warn "build/soong missing, re-syncing..."
        repo sync -c -j4 --force-sync build/soong || true
    fi
    [[ -f "build/soong/soong_ui.bash" ]] || die "Missing build/soong/soong_ui.bash"

    if ! command -v git-lfs >/dev/null 2>&1; then
        (sudo apt-get update && sudo apt-get install -y git-lfs) 2>/dev/null || true
    fi
    git lfs install 2>/dev/null || true

    for dir in prebuilts/clang/host/linux-x86 prebuilts/rust; do
        if [[ -d "$dir" ]]; then
            git -C "$dir" reset --hard HEAD 2>/dev/null || true
            git -C "$dir" lfs pull 2>/dev/null || true
        fi
    done
    repo forall -r "prebuilts/.*" -c "git lfs pull" 2>/dev/null || true

    local clang_dir="prebuilts/clang/host/linux-x86"
    local clang_bin
    clang_bin="$(find "${clang_dir}" -type f -name "clang" 2>/dev/null | head -n 1)"
    if [[ -n "$clang_bin" && "$(file "$clang_bin" 2>/dev/null)" == *"ASCII text"* ]]; then
        log_warn "Healing unexpanded Clang LFS pointer..."
        rm -rf "${clang_dir}"
        repo sync -c -j4 --force-sync "${clang_dir}"
        (cd "${clang_dir}" && git lfs pull) 2>/dev/null || true
    fi

    find prebuilts/ -type f \( -name "clang*" -o -name "lld*" -o -name "llvm-*" \) -exec chmod +x {} + 2>/dev/null || true
}

sanitize_configs() {
    log_section "Normalizing configs and kernel tree..."

    find device/ hardware/ vendor/ system/ -type f \( \
        -name "*.sh" -o -name "*.env" -o -name "*.bp" -o \
        -name "*.mk" -o -name "*.xml" -o -name "*.rc" -o \
        -path "*/sepolicy/*" \
    \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

    local kernel_dir="kernel/xiaomi/sm6150"
    if [[ -d "$kernel_dir" ]]; then
        rm -rf "${kernel_dir}/KernelSU"
        rm -f "${kernel_dir}/drivers/kernelsu"
        git -C "$kernel_dir" checkout HEAD -- drivers/kernelsu drivers/Makefile drivers/Kconfig fs/ 2>/dev/null || true
    fi
}

cleanup_storage() {
    log_section "Cleaning storage and invalidating conflicting targets..."

    if [[ -f "/swapfile" ]]; then
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile 2>/dev/null || true
    fi

    sudo rm -rf /tmp/* /tmp/.* 2>/dev/null || rm -rf /tmp/* 2>/dev/null || true
    rm -rf out/soong/.temp 2>/dev/null || true

    rm -rf \
        out/target/product/${DEVICE_CODENAME}/symbols \
        out/target/product/${DEVICE_CODENAME}/data \
        out/target/product/${DEVICE_CODENAME}/testcases \
        out/host/linux-x86/testcases \
        out/dist \
        out/soong/.intermediates/art \
        out/soong/.intermediates/bionic \
        out/target/product/${DEVICE_CODENAME}/obj/KERNEL_OBJ \
        out/target/product/${DEVICE_CODENAME}/obj/PACKAGING/check_vintf* \
        out/target/product/${DEVICE_CODENAME}/obj/PACKAGING/privapp_permissions* \
        out/target/product/${DEVICE_CODENAME}/*/etc/vintf \
        out/target/product/${DEVICE_CODENAME}/etc/vintf \
        out/target/product/${DEVICE_CODENAME}/system/etc/vintf/compatibility_matrix.device.xml \
        out/target/product/${DEVICE_CODENAME}/system_ext/etc/permissions \
        out/soong/.intermediates/frameworks/base/core/jni/libandroid_runtime/*/obj/frameworks/base/core/jni/android_os_SELinux.o \
        out/soong/.intermediates/system/sepolicy/tools/version_policy/*/obj/system/sepolicy/tools/version_policy.o \
        out/soong/.intermediates/hardware/qcom/wlan/legacy/qcwcn/wifi_hal \
        out/soong/.intermediates/frameworks/av/services/camera/libcameraservice \
        out/soong/.intermediates/device/xiaomi/sm6150-common/camera \
        out/soong/.intermediates/device/xiaomi/sm6150-common/parts \
        out/target/product/${DEVICE_CODENAME}/system_ext/priv-app/XiaomiParts \
        out/target/product/${DEVICE_CODENAME}/system/bin/cameraserver \
        out/target/product/${DEVICE_CODENAME}/system/app/Stk \
        out/target/product/${DEVICE_CODENAME}/system/priv-app/Stk \
        out/target/product/${DEVICE_CODENAME}/system_ext/app/Aperture* \
        out/target/product/${DEVICE_CODENAME}/product/app/SafetyHub* \
        out/target/product/${DEVICE_CODENAME}/product/priv-app/SafetyHub* \
        out/target/product/${DEVICE_CODENAME}/system/app/FMRadio \
        out/target/product/${DEVICE_CODENAME}/system/app/FM2 \
        out/target/product/${DEVICE_CODENAME}/product/priv-app/EmergencyInfo \
        out/target/product/${DEVICE_CODENAME}/system/priv-app/GooglePartnerSetup* \
        out/target/product/${DEVICE_CODENAME}/product/priv-app/GooglePartnerSetup* \
        out/target/product/${DEVICE_CODENAME}/system/app/PlayAutoInstall* \
        out/target/product/${DEVICE_CODENAME}/product/app/PlayAutoInstall* \
        out/soong/.intermediates/system/sepolicy/recovery_sepolicy.* \
        out/soong/.intermediates/system/sepolicy/vendor_sepolicy.* \
        out/soong/.intermediates/vendor/GCam_sweet2 \
        out/target/product/${DEVICE_CODENAME}/product/app/GoogleCameraEng 2>/dev/null || true

    find . -type d -name "lfs" -path "*/.git/lfs" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "objects" -path "*/.git/lfs/objects" -exec rm -rf {} + 2>/dev/null || true
}

setup_environment() {
    log_section "Configuring build environment..."

    export BUILD_USERNAME="rony1duet"
    export BUILD_HOSTNAME="crave"
    export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
    export DONT_INSTALL_DEXPREOPT_TESTS=true
    export SKIP_BOOT_JARS_CHECK=true
    export WITHOUT_CHECK_API=true

    export GOGC=40
    export GOMEMLIMIT="14GiB"
    export MALLOC_ARENA_MAX=2
    export SOONG_GOGC=40
    export SOONG_INCREMENTAL_ANALYSIS=false

    free -h 2>/dev/null || true
    df -h / /tmp 2>/dev/null || true
}

setup_gcam() {
    log_section "Preparing GCam prebuilt assets..."

    local gcam_dir="vendor/GCam_sweet2"
    local prebuilts_dir="vendor/android_prebuilts_sweet2"

    [[ -d "$gcam_dir" ]] || git clone https://github.com/rony1duet/GCam_sweet2.git "$gcam_dir" -b "${DEVICE_BRANCH}" --depth=1
    [[ -d "$prebuilts_dir" ]] || git clone https://github.com/rony1duet/android_prebuilts_sweet2.git "$prebuilts_dir" -b "${DEVICE_BRANCH}" --depth=1

    rm -f "${gcam_dir}/Android.mk" 2>/dev/null || true

    local fetcher="${prebuilts_dir}/gcam/fetch_gcam_prebuilt.sh"
    if [[ -f "$fetcher" ]]; then
        sed -i 's/\r$//' "${prebuilts_dir}/gcam/"*.sh "${prebuilts_dir}/gcam/"*.env 2>/dev/null || true
        bash "$fetcher" "${gcam_dir}/system/product/app/GoogleCameraEng"
    fi

    local apk_path="${gcam_dir}/system/product/app/GoogleCameraEng/GoogleCameraEng.apk"
    [[ -f "$apk_path" ]] || die "GoogleCameraEng.apk missing"
}

build_target() {
    log_section "Building PixelOS sweet2 (A16)..."

    # shellcheck source=/dev/null
    source build/envsetup.sh || die "Failed to source build/envsetup.sh"
    breakfast "${DEVICE_CODENAME}" || die "breakfast failed"
    m "${BUILD_TARGET}" || die "Build failed"
}

upload_artifacts() {
    log_section "Dispatching release upload..."
    local uploader="/tmp/upload_to_pixeldrain.sh"
    curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/${DEVICE_BRANCH}/upload_to_pixeldrain.sh" -o "$uploader" || \
        curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh" -o "$uploader"
    bash "$uploader"
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
