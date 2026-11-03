# PixelOS sweet2 Build Scripts

Automated build and packaging scripts for compiling **PixelOS** on **Redmi Note 12 Pro 4G (`sweet2`)** via [Crave](https://crave.io).

---

## 📋 Official Release & Changelog Documentation

The official release documentation, hardware matrix, subsystem changes, and flashing runbooks are hosted in:
👉 **[CHANGELOG.md](./CHANGELOG.md)**

---

## 🌿 Branch & Script Organization

Build scripts and deployment assets are strictly separated across dedicated branches:

| Branch | Android Version | Primary Build Script | Description |
| :--- | :--- | :--- | :--- |
| **`main`** | All / Docs | [`CHANGELOG.md`](./CHANGELOG.md) | Central documentation hub and release changelogs |
| **`PixelOS-17-base`** | Android 17.0 | [`pixelos_a17.sh`](https://github.com/rony1duet/build_scripts_sweet2/blob/PixelOS-17-base/pixelos_a17.sh) | Automated Crave build script for PixelOS 17 |
| **`PixelOS-16-QPR2`** | Android 16.2 | [`pixelos_a16.sh`](https://github.com/rony1duet/build_scripts_sweet2/blob/PixelOS-16-QPR2/pixelos_a16.sh) | Automated Crave build script for PixelOS 16 QPR2 |

---

## 🚀 Quick Start on Crave

### Build PixelOS 17 (Android 17)
```bash
crave run --no-patch -- "bash <(curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-17-base/pixelos_a17.sh)"
```

### Build PixelOS 16.2 (Android 16 QPR2)
```bash
crave run --no-patch -- "bash <(curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-16-QPR2/pixelos_a16.sh)"
```

---

## 🛠️ Automated Script Capabilities

1. **Manifest Setup:** Automatically clones and configures the appropriate local manifest branch (`PixelOS-16-QPR2` or `PixelOS-17-base`) from [`rony1duet/manifest_sweet2`](https://github.com/rony1duet/manifest_sweet2).
2. **Repository Sync & Parity:** Automatically resyncs and checks out the matching remote branch for all custom device trees, vendor packages, kernel, and hardware HALs.
3. **Clang Pointer Verification:** Inspects Clang compiler binaries. If Git LFS pointer files are detected instead of real binaries, the script automatically triggers force-resync and LFS pull before invoking the build.
4. **Policy Normalization:** Strips Windows CRLF line endings from all `sepolicy` files across device, hardware, vendor, and system directories to prevent policy compiler syntax errors.
5. **KernelSU-Next & SusFS Preservation:** Preserves native kernel drivers for Multi-Manager KernelSU-Next (UAPI 6, v3.4.2 manager compatible) and SusFS v2.3.0.
6. **Smart Intermediate Cleaning:** Removes partial intermediate objects (`KERNEL_OBJ`, `XiaomiParts`, `libcameraservice`, `check_vintf`, and debloated app targets) ensuring incremental builds compile updated camera, parts, and sepolicy modules cleanly without requiring a full multi-hour workspace wipe.
7. **Cloud Upload:** Automatically packages build artifacts and uploads the resulting flashable ROM zip directly to Pixeldrain upon successful completion.
