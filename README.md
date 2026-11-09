# OrangeFox Recovery Project (OFRP) Build Scripts for sweet2

Automated build, environment configuration, and packaging scripts for compiling the latest **OrangeFox Recovery (R12.1 / Android 12.1 base)** for Redmi Note 12 Pro 4G (`sweet2`).

---

## Hardware & System Requirements

Building OrangeFox Recovery is significantly lighter than compiling a full Android OS ROM, but still requires a POSIX-compliant Linux environment.

### 1. Host Operating System
- **Linux (Recommended)**: Ubuntu 20.04 LTS, Ubuntu 22.04 LTS, or Debian 11/12.
- **Windows Users**: Must use **WSL2** (Windows Subsystem for Linux) running Ubuntu 22.04 LTS.
  > [!IMPORTANT]
  > Android build systems (Kati, Soong, Ninja, toybox) cannot run on native Windows Command Prompt or PowerShell. Native Windows NTFS filesystems (`/mnt/c`, `/mnt/g`) cause case-insensitivity corruption and severe I/O slowdowns. Always clone and build inside the native Linux ext4 filesystem (e.g. `~/fox_12.1`).

### 2. Hardware Specifications
- **CPU**: 4 cores minimum (8+ cores recommended).
- **RAM**: 16 GB recommended (8–12 GB minimum if paired with an 8–16 GB swap file).
- **Storage**: Minimum **45–60 GB** free space on an `ext4` partition.
- **Network**: Broadband connection for shallow sync of OrangeFox minimal manifest (~15–20 GB).

---

## Setting Up Your Local PC (WSL2 / Ubuntu)

### If you are on Windows:
1. Open PowerShell as Administrator and install WSL2 Ubuntu:
   ```powershell
   wsl --install -d Ubuntu-22.04
   ```
2. Restart your PC if prompted, then launch Ubuntu from your Start menu.
3. Once inside Ubuntu, update packages:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

---

## Quick Start (Building OrangeFox)

### One-Line Build Command (Run inside Linux / WSL2 Terminal):
```bash
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash
```

### With Custom Options:
```bash
# Automatically install missing dependencies and run with 8 threads:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- --install-deps -j8

# Force re-sync of the OrangeFox manifest:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- --sync

# Compile without auto-uploading to Pixeldrain:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/orangefox/orangefox_local.sh | bash -s -- --no-upload
```

---

### Alternative: Clone Repository Locally
```bash
git clone https://github.com/rony1duet/build_scripts_sweet2.git -b orangefox ~/build_scripts_sweet2
cd ~/build_scripts_sweet2
chmod +x orangefox_local.sh build_orangefox_sweet2.sh upload_to_pixeldrain.sh
./orangefox_local.sh
```

---

## What the Script Automates

1. **Host Environment Validation**: Ensures the script is running inside a POSIX Linux / WSL2 environment and verifies available disk space (>= 45 GB) and RAM/swap.
2. **Dependency Installation (`--install-deps`)**: Installs all required native compilation packages, tools, and Google's `repo` command.
3. **OrangeFox Manifest Sync**: Initializes and shallow-syncs `https://gitlab.com/OrangeFox/manifest.git` (`fox_12.1`).
4. **Device Recovery Tree Configuration**: Sets up the recovery device tree for `sweet2` in `device/xiaomi/sweet2` with required OrangeFox makefiles.
5. **Ccache Optimization**: Configures 25 GB ccache in `~/.ccache_orangefox` to accelerate subsequent builds.
6. **OrangeFox Flags**: Exports all necessary device environment variables:
   - `OF_MAINTAINER="rony1duet"`
   - `FOX_VERSION="R12.1"`
   - `FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1`
   - Screen resolution: 1080x2400 (`OF_SCREEN_H=2400`, `OF_STATUS_H=95`)
   - Decryption support for FBE v2 and metadata encryption.
7. **Compilation**: Runs `lunch twrp_sweet2-eng` and compiles `mka recoveryimage`.
8. **Artifact Verification & Upload**:
   - Generates `out/target/product/sweet2/recovery.img` (Fastboot flashable)
   - Generates `out/target/product/sweet2/OrangeFox-*.zip` (Recovery flashable)
   - Automatically uploads the flashable ZIP to Pixeldrain and outputs the download link.

---

## Flashing OrangeFox Recovery to sweet2

Once built, you can flash the recovery via Fastboot:

```bash
# 1. Reboot device to bootloader (Fastboot mode)
adb reboot bootloader

# 2. Flash OrangeFox recovery image to the dedicated recovery partition
fastboot flash recovery out/target/product/sweet2/recovery.img

# 3. Boot directly into OrangeFox Recovery
fastboot reboot recovery
```

---

## Branches in this Repository

- `orangefox`: OrangeFox Recovery Project build scripts and configuration for sweet2
- `main` / `PixelOS-17-base`: PixelOS Android 17 ROM build scripts
- `PixelOS-16-QPR2`: PixelOS Android 16 QPR2 ROM build scripts
