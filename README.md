# PixelOS sweet2 build scripts

Run the PixelOS sweet2 build on Crave with:

```bash
crave run --clean --no-patch --env BUILD_USERNAME=rony1duet --env BUILD_HOSTNAME=crave -- "curl -v https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16.sh | bash"
```

Run on a local machine with `/mnt/build_drive` (sda2) + `/mnt/cache_drive` (sdb2):

```bash
bash pixelos_a16_local.sh
```
