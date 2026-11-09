# PixelOS for Redmi Note 12 Pro 4G (sweet2)

Official release notes and comprehensive changelog for PixelOS Android 17 (`PixelOS-17-base` / `seventeen`).

---

## 🚀 Release Highlights

- **Initial Android 17 Bringup**: Full platform migration to Android 17 with VINTF target-level 7 and AIDL HAL compatibility.
- **Dolby Atmos Integration**: Native `LunarisDolby` audio architecture with real-time Quick Settings tile state synchronization.
- **Hardware-Tuned Google Camera**: Bundled `GoogleCameraEng` (BSG MGC 9.6.080) with custom noise reduction, AWB calibration, and ISP crash prevention.
- **Advanced Kernel Stack**: Linux 4.14 SM6150 kernel featuring Multi-Manager KernelSU (UAPI 6), SuSFS v22 nomount hooks, and USB UVC NULL dereference fix.
- **Debloated & Clean**: Permanently purged legacy packages, deprecated ConfigStore/SafetyHub, and Android 13 spoofing for genuine Pixel experience.
- **Audio Routing**: Dedicated mixer paths for headset-mic fluence and VoIP transmit routes.

---

## 📋 Detailed Changelog by Subsystem

### 📱 Device Tree & Hardware Configurations (`device/xiaomi/sweet2` & `device/xiaomi/sm6150-common`)
- **VINTF Compatibility**: Bumped manifest target-level to `7` for Android 17 AIDL HAL enforcement (`bd9e946`).
- **SEPolicy Hygiene**: Eliminated duplicate declarations and redundant rules for `per_boot_file` (`67a98b4`, `e47a74d`).
- **Permission Whitelisting**: Granted `DEVICE_POWER` permission to `org.lineageos.settings` (`6d79f4a`).
- **Xiaomi Parts & Ambient Display**: Defined missing string resources for doze help and ambient display (`c09d6fe`).
- **Flashlight Slider**: Fixed flashlight intensity control sysfs paths and permissions for real-time Quick Settings adjustment (`9f2c6c3`).
- **Client ID & Debloat**: Switched client ID to `android-google`, dropped Play Auto Install packages, and removed Android 13 fingerprint spoofing (`8f42692`, `1d144f7`).
- **Deprecated Package Purge**: Removed packages not present or deprecated in Android 17 (`disable_configstore`, `fs_config_files`, `FM2`, `librecovery_updater_xiaomi`, `Aperture`, `SafetyHub`) (`cb44d37`, `27f68c2`, `965b766`).
- **Settings Provider Defaults**: Imported device preference defaults overlay for SettingsProvider (`23357ff`).
- **WebView Overlay**: Integrated `config_webview_packages` overlay (`dfbf3ab`).
- **Screen & Kernel Configurations**: Defined display dimensions and updated kernel config paths (`ce713ed`).

---

### 🔊 Audio & Dolby Atmos (`hardware/dolby` & Device Trees)
- **Real-Time QS Tile Sync**: Implemented live bidirectional state synchronization between Dolby Atmos audio engine and Quick Settings tile (`6db226b`).
- **Volume Step Synchronization**: Integrated `DolbyDSPVolumeSynchronizer` (`f279a33`) and resolved duplicate sysconfig installation conflicts with `hardware/xiaomi` (`8763057`, `beaea64`).
- **Module De-duplication**: Resolved Soong duplicate module definitions for `LunarisDolby` and cleaned up package declarations (`5e785b9`, `a2bafe5`, `8678639`).
- **VoIP & Headset Mic Routes**: Added Wired Headset Mic to `voip_tx` routes and defined mixer paths for `headset-mic-fluence` and `voip-headset-mic` (`b5b5104`, `ebe8bab`).
- **Clean UI**: Removed non-standard credits and dialog overhead to preserve clean Pixel aesthetic (`656c7ed`).

---

### 📷 Camera & GCam Stack (`vendor/GCam_sweet2` & `vendor/android_prebuilts_sweet2`)
- **Bundled Google Camera**: Integrated `GoogleCameraEng` (BSG MGC 9.6.080) prebuilt with sweet2 sensor tuning (`5ea7580`, `c54ee56`).
- **ISP Crash Prevention**: Configured hardware-correct video caps (FHD all fps, 4K@30fps; disabled unsupported 8K and 4K@60fps to prevent Snapdragon 732G ISP driver crashes) (`377abc0`, `9843bee`).
- **Tuned Profiles**: Calibrated noise model and AWB parameters in `GCam_Config_sweet2.xml`.
- **XML Parser Fix**: Removed XML comments causing crashes in Android `SharedPreferences` parser (`b3c28de`).
- **Presigned APK Soong Fix**: Added `skip_preprocessed_apk_checks: true` to prevent Soong build failure with compressed dex in privileged presigned APK (`a4b53e8`, `404119c`).
- **Resilient Prebuilt Fetcher**: Implemented multi-mirror prebuilt fetcher supporting GitHub Release assets, CelsoAzevedo CDN, and local caching (`d9b8653`, `2ced3ee`).

---

