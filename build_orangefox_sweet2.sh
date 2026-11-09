#!/usr/bin/env bash
#
# OrangeFox Recovery Project (OFRP) Build Script for Redmi Note 12 Pro 4G (sweet2)
# Target Base: fox_12.1 (Android 12.1 / TWRP 12.1 base)
# Maintainer: rony1duet
# Supported Environments: Linux (Ubuntu 20.04/22.04, Debian 11/12, WSL2)
#

set -eo pipefail

readonly SCRIPT_VERSION="1.0.0"
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

# Default Parameters
WORKSPACE_DIR="${FOX_WORKSPACE:-${HOME}/fox_12.1}"
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
print_help() {
    cat << EOF
OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_CODENAME}
Version: ${SCRIPT_VERSION}

Usage: $(basename "$0") [options] [workspace_dir]

Options:
  -i, --install-deps       Install all required build tools and libraries (Ubuntu/Debian)
  -s, --sync               Force re-sync of the OrangeFox manifest and repositories
  -c, --clean              Execute 'mka clean' before starting the build
  -j, --jobs=<N>           Number of parallel build threads (default: ${JOBS})
  --tree=<url>             Git repository URL for the device recovery tree
  --tree-branch=<branch>   Branch for the device recovery tree (default: ${DEVICE_TREE_BRANCH})
  --no-upload              Skip automatic upload to Pixeldrain after a successful build
  -h, --help               Display this help text and exit

Environment Variables:
  FOX_WORKSPACE            Directory where the OrangeFox source tree will be located
  DEVICE_TREE_URL          Git URL for the recovery device tree
  DEVICE_TREE_BRANCH       Branch to use for the recovery device tree
  PIXELDRAIN_API_KEY       Pixeldrain API key for uploading the output recovery zip

Example:
  $(basename "$0") --install-deps --sync ~/fox_12.1
EOF
    exit 0
}

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
            print_help
            ;;
        *)
            if [[ "$arg" != -* ]]; then
                WORKSPACE_DIR="$arg"
            fi
            ;;
    esac
done

# Ensure POSIX / Linux Environment
check_environment() {
    info "Validating host build environment..."

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        die "Native Windows / Git-Bash detected. Android and OrangeFox recovery cannot be compiled natively on Windows. Please install WSL2 (Ubuntu 22.04 LTS) and run this script inside WSL2."
    fi

    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        info "Running under Windows Subsystem for Linux (WSL2)."
        
        # Warn if working inside a Windows DrvFs mount (/mnt/c, /mnt/g, etc.)
        if [[ "$WORKSPACE_DIR" =~ ^/mnt/[a-zA-Z]/ ]]; then
            warn "WARNING: Your workspace is set to a Windows NTFS drive (${WORKSPACE_DIR})."
            warn "Building Android / Recovery on Windows DrvFs (/mnt/*) causes severe I/O slowdowns, case-insensitivity issues, and broken symlinks."
            warn "It is STRONGLY recommended to use native Linux ext4 storage inside WSL2 (e.g. ~/fox_12.1)."
            read -rp "Do you want to switch workspace to ~/fox_12.1? [Y/n] " choice
            choice="${choice:-Y}"
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                WORKSPACE_DIR="${HOME}/fox_12.1"
                info "Switched workspace to ${WORKSPACE_DIR}"
            fi
        fi
    fi

    # Check available storage (Minimum 45 GB required for minimal recovery manifest)
    local target_check="${WORKSPACE_DIR}"
    [[ -d "$target_check" ]] || target_check="$(dirname "$target_check")"
    [[ -d "$target_check" ]] || target_check="${HOME}"

    local avail_gb
    avail_gb=$(df -BG "$target_check" | awk 'NR==2 {gsub("G",""); print $4}')
    if [[ -n "$avail_gb" && "$avail_gb" -lt 40 ]]; then
        warn "Available disk space is ${avail_gb} GB. OrangeFox minimal manifest requires at least ~45 GB."
        warn "You may run out of disk space during compilation!"
    else
        success "Disk space check passed: ${avail_gb} GB available in ${target_check}."
    fi

    # Check RAM and Swap
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_swap_mb
    total_swap_mb=$(free -m | awk '/^Swap:/{print $2}')

    info "System RAM: ${total_ram_mb} MB | Swap: ${total_swap_mb} MB"
    if [[ "$total_ram_mb" -lt 12000 && "$total_swap_mb" -lt 8000 ]]; then
        warn "Your machine has under 12 GB RAM and insufficient swap space."
        warn "Compiling with high parallelism may trigger the Linux OOM (Out Of Memory) killer."
        warn "Consider adding a 16 GB swap file or reducing jobs (-j2 or -j4)."
    fi
}

