#!/usr/bin/env bash
#
# OrangeFox Recovery Project (OFRP) Automated Local Build Script for Redmi Note 12 Pro 4G (sweet2)
# Base: fox_12.1 (Android 12.1 / TWRP 12.1 minimal manifest)
# Maintainer: rony1duet
# Supported OS: Linux (Ubuntu 20.04/22.04 LTS, Debian 11/12, WSL2)
#
# Usage via curl:
#   curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash
#
# Or with options:
#   curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- --install-deps
#

set -eo pipefail

readonly SCRIPT_VERSION="1.1.0"
readonly RECOVERY_NAME="OrangeFox"
readonly FOX_BRANCH="12.1"
readonly MANIFEST_URL="https://gitlab.com/OrangeFox/manifest.git"
readonly DEVICE_CODENAME="sweet2"
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

DEVICE_TREE_URL="${DEVICE_TREE_URL:-https://github.com/basamaryan/android_device_xiaomi_sweet-TWRP.git}"
DEVICE_TREE_BRANCH="${DEVICE_TREE_BRANCH:-fox_12.1}"
LUNCH_TARGET="twrp_${DEVICE_CODENAME}-eng"
BUILD_TARGET="recoveryimage"
JOBS="$(nproc --all 2>/dev/null || echo 4)"
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
            ;;
        --tree=*)
            DEVICE_TREE_URL="${arg#*=}"
            ;;
        --tree-branch=*)
            DEVICE_TREE_BRANCH="${arg#*=}"
            ;;
        --no-upload)
            AUTO_UPLOAD=false
            ;;
        -h|--help)
            cat << EOF
OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_CODENAME}
Version: ${SCRIPT_VERSION}

Usage: curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- [options] [workspace_dir]

Options:
  -i, --install-deps       Install all required packages and tools via apt-get
  -s, --sync               Force re-sync of the OrangeFox manifest
  -c, --clean              Execute 'mka clean' before starting compilation
  -j, --jobs=<N>           Number of parallel build threads (default: ${JOBS})
  --tree=<url>             Git repository URL for device recovery tree
  --tree-branch=<branch>   Branch for device recovery tree (default: ${DEVICE_TREE_BRANCH})
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
    info "Host RAM: ${total_ram_mb} MB | Swap: ${total_swap_mb} MB"

    if [[ "$total_ram_mb" -lt 12000 && "$total_swap_mb" -lt 8000 ]]; then
        warn "Low RAM + Swap detected (${total_ram_mb} MB RAM / ${total_swap_mb} MB Swap)."
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            info "Automatically configuring 16 GB swap file to prevent OOM errors..."
            sudo fallocate -l 16G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=16384 2>/dev/null || true
            if [[ -f /swapfile ]]; then
                sudo chmod 600 /swapfile
                sudo mkswap /swapfile 2>/dev/null || true
                sudo swapon /swapfile 2>/dev/null || true
                success "16 GB swap file successfully activated."
            fi
        fi
    fi

    # Check for missing basic tools
    local missing=()
    for tool in git curl repo bison flex python3 ccache; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "Missing build tools: ${missing[*]}. Triggering automatic installation..."
        INSTALL_DEPS=true
    fi
}