### 🐧 Kernel & Security (`kernel/xiaomi/sm6150`)
- **USB Gadget Stability**: Resolved kernel NULL pointer dereference on USB function switch during unbind (`1a448d577ffb`).
- **SuSFS & NoMount**: Updated NoMount driver protocol to v22 (`e95ba9dbafe2`), reordered struct members to align with userspace modules (`3aa6c50ae25f`), and set open-redirect bit flag on inode `i_state` (`3f17b76c3ea3`).
- **Sleep-of-Death Fix**: Fixed system freeze caused by blocking fsnotify and delayed work in SuSFS (`8b7bb2855c2a`).
- **KernelSU Multi-Manager**: Integrated Multi-Manager KSU (UAPI 6) with signature-first manager discovery for spoofed/obfuscated managers (`3d60f3ce2e03`, `f7782251186f`, `46602530d227`).
- **Memory & Defconfig Tuning**: Restored default `mmap_min_addr`, enabled cgroup pressure monitoring, and disabled `CONFIG_SHADOW_CALL_STACK` for Zygisk hooking (`a426b2d96c37`, `3ff1d0b5905c`).

---

### 🧱 Vendor HALs & System Blobs (`vendor/xiaomi/*` & `hardware/xiaomi`)
- **Display HAL**: Switched to `display.config-V12-ndk` and disabled ELF check violations (`fd67f2d`).
- **Soter Cleanup**: Dropped Soter cleanly without breaking multiline variable continuation (`9d3cf9c`).
- **Git Hygiene**: Added `.gitattributes` enforcing UNIX LF line endings across all vendor and hardware repositories (`8500e06`, `79ed370`, `940f851`).

---

### ⚙️ Build Infrastructure & Automation (`build_scripts_sweet2` & `manifest_sweet2`)
- **OrangeFox Builder v1.8.1**: Enforced single-threaded AST evaluation (`GOMAXPROCS=1`), aggressive garbage collection (`GOGC=10`), and Linux `MADV_DONTNEED` paging (`GODEBUG=gctrace=1,madvdontneed=1,asyncpreemptoff=1`) directly into `build/blueprint/bootstrap/bootstrap.go` and `out/soong/.bootstrap/build.ninja` via literal heredoc Python patcher; set finite 64MB stack limit (`ulimit -s 65536`) to protect modern 64-bit kernel memory layouts from OOM kills in zero-swap containers.
- **Manifest Synchronization**: Local manifest updated to track `PixelOS-17-base` across all device trees with `clone-depth="1"` (`71a4274`, `8867344`).
- **Modern Soong Stubs Enforcement**: Purged deprecated `WITHOUT_CHECK_API=true` and enforced `BUILD_FROM_SOURCE_STUB=true` to comply with Android 17 text stubs (`2fef4ff`).
- **Container Memory Stability**: Capped compiler concurrency (`jobs=8`, `GOMAXPROCS=4`) and unset `GOMEMLIMIT` in zero-swap environments to eliminate `soong_build` OOM kills (`7ab5645`, `22dc3e1`).
- **Automated Cleanup**: Added automatic invalidation of stale ninja files (`build.*.ninja`), bootstrap caches (`.bootstrap`), and variables (`soong.*.variables`).
- **Streaming Uploader**: Engineered high-speed HTTP PUT streaming uploader to Pixeldrain with redirect following, retry logic, and multipart fallback (`7679892`).

---

## 📊 Hardware Support Status

| Hardware Component | Status | Operational Notes |
| :--- | :---: | :--- |
| **Display & Touch** | 🟢 Working | 120Hz AMOLED, HDR10, smooth touch response |
| **Audio** | 🟢 Working | Stereo loudspeakers, Dolby Atmos, 3.5mm headphone jack |
| **Microphone & VoIP** | 🟢 Working | Headset mic, dual mic noise cancellation, VoIP calling |
| **Camera & Flash** | 🟢 Working | 108MP main, 8MP ultrawide, 2MP macro, 4K@30fps, adjustable flashlight |
| **Cellular & Connectivity**| 🟢 Working | Dual SIM 4G VoLTE, Wi-Fi 2.4/5GHz, Bluetooth 5.0 |
| **Biometrics** | 🟢 Working | Side-mounted fingerprint sensor & Face unlock |
| **Sensors** | 🟢 Working | Accelerometer, Gyroscope, Proximity, Light, IR Blaster |
| **Root & Integrity** | 🟢 Working | KernelSU-Next v3.4.2 + SuSFS v22, Play Integrity passing |

---

## 📦 Flashing Guide

### Clean Flash (Recommended for Android 17 Bringup)
1. Boot into OrangeFox or TWRP recovery.
2. Format Data (`Wipe` -> `Format Data` -> type `yes`).
3. Wipe `Dalvik / ART Cache` and `Cache`.
4. Flash `PixelOS_sweet2-17.0-*.zip`.
5. Reboot to System.

### Dirty Flash (Updating an existing PixelOS 17 installation)
1. Boot into recovery.
2. Flash the new `PixelOS_sweet2-17.0-*.zip`.
3. Wipe `Dalvik / ART Cache`.
4. Reboot to System.