# Install Build Dependencies (Debian / Ubuntu / WSL2)
install_dependencies() {
    info "Installing Android & OrangeFox build dependencies..."

    if ! command -v apt-get >/dev/null 2>&1; then
        warn "Package manager 'apt-get' not found. Please ensure all required dependencies are installed manually."
        return 0
    fi

    sudo apt-get update
    sudo apt-get install -y \
        aria2 \
        bc \
        bison \
        build-essential \
        ccache \
        curl \
        flex \
        g++-multilib \
        gcc-multilib \
        git \
        git-lfs \
        gnupg \
        gperf \
        imagemagick \
        lib32ncurses5-dev \
        lib32readline-dev \
        lib32z1-dev \
        libelf-dev \
        liblz4-tool \
        libncurses5 \
        libncurses5-dev \
        libsdl1.2-dev \
        libssl-dev \
        libxml2 \
        libxml2-utils \
        lzop \
        openjdk-11-jdk \
        pngcrush \
        python3 \
        python-is-python3 \
        rsync \
        schedtool \
        squashfs-tools \
        unzip \
        xsltproc \
        zip \
        zlib1g-dev

    # Ensure repo command is installed
    if ! command -v repo >/dev/null 2>&1; then
        info "Installing Google repo tool..."
        sudo mkdir -p /usr/local/bin
        sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
        sudo chmod a+rx /usr/local/bin/repo
    fi

    # Configure Git LFS
    git lfs install 2>/dev/null || true

    success "Dependencies successfully installed."
}

# Sync OrangeFox Source Manifest
sync_orangefox() {
    info "Setting up OrangeFox source workspace at ${WORKSPACE_DIR}..."
    mkdir -p "${WORKSPACE_DIR}"
    cd "${WORKSPACE_DIR}"

    if [[ ! -d ".repo" || "$FORCE_SYNC" == "true" ]]; then
        info "Initializing OrangeFox minimal manifest (branch: fox_${FOX_BRANCH})..."
        repo init -u "${MANIFEST_URL}" -b "fox_${FOX_BRANCH}" --depth=1 --git-lfs

        info "Syncing source repositories (jobs: ${JOBS})..."
        repo sync -c -j"${JOBS}" --force-sync --no-clone-bundle --no-tags
        success "OrangeFox source sync completed."
    else
        info "Existing OrangeFox source tree detected in ${WORKSPACE_DIR}. Skipping full sync (use --sync to force)."
    fi
}

# Setup Device Recovery Tree
setup_device_tree() {
    info "Setting up recovery device tree for ${DEVICE_CODENAME}..."
    cd "${WORKSPACE_DIR}"

    local target_dir="device/${DEVICE_BRAND}/${DEVICE_CODENAME}"

    if [[ -d "${target_dir}/.git" ]]; then
        info "Device tree already present in ${target_dir}. Fetching latest commits..."
        git -C "${target_dir}" fetch origin "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" checkout "${DEVICE_TREE_BRANCH}" || true
        git -C "${target_dir}" pull origin "${DEVICE_TREE_BRANCH}" || true
    elif [[ -d "${target_dir}" ]]; then
        info "Device tree folder ${target_dir} exists (local copy)."
    else
        info "Cloning device tree from ${DEVICE_TREE_URL} (branch: ${DEVICE_TREE_BRANCH})..."
        mkdir -p "device/${DEVICE_BRAND}"
        git clone "${DEVICE_TREE_URL}" -b "${DEVICE_TREE_BRANCH}" "${target_dir}"
    fi

    # Validate device makefile naming
    if [[ ! -f "${target_dir}/AndroidProducts.mk" && ! -f "${target_dir}/twrp_${DEVICE_CODENAME}.mk" && ! -f "${target_dir}/fox_${DEVICE_CODENAME}.mk" ]]; then
        warn "No standard twrp_${DEVICE_CODENAME}.mk or fox_${DEVICE_CODENAME}.mk found in ${target_dir}."
        if [[ -f "${target_dir}/twrp_sweet.mk" ]]; then
            info "Found twrp_sweet.mk. Creating alias for ${DEVICE_CODENAME}..."
            cp "${target_dir}/twrp_sweet.mk" "${target_dir}/twrp_${DEVICE_CODENAME}.mk"
        fi
    fi

    success "Device tree configured in ${target_dir}."
}

# Setup Ccache for Fast Rebuilds
setup_ccache() {
    export USE_CCACHE=1
    export CCACHE_EXEC="/usr/bin/ccache"
    export CCACHE_DIR="${HOME}/.ccache_orangefox"
    mkdir -p "${CCACHE_DIR}"
    ccache -M 25G 2>/dev/null || true
    info "Ccache configured at ${CCACHE_DIR} (Max size: 25G)."
}

