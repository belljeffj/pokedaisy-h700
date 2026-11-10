#!/bin/sh
# PokeDaisy as a NextUI Tools pak on Anbernic H700 (RG SP etc.), NextUI-H700 rc11 or later.
# POSIX sh only: /bin/sh may be dash on H700.
#
# Games stay in NextUI's own Roms folders: all Roms/ subfolders matching a line of
# roms-folder.txt ("Game Boy*", "Nintendo DS*"). While PokeDaisy runs, a temporary folder
# of symlinks to every game in them is mounted as PokeDaisy/roms (PokeDaisy only lists games
# from <data>/roms). The SD card's FAT/exFAT can't hold symlinks or act as an overlayfs layer,
# so the links live in /tmp. If that fails, the first folder is bind-mounted instead.
# PokeDaisy's own files live OUTSIDE the pak, in $SDCARD_PATH/PokeDaisy/, so replacing the pak
# with a newer build never touches them:
#   PokeDaisy/saves/   battery saves (<full ROM filename>.sav: Emerald.gba.sav, Platinum.nds.sav)
#   PokeDaisy/states/  save states
#   PokeDaisy/roms/    leave empty (mount point)
#   PokeDaisy/.unzipped/  unpacked copies of zipped Pokemon games (safe to delete; rebuilt as needed)
set -eu
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SD="${SDCARD_PATH:-/mnt/SDCARD}"
DATA="$SD/PokeDaisy"
# Folders to show, one per line.
NL='
'
FOLDERS="${POKEDAISY_ROMS:-}"
if [ -z "$FOLDERS" ]; then
  patterns=$(cat "$PAK_DIR/roms-folder.txt" 2>/dev/null || printf 'Game Boy*\n')
  oldifs=$IFS; IFS=$NL
  for pattern in $patterns; do
    [ -n "$pattern" ] || continue
    for d in "$SD"/Roms/$pattern; do   # every match: e.g. both "(GBA)" and "(MGBA)"
      if [ -d "$d" ]; then FOLDERS="$FOLDERS${FOLDERS:+$NL}$d"; fi
    done
  done
  IFS=$oldifs
fi
mkdir -p "$DATA/roms" "$DATA/saves" "$DATA/states"

LOG_DIR="${LOGS_PATH:-$PAK_DIR}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/PokeDaisy.txt"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 1048576 ]; then
  mv -f "$LOG" "$LOG.previous"
fi

export POCKET_FULLSCREEN=1
# NextUI-H700 rc11+ exposes the built-in controls as a standard SDL controller,
# so PokeDaisy's SDL GameController path handles them. The TrimUI raw layout is wrong here.
export POCKET_RAW_TRIMUI=0

cd "$PAK_DIR"
echo "=== $(date) PokeDaisy $(sed -n 's/^Commit: //p' SOURCE.txt 2>/dev/null) PLATFORM=${PLATFORM:-?} DEVICE=${DEVICE:-?}" >> "$LOG"

# Show the games folders as PokeDaisy/roms for this session only.
is_mounted() { grep -qs " $DATA/roms " /proc/mounts; }
mounted=0
if is_mounted; then
  umount "$DATA/roms" 2>> "$LOG" || true   # left over from a crash
fi
count=0; first=""; links=""
oldifs=$IFS; IFS=$NL
for d in $FOLDERS; do
  count=$((count + 1))
  [ -n "$first" ] || first=$d
done
IFS=$oldifs
if [ "$count" -ge 1 ]; then
  links=$(mktemp -d "${TMPDIR:-/tmp}/pokedaisy-roms.XXXXXX" 2>/dev/null) || links=""
