#!/bin/sh
# Main-menu entry for PokeDaisy: Roms/PokeDaisy (PKDAISY) -> this pak.
# Hands off to the Tools pak, so the PokeDaisy Updater keeps it current.
SD="${SDCARD_PATH:-/mnt/SDCARD}"
PAK="$SD/Tools/${PLATFORM:-h700}/PokeDaisy.pak"
if [ -x "$PAK/launch.sh" ] || [ -f "$PAK/launch.sh" ]; then
  exec sh "$PAK/launch.sh"
fi
echo "PokeDaisy.pak not found at $PAK" > "${LOGS_PATH:-$SD/.userdata/h700/logs}/PKDAISY.txt"
