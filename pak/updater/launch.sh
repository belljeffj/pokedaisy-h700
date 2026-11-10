#!/bin/sh
# PokeDaisy Updater: a NextUI Tools pak (Anbernic H700) that installs the newest builds of the PokeDaisy paks
# you already have, straight from https://github.com/belljeffj/pokedaisy-h700/releases, over Wi-Fi.
#
#   Tools/h700/PokeDaisy.pak           <- newest stable release        (PokeDaisy-h700-<commit>-b<build>.zip)
#   Tools/h700/PokeDaisy 1-Screen.pak  <- newest one-screen pre-release (PokeDaisy-one-screen-h700-...zip)
#   Tools/h700/PokeDaisy Updater.pak   <- itself, from the same zip, last
#
# A pak is only replaced when a newer build exists (each pak's RELEASE.txt names the zip it came from), and
# only after the download unpacked cleanly; the old pak is kept until the new one is in place. Games, saves
# and states live in PokeDaisy/ and the Roms/Saves folders, never inside a pak, so they are not touched.
# There is no progress screen: it runs, then returns to NextUI. What it did is in "PokeDaisy Updater.txt" in
# NextUI's logs folder. POSIX sh only (/bin/sh may be dash).
set -u
REPO=belljeffj/pokedaisy-h700
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TOOLS=$(dirname -- "$PAK_DIR")
SD="${SDCARD_PATH:-/mnt/SDCARD}"
WORK="$SD/PokeDaisy/.update"
LOG_DIR="${LOGS_PATH:-$PAK_DIR}"
mkdir -p "$LOG_DIR" "$WORK"
LOG="$LOG_DIR/PokeDaisy Updater.txt"
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then mv -f "$LOG" "$LOG.previous"; fi
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

fetch() {   # <url> <file>
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 20 -o "$2" "$1" 2>> "$LOG" && return 0
  fi
  if command -v wget > /dev/null 2>&1; then
    wget -q -O "$2" "$1" 2>> "$LOG" && return 0
  fi
  return 1
}

log "=== checking $REPO"
rm -rf "$WORK/x" "$WORK"/*.zip "$WORK/releases.json" "$WORK/urls.txt" 2>/dev/null
API="${POKEDAISY_RELEASES_URL:-https://api.github.com/repos/$REPO/releases?per_page=30}"   # override: testing
if ! fetch "$API" "$WORK/releases.json"; then
  log "Could not reach GitHub. Is Wi-Fi on?"
  exit 1
fi
# Download links, newest release first (the API's order).
grep -o '"browser_download_url": *"[^"]*"' "$WORK/releases.json" | sed 's/.*: *"\([^"]*\)"$/\1/' > "$WORK/urls.txt"
if [ ! -s "$WORK/urls.txt" ]; then
  log "GitHub answered, but listed no downloads (repo private, or rate-limited?):"
  head -c 300 "$WORK/releases.json" >> "$LOG"; echo >> "$LOG"
  exit 1
fi

update_pak() {   # <pak name> <zip name prefix>
  name=$1; prefix=$2; pak="$TOOLS/$name.pak"
  [ -d "$pak" ] || return 0
  url=$(grep "/$prefix[0-9a-f]\{7\}-b[0-9]*\.zip$" "$WORK/urls.txt" | head -n 1)
  if [ -z "$url" ]; then log "$name: no release found"; return 0; fi
  zip=${url##*/}
  have=$(cat "$pak/RELEASE.txt" 2>/dev/null)
  if [ "$have" = "$zip" ]; then log "$name: up to date ($zip)"; return 0; fi
  log "$name: ${have:-unknown build} -> $zip"
  if ! fetch "$url" "$WORK/$zip"; then log "$name: download failed"; return 0; fi
  rm -rf "$WORK/x"; mkdir -p "$WORK/x"
  if ! unzip -o -q "$WORK/$zip" -d "$WORK/x" >> "$LOG" 2>&1; then log "$name: could not unzip"; return 0; fi
  new="$WORK/x/Tools/h700/$name.pak"
  if [ ! -f "$new/pokedaisy-linux" ] || [ ! -f "$new/launch.sh" ]; then log "$name: zip has no $name.pak"; return 0; fi
  rm -rf "$pak.old"
  if mv "$pak" "$pak.old" && mv "$new" "$pak"; then
    rm -rf "$pak.old"
    chmod 755 "$pak/launch.sh" "$pak/pokedaisy-linux" 2>/dev/null
    log "$name: updated to $zip"
  else
    log "$name: could not swap in the new pak; keeping the old one"
    [ -d "$pak" ] || mv "$pak.old" "$pak"
    return 0
  fi
  # Keep this zip's updater for the end.
  if [ -d "$WORK/x/Tools/h700/PokeDaisy Updater.pak" ]; then
    rm -rf "$WORK/updater"; mv "$WORK/x/Tools/h700/PokeDaisy Updater.pak" "$WORK/updater"
  fi
}

update_pak "PokeDaisy" "PokeDaisy-h700-"
update_pak "PokeDaisy 1-Screen" "PokeDaisy-one-screen-h700-"

# Last: a newer updater from a downloaded zip. Each file is written beside the old one and renamed over
# it, so the copy of this script that is running now is never changed underneath the shell.
if [ -f "$WORK/updater/launch.sh" ] && ! cmp -s "$WORK/updater/launch.sh" "$PAK_DIR/launch.sh"; then
  for f in "$WORK/updater"/*; do
    [ -f "$f" ] || continue
    cp "$f" "$PAK_DIR/.${f##*/}.new" && mv -f "$PAK_DIR/.${f##*/}.new" "$PAK_DIR/${f##*/}"
  done
  chmod 755 "$PAK_DIR/launch.sh" 2>/dev/null
  log "PokeDaisy Updater: updated itself"
fi
rm -rf "$WORK/x" "$WORK/updater" "$WORK"/*.zip 2>/dev/null
sync
log "=== done"
exit 0
