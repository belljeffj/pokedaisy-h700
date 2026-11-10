#!/bin/sh
# Main-menu entry for PokeDaisy. Roms/PokeDaisy (PKDAISY) holds one placeholder per version
# ("PokeDaisy.pkd", "PokeDaisy 1-Screen.pkd"); NextUI lists them and passes the chosen one as $1.
# This hands off to the matching Tools pak, which the PokeDaisy Updater keeps current.
SD="${SDCARD_PATH:-/mnt/SDCARD}"
case "$(basename -- "${1:-}")" in
  *1-Screen*) NAME="PokeDaisy 1-Screen" ;;
  *)          NAME="PokeDaisy" ;;
esac
PAK="$SD/Tools/${PLATFORM:-h700}/$NAME.pak"
if [ -f "$PAK/launch.sh" ]; then
  exec sh "$PAK/launch.sh"
fi
echo "$NAME.pak not found at $PAK" > "${LOGS_PATH:-$SD/.userdata/h700/logs}/PKDAISY.txt"
PRESENTER="$SD/Tools/${PLATFORM:-h700}/PokeDaisy Updater.pak/bin/${PLATFORM:-h700}/minui-presenter"
[ -x "$PRESENTER" ] && "$PRESENTER" --message "$NAME is not installed.\nCopy $NAME.pak into Tools." --timeout 0 --confirm-show --confirm-text "OK"
exit 1
