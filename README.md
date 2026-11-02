# PixelOS 16 Build Scripts (`sweet2`)

Automated build and packaging scripts for compiling **PixelOS 16.2 (Android 16 QPR2)** on **Redmi Note 12 Pro 4G (`sweet2`)** via [Crave](https://crave.io) or local build servers.

---

## 📋 Full Documentation & Release Changelog

The complete ROM release changelog and architecture documentation are maintained on the **main** branch:
👉 **[View Official Release Changelog](https://github.com/rony1duet/build_scripts_sweet2/blob/main/CHANGELOG.md)**

---

## 🚀 Quick Start on Crave

To compile PixelOS 16.2 for sweet2:

```bash
crave run --no-patch -- "bash <(curl -sL https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/PixelOS-16-QPR2/pixelos_a16.sh)"
```

---

## 💻 Local Build Server Usage

For dedicated Linux servers with local drive mounts:

```bash
chmod +x pixelos_a16_local.sh
bash pixelos_a16_local.sh
```

---

## 🛠️ Script Capabilities

[`pixelos_a16.sh`](./pixelos_a16.sh) automates the full build lifecycle:
1. **Manifest Setup:** Clones and configures `sweet2.xml` from [`manifest_sweet2`](https://github.com/rony1duet/manifest_sweet2) (`PixelOS-16-QPR2`).
2. **Repository Sync:** Resets and synchronizes all device trees and vendor repositories.
3. **Pixeldrain Upload:** Automatically packages and uploads the ROM zip via [`upload_to_pixeldrain.sh`](./upload_to_pixeldrain.sh).
