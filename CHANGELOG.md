# PixelOS 17.0 for Redmi Note 12 Pro 4G (sweet2) — Official Release

[![Android](https://img.shields.io/badge/Platform-Android_17-34A853.svg?logo=android&logoColor=white)](https://android.com)
[![Device](https://img.shields.io/badge/Device-Redmi_Note_12_Pro_4G_(sweet2)-EA4335.svg)](https://github.com/rony1duet)
[![Security Patch](https://img.shields.io/badge/Security_Patch-October_2026-4285F4.svg)]()
[![Status](https://img.shields.io/badge/Build_Status-Stable-brightgreen.svg)]()

---

## 🚀 Highlights & Major Improvements

- **Android 17 Platform Bringup**: Initial base upgrade to Android 17 (PixelOS-17-base) with refreshed UI, improved scheduling, and upgraded Treble compatibility.
- **Dolby Atmos Audio System**: Fully integrated `LunarisDolby` audio architecture with real-time Quick Settings tile state synchronization, dynamic effect routing, and low-latency DSP profiles.
- **Hardware-Tuned Google Camera**: Prebuilt GCam (MGC 9.6.080) tuned specifically for Sweet2's 108MP main sensor, ultra-wide lens, macro, and 4K@30fps video stabilization.
- **Performance Kernel & KernelSU Next**: Powered by Linux 4.14 SM6150 kernel featuring integrated KernelSU-Next v3.4.2_33355, SUSFS v22 nomount hooks, and cgroup memory optimizations.
- **Expressive Theming & M3E UI**: Updated Xiaomi Parts with Material You expressive theme styling and per-app thermal profile controls.
- **Debloated & Streamlined**: Purged obsolete, conflicting, and telemetry packages for extended battery longevity and smoother animations.

---

## 🛠️ Detailed Changelog

### 📱 Device Trees (`sweet2` & `sm6150-common`)
- **VINTF Compatibility**: Bumped device manifest `target-level` to `7` to align with Android 17's framework compatibility matrix (`compatibility_matrix.7.xml`).
- **SELinux Security**: Purged redundant vendor `per_boot_file` policies to resolve Android Treble separation rules while maintaining SELinux enforcing integrity.
- **Priv-App Security Whitelist**: Whitelisted `android.permission.DEVICE_POWER` for `org.lineageos.settings` in `system_ext-privapp-permissions-qti.xml`.
- **Xiaomi Parts**:
  - Defined missing localized Ambient Display / Doze help string resources.
  - Implemented Material 3 Expressive (`Theme.SubSettingsBase.Expressive`) styling.
  - Added QS flashlight intensity slider controls and permissions.
  - Retained per-app thermal configuration profiles (Benchmark, Gaming, Camera, Streaming, Video).
- **Display & Visuals**: Adopted KawaseDarkmoon background blur algorithm for fluid lockscreen and QS blur rendering.
- **Client ID**: Switched to `android-google` client ID base and purged Play Auto Install bloat.
- **Cleaned Obsolete Bloat**: Removed deprecated packages (`disable_configstore`, `fs_config_files`, `FM2`, `librecovery_updater_xiaomi`, `Aperture`, `SafetyHub`).

---

### 🔊 Audio & Dolby Atmos (`hardware_dolby`)
- **Real-Time QS Sync**: Synchronized Dolby Atmos master power toggle with Quick Settings tile state using reactive preference listeners.
- **Tile State Listener**: Added `TileService.requestListeningState` on audio route shifts (headset, speaker, Bluetooth A2DP).
- **DSP Harmonization**: Fixed volume synchronization conflicts and cleaned deprecated field references in audio companion objects.
- **Documentation & UI**: Streamlined interface and removed extraneous UI clutter.

---

### 📷 Camera & Imaging (`GCam_sweet2` & `android_prebuilts_sweet2`)
- **Google Camera Integration**: Imported prebuilt `GoogleCameraEng` module with `dex_preopt` disabled to avoid multidex dex2oat conflicts.
- **Architecture Fix**: Migrated package registration from legacy Kati `Android.mk` to modern blueprint inheritance (`device_sweet2_gcam.mk`).
- **Download Automation**: Enforced UNIX LF line endings across fetchers and configured Pixeldrain API high-speed mirror.
- **Multi-Camera Profiles**: Maintained auxiliary camera access for 108MP primary, 8MP ultra-wide, and 2MP macro sensors.

---

### ⚡ Kernel & Root Engine (`android_kernel_xiaomi_sm6150`)
- **KernelSU-Next**: Integrated KernelSU-Next v3.4.2_33355 with signature-first manager discovery.
- **NOMOUNT Protocol**: Updated nomount protocol to v22 for stealth root mounting.
- **SUSFS Enhancements**: Fixed sleep-of-death freeze caused by blocking fsnotify and delayed work.
- **USB Gadget**: Prevented NULL pointer dereference on USB function switch during unbind.
- **Memory Management**: Restored default mmap minimum address and enabled cgroup memory pressure monitoring.

---

### 🔌 Vendor HALs & Proprietary Blobs
- **Display HAL**: Switched to `display.config-V12-ndk` with ELF check accommodations.
- **WFD / Miracast**: Updated WFD system blobs from nezha OS3.0.332.0.XPAMIXM.
- **Audio Linkage**: Patched audio libraries to resolve symbols against `libaudioroute-v34.so` and `libtinyxml2-v34.so`.
- **Infrared**: Switched to modern AIDL ConsumerIR service implementation.
- **Biometrics**: Restored face detection libraries and Goodix fingerprint daemon stability.

---

## 📊 Hardware Working Status

| Component | Status | Notes |
| :--- | :---: | :--- |
| **Display** | 🟢 Working | 120Hz smooth display, AMOLED, HDR10 |
| **Audio** | 🟢 Working | Stereo speakers, Dolby Atmos DSP, 3.5mm jack |
| **Camera** | 🟢 Working | 108MP GCam, 4K@30fps, Aux lenses, Slow-mo |
| **Connectivity** | 🟢 Working | Dual SIM VoLTE / VoWiFi, 5GHz Wi-Fi, Bluetooth 5.2 |
| **Biometrics** | 🟢 Working | Side fingerprint & Face unlock |
| **Sensors** | 🟢 Working | Proximity, Ambient light, Accelerometer, Gyroscope, IR |
| **Security** | 🟢 Enforcing | SELinux Enforcing, SafetyNet / Play Integrity |

---

## 📲 Installation Instructions

### First Time Installation (Clean Flash Required)
1. Boot into custom recovery (OrangeFox / TWRP recommended).
2. **Format Data** (Type `yes` to decrypt internal storage).
3. Wipe `Dalvik / ART Cache`, `Metadata`, and `Cache`.
4. Flash the PixelOS ROM ZIP.
5. *(Optional)* Flash Magisk or KernelSU-Next manager if root is desired.
6. Reboot to System.

### Updating from Previous Android 17 Builds (Dirty Flash)
1. Boot into recovery.
2. Flash the updated ROM ZIP.
3. Wipe `Dalvik / ART Cache`.
4. Reboot to System.

---

## 🔗 Downloads & Credits
- **Maintainer**: [@rony1duet](https://github.com/rony1duet)
- **Source Code**: [PixelOS-AOSP](https://github.com/PixelOS-AOSP) | [Device Trees](https://github.com/rony1duet/android_device_xiaomi_sweet2)
