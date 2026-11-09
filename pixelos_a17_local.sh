#!/usr/bin/env bash
#
# PixelOS A17 Local Build Script for sweet2 (Redmi Note 12 Pro)
# Works on any Linux machine (Ubuntu / Debian / WSL2 / Docker)
# Includes automatic dependency installation, swap setup, and Pixeldrain upload
# Maintainer: rony1duet
#

set -eo pipefail

readonly SCRIPT_VERSION="1.3.5"
readonly ROM_NAME="PixelOS"
readonly ROM_MANIFEST_BRANCH="seventeen"
readonly DEVICE_BRANCH="PixelOS-17-base"
readonly DEVICE_CODENAME="sweet2"

WORKSPACE_DIR="$(pwd)"
AUTO_UPLOAD=true
INSTALL_DEPS=false
TARGET_RELEASE="${TARGET_RELEASE:-trunk_staging}"

for arg in "$@"; do
    case "$arg" in
        --install-deps|-i)
            INSTALL_DEPS=true
            ;;
        --no-upload)
            AUTO_UPLOAD=false
            ;;
        --release=*|-r=*)
            TARGET_RELEASE="${arg#*=}"
            ;;
        *)
            if [[ -d "$arg" ]]; then
                WORKSPACE_DIR="$arg"
            fi
            ;;
    esac
done

readonly FAILURE_LOG="${WORKSPACE_DIR}/build_failure.log"
BUILD_SUCCESS=false
LAST_ERROR_MSG=""
COLLECTED_FAILURE_LOGS=false

