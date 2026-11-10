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
#   PokeDaisy/.unzipped/  unpacked copies of zipped supported games (safe to delete; rebuilt as needed)
#   PokeDaisy/.verdicts   which files are on the compatibility list (safe to delete)
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
# Like the Android library, list only the games on PokeDaisy's compatibility list
# (https://pokedaisy.com/compatibility/), checked the same way as its ROM check and the app:
#   Game Boy / Color: the ROM's SHA-1 is a supported build (retail or hack)
#   GBA: a supported retail cart + revision (header), or a supported hack / retail build (SHA-1)
#   DS: a supported cart + revision (header), or a DS hack under a retail header (a word in its code)
# The list is compat.txt, made from upstream's own data at every build. Not covered here: trimmed or
# flash-patched retail dumps and Universal Randomizer copies (the app recognises those too).
# Verdicts are cached in PokeDaisy/.verdicts per file size + date and list version.
# POKEDAISY_ALL=1 lists every game.
COMPAT="$PAK_DIR/compat.txt"
VCACHE="$DATA/.verdicts"; NEWV="$VCACHE.new"; : > "$NEWV"
CHECK=1
if [ "${POKEDAISY_ALL:-0}" = 1 ]; then CHECK=0
elif [ ! -s "$COMPAT" ]; then CHECK=0; echo "No compatibility list: listing every game" >> "$LOG"
else
  for t in od dd sha1sum grep; do
    command -v "$t" > /dev/null 2>&1 || { CHECK=0; echo "No $t: listing every game" >> "$LOG"; }
  done
