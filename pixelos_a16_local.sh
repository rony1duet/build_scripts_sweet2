#!/usr/bin/env bash
#
# PixelOS A16 (QPR2) Local Build Script for sweet2 (Redmi Note 12 Pro 4G)
# Works on any Linux machine (Ubuntu / Debian / WSL2 / Docker)
# Includes automatic dependency installation, swap setup, and Pixeldrain upload
# Maintainer: rony1duet
#

set -eo pipefail

readonly SCRIPT_VERSION="1.3.0"
readonly ROM_NAME="PixelOS"
readonly ROM_MANIFEST_URL="https://github.com/PixelOS-AOSP/android_manifest.git"
readonly ROM_MANIFEST_BRANCH="sixteen-qpr2"
readonly DEVICE_MANIFEST_URL="https://github.com/rony1duet/manifest_sweet2.git"
readonly DEVICE_BRANCH="PixelOS-16-QPR2"
readonly DEVICE_CODENAME="sweet2"

WORKSPACE_DIR="$(pwd)"
AUTO_UPLOAD=true
INSTALL_DEPS=false

for arg in "$@"; do
    case "$arg" in
        --install-deps|-i)
            INSTALL_DEPS=true
            ;;
        --no-upload)
            AUTO_UPLOAD=false
            ;;
        *)
            if [[ -d "$arg" ]]; then
                WORKSPACE_DIR="$arg"
            fi
            ;;
    esac
done

info() { printf "\033[0;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[x]\033[0m %s\n" "$*" >&2; exit 1; }

