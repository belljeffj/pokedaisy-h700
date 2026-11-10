#!/bin/sh
# PokeDaisy as a NextUI Tools pak on Anbernic H700 (RG SP etc.), NextUI-H700 rc11 or later.
# POSIX sh only: /bin/sh may be dash on H700.
#
# Games stay in NextUI's own Roms folder: the first Roms/ subfolder matching the pattern in
# roms-folder.txt (GBA pak: "Game Boy Advance*", DS pak: "Nintendo DS*"). PokeDaisy's own files live OUTSIDE the
# pak, in $SDCARD_PATH/PokeDaisy/, so replacing the pak with a newer build never touches them:
#   PokeDaisy/saves/   battery saves (<full ROM filename>.sav, e.g. Emerald.gba.sav, Platinum.nds.sav)
#   PokeDaisy/states/  save states
#   PokeDaisy/roms/    empty: while PokeDaisy runs, ROMS is bind-mounted here
#                      (PokeDaisy only lists games from <data>/roms)
set -eu
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SD="${SDCARD_PATH:-/mnt/SDCARD}"
DATA="$SD/PokeDaisy"
PATTERN=$(head -n 1 "$PAK_DIR/roms-folder.txt" 2>/dev/null || echo 'Game Boy Advance*')
ROMS="${POKEDAISY_ROMS:-}"
if [ -z "$ROMS" ]; then
  oldifs=$IFS; IFS='
'
  for d in "$SD"/Roms/$PATTERN; do
    if [ -d "$d" ]; then ROMS=$d; break; fi
  done
  IFS=$oldifs
fi
ROMS="${ROMS:-$SD/Roms/$PATTERN}"
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

# Show NextUI's games folder as PokeDaisy/roms for this session only.
is_mounted() { grep -qs " $DATA/roms " /proc/mounts; }
mounted=0
if is_mounted; then
  umount "$DATA/roms" 2>> "$LOG" || true   # left over from a crash
fi
if [ -d "$ROMS" ]; then
  if mount --bind "$ROMS" "$DATA/roms" 2>> "$LOG" || mount -o bind "$ROMS" "$DATA/roms" 2>> "$LOG"; then
    mounted=1
    echo "Games from: $ROMS" >> "$LOG"
  else
    echo "Could not bind-mount $ROMS; listing $DATA/roms instead" >> "$LOG"
  fi
else
  echo "No folder $ROMS; listing $DATA/roms instead" >> "$LOG"
fi
cleanup() {
  if [ "$mounted" = 1 ]; then
    sync
    umount "$DATA/roms" 2>> "$LOG" || umount -l "$DATA/roms" 2>> "$LOG" || true
    mounted=0
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

status=0
./pokedaisy-linux --data "$DATA" "$@" >> "$LOG" 2>&1 || status=$?
echo "=== exit $status" >> "$LOG"
exit "$status"