fi
MAXBASE=$(sed -n 's/^MAXBASE //p' "$COMPAT" 2>/dev/null); MAXBASE=${MAXBASE:-16777216}
# Cached verdicts belong to one version of the list: a newer pak's list (new games, new hacks)
# makes every file be checked again.
LISTID=$(cksum < "$COMPAT" 2>/dev/null | cut -d' ' -f1); LISTID=${LISTID:-none}
hexat() { od -An -tx1 -j "$2" -N "$3" "$1" 2>/dev/null | tr -d ' \n'; }
chars() { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null; }
has() { grep -qxF "$1" "$COMPAT"; }
fsize() { wc -c < "$1" | tr -d ' '; }
stamp() { echo "$(fsize "$1") $(date -r "$1" +%s 2>/dev/null || echo 0)"; }
# quick <file holding the ROM's start> <ROM size, or empty>: yes / no / sha (needs the SHA-1)
quick() {
  if [ "$(hexat "$1" 260 4)" = ceed6666 ]; then echo sha; return; fi       # Game Boy logo at 0x104
  if [ "$(hexat "$1" 348 2)" = 56cf ]; then                                 # DS logo checksum at 0x15C
    code=$(chars "$1" 12 4); h=$(hexat "$1" 30 1); rev=$((0x${h:-0}))
    if has "DS $code $rev"; then echo yes; return; fi
    hit=$(grep "^DSHACK $code $rev " "$COMPAT" | while read -r _ _ _ off word; do
      w=$(hexat "$1" "$off" 4); [ ${#w} = 8 ] || continue
      le=$(( 0x$(echo "$w" | cut -c7-8)$(echo "$w" | cut -c5-6)$(echo "$w" | cut -c3-4)$(echo "$w" | cut -c1-2) ))
      [ "$le" = "$word" ] && { echo yes; break; }
    done)
    if [ "$hit" = yes ]; then echo yes; else echo no; fi; return
  fi
  code=$(chars "$1" 172 4)                                                  # GBA game code at 0xAC
  case "$code" in ????) ;; *) echo no; return ;; esac
  case "$code" in *[!A-Z0-9]*) echo no; return ;; esac
  h=$(hexat "$1" 188 1); rev=$((0x${h:-0}))
  if grep -q "^RETAIL $code " "$COMPAT"; then
    if has "RETAIL $code $rev" && { [ -z "$2" ] || [ "$2" -le "$MAXBASE" ]; }; then echo yes; else echo no; fi
    return
  fi
  if has "BASECODE $code" || has "OWNCODE $code"; then echo sha; else echo no; fi
}
# full <ROM>: the verdict with its SHA-1
full() {
  s=$(sha1sum "$1" | cut -d' ' -f1)
  if [ "$(hexat "$1" 260 4)" = ceed6666 ]; then
    if has "GB $s"; then echo yes; else echo no; fi; return
  fi
  if has "HACK $s"; then echo yes; return; fi
  if ! has "OWNCODE $(chars "$1" 172 4)" && [ "$(fsize "$1")" -le "$MAXBASE" ] && has "TITLE $s"; then echo yes; return; fi
  echo no
}
remember() { echo "$1|$2" >> "$NEWV"; echo "$2"; }
cached() { grep -F "$1|" "$VCACHE" 2>/dev/null | head -n 1 | sed 's/.*|//'; }
verdict_file() {   # <ROM>
  [ "$CHECK" = 1 ] || { echo yes; return; }
  key="$LISTID|$(stamp "$1")|$1"; v=$(cached "$key")
  if [ -z "$v" ]; then v=$(quick "$1" "$(fsize "$1")"); [ "$v" = sha ] && v=$(full "$1"); fi
  remember "$key" "$v"
}
# Zipped games: PokeDaisy reads only unpacked ROMs, so a supported game's zip is unpacked once into
# PokeDaisy/.unzipped/<zip name>/ (again only when the zip changes). .7z is not supported.
CACHE="$DATA/.unzipped"
unzipped_rom() {   # <zip> -> prints the unpacked ROM's path, or nothing
  z=$1; zname=${z##*/}; dir="$CACHE/$zname"; st=$(stamp "$z")
  if [ ! -f "$dir/.stamp" ] || [ "$(cat "$dir/.stamp")" != "$st" ]; then
    rm -rf "$dir" 2>/dev/null; mkdir -p "$dir"
    if unzip -o -q "$z" -d "$dir" >> "$LOG" 2>&1; then echo "$st" > "$dir/.stamp"
    else echo "Could not unzip $zname" >> "$LOG"; rm -rf "$dir"; return; fi
  fi
  for r in "$dir"/*.gba "$dir"/*.GBA "$dir"/*.gbc "$dir"/*.GBC "$dir"/*.gb "$dir"/*.GB "$dir"/*.nds "$dir"/*.NDS; do
    [ -f "$r" ] && { echo "$r"; return; }
  done
}
HEAD_TMP="${TMPDIR:-/tmp}/pokedaisy-head.$$"
verdict_zip() {   # <zip>: yes / no; unpacks it when yes
  key="$LISTID|$(stamp "$1")|$1"; v=""
  [ "$CHECK" = 1 ] && v=$(cached "$key")
  if [ -z "$v" ]; then
    if [ "$CHECK" = 1 ]; then
      unzip -p "$1" 2>/dev/null | head -c 262144 > "$HEAD_TMP" || true
      v=$(quick "$HEAD_TMP" "")
    else v=yes; fi
    if [ "$v" = sha ]; then
      r=$(unzipped_rom "$1")
      if [ -n "$r" ]; then v=$(full "$r"); else v=no; fi
      [ "$v" = yes ] || rm -rf "$CACHE/${1##*/}" 2>/dev/null
    fi
  fi
  remember "$key" "$v"
}
games=0; skipped=0; zips=0
if [ -n "$links" ]; then
  oldifs=$IFS; IFS=$NL
  for d in $FOLDERS; do
    for f in "$d"/*.gba "$d"/*.GBA "$d"/*.gbc "$d"/*.GBC "$d"/*.gb "$d"/*.GB "$d"/*.nds "$d"/*.NDS; do
      [ -f "$f" ] || continue
      name=${f##*/}
      if [ "$(verdict_file "$f")" != yes ]; then skipped=$((skipped + 1)); continue; fi
      [ -e "$links/$name" ] || { ln -s "$f" "$links/$name" && games=$((games + 1)); }
    done
    command -v unzip > /dev/null 2>&1 || continue
    for z in "$d"/*.zip "$d"/*.ZIP; do
      [ -f "$z" ] || continue
      if [ "$(verdict_zip "$z")" != yes ]; then skipped=$((skipped + 1)); continue; fi
      r=$(unzipped_rom "$z")
      [ -n "$r" ] || continue
      name=${r##*/}
      [ -e "$links/$name" ] || { ln -s "$r" "$links/$name" && games=$((games + 1)) && zips=$((zips + 1)); }
    done
  done
  IFS=$oldifs
  mv -f "$NEWV" "$VCACHE" 2>/dev/null || true
  rm -f "$HEAD_TMP"
fi
if [ -n "$links" ] && { mount --bind "$links" "$DATA/roms" 2>> "$LOG" || mount -o bind "$links" "$DATA/roms" 2>> "$LOG"; }; then
  mounted=1
  echo "Supported games: $games, $zips of them from zips (other games hidden: $skipped) from: $(printf '%s' "$FOLDERS" | tr '\n' ';')" >> "$LOG"
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
