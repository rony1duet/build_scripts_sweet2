#!/usr/bin/env bash
#
# OrangeFox Recovery Project (OFRP) Automated Local Build Script for Redmi Note 12 Pro 4G (sweet2 / sweet_k6a)
# Base: fox_12.1 (Android 12.1 / TWRP 12.1 minimal manifest)
# Device Tree: MiDoNaSR545/device_xiaomi_sweet_k6a-OFOX (branch: fox-12.1)
# Maintainer: rony1duet
# Supported OS: Linux (Ubuntu 20.04/22.04 LTS, Debian 11/12, WSL2, Docker)
#
# Usage via curl:
#   curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- -j8
#

set -eo pipefail

readonly SCRIPT_VERSION="1.6.0"
readonly RECOVERY_NAME="OrangeFox"
readonly FOX_BRANCH="12.1"
readonly SYNC_REPO_URL="https://gitlab.com/OrangeFox/sync.git"
readonly DEVICE_CODENAME="sweet_k6a"
readonly DEVICE_ALIAS="sweet2"
readonly DEVICE_BRAND="xiaomi"
readonly DEFAULT_MAINTAINER="rony1duet"

# Terminal Colors
info()    { printf "\033[0;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
success() { printf "\033[0;32m[✓]\033[0m \033[1m%s\033[0m\n" "$*"; }
warn()    { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die()     { printf "\033[0;31m[x]\033[0m %s\n" "$*" >&2; exit 1; }

# Determine Workspace Directory
# If running inside a Windows mount (/mnt/c, /mnt/g), automatically switch to native ext4 ~/fox_12.1
if [[ "$(pwd)" =~ ^/mnt/[a-zA-Z]/ || "$(pwd)" == "/root" ]]; then
    WORKSPACE_DIR="${HOME}/fox_12.1"
else
    WORKSPACE_DIR="$(pwd)/fox_12.1"
fi

# MiDoNaSR545 repository specifically authored for sweet_k6a / sweet2 (Redmi Note 12 Pro 4G)
DEVICE_TREE_URL="${DEVICE_TREE_URL:-https://github.com/MiDoNaSR545/device_xiaomi_sweet_k6a-OFOX.git}"
DEVICE_TREE_BRANCH="${DEVICE_TREE_BRANCH:-fox-12.1}"
LUNCH_TARGET="twrp_${DEVICE_CODENAME}-eng"
BUILD_TARGET="recoveryimage"
# Parallelism safeguards:
# OrangeFox recovery image is lightweight (~300 source targets).
# Uncapped 48 threads on containers spikes RAM & arenas, triggering soong_build OOM kills.
CUSTOM_JOBS=""
DETECTED_CORES="$(nproc --all 2>/dev/null || echo 4)"
if [[ "$DETECTED_CORES" -gt 8 ]]; then
    JOBS=8
else
    JOBS="$DETECTED_CORES"
fi
INSTALL_DEPS=false
FORCE_SYNC=false
RUN_CLEAN=false
AUTO_UPLOAD=true

# Parse Command Line Options
for arg in "$@"; do
    case "$arg" in
        -i|--install-deps)
            INSTALL_DEPS=true
            ;;
        -s|--sync)
            FORCE_SYNC=true
            ;;
        -c|--clean)
            RUN_CLEAN=true
            ;;
        -j=*|--jobs=*)
            JOBS="${arg#*=}"
            CUSTOM_JOBS="${arg#*=}"
            ;;
        -j*)
            JOBS="${arg#-j}"
            CUSTOM_JOBS="${arg#-j}"
            ;;
        --tree=*)
            DEVICE_TREE_URL="${arg#*=}"
            ;;
        --tree-branch=*)
            DEVICE_TREE_BRANCH="${arg#*=}"
            ;;
        --lunch=*)
            LUNCH_TARGET="${arg#*=}"
            ;;
        --no-upload)
            AUTO_UPLOAD=false
            ;;
        -h|--help)
            cat << EOF
OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_ALIAS} / ${DEVICE_CODENAME}
Version: ${SCRIPT_VERSION}

Usage: curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- [options] [workspace_dir]

Options:
  -i, --install-deps       Install all required packages and tools via apt-get
  -s, --sync               Force re-sync of the OrangeFox manifest
  -c, --clean              Execute 'mka clean' before starting compilation
  -j, --jobs=<N>           Number of parallel build threads (default: ${JOBS})
  --tree=<url>             Git repository URL for device recovery tree
  --tree-branch=<branch>   Branch for device recovery tree (default: ${DEVICE_TREE_BRANCH})
  --lunch=<target>         Custom lunch target (default: ${LUNCH_TARGET})
  --no-upload              Skip automatic upload to Pixeldrain
  -h, --help               Display this help text and exit
EOF
            exit 0
            ;;
        *)
            if [[ "$arg" != -* && -d "$arg" ]]; then
                WORKSPACE_DIR="$arg"
            fi
            ;;
    esac
done

# Failure Diagnostics Trap
cleanup_on_error() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        printf "\n\033[0;31m[x]\033[0m OrangeFox build failed with exit code %s.\n" "$rc"
        echo "Check build output above for detailed errors."
    fi
}
trap cleanup_on_error EXIT

# 1. Environment & Architecture Validation
check_environment() {
    info "Validating host build environment..."

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        die "Native Windows detected. Android and OrangeFox recovery cannot be compiled on Windows natively. Please install WSL2 (Ubuntu 22.04 LTS) and run this command inside Ubuntu WSL2."
    fi

    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        info "Running under Windows Subsystem for Linux (WSL2)."
        if [[ "$WORKSPACE_DIR" =~ ^/mnt/[a-zA-Z]/ ]]; then
            warn "Current directory is on Windows NTFS (/mnt/*). Switching workspace to native Linux ext4 ~/fox_12.1 for performance and case-sensitivity."
            WORKSPACE_DIR="${HOME}/fox_12.1"
        fi
    fi

    mkdir -p "${WORKSPACE_DIR}"
    info "Workspace directory: ${WORKSPACE_DIR}"

    # Verify Free Storage (Minimum 45 GB required)
    local avail_gb
    avail_gb=$(df -BG "${WORKSPACE_DIR}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' | tr -dc '0-9')
    if [[ -n "$avail_gb" && "$avail_gb" -lt 40 ]]; then
        warn "Free disk space is ${avail_gb} GB. OrangeFox minimal manifest requires at least ~45 GB."
    elif [[ -n "$avail_gb" ]]; then
        success "Disk space check passed: ${avail_gb} GB available."
    fi

    # Check RAM and configure Swap if needed
    local total_ram_mb total_swap_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    total_swap_mb=$(free -m | awk '/^Swap:/{print $2}')
    info "Host RAM: ${total_ram_mb} MB | Swap: ${total_swap_mb} MB (Build threads capped to: ${JOBS})"

    if [[ "$total_swap_mb" -lt 4000 ]]; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            info "Zero/low swap space detected. Attempting to activate 8 GB swapfile..."
            if [[ ! -f /swapfile ]]; then
                sudo fallocate -l 8G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 2>/dev/null || true
            fi
            if [[ -f /swapfile ]]; then
                sudo chmod 600 /swapfile 2>/dev/null || true
                sudo mkswap /swapfile 2>/dev/null || true
                sudo swapon /swapfile 2>/dev/null && success "8 GB swap file successfully activated." || warn "Could not activate swap (container restricted). Memory limits enabled."
            fi
        fi
    fi

    # Ensure git identity exists to avoid repo init prompts
    if [[ -z "$(git config --global user.email 2>/dev/null || true)" ]]; then
        git config --global user.email "rony1duet@users.noreply.github.com"
    fi
    if [[ -z "$(git config --global user.name 2>/dev/null || true)" ]]; then
        git config --global user.name "rony1duet"
    fi

    # Check for missing basic tools
    local missing=()
    for tool in patch bison flex ccache repo git curl python3; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Missing build tools: ${missing[*]}. Triggering automatic installation..."
        INSTALL_DEPS=true
    fi
}

# 2. Robust Dependency Installation
install_dependencies() {
    info "Installing Android & OrangeFox build dependencies via apt-get..."

    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get package manager not found. Please ensure all build dependencies are installed manually."
        return 0
    fi

    local SUDO=""
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi

    $SUDO apt-get update -y || true

    # Step A: Install essential tools individually first to avoid batch failures from deprecated packages
    local core_tools=(patch bison flex ccache git git-lfs curl python3 build-essential rsync zip unzip)
    for tool in "${core_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            info "Installing core tool: ${tool}..."
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$tool" || true
        fi
    done

    # Step B: Install the rest of the libraries
    local pkgs=(
        aria2 bc g++-multilib gcc-multilib gnupg gperf imagemagick lib32readline-dev
        lib32z1-dev libelf-dev libncurses-dev libssl-dev libxml2 libxml2-utils
        lz4 liblz4-tool lzop pngcrush python-is-python3 schedtool squashfs-tools
        xsltproc zlib1g-dev openjdk-17-jdk openjdk-11-jdk
    )

    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null || {
        for p in "${pkgs[@]}"; do
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$p" 2>/dev/null || true
        done
    }

    # Step C: Ensure Google repo command is installed
    if ! command -v repo >/dev/null 2>&1; then
        info "Installing Google repo tool to /usr/local/bin/repo..."
        $SUDO curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo || true
        $SUDO chmod a+rx /usr/local/bin/repo || true
    fi

    # Step D: Configure Git LFS
    git lfs install 2>/dev/null || true

    # Step E: Verify critical compilation tools are in PATH
    for tool in patch bison flex ccache repo python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "Critical build tool '$tool' is missing and could not be installed. Please run: sudo apt-get install -y $tool"
        fi
    done

    success "Build dependencies installed and verified."
}

# 3. OrangeFox Manifest Sync (Using official sync tool and patches)
sync_orangefox() {
    info "Entering OrangeFox workspace: ${WORKSPACE_DIR}..."
    cd "${WORKSPACE_DIR}"

    # If vendor/recovery does not exist or force-sync requested, perform fresh/resume sync
    if [[ ! -d "${WORKSPACE_DIR}/vendor/recovery" || "$FORCE_SYNC" == "true" ]]; then
        local sync_tool_dir="/tmp/ofox_sync_$$"
        rm -rf "${sync_tool_dir}"
        info "Cloning official OrangeFox synchronization tool from GitLab..."
        git clone --depth=1 "${SYNC_REPO_URL}" "${sync_tool_dir}"

        # Copy patches into workspace directory to ensure patch files exist in both locations
        mkdir -p "${WORKSPACE_DIR}/patches"
        cp -rf "${sync_tool_dir}/patches/"* "${WORKSPACE_DIR}/patches/" 2>/dev/null || true

        info "Synchronizing OrangeFox ${FOX_BRANCH} minimal manifest into ${WORKSPACE_DIR}..."
        (
            cd "${sync_tool_dir}"
            bash ./orangefox_sync.sh --branch "${FOX_BRANCH}" --path "${WORKSPACE_DIR}" --ssh 0
        )

        rm -rf "${sync_tool_dir}"
        success "OrangeFox source sync and patch completed."
    else
        info "Existing OrangeFox source tree detected in ${WORKSPACE_DIR}. Skipping sync (use --sync to force)."
    fi
}

# 4. Device Recovery Tree Setup (Using MiDoNaSR545 repository)
setup_device_tree() {
    info "Setting up recovery device tree for ${DEVICE_ALIAS} (${DEVICE_CODENAME}) using MiDoNaSR545 repo..."
    cd "${WORKSPACE_DIR}"

    local target_dir="device/${DEVICE_BRAND}/${DEVICE_CODENAME}"
    local alias_dir="device/${DEVICE_BRAND}/${DEVICE_ALIAS}"

    # Remove any existing alias symlink/dir to prevent duplicate vendorsetup inclusion and Soong/Kati collisions
    if [[ -e "${alias_dir}" || -L "${alias_dir}" ]]; then
        info "Cleaning up old alias symlink/dir: ${alias_dir}..."
        rm -rf "${alias_dir}"
    fi

    if [[ -d "${target_dir}/.git" ]]; then
        info "Device tree already present in ${target_dir}. Updating latest commits..."
        git -C "${target_dir}" fetch origin "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" checkout "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" pull origin "${DEVICE_TREE_BRANCH}" || true
    elif [[ -d "${target_dir}" ]]; then
        info "Device tree folder ${target_dir} exists."
    else
        info "Cloning MiDoNaSR device tree from ${DEVICE_TREE_URL} (branch: ${DEVICE_TREE_BRANCH})..."
        mkdir -p "device/${DEVICE_BRAND}"
        git clone "${DEVICE_TREE_URL}" -b "${DEVICE_TREE_BRANCH}" "${target_dir}"
    fi

    # Ensure sweet2 alias target makefile exists cleanly without path corruption
    info "Configuring alias makefile: ${target_dir}/twrp_${DEVICE_ALIAS}.mk..."
    cat << EOF > "${target_dir}/twrp_${DEVICE_ALIAS}.mk"
#
# Copyright (C) $(date +%Y) The Android Open Source Project
# Inherit sweet_k6a base configuration
\$(call inherit-product, device/${DEVICE_BRAND}/${DEVICE_CODENAME}/twrp_${DEVICE_CODENAME}.mk)

PRODUCT_NAME := twrp_${DEVICE_ALIAS}
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_MODEL := Redmi Note 12 Pro 4G
EOF

    # Configure AndroidProducts.mk with both targets cleanly
    info "Configuring lunch targets in ${target_dir}/AndroidProducts.mk..."
    cat << EOF > "${target_dir}/AndroidProducts.mk"
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk \\
    \$(LOCAL_DIR)/twrp_${DEVICE_ALIAS}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-eng \\
    twrp_${DEVICE_ALIAS}-eng
EOF

    # Ensure device.mk asserts sweet2, sweet_k6a, and sweet
    if [[ -f "${target_dir}/device.mk" ]]; then
        if ! grep -q "TARGET_OTA_ASSERT_DEVICE" "${target_dir}/device.mk"; then
            echo "" >> "${target_dir}/device.mk"
            echo "# OTA Assert Devices" >> "${target_dir}/device.mk"
            echo "TARGET_OTA_ASSERT_DEVICE := ${DEVICE_ALIAS},${DEVICE_CODENAME},sweet" >> "${target_dir}/device.mk"
        fi
    fi

    success "MiDoNaSR545 device tree configured in ${target_dir}."
}

# 5. Ccache & Environment Setup
setup_build_environment() {
    info "Configuring build environment and ccache..."

    export USE_CCACHE=1
    export CCACHE_EXEC="/usr/bin/ccache"
    export CCACHE_DIR="${HOME}/.ccache_orangefox"
    mkdir -p "${CCACHE_DIR}"
    ccache -M 25G 2>/dev/null || true

    export ALLOW_MISSING_DEPENDENCIES=true
    export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
    export LC_ALL="C"

    # OrangeFox Metadata & Customization
    export OF_MAINTAINER="${OF_MAINTAINER:-${DEFAULT_MAINTAINER}}"
    export FOX_VERSION="R12.1"
    export FOX_BUILD_TYPE="Unofficial"
    export TARGET_DEVICE="${DEVICE_CODENAME}"
    export FOX_BUILD_DEVICE="${DEVICE_CODENAME}"
    export FDEVICE="${DEVICE_CODENAME}"
    export FOX_TARGET_DEVICES="${DEVICE_ALIAS},${DEVICE_CODENAME},sweet"
    export TARGET_DEVICE_ALT="${DEVICE_ALIAS},${DEVICE_CODENAME},sweet"

    # Memory & Concurrency Safeguards for Soong & Compiler
    export GOMAXPROCS="${JOBS}"
    export GOMEMLIMIT=12GiB
    export GOGC=40
    export MALLOC_ARENA_MAX=2
    export NINJA_ARGS="-j${JOBS}"

    # Display Dimensions (Redmi Note 12 Pro 4G: 1080x2400)
    export OF_SCREEN_H=2400
    export OF_STATUS_H=100
    export OF_STATUS_INDENT_LEFT=48
    export OF_STATUS_INDENT_RIGHT=48
    export OF_HIDE_NOTCH=1
    export OF_CLOCK_POS=1

    # Storage Decryption (FBE v2 + Metadata Encryption)
    export TW_INCLUDE_CRYPTO=true
    export TW_INCLUDE_CRYPTO_FBE=true
    export TW_INCLUDE_FBE_METADATA_DECRYPT=true
    export BOARD_USES_METADATA_PARTITION=true
    export BOARD_USES_QCOM_FBE_DECRYPTION=true

    # Display wake fix for 120Hz AMOLED
    export TW_NO_SCREEN_BLANK=true
    export TW_NO_SCREEN_TIMEOUT=true

    # OrangeFox UI & Addons
    export OF_USE_GREEN_LED=0
    export FOX_ENABLE_APP_MANAGER=1
    if [[ -f "${WORKSPACE_DIR}/device/${DEVICE_BRAND}/${DEVICE_CODENAME}/addon/Magisk-v27.0.zip" ]]; then
        export FOX_USE_SPECIFIC_MAGISK_ZIP="${WORKSPACE_DIR}/device/${DEVICE_BRAND}/${DEVICE_CODENAME}/addon/Magisk-v27.0.zip"
    fi
}

# 6. Compilation
compile_recovery() {
    info "Sourcing Android build environment..."
    cd "${WORKSPACE_DIR}"

    # Clean up incomplete/corrupted Soong bootstrap cache from previous OOM kill
    if [[ -d "${WORKSPACE_DIR}/out/soong" && ! -f "${WORKSPACE_DIR}/out/soong/build.ninja" ]]; then
        warn "Cleaning incomplete/corrupted Soong bootstrap cache from prior interrupted run..."
        rm -rf "${WORKSPACE_DIR}/out/soong" "${WORKSPACE_DIR}/out/.module_paths"
    fi

    # Envsetup and vendorsetup scripts contain subshells, grep checks, and tests
    # that return non-zero exit codes. Disable -e during envsetup and lunch.
    set +e
    # shellcheck source=/dev/null
    source build/envsetup.sh

    info "Executing lunch for target: ${LUNCH_TARGET}..."
    lunch "${LUNCH_TARGET}"
    local lunch_rc=$?

    if [[ $lunch_rc -ne 0 ]]; then
        warn "Target '${LUNCH_TARGET}' failed. Checking alternative lunch targets..."
        if lunch "twrp_${DEVICE_ALIAS}-eng"; then
            LUNCH_TARGET="twrp_${DEVICE_ALIAS}-eng"
            lunch_rc=0
        elif lunch "fox_${DEVICE_CODENAME}-eng"; then
            LUNCH_TARGET="fox_${DEVICE_CODENAME}-eng"
            lunch_rc=0
        elif lunch "twrp_sweet-eng"; then
            LUNCH_TARGET="twrp_sweet-eng"
            lunch_rc=0
        fi
    fi

    # Re-enable errexit for compilation
    set -e

    if [[ $lunch_rc -ne 0 ]]; then
        die "Failed to lunch any recovery target for ${DEVICE_CODENAME} / ${DEVICE_ALIAS}."
    fi

    if [[ "$RUN_CLEAN" == "true" ]]; then
        info "Cleaning prior build output..."
        if type m &>/dev/null; then
            m clean
        else
            make clean
        fi
    fi

    local start_time
    start_time=$(date +%s)

    info "Starting OrangeFox compilation (target: ${BUILD_TARGET}, threads: ${JOBS})..."
    if type m &>/dev/null; then
        m -j"${JOBS}" "${BUILD_TARGET}"
    else
        make -j"${JOBS}" "${BUILD_TARGET}"
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    success "OrangeFox compilation finished successfully in ${minutes}m ${seconds}s!"
}

# 7. Verification and Pixeldrain Upload
package_and_export() {
    info "Verifying built output..."
    cd "${WORKSPACE_DIR}"

    local out_dir=""
    for d in "out/target/product/${DEVICE_CODENAME}" "out/target/product/${DEVICE_ALIAS}" "out/target/product/sweet"; do
        if [[ -d "$d" ]]; then
            out_dir="$d"
            break
        fi
    done

    if [[ -z "$out_dir" || ! -d "$out_dir" ]]; then
        die "Output directory not found. Compilation may have failed to produce output."
    fi

    local fox_zip
    fox_zip=$(find "${out_dir}" -maxdepth 1 -name "OrangeFox-*.zip" -type f 2>/dev/null | head -n 1)
    local recovery_img="${out_dir}/recovery.img"

    echo ""
    echo "============================================================"
    echo "            ORANGEFOX BUILD COMPLETE!                       "
    echo "============================================================"
    if [[ -f "$recovery_img" ]]; then
        local img_size
        img_size=$(du -h "$recovery_img" | cut -f1)
        echo "  Recovery Image: ${recovery_img} (${img_size})"
        echo "  Fastboot Flash: fastboot flash recovery ${recovery_img}"
    fi
    if [[ -n "$fox_zip" && -f "$fox_zip" ]]; then
        local zip_size
        zip_size=$(du -h "$fox_zip" | cut -f1)
        echo "  Flashable ZIP:  ${fox_zip} (${zip_size})"
        echo "  MD5 Checksum:   $(md5sum "${fox_zip}" | cut -d' ' -f1)"
    fi
    echo "============================================================"
    echo ""

    if [[ "$AUTO_UPLOAD" == "true" && -n "$fox_zip" && -f "$fox_zip" ]]; then
        info "Uploading OrangeFox flashable package to Pixeldrain..."
        local uploader_script="$(dirname "$(readlink -f "$0" 2>/dev/null || echo ".")")/upload_to_pixeldrain.sh"
        if [[ -f "$uploader_script" ]]; then
            bash "$uploader_script" "$fox_zip" || warn "Pixeldrain upload failed, but build artifact is saved locally."
        else
            curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/upload_to_pixeldrain.sh" | bash -s -- "$fox_zip" || warn "Pixeldrain upload failed, but build artifact is saved locally."
        fi
    fi
}

# Main Execution Flow
main() {
    echo "============================================================"
    echo "  OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_ALIAS} (${DEVICE_CODENAME})"
    echo "  Version: ${SCRIPT_VERSION} | Base: fox_${FOX_BRANCH}              "
    echo "============================================================"
    echo ""

    check_environment

    if [[ "$INSTALL_DEPS" == "true" ]]; then
        install_dependencies
    fi

    sync_orangefox
    setup_device_tree
    setup_build_environment
    compile_recovery
    package_and_export

    trap - EXIT
    success "OrangeFox Recovery build and packaging completed successfully!"
}

main "$@"