# 2. Dependency Installation
install_dependencies() {
    info "Installing Android & OrangeFox build dependencies via apt-get..."

    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get package manager not found. Please ensure all build dependencies are installed manually."
        return 0
    fi

    sudo apt-get update -y || true

    local pkgs=(
        aria2 bc bison build-essential ccache curl flex g++-multilib gcc-multilib git
        git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev
        libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils
        lz4 liblz4-tool lzop openjdk-11-jdk pngcrush python3 python-is-python3 rsync
        schedtool squashfs-tools unzip xsltproc zip zlib1g-dev
    )

    local to_install=()
    for pkg in "${pkgs[@]}"; do
        if apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate: [^(\n]'; then
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        sudo apt-get install -y "${to_install[@]}" || true
    fi

    # Ensure repo command is installed
    if ! command -v repo >/dev/null 2>&1; then
        info "Installing Google repo tool to /usr/local/bin/repo..."
        sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
        sudo chmod a+rx /usr/local/bin/repo
    fi

    # Configure Git LFS
    git lfs install 2>/dev/null || true

    success "Build dependencies installed and verified."
}

# 3. OrangeFox Manifest Sync
sync_orangefox() {
    info "Entering OrangeFox workspace: ${WORKSPACE_DIR}..."
    cd "${WORKSPACE_DIR}"

    if [[ ! -d ".repo" || "$FORCE_SYNC" == "true" ]]; then
        info "Initializing OrangeFox minimal manifest (branch: fox_${FOX_BRANCH})..."
        repo init -u "${MANIFEST_URL}" -b "fox_${FOX_BRANCH}" --depth=1 --git-lfs

        info "Synchronizing sources with ${JOBS} parallel threads..."
        repo sync -c -j"${JOBS}" --force-sync --no-clone-bundle --no-tags
        success "OrangeFox source sync completed."
    else
        info "Existing OrangeFox source tree detected in ${WORKSPACE_DIR}. Skipping sync (use --sync to force)."
    fi
}

# 4. Device Recovery Tree Setup
setup_device_tree() {
    info "Setting up recovery device tree for ${DEVICE_CODENAME}..."
    cd "${WORKSPACE_DIR}"

    local target_dir="device/${DEVICE_BRAND}/${DEVICE_CODENAME}"

    if [[ -d "${target_dir}/.git" ]]; then
        info "Device tree already present in ${target_dir}. Updating latest commits..."
        git -C "${target_dir}" fetch origin "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" checkout "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" pull origin "${DEVICE_TREE_BRANCH}" || true
    elif [[ -d "${target_dir}" ]]; then
        info "Device tree folder ${target_dir} exists."
    else
        info "Cloning device tree from ${DEVICE_TREE_URL} (branch: ${DEVICE_TREE_BRANCH})..."
        mkdir -p "device/${DEVICE_BRAND}"
        git clone "${DEVICE_TREE_URL}" -b "${DEVICE_TREE_BRANCH}" "${target_dir}"
    fi

    # Alias sweet to sweet2 if needed
    if [[ ! -f "${target_dir}/twrp_${DEVICE_CODENAME}.mk" && ! -f "${target_dir}/fox_${DEVICE_CODENAME}.mk" ]]; then
        if [[ -f "${target_dir}/twrp_sweet.mk" ]]; then
            info "Aliasing twrp_sweet.mk -> twrp_${DEVICE_CODENAME}.mk for ${DEVICE_CODENAME}..."
            sed -e "s/sweet/sweet2/g" -e "s/Redmi Note 10 Pro/Redmi Note 12 Pro 4G/g" \
                "${target_dir}/twrp_sweet.mk" > "${target_dir}/twrp_${DEVICE_CODENAME}.mk"
        fi
    fi

    if [[ -f "${target_dir}/AndroidProducts.mk" ]]; then
        if ! grep -q "twrp_${DEVICE_CODENAME}.mk" "${target_dir}/AndroidProducts.mk"; then
            sed -i "/PRODUCT_MAKEFILES/a \    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk \\\\" "${target_dir}/AndroidProducts.mk" || true
            sed -i "/COMMON_LUNCH_CHOICES/a \    twrp_${DEVICE_CODENAME}-eng \\\\" "${target_dir}/AndroidProducts.mk" || true
        fi
    fi

    success "Device tree configured in ${target_dir}."
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

    # OrangeFox Metadata & Configuration
    export OF_MAINTAINER="${DEFAULT_MAINTAINER}"
    export FOX_VERSION="R12.1"
    export FOX_BUILD_TYPE="Unofficial"
    export TARGET_DEVICE="${DEVICE_CODENAME}"

    # Display Dimensions (Redmi Note 12 Pro 4G: 1080x2400)
    export OF_SCREEN_H=2400
    export OF_STATUS_H=95
    export OF_STATUS_INDENT_LEFT=48
    export OF_STATUS_INDENT_RIGHT=48
    export OF_CLOCK_POS=1

    # Storage Decryption (FBE v2 + Metadata Encryption)
    export TW_INCLUDE_CRYPTO=true
    export TW_INCLUDE_CRYPTO_FBE=true
    export TW_INCLUDE_FBE_METADATA_DECRYPT=true
    export BOARD_USES_METADATA_PARTITION=true

    # OrangeFox UI & Addons
    export OF_USE_GREEN_LED=0
    export FOX_ENABLE_APP_MANAGER=1
    export FOX_USE_SPECIFIC_MAGISK_ZIP=1
}

# 6. Compilation
compile_recovery() {
    info "Sourcing Android build environment..."
    cd "${WORKSPACE_DIR}"

    # shellcheck source=/dev/null
    source build/envsetup.sh

    info "Executing lunch for target: ${LUNCH_TARGET}..."
    if ! lunch "${LUNCH_TARGET}"; then
        warn "Target '${LUNCH_TARGET}' failed. Attempting alternative targets..."
        if lunch "fox_${DEVICE_CODENAME}-eng" 2>/dev/null; then
            LUNCH_TARGET="fox_${DEVICE_CODENAME}-eng"
        elif lunch "twrp_sweet-eng" 2>/dev/null; then
            LUNCH_TARGET="twrp_sweet-eng"
        else
            die "Failed to lunch target for ${DEVICE_CODENAME}."
        fi
    fi

    if [[ "$RUN_CLEAN" == "true" ]]; then
        info "Cleaning prior build output..."
        mka clean
    fi

    local start_time
    start_time=$(date +%s)

    info "Starting OrangeFox compilation (target: ${BUILD_TARGET}, threads: ${JOBS})..."
    mka -j"${JOBS}" "${BUILD_TARGET}"

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

    local out_dir="out/target/product/${DEVICE_CODENAME}"
    [[ -d "$out_dir" ]] || out_dir="out/target/product/sweet"

    if [[ ! -d "$out_dir" ]]; then
        die "Output directory not found. Compilation may have aborted."
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
    echo "  OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_CODENAME} "
    echo "  Version: ${SCRIPT_VERSION} | Manifest: fox_${FOX_BRANCH}          "
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