install_dependencies() {
    info "Installing system build packages and toolchain dependencies..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y || true

        # Modern package list compatible with Ubuntu 20.04, 22.04, 24.04, 26.04, and newer
        local pkgs=(
            bc bison build-essential ccache curl flex g++-multilib gcc-multilib git
            git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev
            libncurses-dev libssl-dev libxml2-utils lz4 liblz4-dev lzop pngcrush rsync
            schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3
            openjdk-17-jdk file pkg-config
        )

        local to_install=()
        for pkg in "${pkgs[@]}"; do
            if apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate: [^(\n]'; then
                to_install+=("$pkg")
            fi
        done

        if [[ ${#to_install[@]} -gt 0 ]]; then
            sudo apt-get install -y "${to_install[@]}" || {
                warn "Batch install encountered issues; attempting individual package installs..."
                for p in "${to_install[@]}"; do
                    sudo apt-get install -y "$p" 2>/dev/null || true
                done
            }
        fi
    fi

    if ! command -v repo >/dev/null 2>&1; then
        info "Installing Google repo tool..."
        if sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo 2>/dev/null; then
            sudo chmod a+rx /usr/local/bin/repo
        else
            mkdir -p "$HOME/.local/bin"
            curl -s https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/.local/bin/repo"
            chmod a+rx "$HOME/.local/bin/repo"
        fi
    fi

    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
    git lfs install 2>/dev/null || true
}

check_requirements() {
    info "Checking local system requirements..."
    cd "$WORKSPACE_DIR" || die "Directory $WORKSPACE_DIR not found"

    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

    if [[ "$INSTALL_DEPS" == "true" ]] || ! command -v repo >/dev/null 2>&1 || ! command -v git-lfs >/dev/null 2>&1; then
        install_dependencies
    fi

    local missing_tools=()
    for tool in git curl repo python3; do
        command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing_tools[*]}. Run with --install-deps to install them automatically."
    fi

    local avail_gb
    avail_gb=$(df -BG "$WORKSPACE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9')
    if [[ -n "$avail_gb" && "$avail_gb" -lt 150 ]]; then
        warn "Free disk space is only ${avail_gb}GB. Android 16 builds typically require 200GB-300GB."
    elif [[ -n "$avail_gb" ]]; then
        info "Available disk space: ${avail_gb}GB"
    fi

    local host_ram_gb=16 host_swap_gb=0
    [[ -f /proc/meminfo ]] && host_ram_gb=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)
    [[ -f /proc/meminfo ]] && host_swap_gb=$(awk '/SwapTotal/{print int($2/1024/1024)}' /proc/meminfo)

    # Check for container cgroup memory limits (cgroups v1 and v2)
    local cgroup_limit_bytes=0
    if [[ -f /sys/fs/cgroup/memory.max ]]; then
        local max_str
        max_str=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        if [[ "$max_str" =~ ^[0-9]+$ ]]; then
            cgroup_limit_bytes="$max_str"
        fi
    elif [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        local max_str
        max_str=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
        if [[ "$max_str" =~ ^[0-9]+$ && "$max_str" -lt 9000000000000000000 ]]; then
            cgroup_limit_bytes="$max_str"
        fi
    fi

    local effective_ram_gb="$host_ram_gb"
    if [[ "$cgroup_limit_bytes" -gt 0 ]]; then
        local cg_gb=$(( cgroup_limit_bytes / 1024 / 1024 / 1024 ))
        if [[ "$cg_gb" -gt 0 && "$cg_gb" -lt "$host_ram_gb" ]]; then
            effective_ram_gb="$cg_gb"
            info "Host RAM: ${host_ram_gb}GB, Container CGroup Limit: ${effective_ram_gb}GB (Swap: ${host_swap_gb}GB)"
        else
            info "System RAM: ${host_ram_gb}GB (Unconstrained Container / Host, Swap: ${host_swap_gb}GB)"
        fi
    else
        info "System RAM: ${host_ram_gb}GB (Swap: ${host_swap_gb}GB)"
    fi

    local is_container=false
    if [[ -f /.dockerenv ]] || grep -qa 'container=docker' /proc/1/environ 2>/dev/null; then
        is_container=true
    fi

    if [[ "$effective_ram_gb" -lt 24 && "$host_swap_gb" -lt 8 ]]; then
        warn "Effective RAM is under 24GB with minimal swap (${host_swap_gb}GB)."
        if [[ "$is_container" == "true" ]]; then
            info "Running inside a container; allocate additional RAM/swap on host if build is OOM killed."
        elif [[ "$INSTALL_DEPS" == "true" ]] && ! swapon --show 2>/dev/null | grep -q "/swapfile"; then
            info "Auto-provisioning 16GB /swapfile..."
            sudo fallocate -l 16G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=16384 status=progress 2>/dev/null || true
            sudo chmod 600 /swapfile 2>/dev/null || true
            sudo mkswap /swapfile 2>/dev/null || true
            sudo swapon /swapfile 2>/dev/null || true
        else
            warn "To add a 16GB swap file, run: sudo fallocate -l 16G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
        fi
    fi
}

setup_manifests() {
    info "Setting up manifests (${ROM_MANIFEST_BRANCH} / ${DEVICE_BRANCH})..."

    if [[ ! -d ".repo" ]]; then
        repo init \
            -u "${ROM_MANIFEST_URL}" \
            -b "${ROM_MANIFEST_BRANCH}" \
            --git-lfs \
            --depth=1
    fi

    if [[ ! -d ".repo/local_manifests" ]]; then
        git clone "${DEVICE_MANIFEST_URL}" .repo/local_manifests -b "${DEVICE_BRANCH}"
    else
        git -C .repo/local_manifests fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
        git -C .repo/local_manifests reset --hard "origin/${DEVICE_BRANCH}" 2>/dev/null || true
    fi
}

sync_sources() {
    info "Syncing sources..."
    local jobs
    jobs=$(nproc --all 2>/dev/null || echo 4)
    # Cap parallel network sync jobs to 4 to prevent Google Git HTTP 429 rate limiting
    if [[ "$jobs" -gt 4 ]]; then
        jobs=4
    fi

    local attempt=1
    local max_attempts=5
    until repo sync -c -j"${jobs}" --force-sync --no-clone-bundle --no-tags --optimized-fetch --retry-fetches=5; do
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            warn "Rate limit encountered. Falling back to single-threaded sync (-j1)..."
            repo sync -c -j1 --force-sync --no-clone-bundle --no-tags --optimized-fetch || die "Source sync failed"
            break
        fi
        warn "Network sync throttled or interrupted (attempt ${attempt}/${max_attempts}). Waiting 15s before retry..."
        sleep 15
        jobs=2
        attempt=$((attempt + 1))
    done
}

sync_device_repos() {
    info "Updating device repositories..."

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
            git -C "$repo" fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
            git -C "$repo" reset --hard "origin/${DEVICE_BRANCH}" 2>/dev/null || true
            echo "  -> $repo: $(git -C "$repo" log -1 --oneline 2>/dev/null)"
        fi
    done
}

setup_toolchain() {
    info "Validating toolchains and Git LFS..."

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

    # Clear stale or aborted soong bootstrap ninja state
    rm -rf out/soong/.bootstrap out/soong/build.*.ninja out/soong/.temp 2>/dev/null || true
}

setup_environment() {
    info "Exporting local build environment..."

    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
    export BUILD_USERNAME="${USER:-rony1duet}"
    export BUILD_HOSTNAME="${HOSTNAME:-local}"
    export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
    export DONT_INSTALL_DEXPREOPT_TESTS=true
    export SKIP_BOOT_JARS_CHECK=true
    export WITHOUT_CHECK_API=true

    # Use standard battle-tested Ninja instead of Siso to eliminate memory stall watcher kills
    export SOONG_NINJA=ninja

    # Raise open files, process, and stack size limits
    ulimit -n 65535 2>/dev/null || true
    ulimit -s 16384 2>/dev/null || true
    ulimit -u 65535 2>/dev/null || true

    # Disable systemd-oomd if running, as it kills soong_build during high I/O memory stalls
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop systemd-oomd 2>/dev/null || true
        sudo systemctl disable --now systemd-oomd 2>/dev/null || true
    fi

    # Enable ccache
    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache || echo '/usr/bin/ccache')"
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
    if command -v ccache >/dev/null 2>&1; then
        ccache -M 50G >/dev/null 2>&1 || true
    fi

    # Dynamically scale Go runtime and parallel workers based on effective RAM
    local host_ram_gb=16
    [[ -f /proc/meminfo ]] && host_ram_gb=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)

    local cgroup_limit_bytes=0
    if [[ -f /sys/fs/cgroup/memory.max ]]; then
        local max_str
        max_str=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        if [[ "$max_str" =~ ^[0-9]+$ ]]; then
            cgroup_limit_bytes="$max_str"
        fi
    elif [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        local max_str
        max_str=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
        if [[ "$max_str" =~ ^[0-9]+$ && "$max_str" -lt 9000000000000000000 ]]; then
            cgroup_limit_bytes="$max_str"
        fi
    fi

    local effective_ram_gb="$host_ram_gb"
    if [[ "$cgroup_limit_bytes" -gt 0 ]]; then
        local cg_gb=$(( cgroup_limit_bytes / 1024 / 1024 / 1024 ))
        if [[ "$cg_gb" -gt 0 && "$cg_gb" -lt "$host_ram_gb" ]]; then
            effective_ram_gb="$cg_gb"
        fi
    fi

    info "Allocating Go build parameters for ${effective_ram_gb}GB RAM system..."

    if [[ "$effective_ram_gb" -ge 128 ]]; then
        # High-spec workstation/server (755GB EPYC)
        export GOMEMLIMIT="128GiB"
        export GOGC=100
        export SOONG_GOGC=100
        export GOMAXPROCS=32
    elif [[ "$effective_ram_gb" -ge 64 ]]; then
        export GOMEMLIMIT="48GiB"
        export GOGC=100
        export SOONG_GOGC=100
        export GOMAXPROCS=24
    elif [[ "$effective_ram_gb" -ge 32 ]]; then
        export GOMEMLIMIT="24GiB"
        export GOGC=80
        export SOONG_GOGC=80
        export GOMAXPROCS=16
    elif [[ "$effective_ram_gb" -ge 16 ]]; then
        export GOMEMLIMIT="12GiB"
        export GOGC=50
        export SOONG_GOGC=50
        export GOMAXPROCS=8
    else
        export GOMEMLIMIT="8GiB"
        export GOGC=30
        export SOONG_GOGC=30
        export GOMAXPROCS=4
    fi

    # DO NOT set MALLOC_ARENA_MAX=2 on high-core systems to prevent thread lock contention
    unset MALLOC_ARENA_MAX
    export SOONG_INCREMENTAL_ANALYSIS=false
}

setup_gcam() {
    info "Preparing GCam prebuilt..."
    local fetcher="vendor/android_prebuilts_sweet2/gcam/fetch_gcam_prebuilt.sh"
    if [[ -f "$fetcher" ]]; then
        bash "$fetcher" vendor/GCam_sweet2/system/product/app/GoogleCameraEng
    fi

    [[ -f "vendor/GCam_sweet2/system/product/app/GoogleCameraEng/GoogleCameraEng.apk" ]] || die "GoogleCameraEng.apk not found"
}

build_target() {
    info "Starting build for ${DEVICE_CODENAME}..."

    set +e
    # shellcheck source=/dev/null
    source build/envsetup.sh
    breakfast "${DEVICE_CODENAME}"
    local rc=$?
    set -e
    [[ $rc -eq 0 ]] || die "breakfast ${DEVICE_CODENAME} failed"

    info "Compiling m pixelos..."
    m pixelos || die "Build failed! Check out/error.log"

    info "Build completed successfully!"
    local out_zip
    out_zip=$(ls -t out/target/product/${DEVICE_CODENAME}/PixelOS_${DEVICE_CODENAME}-*.zip 2>/dev/null | head -n 1 || true)
    if [[ -n "$out_zip" && -f "$out_zip" ]]; then
        echo "=========================================================="
        echo "LOCAL ARTIFACT: $out_zip"
        echo "SIZE:           $(du -h "$out_zip" | cut -f1)"
        echo "MD5:            $(md5sum "$out_zip" | awk '{print $1}')"
        echo "=========================================================="
    fi
}

upload_artifacts() {
    if [[ "$AUTO_UPLOAD" == "true" ]]; then
        info "Uploading build artifact to Pixeldrain..."
        if [[ -f "upload_to_pixeldrain.sh" ]]; then
            bash upload_to_pixeldrain.sh
        else
            curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh" | bash
        fi
    else
        info "Auto-upload skipped (--no-upload)."
    fi
}

main() {
    check_requirements
    setup_manifests
    sync_sources
    sync_device_repos
    setup_toolchain
    sanitize_configs
    setup_environment
    setup_gcam
    build_target
    upload_artifacts
}

main "$@"
