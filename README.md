# PixelOS Build Scripts for sweet2

Automated build and packaging scripts for compiling PixelOS on Redmi Note 12 Pro 4G (`sweet2`) via Crave.

## Quick Start (Crave)

To run a build on Crave:

```bash
# Android 17 (PixelOS-17-base)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17.sh | bash"

# Android 16 (PixelOS-16-QPR2)
crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-16-QPR2/pixelos_a16.sh | bash"
```

## What the Scripts Do

1. **Manifest Setup:** Inits ROM manifest and configures `sweet2.xml` from `manifest_sweet2`.
2. **Device Trees Sync:** Updates device, vendor, hardware, and kernel trees to latest branch HEAD.
3. **Toolchain Check:** Validates Git LFS toolchains and heals unexpanded Clang pointer files if needed.
4. **Intermediate Cleanup:** Purges test suites, unneeded debug symbols, and conflicting module targets while preserving incremental compilation objects.
5. **GCam Prebuilt:** Prepares Google Camera prebuilts with local caching and SHA-256 verification.
6. **Compilation:** Executes `breakfast sweet2` and builds `pixelos`.
7. **Upload:** Dispatches the completed ROM zip to Pixeldrain and prints the direct download link.

## Branches

- `main` / `PixelOS-17-base`: Android 17 builds
- `PixelOS-16-QPR2`: Android 16 QPR2 builds

Changelog and device details are available in [CHANGELOG.md](CHANGELOG.md).