info() { printf "\033[0;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
die()  {
    local msg="$*"
    LAST_ERROR_MSG="$msg"
    printf "\033[0;31m[x]\033[0m %s\n" "$msg" >&2
    collect_failure_logs 1 "$LINENO" "$msg"
    exit 1
}

collect_failure_logs() {
    local rc="${1:-1}"
    local line="${2:-$LINENO}"
    local cmd="${3:-unknown}"

    if [[ "$COLLECTED_FAILURE_LOGS" == "true" ]]; then
        return 0
    fi
    COLLECTED_FAILURE_LOGS=true

    # Temporarily disable set -e and ERR trap while writing diagnostic log
    set +e
    trap - ERR

    printf "\n\033[0;31m[x]\033[0m Build failed (exit code %s). Collecting all diagnostic logs into \033[1m%s\033[0m...\n" "$rc" "$FAILURE_LOG"

    {
        echo "================================================================================"
        echo "                      PIXELOS BUILD FAILURE DIAGNOSTIC REPORT                   "
        echo "================================================================================"
        echo "Timestamp:         $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Script Version:    ${SCRIPT_VERSION}"
        echo "Target ROM:        ${ROM_NAME} (${ROM_MANIFEST_BRANCH})"
        echo "Target Device:     ${DEVICE_CODENAME} (${DEVICE_BRANCH})"
        echo "Exit Code:         ${rc}"
        echo "Failed Line:       ${line}"
        echo "Failed Command:    ${cmd}"
        [[ -n "$LAST_ERROR_MSG" ]] && echo "Error Message:     ${LAST_ERROR_MSG}"
        echo "Hostname:          $(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo 'unknown')"
        echo "User:              $(whoami 2>/dev/null || id -un 2>/dev/null || echo 'unknown')"
        echo "Working Directory: ${WORKSPACE_DIR}"
        echo "================================================================================"
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "1. SYSTEM & RESOURCE DIAGNOSTICS"
        echo "--------------------------------------------------------------------------------"
        echo "--> System Uptime and Load Average:"
        uptime 2>&1 || true
        echo ""
        echo "--> Memory and Swap Allocation (free -h):"
        free -h 2>&1 || true
        echo ""
        echo "--> Workspace Disk Usage (df -h):"
        df -h "${WORKSPACE_DIR}" 2>&1 || true
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "2. CGROUP MEMORY CONTROLLER & CONTAINER STATS"
        echo "--------------------------------------------------------------------------------"
        if [[ -f /sys/fs/cgroup/memory.events ]]; then
            echo "--> CGroup v2 Events (/sys/fs/cgroup/memory.events):"
            cat /sys/fs/cgroup/memory.events 2>&1 || true
            echo "--> CGroup v2 Current Usage (/sys/fs/cgroup/memory.current):"
            cat /sys/fs/cgroup/memory.current 2>&1 || true
            echo "--> CGroup v2 Max Limit (/sys/fs/cgroup/memory.max):"
            cat /sys/fs/cgroup/memory.max 2>&1 || true
        fi
        if [[ -f /sys/fs/cgroup/memory/memory.oom_control ]]; then
            echo "--> CGroup v1 OOM Control (/sys/fs/cgroup/memory/memory.oom_control):"
            cat /sys/fs/cgroup/memory/memory.oom_control 2>&1 || true
            echo "--> CGroup v1 Memory Limit (/sys/fs/cgroup/memory/memory.limit_in_bytes):"
            cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>&1 || true
            echo "--> CGroup v1 Memory Usage (/sys/fs/cgroup/memory/memory.usage_in_bytes):"
            cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>&1 || true
        fi
        echo "--> Process CGroup Membership (/proc/self/cgroup):"
        cat /proc/self/cgroup 2>&1 || true
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "3. KERNEL DMESG OOM & KILLED EVENTS"
        echo "--------------------------------------------------------------------------------"
        if dmesg -T >/dev/null 2>&1; then
            dmesg -T | grep -E -i "oom|killed|soong|out of memory" | tail -n 30 || echo "No OOM/killed messages found in dmesg."
        else
            echo "Kernel buffer read not permitted (unprivileged container environment)."
        fi
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "4. ANDROID BUILD ERROR LOG (out/error.log)"
        echo "--------------------------------------------------------------------------------"
        if [[ -f "${WORKSPACE_DIR}/out/error.log" ]]; then
            cat "${WORKSPACE_DIR}/out/error.log"
        else
            echo "out/error.log was not generated."
        fi
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "5. SOONG BUILD LOG (out/soong.log - Last 150 Lines)"
        echo "--------------------------------------------------------------------------------"
        if [[ -f "${WORKSPACE_DIR}/out/soong.log" ]]; then
            tail -n 150 "${WORKSPACE_DIR}/out/soong.log"
        else
            echo "out/soong.log was not generated."
        fi
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "6. SISO / NINJA BUILD LOGS"
        echo "--------------------------------------------------------------------------------"
        local found_ninja=false
        for ninja_file in "${WORKSPACE_DIR}"/out/soong/siso* "${WORKSPACE_DIR}"/out/siso* "${WORKSPACE_DIR}"/out/.ninja_log; do
            if [[ -f "$ninja_file" ]]; then
                found_ninja=true
                echo "--> File: ${ninja_file} (Last 50 lines):"
                tail -n 50 "$ninja_file" 2>&1 || true
                echo ""
            fi
        done
        if [[ "$found_ninja" == "false" ]]; then
            echo "No siso or ninja failure logs found."
        fi
        echo ""

        echo "--------------------------------------------------------------------------------"
        echo "7. TERMINAL COMPILATION STREAM (Last 200 Lines)"
        echo "--------------------------------------------------------------------------------"
        if [[ -f "${WORKSPACE_DIR}/out/.last_build.log" ]]; then
            tail -n 200 "${WORKSPACE_DIR}/out/.last_build.log"
        else
            echo "Terminal compilation log out/.last_build.log not found."
        fi
        echo ""
        echo "================================================================================"
        echo "                          END OF DIAGNOSTIC REPORT                              "
        echo "================================================================================"
    } > "$FAILURE_LOG"

    # Clear intermediate / fragmented log files and temp build folders after failure
    rm -f "${WORKSPACE_DIR}/out/error.log" \
          "${WORKSPACE_DIR}/out/soong.log" \
          "${WORKSPACE_DIR}/out/.last_build.log" \
          "${WORKSPACE_DIR}"/out/*.log \
          "${WORKSPACE_DIR}"/out/soong/*.log \
          "${WORKSPACE_DIR}"/out/soong/siso* 2>/dev/null || true
    rm -rf "${WORKSPACE_DIR}/out/soong/.bootstrap" \
           "${WORKSPACE_DIR}/out/soong/build."*".ninja" \
           "${WORKSPACE_DIR}/out/soong/.temp" 2>/dev/null || true

    printf "\033[0;32m[✓]\033[0m Consolidated failure log saved to: \033[1m%s\033[0m\n" "$FAILURE_LOG"
    printf "\033[0;34m==>\033[0m Intermediate log files and temp build folders in out/ have been cleaned.\n"

    # Display concise failure summary directly in console
    if [[ -f "$FAILURE_LOG" ]]; then
        printf "\n\033[1;33m--- Consolidated Diagnostic Summary ---\033[0m\n"
        tail -n 25 "$FAILURE_LOG"
        printf "\033[1;33m---------------------------------------\033[0m\n\n"
    fi
}

record_failure() {
    local rc="$1"
    local line="$2"
    local cmd="$3"
    if [[ "$BUILD_SUCCESS" != "true" ]]; then
        LAST_ERROR_MSG="Command '${cmd}' failed on line ${line} with exit code ${rc}"
        collect_failure_logs "$rc" "$line" "$cmd"
        exit "$rc"
    fi
}

trap 'record_failure $? $LINENO "$BASH_COMMAND"' ERR

install_dependencies() {
    info "Installing system build packages and toolchain dependencies..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y || true

        # Modern package list compatible with Ubuntu 20.04, 22.04, 24.04, 24.10, and newer
        local pkgs=(
            bc bison build-essential ccache curl flex g++-multilib gcc-multilib git
            git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev
            libncurses-dev libssl-dev libxml2-utils lz4 liblz4-dev lzop pngcrush rsync
            schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3
            openjdk-17-jdk file pkg-config util-linux
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

    # Clean any stale failure log and previous build capture stream
    rm -f "${FAILURE_LOG}" "${WORKSPACE_DIR}/out/.last_build.log" 2>/dev/null || true

    # Deactivate Python virtual environment if active to avoid build tool conflicts
    if [[ -n "$VIRTUAL_ENV" ]] && command -v deactivate >/dev/null 2>&1; then
        deactivate 2>/dev/null || true
    fi

    # Ensure Git global identity and safe repository ownership
    if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
        git config --global user.name "rony1duet"
    fi
    if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
        git config --global user.email "rony.hossen.duet@gmail.com"
    fi
    git config --global --add safe.directory "*" 2>/dev/null || true

    export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

    if [[ "$INSTALL_DEPS" == "true" ]] || ! command -v repo >/dev/null 2>&1 || ! command -v git-lfs >/dev/null 2>&1; then
        install_dependencies
    fi

    # Ensure python symlink exists for legacy build scripts
    if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        sudo ln -sf "$(command -v python3)" /usr/local/bin/python 2>/dev/null || true
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
    if [[ -n "$avail_gb" && "$avail_gb" -lt 200 ]]; then
        warn "Free disk space is only ${avail_gb}GB. Android 17 builds typically require 250GB-350GB."
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
            -u https://github.com/PixelOS-AOSP/android_manifest.git \
            -b "${ROM_MANIFEST_BRANCH}" \
            --git-lfs \
            --depth=1
    fi

    if [[ ! -d ".repo/local_manifests" ]]; then
        git clone https://github.com/rony1duet/manifest_sweet2.git .repo/local_manifests -b "${DEVICE_BRANCH}"
    else
        git -C .repo/local_manifests fetch origin "${DEVICE_BRANCH}" --depth=1 2>/dev/null || true
        git -C .repo/local_manifests reset --hard "origin/${DEVICE_BRANCH}" 2>/dev/null || true
    fi

    # If build/soong was previously tracking a custom fork, reset it so repo sync cleanly restores official PixelOS build/soong
    if [[ -d "build/soong/.git" ]] && git -C build/soong remote -v 2>/dev/null | grep -q "rony1duet"; then
        info "Restoring official PixelOS-AOSP/android_build_soong..."
        rm -rf build/soong .repo/projects/build/soong.git .repo/project-objects/*build_soong* 2>/dev/null || true
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
    info "Validating build/soong, toolchains, and Git LFS..."

    if [[ ! -f "build/soong/soong_ui.bash" ]]; then
        info "Syncing official build/soong..."
        repo sync -c -j4 --force-sync build/soong
    fi
    [[ -f "build/soong/soong_ui.bash" ]] || die "Missing build/soong/soong_ui.bash"

    # Ensure build/soong working tree is clean stock
    if [[ -d "build/soong/.git" ]]; then
        git -C build/soong checkout HEAD -- . 2>/dev/null || true
    fi

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

    # Ensure build/soong passes container memory limits to soong_build under env -i
    if [[ -f "build/soong/ui/build/soong.go" ]]; then
        python3 -c '
path = "build/soong/ui/build/soong.go"
try:
    with open(path, "r") as f:
        content = f.read()
    target = "invocationEnv := make(map[string]string)"
    if "GOMEMLIMIT" not in content and target in content:
        injection = target + "\n\tfor _, envVar := range []string{\"GOMEMLIMIT\", \"GOGC\", \"GODEBUG\", \"GOMAXPROCS\", \"TARGET_RELEASE\"} {\n\t\tif val := os.Getenv(envVar); val != \"\" {\n\t\t\tinvocationEnv[envVar] = val\n\t\t}\n\t}"
        content = content.replace(target, injection, 1)
        with open(path, "w") as f:
            f.write(content)
        print("Configured build/soong container memory forwarding")
except Exception as e:
    pass
' 2>/dev/null || true
    fi

    # Fix GoogleCameraEng check_prebuilt_presigned_apk failure (contains compressed dex files and is privileged)
    if [[ -f "vendor/GCam_sweet2/Android.bp" ]] && ! grep -q "skip_preprocessed_apk_checks" vendor/GCam_sweet2/Android.bp; then
        sed -i '/preprocessed: true,/a \    skip_preprocessed_apk_checks: true,' vendor/GCam_sweet2/Android.bp
    fi
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
    export DONT_UNCOMPRESS_PRIV_APPS_DEXS=true
    export TARGET_RELEASE="${TARGET_RELEASE:-trunk_staging}"

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
    local host_ram_gb=16 host_swap_gb=0
    [[ -f /proc/meminfo ]] && host_ram_gb=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)
    [[ -f /proc/meminfo ]] && host_swap_gb=$(awk '/SwapTotal/{print int($2/1024/1024)}' /proc/meminfo)

    local is_container=false
    if [[ -f /.dockerenv ]] || grep -qa 'container=docker' /proc/1/environ 2>/dev/null; then
        is_container=true
    fi

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

    info "Allocating build parameters for ${effective_ram_gb}GB RAM system..."

    # Clean up dead unmounted swapfile to reclaim disk space
    if [[ -f /swapfile ]] && ! swapon --show 2>/dev/null | grep -q "/swapfile"; then
        sudo rm -f /swapfile 2>/dev/null || true
    fi

    if [[ "$is_container" == "true" || "$host_swap_gb" -eq 0 ]]; then
        info "Constrained container / zero-swap environment detected (Container: ${is_container}, Swap: ${host_swap_gb}GB)."
        info "Allocating safe memory parameters to prevent OOM killer..."
        # Do NOT set GOMEMLIMIT in zero-swap containers: soong_build needs ~5-6 GB live heap
        # and an artificial ceiling below that causes GC thrashing which triggers the OOM killer.
        # Instead, reduce goroutine parallelism to keep peak RSS below the natural ceiling.
        unset GOMEMLIMIT
        export GOGC=50
        export SOONG_GOGC=50
        export GOMAXPROCS=4
        export NINJA_HIGHMEM_NUM_JOBS=1
    elif [[ "$effective_ram_gb" -ge 64 ]]; then
        # Dedicated large server / VM (e.g. 755GB EPYC or 62.7GB Ryzen) with active swap
        export GOMEMLIMIT="24GiB"
        export GOGC=80
        export SOONG_GOGC=80
        export GOMAXPROCS=16
        export NINJA_HIGHMEM_NUM_JOBS=2
    elif [[ "$effective_ram_gb" -ge 32 ]]; then
        export GOMEMLIMIT="16GiB"
        export GOGC=60
        export SOONG_GOGC=60
        export GOMAXPROCS=8
        export NINJA_HIGHMEM_NUM_JOBS=1
    elif [[ "$effective_ram_gb" -ge 16 ]]; then
        export GOMEMLIMIT="10GiB"
        export GOGC=40
        export SOONG_GOGC=40
        export GOMAXPROCS=4
        export NINJA_HIGHMEM_NUM_JOBS=1
    else
        export GOMEMLIMIT="6GiB"
        export GOGC=30
        export SOONG_GOGC=30
        export GOMAXPROCS=2
        export NINJA_HIGHMEM_NUM_JOBS=1
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

    # Invalidate stale GCam prebuilt check stamps so Soong re-evaluates check_prebuilt_presigned_apk
    rm -rf out/soong/.intermediates/vendor/GCam_sweet2 2>/dev/null || true

    # Ensure GCam Android.bp skips preprocessed compressed dex validation for presigned APK
    if [[ -f "vendor/GCam_sweet2/Android.bp" ]] && ! grep -q "skip_preprocessed_apk_checks" vendor/GCam_sweet2/Android.bp; then
        sed -i '/preprocessed: true,/a \    skip_preprocessed_apk_checks: true,' vendor/GCam_sweet2/Android.bp
    fi
}

build_target() {
    info "Starting build for ${DEVICE_CODENAME}..."

    mkdir -p "${WORKSPACE_DIR}/out"

    export TARGET_RELEASE="${TARGET_RELEASE:-trunk_staging}"
    export TARGET_PRODUCT="custom_${DEVICE_CODENAME}"
    export TARGET_BUILD_VARIANT="userdebug"

    set +e
    # shellcheck source=/dev/null
    source build/envsetup.sh

    info "Configuring build target (${TARGET_PRODUCT}-${TARGET_RELEASE}-${TARGET_BUILD_VARIANT})..."
    lunch "${TARGET_PRODUCT}-${TARGET_RELEASE}-${TARGET_BUILD_VARIANT}" 2>&1 | tee -a "${WORKSPACE_DIR}/out/.last_build.log"
    local rc=${PIPESTATUS[0]}
    if [[ $rc -ne 0 ]]; then
        warn "Direct 3-part lunch encountered an issue; falling back to breakfast ${DEVICE_CODENAME}..."
        breakfast "${DEVICE_CODENAME}" 2>&1 | tee -a "${WORKSPACE_DIR}/out/.last_build.log"
        rc=${PIPESTATUS[0]}
    fi
    set -e
    [[ $rc -eq 0 ]] || die "Target configuration failed for ${DEVICE_CODENAME}"

    # Ensure TARGET_RELEASE is explicitly exported for Soong and Kati dumpvars
    export TARGET_RELEASE="${TARGET_RELEASE:-trunk_staging}"

    # Determine safe parallelism for compilation
    local total_cores
    total_cores=$(nproc --all 2>/dev/null || echo 8)
    local jobs="$total_cores"

    local host_swap_gb=0
    [[ -f /proc/meminfo ]] && host_swap_gb=$(awk '/SwapTotal/{print int($2/1024/1024)}' /proc/meminfo)
    local is_container=false
    if [[ -f /.dockerenv ]] || grep -qa 'container=docker' /proc/1/environ 2>/dev/null; then
        is_container=true
    fi

    if [[ "$is_container" == "true" || "$host_swap_gb" -eq 0 ]]; then
        # In containers or zero-swap systems, cap parallel build jobs to 8 to avoid OOM kills
        if [[ "$jobs" -gt 8 ]]; then
            jobs=8
        fi
    elif [[ "$jobs" -gt 16 ]]; then
        # Default cap to 16 for build stability on high-core server CPUs
        jobs=16
    fi

    info "Compiling m -j${jobs} pixelos..."
    set +e
    if command -v taskset >/dev/null 2>&1 && [[ "$total_cores" -gt "$jobs" ]]; then
        taskset -c 0-$((jobs - 1)) m -j"${jobs}" pixelos 2>&1 | tee -a "${WORKSPACE_DIR}/out/.last_build.log"
    else
        m -j"${jobs}" pixelos 2>&1 | tee -a "${WORKSPACE_DIR}/out/.last_build.log"
    fi
    local build_rc=${PIPESTATUS[0]}
    set -e
    [[ $build_rc -eq 0 ]] || die "Build failed! Check ${FAILURE_LOG}"

    BUILD_SUCCESS=true
    rm -f "${WORKSPACE_DIR}/out/.last_build.log" "${FAILURE_LOG}" 2>/dev/null || true

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
            bash upload_to_pixeldrain.sh || warn "Artifact upload failed, but build succeeded."
        else
            curl -fsSL "https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/upload_to_pixeldrain.sh" | bash || warn "Artifact upload failed, but build succeeded."
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
