# PixelOS sweet2 Build Scripts

Automated build and packaging scripts for compiling **PixelOS** on **Redmi Note 12 Pro 4G (`sweet2`)** via [Crave](https://crave.io) or local build environments.

---

## Quick Start on Crave

### Build PixelOS 16.2 (Android 16 QPR2)
Builds PixelOS based on branch `sixteen-qpr2` using device trees and manifests from branch `PixelOS-16-QPR2`:

```bash
crave run --no-patch -- "curl -v https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16.sh | bash"
```

### Build PixelOS 17 (Android 17)
Builds PixelOS based on branch `seventeen` using device trees and manifests from branch `PixelOS-17-base`:

```bash
crave run --no-patch -- "curl -v https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17.sh | bash"
```

---

## Local Build Machine Usage

For dedicated Linux build servers with `/mnt/build_drive` and `/mnt/cache_drive`:

```bash
chmod +x pixelos_a16_local.sh
bash pixelos_a16_local.sh
```

---

## Automated Script Capabilities

Both `pixelos_a16.sh` and `pixelos_a17.sh` automate the entire build lifecycle with built-in self-healing routines:

1. **Manifest Setup:** Automatically clones and configures the appropriate local manifest branch (`PixelOS-16-QPR2` or `PixelOS-17-base`) from [`rony1duet/manifest_sweet2`](https://github.com/rony1duet/manifest_sweet2).
2. **Repository Sync:** Resets unstaged build modifications and pulls Git LFS objects for toolchains (`prebuilts/clang`, `prebuilts/rust`).
3. **Clang Pointer Verification:** Inspects Clang compiler binaries. If Git LFS pointer files are detected instead of real binaries, the script automatically triggers force-resync and LFS pull before invoking the build.
4. **Policy Normalization:** Strips Windows CRLF line endings from all `sepolicy` files across device, hardware, vendor, and system directories to prevent policy compiler syntax errors.
5. **KernelSU-Next & SusFS Preservation:** Preserves native kernel drivers for Multi-Manager KernelSU-Next (UAPI 6, v3.4.2 manager compatible) and SusFS v2.3.0.
6. **Smart Intermediate Cleaning:** Removes partial intermediate objects (`KERNEL_OBJ`, `cameraserver`, `libcameraservice`, `check_vintf`, and debloated app targets) ensuring incremental builds compile updated camera and kernel modules cleanly without requiring a full multi-hour workspace wipe.
7. **Cloud Upload:** Automatically packages build artifacts and uploads the resulting flashable ROM zip directly to Pixeldrain upon successful completion.
