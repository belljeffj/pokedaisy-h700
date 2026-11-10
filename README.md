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
- `pak/launch.sh` replaces upstream's TrimUI launcher:
  - keeps games, saves and states in `PokeDaisy/` at the SD card root, outside the pak, so
    updates never overwrite them;
  - turns off the TrimUI raw-button layout (NextUI-H700 rc11+ exposes the built-in controls as a
    standard SDL controller);
  - logs to NextUI's logs folder as `PokeDaisy.txt`.

## Install or update

1. Back up `PokeDaisy/saves` on the card.
2. Download the latest release zip and unzip it at the root of the NextUI SD card, replacing
   `Tools/h700/PokeDaisy.pak`.
3. Put games in `PokeDaisy/roms/`. To use an existing save, copy it to
   `PokeDaisy/saves/<full ROM filename>.sav` (PokeDaisy does not import saves on its own).

## If it does not start

Read `PokeDaisy.txt` in NextUI's logs folder (or in the pak if no logs folder is set). The
release notes and `DEPENDENCIES.txt` list the libraries and glibc version the binary needs.
