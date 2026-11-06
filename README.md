# PixelOS Build Scripts for sweet2

Automated build and packaging scripts for compiling PixelOS on Redmi Note 12 Pro 4G (`sweet2`) via Crave or on a local Linux PC.

---

## Pre-Installation Requirements (For Local Builds)

Before building on a physical PC or WSL2 (Ubuntu 22.04 / 24.04 LTS), ensure your system has the required packages, tools, and swap space configured:

### 1. Build Packages and Repo Tool
```bash
sudo apt update && sudo apt install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
    git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev \
    libncurses-dev libssl-dev libxml2-utils lz4 liblz4-dev lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3 \
    openjdk-17-jdk file pkg-config

# Install Google repo tool
sudo curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
sudo chmod a+rx /usr/local/bin/repo

# Configure Git LFS
git lfs install
```

### 2. Configure 16GB Swap File (Prevents Out-Of-Memory Linker Crashes)
```bash
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Quick Start

### 1. Local Machine Build (Ubuntu / Debian / WSL2 / Docker)

Inside your build workspace directory:

#### Android 16 (PixelOS-16-QPR2):
```bash
# Create and enter workspace directory
mkdir -p ~/pixelos-a16 && cd ~/pixelos-a16

# Run build with auto-upload to Pixeldrain
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16_local.sh | bash

# With automatic dependency and toolchain installation:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16_local.sh | bash -s -- --install-deps

# Build locally without uploading:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16_local.sh | bash -s -- --no-upload
```

#### Android 17 (PixelOS-17-base):
```bash
# Create and enter workspace directory
mkdir -p ~/pixelos-a17 && cd ~/pixelos-a17

# Run build with auto-upload to Pixeldrain
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17_local.sh | bash

# With automatic dependency and toolchain installation:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17_local.sh | bash -s -- --install-deps

# Build locally without uploading:
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17_local.sh | bash -s -- --no-upload
```

The local script automatically validates disk space and RAM, configures ccache, sets safe memory limits, syncs sources, pulls prebuilts, compiles `m pixelos`, and uploads the final flashable zip to Pixeldrain.

### 2. Cloud CI Build (Crave)

```bash
# Android 17 (PixelOS-17-base)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17.sh | bash"

# Android 16 (PixelOS-16-QPR2)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-16-QPR2/pixelos_a16.sh | bash"
```

---

## What the Scripts Do

1. **System & Safety Checks**: Validates available disk space, memory, and required packages (supports `--install-deps` for automated setup).
2. **Manifest Setup**: Inits ROM manifest and configures `sweet2.xml` from `manifest_sweet2`.
3. **Device Trees Sync**: Updates device, vendor, hardware, and kernel trees to latest branch HEAD.
4. **Toolchain Check**: Validates Git LFS toolchains and heals unexpanded Clang pointer files if needed.
5. **Ccache & Environment**: Configures ccache and dynamic Go/Soong memory boundaries (`GOMEMLIMIT`) to prevent OOM errors.
6. **GCam Prebuilt**: Prepares Google Camera prebuilts with local caching and SHA-256 verification.
7. **Compilation**: Executes `breakfast sweet2` and builds `pixelos`.
8. **Upload**: Automatically uploads the artifact to Pixeldrain (skippable via `--no-upload`).

---

## Branches

- `main` / `PixelOS-17-base`: Android 17 builds
- `PixelOS-16-QPR2`: Android 16 QPR2 builds

Changelog and device details are available in [CHANGELOG.md](CHANGELOG.md).
