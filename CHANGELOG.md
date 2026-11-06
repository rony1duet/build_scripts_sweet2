# PixelOS for Redmi Note 12 Pro 4G (sweet2)

Release notes and device changelog for PixelOS builds on `sweet2`.

## Highlights

- Initial Android 17 (PixelOS-17-base) bringup
- Dolby Atmos (`LunarisDolby`) integrated with live Quick Settings tile sync
- Prebuilt Google Camera (BSG MGC 9.6.080) tuned for sweet2 sensors
- Linux 4.14 SM6150 kernel with KernelSU-Next v3.4.2_33355 and SUSFS v22
- Xiaomi Parts with thermal profiles and refresh rate controls
- Removed unused bloat packages for better battery life and RAM usage

## Changelog

### Device & Common Trees (`sweet2` / `sm6150-common`)
- Bumped VINTF manifest target-level to 7 for Android 17 compatibility
- Cleaned up redundant per_boot_file sepolicy rules
- Whitelisted `DEVICE_POWER` permission for LineageOS settings
- Added missing Ambient Display string resources in Xiaomi Parts
- Added flashlight intensity tile controls
- Switched client ID to android-google
- Removed deprecated packages: `disable_configstore`, `fs_config_files`, `FM2`, `librecovery_updater_xiaomi`, `Aperture`, `SafetyHub`

### Audio & Dolby Atmos
- Integrated LunarisDolby with live Quick Settings tile state synchronization
- Fixed volume step sync and deprecated audio companion references
- Declared proper mixer paths for headset and VoIP mic routes

### Camera
- Bundled prebuilt GoogleCameraEng (BSG MGC 9.6.080)
- Configured hardware-correct video caps (4K@30fps, 1080p@60fps) to prevent ISP crashes on Snapdragon 732G
- Tuned noise reduction and AWB in GCam_Config_sweet2.xml

### Kernel
- Updated KernelSU-Next to v3.4.2_33355
- Updated SUSFS to v22 nomount hooks
- Fixed USB unbind NULL pointer dereference
- Restored mmap min address and tuned cgroup memory monitoring

## Hardware Status

| Feature | Status | Notes |
| :--- | :---: | :--- |
| Display | Working | 120Hz AMOLED, HDR10 |
| Audio | Working | Stereo speakers, Dolby Atmos, 3.5mm jack |
| Camera | Working | 108MP, Ultrawide, Macro, 4K30 video |
| Network | Working | Dual SIM VoLTE, Wi-Fi 5GHz, Bluetooth |
| Biometrics | Working | Fingerprint & Face unlock |
| Sensors | Working | All sensors, IR blaster |
| SELinux | Enforcing | Play Integrity / SafetyNet passes |

## Flashing Instructions

### Clean Flash (First install or switching from another ROM)
1. Boot into custom recovery (OrangeFox or TWRP).
2. Format Data (type `yes`).
3. Wipe Cache and Dalvik/ART Cache.
4. Flash ROM zip.
5. *(Optional)* Flash KernelSU or Magisk if root is desired.
6. Reboot to system.

### Dirty Flash (Updating current PixelOS)
1. Boot into recovery.
2. Flash updated ROM zip.
3. Wipe Dalvik/ART Cache.
4. Reboot to system.
