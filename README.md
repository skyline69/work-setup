# work-setup

Unified Hyprland + Quickshell setup with one installer entrypoint.

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/skyline69/work-setup/main/install.sh | bash -s -- --yes
```

Add your usual flags after `--`, for example:

```bash
curl -fsSL https://raw.githubusercontent.com/skyline69/work-setup/main/install.sh | bash -s -- --dry-run --distro arch --machine $(uname -n) --yes
```

## Layout

- `install.sh`: root installer and optional standalone bootstrap entrypoint
- `hypr/`: Hyprland config, machine overlays, and active generated includes
- `quickshell/`: Quickshell config deployed by the same installer
- `scripts/packages/`: distro-specific package maps for Arch, Fedora, and Ubuntu
- `tests/`: installer tests

## Normal Usage

Run from a checked-out repo:

```bash
bash install.sh --dry-run --distro arch --machine $(uname -n) --yes
bash install.sh --distro arch --machine $(uname -n) --yes
```

Useful flags:

- `--groups core,quickshell,fonts,media,wallpaper,apps`
- `--wallpaper cozy-campfire-by-abi-toads.3840x2160.gif`
- `--no-quickshell`
- `--copy` or `--symlink`
- `--home /path/to/home`

When the `wallpaper` group is enabled, the installer downloads the wallpaper assets from the GitHub release for this repo into `~/.local/share/work-setup/wallpapers` and asks which wallpaper to use during interactive installs. Unattended runs default to `cozy-campfire-by-abi-toads.3840x2160.gif` unless `--wallpaper` is provided.

## Standalone Bootstrap Usage

If you only have `install.sh`, it defaults to the GitHub archive for this repo. You can still override that source with `--archive-url` or `WORK_SETUP_ARCHIVE_URL`.

```bash
bash install.sh --archive-url https://example.com/work-setup.tar.gz --dry-run --distro arch --machine $(uname -n) --yes
bash install.sh --archive-url file:///tmp/work-setup.tar.gz --dry-run --distro arch --machine $(uname -n) --yes
```

You can also set:

```bash
export WORK_SETUP_ARCHIVE_URL=https://example.com/work-setup.tar.gz
bash install.sh --dry-run --distro arch --machine $(uname -n) --yes
```

The archive must extract to a tree containing:

- `install.sh`
- `hypr/`
- `quickshell/`
- `scripts/packages/`

## Notes

- Existing `~/.config/hypr` and `~/.config/quickshell` directories are backed up before deployment.
- `quickshell/install.sh` is deprecated and now delegates to the root installer.
- Ubuntu support is best-effort; unsupported groups are reported rather than treated as fully supported.