# Configure OrangeFox Environment Variables
configure_build_flags() {
    info "Configuring OrangeFox build environment variables..."

    export ALLOW_MISSING_DEPENDENCIES=true
    export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
    export LC_ALL="C"

    # OrangeFox Build Customization
    export OF_MAINTAINER="${DEFAULT_MAINTAINER}"
    export FOX_VERSION="R12.1"
    export FOX_BUILD_TYPE="Unofficial"
    export TARGET_DEVICE="${DEVICE_CODENAME}"
    
    # Display dimensions (Redmi Note 12 Pro 4G: 1080x2400)
    export OF_SCREEN_H=2400
    export OF_STATUS_H=95
    export OF_STATUS_INDENT_LEFT=48
    export OF_STATUS_INDENT_RIGHT=48
    export OF_CLOCK_POS=1

    # Security & Decryption
    export TW_INCLUDE_CRYPTO=true
    export TW_INCLUDE_CRYPTO_FBE=true
    export TW_INCLUDE_FBE_METADATA_DECRYPT=true
    export BOARD_USES_METADATA_PARTITION=true

    # OrangeFox UI & Addons
    export OF_USE_GREEN_LED=0
    export FOX_ENABLE_APP_MANAGER=1
    export FOX_USE_SPECIFIC_MAGISK_ZIP=1
}

# Compile OrangeFox Recovery
compile_recovery() {
    info "Initializing Android build environment..."
    cd "${WORKSPACE_DIR}"

    # shellcheck source=/dev/null
    source build/envsetup.sh

    info "Selecting lunch target: ${LUNCH_TARGET}..."
    if ! lunch "${LUNCH_TARGET}"; then
        warn "Target '${LUNCH_TARGET}' failed. Checking alternative lunch combos..."
        if lunch "fox_${DEVICE_CODENAME}-eng" 2>/dev/null; then
            LUNCH_TARGET="fox_${DEVICE_CODENAME}-eng"
        elif lunch "twrp_sweet-eng" 2>/dev/null; then
            LUNCH_TARGET="twrp_sweet-eng"
        else
            die "Failed to lunch target for ${DEVICE_CODENAME}. Check your device tree AndroidProducts.mk."
        fi
    fi

    if [[ "$RUN_CLEAN" == "true" ]]; then
        info "Cleaning previous build output..."
        mka clean
    fi

    local start_time
    start_time=$(date +%s)

    info "Starting OrangeFox compilation for ${DEVICE_CODENAME} (target: ${BUILD_TARGET}, threads: ${JOBS})..."
    mka -j"${JOBS}" "${BUILD_TARGET}"

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    success "Compilation finished successfully in ${minutes}m ${seconds}s!"
}

# Verify Build Output and Optionally Upload
package_and_export() {
    info "Verifying output artifacts..."
    cd "${WORKSPACE_DIR}"

    local out_dir="out/target/product/${DEVICE_CODENAME}"
    [[ -d "$out_dir" ]] || out_dir="out/target/product/sweet"

    if [[ ! -d "$out_dir" ]]; then
        die "Output directory not found. Build may have failed to produce output."
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

    # Automatic Upload via Pixeldrain
    if [[ "$AUTO_UPLOAD" == "true" && -n "$fox_zip" && -f "$fox_zip" ]]; then
        local uploader_script
        uploader_script="$(dirname "$(readlink -f "$0")")/upload_to_pixeldrain.sh"
        if [[ -x "$uploader_script" ]]; then
            info "Uploading OrangeFox zip to Pixeldrain..."
            "$uploader_script" "$fox_zip" || warn "Pixeldrain upload failed, but recovery build is intact."
        elif command -v curl >/dev/null 2>&1; then
            info "Uploading via inline Pixeldrain API..."
            local fname
            fname=$(basename "$fox_zip")
            local resp
            resp=$(curl -s -L --upload-file "$fox_zip" "https://pixeldrain.com/api/file/${fname}" 2>/dev/null || true)
            local file_id
            file_id=$(echo "$resp" | grep -oP '"id":\s*"\K[^"]+' || true)
            if [[ -n "$file_id" ]]; then
                success "Uploaded to Pixeldrain: https://pixeldrain.com/u/${file_id}"
            fi
        fi
    fi
}

# Main Execution Flow
main() {
    echo "============================================================"
    echo "  OrangeFox Recovery Project (OFRP) Builder for ${DEVICE_CODENAME} "
    echo "  Version: ${SCRIPT_VERSION} | Base: fox_${FOX_BRANCH}              "
    echo "============================================================"
    echo ""

    check_environment

    if [[ "$INSTALL_DEPS" == "true" ]]; then
        install_dependencies
    fi

    sync_orangefox
    setup_device_tree
    setup_ccache
    configure_build_flags
    compile_recovery
    package_and_export

    success "All tasks completed successfully!"
}

main "$@"
