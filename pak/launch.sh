#!/bin/sh
# PokeDaisy as a NextUI Tools pak on Anbernic H700 (RG SP etc.), NextUI-H700 rc11 or later.
# POSIX sh only: /bin/sh may be dash on H700.
#
# Your games, saves and states live OUTSIDE the pak, in $SDCARD_PATH/PokeDaisy/, so replacing
# the pak with a newer build never touches them:
#   PokeDaisy/roms/    your .gba / .gb / .gbc files
#   PokeDaisy/saves/   battery saves (<full ROM filename>.sav)
#   PokeDaisy/states/  save states
set -eu
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SD="${SDCARD_PATH:-/mnt/SDCARD}"
DATA="$SD/PokeDaisy"
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
{
  echo "=== $(date) PokeDaisy $(sed -n 's/^Commit: //p' SOURCE.txt 2>/dev/null) PLATFORM=${PLATFORM:-?} DEVICE=${DEVICE:-?}"
} >> "$LOG" 2>&1
status=0
./pokedaisy-linux --data "$DATA" "$@" >> "$LOG" 2>&1 || status=$?
echo "=== exit $status" >> "$LOG"
exit "$status"
