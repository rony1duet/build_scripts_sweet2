#!/usr/bin/env bash
#
# PixelOS Automated Build Script for sweet2 (Redmi Note 10 Pro / Pro Max)
# Target: Android 17 (seventeen / PixelOS-17-base)
# Maintainer: rony1duet
#

set -eo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly ROM_MANIFEST_URL="https://github.com/PixelOS-AOSP/android_manifest.git"
readonly ROM_MANIFEST_BRANCH="seventeen"
readonly LOCAL_MANIFEST_URL="https://github.com/rony1duet/manifest_sweet2.git"
readonly DEVICE_BRANCH="PixelOS-17-base"
readonly DEVICE_CODENAME="sweet2"
readonly BUILD_TARGET="pixelos"

# -----------------------------------------------------------------------------
# Console Helpers & Logging
# -----------------------------------------------------------------------------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'
readonly C_BLUE='\033[0;34m'

log_section() {
    printf "\n${C_BLUE}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"
}

log_info() {
    printf "  ${C_GREEN}->${C_RESET} %s\n" "$*"
}

log_warn() {
    printf "  ${C_YELLOW}[!]${C_RESET} %s\n" "$*"
}

log_error() {
    printf "  ${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# -----------------------------------------------------------------------------
# Workspace Sanitization & Cache Preservation
# -----------------------------------------------------------------------------
clean_workspace() {
    log_section "Preparing clean workspace..."

    # Preserve existing GCam prebuilt APK to avoid unnecessary re-downloads across runs
    local gcam_existing="vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk"
    if [[ -f "$gcam_existing" ]]; then
        log_info "Caching existing GCam prebuilt APK..."
        mkdir -p /tmp/gcam_cache "${HOME:-/root}/.cache/gcam" 2>/dev/null || true
        cp -f "$gcam_existing" /tmp/gcam_cache/GoogleCameraEng.apk 2>/dev/null || true
        cp -f "$gcam_existing" "${HOME:-/root}/.cache/gcam/GoogleCameraEng.apk" 2>/dev/null || true
    fi

    # Reset root repository and repo manifest metadata
    git reset --hard HEAD 2>/dev/null || true
    git clean -fdx 2>/dev/null || true

    for gdir in .repo/manifests .repo/repo; do
        if [[ -d "$gdir" ]]; then
            git -C "$gdir" reset --hard HEAD 2>/dev/null || true
            git -C "$gdir" clean -fdx 2>/dev/null || true
        fi
    done
}

# -----------------------------------------------------------------------------
# Manifests Setup
# -----------------------------------------------------------------------------
setup_manifests() {
    log_section "Initializing ROM manifest (${ROM_MANIFEST_BRANCH})..."

    repo init \
        -u "${ROM_MANIFEST_URL}" \
        -b "${ROM_MANIFEST_BRANCH}" \
        --git-lfs \
        --depth=1

    log_section "Configuring local device manifest (${DEVICE_BRANCH})..."
    rm -rf .repo/local_manifests/
    git clone "${LOCAL_MANIFEST_URL}" .repo/local_manifests -b "${DEVICE_BRANCH}"

    # Reset any dirty trees before sync
    repo forall -c "git reset --hard HEAD && git clean -fdx" 2>/dev/null || true
    local dirty_repos=(
        kernel/xiaomi/sm6150
        device/xiaomi/sweet2
        device/xiaomi/sm6150-common
        vendor/xiaomi/sweet2
        vendor/xiaomi/sm6150-common
        hardware/xiaomi
        hardware/dolby
        build/soong
    )
    for repo_dir in "${dirty_repos[@]}"; do
        if [[ -d "$repo_dir/.git" ]]; then
            git -C "$repo_dir" reset --hard HEAD 2>/dev/null || true
            git -C "$repo_dir" clean -fdx 2>/dev/null || true
        fi
    done
}

# -----------------------------------------------------------------------------
# Source Tree Synchronization
# -----------------------------------------------------------------------------
sync_sources() {
    log_section "Syncing source repositories..."

    if [[ -x "/opt/crave/resync.sh" ]]; then
        /opt/crave/resync.sh
    else
        repo sync -c -j"$(nproc --all 2>/dev/null || echo 4)" --force-sync --no-clone-bundle --no-tags
    fi
}

# -----------------------------------------------------------------------------
# Device & Vendor Repositories Checkout
# -----------------------------------------------------------------------------
sync_device_repos() {
    log_section "Pinning custom device repositories to ${DEVICE_BRANCH}..."

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
            local commit_log
            commit_log="$(git -C "$rdir" log -1 --oneline 2>/dev/null || true)"
            log_info "$rdir -> $commit_log"
        fi
    done
}

# -----------------------------------------------------------------------------
# Toolchain & Git LFS Validation
# -----------------------------------------------------------------------------
setup_toolchain() {
    log_section "Validating build toolchains and Git LFS..."

    # Ensure build/soong UI script is intact
    if [[ ! -f "build/soong/soong_ui.bash" ]]; then
        log_warn "build/soong/soong_ui.bash missing after sync. Re-fetching build/soong..."
        repo sync -c -j4 --force-sync build/soong || true
    fi
    [[ -f "build/soong/soong_ui.bash" ]] || die "Missing build/soong/soong_ui.bash!"

    # Ensure git-lfs is installed on host/container
    if ! command -v git-lfs >/dev/null 2>&1; then
        log_info "git-lfs not found; installing via apt..."
        (sudo apt-get update && sudo apt-get install -y git-lfs) 2>/dev/null || true
    fi
    git lfs install 2>/dev/null || true

    # Pull LFS blobs for prebuilt compilers
    for dir in prebuilts/clang/host/linux-x86 prebuilts/rust; do
        if [[ -d "$dir" ]]; then
            log_info "Pulling LFS objects in $dir..."
            git -C "$dir" reset --hard HEAD 2>/dev/null || true
            git -C "$dir" lfs pull 2>/dev/null || true
        fi
    done
    repo forall -r "prebuilts/.*" -c "git lfs pull" 2>/dev/null || true

    # Verify Clang binary integrity and heal if pointer text file
    local clang_dir="prebuilts/clang/host/linux-x86"
    local clang_bin
    clang_bin="$(find "${clang_dir}" -type f -name "clang" 2>/dev/null | head -n 1)"

    if [[ -n "$clang_bin" ]]; then
        if file "$clang_bin" | grep -q "ASCII text"; then
            log_warn "Clang binary is an unresolved Git LFS pointer. Re-syncing ${clang_dir}..."
            rm -rf "${clang_dir}"
            repo sync -c -j4 --force-sync "${clang_dir}"
            (cd "${clang_dir}" && git lfs pull) 2>/dev/null || true
            clang_bin="$(find "${clang_dir}" -type f -name "clang" 2>/dev/null | head -n 1)"
        fi

        if [[ -n "$clang_bin" ]]; then
            chmod +x "$clang_bin"
            "$clang_bin" --version >/dev/null 2>&1 || log_warn "Clang execution check failed"
        fi
    fi

    # Mark toolchain executables
    find prebuilts/ -type f \( -name "clang*" -o -name "lld*" -o -name "llvm-*" \) -exec chmod +x {} + 2>/dev/null || true

    # Free cache in prebuilts
    find prebuilts/ -type d -name "lfs" -path "*/.git/lfs" -exec rm -rf {} + 2>/dev/null || true
    git lfs prune 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Configuration Normalization & Kernel Tree Sanitization
# -----------------------------------------------------------------------------
sanitize_configs() {
    log_section "Normalizing line endings and kernel tree..."

    # Strip Windows CRLF line endings from build configs and scripts
    find device/ hardware/ vendor/ system/ -type f \( \
        -name "*.sh" -o -name "*.env" -o -name "*.bp" -o \
        -name "*.mk" -o -name "*.xml" -o -name "*.rc" -o \
        -path "*/sepolicy/*" \
    \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

    # Clean native KernelSU state in sm6150 kernel
    local kernel_dir="kernel/xiaomi/sm6150"
    if [[ -d "$kernel_dir" ]]; then
        rm -rf "${kernel_dir}/KernelSU"
        if [[ -L "${kernel_dir}/drivers/kernelsu" ]]; then
            rm -f "${kernel_dir}/drivers/kernelsu"
        fi
        git -C "$kernel_dir" checkout HEAD -- drivers/kernelsu drivers/Makefile drivers/Kconfig fs/ 2>/dev/null || true
        git -C "$kernel_dir" status -s
    fi
}

# -----------------------------------------------------------------------------
# Storage Recovery & Incremental Intermediates Invalidation
# -----------------------------------------------------------------------------
cleanup_storage() {
    log_section "Cleaning storage and invalidating conflicting intermediates..."

    # 1. Recover space from unused /swapfile on container root partition
    if [[ -f "/swapfile" ]]; then
        log_info "Removing unneeded /swapfile..."
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile 2>/dev/null || true
    fi

    # 2. Clear temporary files and sockets
    sudo rm -rf /tmp/* /tmp/.* 2>/dev/null || rm -rf /tmp/* 2>/dev/null || true
    rm -rf out/soong/.temp 2>/dev/null || true

    # 3. Purge test suites, symbols, and dist targets to keep incremental builds lean
    local prune_dirs=(
        "out/target/product/${DEVICE_CODENAME}/symbols"
        "out/target/product/${DEVICE_CODENAME}/data"
        "out/target/product/${DEVICE_CODENAME}/testcases"
        "out/host/linux-x86/testcases"
        "out/dist"
        "out/soong/.intermediates/art"
        "out/soong/.intermediates/bionic"
    )
    for dir in "${prune_dirs[@]}"; do
        rm -rf "$dir" 2>/dev/null || true
    done

    # 4. Invalidate conflicting device and system packaging intermediates
    local conflict_targets=(
        "out/target/product/${DEVICE_CODENAME}/obj/KERNEL_OBJ"
        "out/target/product/${DEVICE_CODENAME}/obj/PACKAGING/check_vintf*"
        "out/target/product/${DEVICE_CODENAME}/obj/PACKAGING/privapp_permissions*"
        "out/target/product/${DEVICE_CODENAME}/*/etc/vintf"
        "out/target/product/${DEVICE_CODENAME}/etc/vintf"
        "out/target/product/${DEVICE_CODENAME}/system/etc/vintf/compatibility_matrix.device.xml"
        "out/target/product/${DEVICE_CODENAME}/system_ext/etc/permissions"
        "out/soong/.intermediates/frameworks/base/core/jni/libandroid_runtime/*/obj/frameworks/base/core/jni/android_os_SELinux.o"
        "out/soong/.intermediates/system/sepolicy/tools/version_policy/*/obj/system/sepolicy/tools/version_policy.o"
        "out/soong/.intermediates/hardware/qcom/wlan/legacy/qcwcn/wifi_hal"
        "out/soong/.intermediates/frameworks/av/services/camera/libcameraservice"
        "out/soong/.intermediates/device/xiaomi/sm6150-common/camera"
        "out/soong/.intermediates/device/xiaomi/sm6150-common/parts"
        "out/target/product/${DEVICE_CODENAME}/system_ext/priv-app/XiaomiParts"
        "out/target/product/${DEVICE_CODENAME}/system/bin/cameraserver"
        "out/target/product/${DEVICE_CODENAME}/system/app/Stk"
        "out/target/product/${DEVICE_CODENAME}/system/priv-app/Stk"
        "out/target/product/${DEVICE_CODENAME}/system_ext/app/Aperture*"
        "out/target/product/${DEVICE_CODENAME}/product/app/SafetyHub*"
        "out/target/product/${DEVICE_CODENAME}/product/priv-app/SafetyHub*"
        "out/target/product/${DEVICE_CODENAME}/system/app/FMRadio"
        "out/target/product/${DEVICE_CODENAME}/system/app/FM2"
        "out/target/product/${DEVICE_CODENAME}/product/priv-app/EmergencyInfo"
        "out/target/product/${DEVICE_CODENAME}/system/priv-app/GooglePartnerSetup*"
        "out/target/product/${DEVICE_CODENAME}/product/priv-app/GooglePartnerSetup*"
        "out/target/product/${DEVICE_CODENAME}/system/app/PlayAutoInstall*"
        "out/target/product/${DEVICE_CODENAME}/product/app/PlayAutoInstall*"
        "out/soong/.intermediates/system/sepolicy/recovery_sepolicy.*"
        "out/soong/.intermediates/system/sepolicy/vendor_sepolicy.*"
        "out/soong/.intermediates/vendor/GCam_sweet2"
        "out/target/product/${DEVICE_CODENAME}/product/app/GoogleCameraEng"
    )
    for target in "${conflict_targets[@]}"; do
        # shellcheck disable=SC2086
        rm -rf $target 2>/dev/null || true
    done

    # 5. Prune duplicate Git LFS blob caches across working trees (saves 20-30GB)
    log_info "Pruning Git LFS object caches..."
    find . -type d -name "lfs" -path "*/.git/lfs" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "objects" -path "*/.git/lfs/objects" -exec rm -rf {} + 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Build Environment & Resource Allocation
# -----------------------------------------------------------------------------
setup_environment() {
    log_section "Configuring build flags and Go runtime..."

    export BUILD_USERNAME="rony1duet"
    export BUILD_HOSTNAME="crave"
    export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
    export DONT_INSTALL_DEXPREOPT_TESTS=true
    export SKIP_BOOT_JARS_CHECK=true
    export WITHOUT_CHECK_API=true

    # Go runtime tuning to avoid OOM killer during Soong graph analysis
    export GOGC=40
    export GOMEMLIMIT="14GiB"
    export MALLOC_ARENA_MAX=2
    export SOONG_GOGC=40
    export SOONG_INCREMENTAL_ANALYSIS=false

    log_info "Available system resources:"
    free -h 2>/dev/null || true
    df -h / /tmp 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Google Camera Prebuilt Integration
# -----------------------------------------------------------------------------
setup_gcam() {
    log_section "Setting up GCam prebuilt assets..."

    local gcam_dir="vendor/GCam_sweet2"
    local prebuilts_dir="vendor/android_prebuilts_sweet2"

    # Clone or update vendor/GCam_sweet2
    if [[ ! -d "$gcam_dir" ]]; then
        log_info "Cloning $gcam_dir (${DEVICE_BRANCH})..."
        git clone https://github.com/rony1duet/GCam_sweet2.git "$gcam_dir" -b "${DEVICE_BRANCH}" --depth=1
    else
        log_info "Updating $gcam_dir..."
        git -C "$gcam_dir" fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
        git -C "$gcam_dir" reset --hard origin/"${DEVICE_BRANCH}" 2>/dev/null || true
    fi
    rm -f "${gcam_dir}/Android.mk" 2>/dev/null || true

    # Clone or update vendor/android_prebuilts_sweet2
    if [[ ! -d "$prebuilts_dir" ]]; then
        log_info "Cloning $prebuilts_dir (${DEVICE_BRANCH})..."
        git clone https://github.com/rony1duet/android_prebuilts_sweet2.git "$prebuilts_dir" -b "${DEVICE_BRANCH}" --depth=1
    else
        log_info "Updating $prebuilts_dir..."
        git -C "$prebuilts_dir" fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
        git -C "$prebuilts_dir" reset --hard origin/"${DEVICE_BRANCH}" 2>/dev/null || true
    fi

    # Execute prebuilt fetcher
    local fetcher="${prebuilts_dir}/gcam/fetch_gcam_prebuilt.sh"
    if [[ -f "$fetcher" ]]; then
        sed -i 's/\r$//' "${prebuilts_dir}/gcam/"*.sh "${prebuilts_dir}/gcam/"*.env 2>/dev/null || true
        bash "$fetcher" "${gcam_dir}/system/product/app/GoogleCameraEng"
    fi

    local apk_path="${gcam_dir}/system/product/app/GoogleCameraEng/GoogleCameraEng.apk"
    [[ -f "$apk_path" ]] || die "GoogleCameraEng.apk missing! Prebuilt fetch failed."
}

# -----------------------------------------------------------------------------
# Compilation
# -----------------------------------------------------------------------------
build_target() {
    log_section "Starting PixelOS sweet2 build (A17)..."

    # shellcheck source=/dev/null
    source build/envsetup.sh || die "Failed to source build/envsetup.sh"
    [[ -f "build/soong/soong_ui.bash" ]] || die "Missing build/soong/soong_ui.bash"

    breakfast "${DEVICE_CODENAME}" || die "Failed to configure target: ${DEVICE_CODENAME}"
    m "${BUILD_TARGET}" || die "PixelOS compilation failed"
}

# -----------------------------------------------------------------------------
# Artifact Delivery
# -----------------------------------------------------------------------------
upload_artifacts() {
    log_section "Build successful! Uploading release..."

    local uploader="/tmp/upload_to_pixeldrain.sh"
    curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh" -o "$uploader"
    bash "$uploader"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
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
