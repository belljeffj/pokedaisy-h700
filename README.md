# PokeDaisy for NextUI H700

Automatic builds of [PokeDaisy](https://github.com/lidor30/pokedaisy)'s Linux host, packaged as a
NextUI Tools pak for Anbernic H700 handhelds (built for the RG SP on BaseOS + NextUI-H700 rc11+).

Unofficial. Not affiliated with PokeDaisy or NextUI. PokeDaisy is GPL-3.0; each release links the
exact upstream commit it was built from, and `SOURCE.txt` inside the pak records it too.

## How it works

- `.github/workflows/build.yml` runs every Monday (or on demand from the Actions tab).
- It checks upstream `main`. If there is a commit it has not built yet, it builds with upstream's
  own checksum-pinned NextUI/TrimUI toolchain, runs upstream's tests under QEMU, and publishes a
  release named `upstream-<commit>` with a ready-to-unzip `PokeDaisy-h700-<commit>.zip`.
- One pak plays GBA, GB/GBC and DS games, like the Android app: it is upstream's DS-enabled build
  (mGBA + the experimental DSperate backend). If the DS build ever fails, that week's release falls
  back to a GBA-only build and says so in its notes.
- `pak/launch.sh` replaces upstream's TrimUI launcher:
  - lists only the games on PokeDaisy's compatibility list (https://pokedaisy.com/compatibility/),
    checked like the site's ROM check: SHA-1 for Game Boy builds and ROM hacks, cart code + revision
    for retail GBA and DS. The list is `compat.txt`, made by `tools/make_compat.py` from upstream's
    `website/src/data/compat.json` at every build, so newly supported games and hack versions arrive
    with the weekly release. Games come from NextUI's `Roms/Game Boy*` and `Roms/Nintendo DS*`
    folders, via symlinks in /tmp mounted onto `PokeDaisy/roms` while PokeDaisy runs.
    `POKEDAISY_ALL=1` in `launch.sh` lists every game instead;
  - keeps saves in step with the Android app's Syncthing folder `Saves/pokedaisy` (Android names
    saves `<ROM name>.sav`/`.srm`, PokeDaisy Linux `<ROM name>.<ext>.sav`): a newer shared save is
    copied in before the game, a newer PokeDaisy save copied back after; every overwritten save is
    copied to `PokeDaisy/backups/` first. `POKEDAISY_SHARED_SAVES` changes the folder;
  - reads file sizes and dates from metadata (stat), so later launches don't re-read the library;
  - handles zipped games: a supported game's `.zip` is unpacked once into `PokeDaisy/.unzipped/`
    (again only when the zip changes; safe to delete). `.7z` is not supported;
  - keeps PokeDaisy's saves and states in `PokeDaisy/` at the SD card root, outside the pak, so
    updates never overwrite them;
  - turns off the TrimUI raw-button layout (NextUI-H700 rc11+ exposes the built-in controls as a
    standard SDL controller);
  - logs to NextUI's logs folder as `PokeDaisy.txt`.

## DS battle screen switching

`tools/patch_ds_battles.py` runs before every DS build. Upstream's Linux DS frontend only detects battles
for the one Platinum dump its companion reads; the patch turns on AUTO switching (and PANEL in the
one-screen build) for every game in PokeDaisy's shared DS field table, as the Android app does:
Platinum, HeartGold / SoulSilver, Black / White, Black 2 / White 2. For those other games it only reads
game memory. The companion itself stays Platinum-only. If upstream changes that code, the build goes on
without the patch and the release notes say so.

`tools/patch_ds_fit.py` also runs before every DS build: DS screens and the DS companion scale to the
largest size that fits with the DS's 4:3 shape (640x480 on the RG SP) instead of whole-number steps
(512x384). `POCKET_DS_INTEGER=1` in `launch.sh` restores whole-number scaling.

## Release lines

- **Stable** (`PokeDaisy.pak`, tags `upstream-<commit>`): lidor30/pokedaisy `main`.
- **One-screen, experimental** (`PokeDaisy 1-Screen.pak`, pre-releases tagged `onescreen-<commit>`): the
  Brick fork's `experiment/ds-one-screen-battles` branch (keeganwhitacre/pokedaisy-brick), which adds
  SET > BATTLES > PANEL: the DS command screen drawn over the battle on one screen. It can be older than
  stable, installs beside it in Tools, and shares the same `PokeDaisy/` saves.

Both are checked every Monday; the Actions tab's Run workflow can build either line on demand.

## Updating on the device

Every release zip also carries `Tools/h700/PokeDaisy Updater.pak`. Run **PokeDaisy Updater** from NextUI's
Tools menu with Wi-Fi on: it checks this repo's releases and replaces each PokeDaisy pak you have
(stable and/or 1-Screen) when a newer build exists, then updates itself. No progress screen; it returns to
NextUI when done and writes `PokeDaisy Updater.txt` in NextUI's logs folder. Each pak's `RELEASE.txt`
names the zip it came from; zips are named `<line>-<upstream commit>-b<build number>.zip`. Needs this repo
to be public (the device has no GitHub credentials).

## Install or update

1. Back up `PokeDaisy/saves` on the card.
2. Download the latest release zip and unzip it at the root of the NextUI SD card, replacing
   `Tools/h700/PokeDaisy.pak`.
3. Keep games in NextUI's `Roms/Game Boy …` and `Roms/Nintendo DS (NDS)/` folders. To use an existing
   save, copy it to `PokeDaisy/saves/<full ROM filename>.sav`, e.g. `Emerald.gba.sav` or
   `Platinum.nds.sav` (PokeDaisy does not import saves on its own). Leave `PokeDaisy/roms/` empty.
4. DS is experimental upstream: the companion supports only Pokemon Platinum (USA) rev 1; other DS
   games are emulation only.

## If it does not start

Read `PokeDaisy.txt` in NextUI's logs folder (or in the pak if no logs folder is set). The
release notes and `DEPENDENCIES.txt` list the libraries and glibc version the binary needs.

## Main-menu entry (optional)

To show PokeDaisy in NextUI's main menu instead of only under Tools, copy the two folders in
`pak/main-menu/` to the root of the SD card:

- `Emus/h700/PKDAISY.pak/launch.sh` hands off to `Tools/h700/PokeDaisy.pak`, so the updater
  keeps it current and it never needs updating itself.
- `Roms/PokeDaisy (PKDAISY)/Open PokeDaisy.pkd` is a placeholder so NextUI shows the folder.

Main menu → PokeDaisy → Open PokeDaisy opens PokeDaisy's own game list.
