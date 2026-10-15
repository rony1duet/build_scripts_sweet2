# PixelOS sweet2 build scripts

Run the PixelOS sweet2 build on Crave with:

```bash
crave run --clean --no-patch --env PIXELDRAIN_API_KEY=026168ac-08ec-4bdb-9dde-99c7635200b0 -- "curl -v https://raw.githubusercontent.com/rony1duet/build_scripts_sweet2/main/pixelos_a16.sh | bash"
```

Run on a local machine with `/mnt/build_drive` (sda2) + `/mnt/cache_drive` (sdb2):

```bash
bash pixelos_a16_local.sh
```