fi
# Like the Android library, list only Pokemon games: each ROM's header says which game it is.
#   GBA (game code at 0xAC): Ruby AXV, Sapphire AXP, Emerald BPE, FireRed BPR, LeafGreen BPG
#     (hacks built on these keep the base game's code)
#   DS (game code at 0x0C): Diamond ADA, Pearl APA, Platinum CPU, HeartGold IPK, SoulSilver IPG,
#     Black IRB, White IRA, Black 2 IRE, White 2 IRD
#   GB/GBC (title at 0x134): POKEMON RED/BLUE/GREEN/YELLOW, POKEMON_GLD/_SLV, PM_CRYSTAL
#   (main-series games only, like the companion: spin-offs such as Pinball, Puzzle Challenge,
#   Trading Card Game and Mystery Dungeon are left out)
# POKEDAISY_ALL=1 lists every game; without dd nothing is hidden.
header() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | tr -d '\000'; }
is_pokemon() {
  [ "${POKEDAISY_ALL:-0}" = 1 ] && return 0
  command -v dd > /dev/null 2>&1 || return 0
  case "$1" in
    *.gba|*.GBA)
      case "$(header "$1" 172 3)" in AXV|AXP|BPE|BPR|BPG) return 0 ;; esac ;;
    *.nds|*.NDS)
      case "$(header "$1" 12 3)" in ADA|APA|CPU|IPK|IPG|IRB|IRA|IRE|IRD) return 0 ;; esac ;;
    *)
      case "$(header "$1" 308 16)" in 'POKEMON RED'*|'POKEMON BLUE'*|'POKEMON GREEN'*|'POKEMON YELLOW'*|POKEMON_GLD*|POKEMON_SLV*|PM_CRYSTAL*) return 0 ;; esac ;;
  esac
  return 1
}
# Header check on the first bytes of a zip's (first) file, whatever its extension.
is_pokemon_head() {
  [ "${POKEDAISY_ALL:-0}" = 1 ] && return 0
  case "$(header "$1" 172 3)" in AXV|AXP|BPE|BPR|BPG) return 0 ;; esac
  case "$(header "$1" 12 3)" in ADA|APA|CPU|IPK|IPG|IRB|IRA|IRE|IRD) return 0 ;; esac
  case "$(header "$1" 308 16)" in 'POKEMON RED'*|'POKEMON BLUE'*|'POKEMON GREEN'*|'POKEMON YELLOW'*|POKEMON_GLD*|POKEMON_SLV*|PM_CRYSTAL*) return 0 ;; esac
  return 1
}
# Zipped games: PokeDaisy reads only unpacked ROMs, so a Pokemon game's zip is unpacked once into
# PokeDaisy/.unzipped/<zip name>/ (again only when the zip changes). .7z is not supported.
CACHE="$DATA/.unzipped"
unzipped_rom() {   # <zip> -> prints the unpacked ROM's path, or nothing
  z=$1; zname=${z##*/}; dir="$CACHE/$zname"
  stamp="$(wc -c < "$z" | tr -d ' ') $(date -r "$z" +%s 2>/dev/null)"
  if [ ! -f "$dir/.stamp" ] || [ "$(cat "$dir/.stamp")" != "$stamp" ]; then
    rm -rf "$dir" 2>/dev/null; mkdir -p "$dir"
    if unzip -o -q "$z" -d "$dir" >> "$LOG" 2>&1; then echo "$stamp" > "$dir/.stamp"
    else echo "Could not unzip $zname" >> "$LOG"; rm -rf "$dir"; return; fi
  fi
  for r in "$dir"/*.gba "$dir"/*.GBA "$dir"/*.gbc "$dir"/*.GBC "$dir"/*.gb "$dir"/*.GB "$dir"/*.nds "$dir"/*.NDS; do
    [ -f "$r" ] && { echo "$r"; return; }
  done
}
HEAD_TMP="${TMPDIR:-/tmp}/pokedaisy-head.$$"
games=0; skipped=0; zips=0
if [ -n "$links" ]; then
  oldifs=$IFS; IFS=$NL
  for d in $FOLDERS; do
    for f in "$d"/*.gba "$d"/*.GBA "$d"/*.gbc "$d"/*.GBC "$d"/*.gb "$d"/*.GB "$d"/*.nds "$d"/*.NDS; do
      [ -f "$f" ] || continue
      name=${f##*/}
      if ! is_pokemon "$f"; then skipped=$((skipped + 1)); continue; fi
      [ -e "$links/$name" ] || { ln -s "$f" "$links/$name" && games=$((games + 1)); }
    done
    command -v unzip > /dev/null 2>&1 || continue
    for z in "$d"/*.zip "$d"/*.ZIP; do
      [ -f "$z" ] || continue
      unzip -p "$z" 2>/dev/null | dd bs=512 count=1 2>/dev/null > "$HEAD_TMP"
      if ! is_pokemon_head "$HEAD_TMP"; then skipped=$((skipped + 1)); continue; fi
      r=$(unzipped_rom "$z")
      [ -n "$r" ] || continue
      name=${r##*/}
      [ -e "$links/$name" ] || { ln -s "$r" "$links/$name" && games=$((games + 1)) && zips=$((zips + 1)); }
    done
  done
  IFS=$oldifs
fi
if [ -n "$links" ] && { mount --bind "$links" "$DATA/roms" 2>> "$LOG" || mount -o bind "$links" "$DATA/roms" 2>> "$LOG"; }; then
  mounted=1
  rm -f "$HEAD_TMP"
  echo "Pokemon games: $games, $zips of them from zips (other games hidden: $skipped) from: $(printf '%s' "$FOLDERS" | tr '\n' ';')" >> "$LOG"
elif [ "$count" -ge 1 ] && { mount --bind "$first" "$DATA/roms" 2>> "$LOG" || mount -o bind "$first" "$DATA/roms" 2>> "$LOG"; }; then
  mounted=1
  echo "Symlink folder unavailable; games from: $first only" >> "$LOG"
elif [ "$count" -ge 1 ]; then
  echo "Could not mount games folders; listing $DATA/roms instead" >> "$LOG"
else
  echo "No matching Roms folders; listing $DATA/roms instead" >> "$LOG"
fi
cleanup() {
  if [ "$mounted" = 1 ]; then
    sync
    umount "$DATA/roms" 2>> "$LOG" || umount -l "$DATA/roms" 2>> "$LOG" || true
    mounted=0
  fi
  [ -n "$links" ] && rm -rf "$links"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

status=0
./pokedaisy-linux --data "$DATA" "$@" >> "$LOG" 2>&1 || status=$?
echo "=== exit $status" >> "$LOG"
exit "$status"
