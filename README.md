# PixelOS 17 Build Scripts (`sweet2`)

Automated build and packaging scripts for compiling **PixelOS 17 (Android 17)** on **Redmi Note 12 Pro 4G (`sweet2`)** via [Crave](https://crave.io).

---

## 📋 Full Documentation & Release Changelog

The complete ROM release changelog and architecture documentation are maintained directly on the **main** branch:
👉 **[View Official Release Changelog](./CHANGELOG.md)**

---

## 🚀 Quick Start on Crave

To compile PixelOS 17 for sweet2:

```bash
crave run --no-patch -- "bash <(curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a17.sh)"
```

---

## 🛠️ Script Capabilities

[`pixelos_a17.sh`](./pixelos_a17.sh) automates the full build lifecycle:
1. **Manifest Setup:** Clones and configures `sweet2.xml` from [`manifest_sweet2`](https://github.com/rony1duet/manifest_sweet2) (`main`).
2. **Repository Parity:** Synchronizes custom device, vendor, kernel, and hardware trees directly to `origin/main`.
3. **Clang Verification:** Inspects Git LFS toolchains and self-heals ASCII pointer files.
4. **Intermediate Invalidation:** Wipes stale VINTF and priv-app permission targets to validate FCM level 7.
5. **GCam Prebuilts:** Automatically downloads and prepares Google Camera prebuilts with local cache preservation and mirror fallbacks.
6. **Pixeldrain Upload:** Packages and uploads flashable ROM zips via [`upload_to_pixeldrain.sh`](./upload_to_pixeldrain.sh).
