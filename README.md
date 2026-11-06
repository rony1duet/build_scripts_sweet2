# PixelOS Build Scripts for sweet2

Automated build and packaging scripts for compiling PixelOS on Redmi Note 12 Pro 4G (`sweet2`) via Crave or on a local Linux PC.

---

## Quick Start

### 1. Local Machine Build (Ubuntu / Debian / WSL2)

Inside your build workspace directory (`mkdir -p ~/pixelos-a17 && cd ~/pixelos-a17`):

```bash
# Android 17 (PixelOS-17-base)
curl -fsSL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17_local.sh | bash
```

The local script automatically validates disk space and RAM, configures ccache, sets safe memory limits, syncs sources, pulls prebuilts, compiles `m pixelos`, and outputs the artifact path without overwriting local swap or files.

### 2. Cloud CI Build (Crave)

```bash
# Android 17 (PixelOS-17-base)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17.sh | bash"

# Android 16 (PixelOS-16-QPR2)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-16-QPR2/pixelos_a16.sh | bash"
```

---

## What the Scripts Do

1. **System & Safety Checks**: Validates available disk space, memory, and required packages.
2. **Manifest Setup**: Inits ROM manifest and configures `sweet2.xml` from `manifest_sweet2`.
3. **Device Trees Sync**: Updates device, vendor, hardware, and kernel trees to latest branch HEAD.
4. **Toolchain Check**: Validates Git LFS toolchains and heals unexpanded Clang pointer files if needed.
5. **Ccache & Environment**: Configures ccache and dynamic Go/Soong memory boundaries (`GOMEMLIMIT`) to prevent OOM errors.
6. **GCam Prebuilt**: Prepares Google Camera prebuilts with local caching and SHA-256 verification.
7. **Compilation**: Executes `breakfast sweet2` and builds `pixelos`.

---

## Branches

- `main` / `PixelOS-17-base`: Android 17 builds
- `PixelOS-16-QPR2`: Android 16 QPR2 builds

Changelog and device details are available in [CHANGELOG.md](CHANGELOG.md).
