#!/bin/sh
# PokeDaisy as a NextUI Tools pak on Anbernic H700 (RG SP etc.), NextUI-H700 rc11 or later.
# POSIX sh only: /bin/sh may be dash on H700.
#
# Games stay in NextUI's own Roms folders: every Roms/ subfolder matching a line of
# roms-folder.txt ("Game Boy Advance*", "Nintendo DS*"). While PokeDaisy runs, a temporary folder
# of symlinks to every game in them is mounted as PokeDaisy/roms (PokeDaisy only lists games
# from <data>/roms). The SD card's FAT/exFAT can't hold symlinks or act as an overlayfs layer,
# so the links live in /tmp. If that fails, the first folder is bind-mounted instead.
# PokeDaisy's own files live OUTSIDE the pak, in $SDCARD_PATH/PokeDaisy/, so replacing the pak
# with a newer build never touches them:
#   PokeDaisy/saves/   battery saves (<full ROM filename>.sav: Emerald.gba.sav, Platinum.nds.sav)
#   PokeDaisy/states/  save states
#   PokeDaisy/roms/    leave empty (mount point)
set -eu
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SD="${SDCARD_PATH:-/mnt/SDCARD}"
DATA="$SD/PokeDaisy"
# Folders to show, one per line.
NL='
'
FOLDERS="${POKEDAISY_ROMS:-}"
if [ -z "$FOLDERS" ]; then
  patterns=$(cat "$PAK_DIR/roms-folder.txt" 2>/dev/null || printf 'Game Boy Advance*\n')
  oldifs=$IFS; IFS=$NL
  for pattern in $patterns; do
    [ -n "$pattern" ] || continue
    for d in "$SD"/Roms/$pattern; do
      if [ -d "$d" ]; then FOLDERS="$FOLDERS${FOLDERS:+$NL}$d"; break; fi
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
games=0
if [ -n "$links" ]; then
  oldifs=$IFS; IFS=$NL
  for d in $FOLDERS; do
    for f in "$d"/*.gba "$d"/*.GBA "$d"/*.gbc "$d"/*.GBC "$d"/*.gb "$d"/*.GB "$d"/*.nds "$d"/*.NDS; do
      [ -f "$f" ] || continue
      name=${f##*/}
      [ -e "$links/$name" ] || { ln -s "$f" "$links/$name" && games=$((games + 1)); }
    done
  done
  IFS=$oldifs
fi
if [ -n "$links" ] && { mount --bind "$links" "$DATA/roms" 2>> "$LOG" || mount -o bind "$links" "$DATA/roms" 2>> "$LOG"; }; then
  mounted=1
  echo "Games ($games) from: $(printf '%s' "$FOLDERS" | tr '\n' ';')" >> "$LOG"
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
