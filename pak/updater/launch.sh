#!/bin/sh
# PokeDaisy Updater: a NextUI Tools pak (Anbernic H700) that installs the newest builds of the PokeDaisy paks
# you already have, straight from https://github.com/belljeffj/pokedaisy-h700/releases, over Wi-Fi.
#
#   Tools/h700/PokeDaisy.pak           <- newest stable release        (PokeDaisy-h700-<commit>-b<build>.zip)
#   Tools/h700/PokeDaisy 1-Screen.pak  <- newest one-screen pre-release (PokeDaisy-one-screen-h700-...zip)
#   Emus/h700/PKDAISY.pak + Roms/PokeDaisy (PKDAISY)  <- the main-menu shortcut, if you installed it
#   Tools/h700/PokeDaisy Updater.pak   <- itself, first, from pak/updater on the repo's main branch
#
# A pak is only replaced when a newer build exists (each pak's RELEASE.txt names the zip it came from), and
# only after the download unpacked cleanly; the old pak is kept until the new one is in place. Games, saves
# and states live in PokeDaisy/ and the Roms/Saves folders, never inside a pak, so they are not touched.
# Progress is shown on screen with minui-presenter (bin/, MIT, github.com/josegonzalez/minui-presenter);
# details go to "PokeDaisy Updater.txt" in NextUI's logs folder. POSIX sh only (/bin/sh may be dash).
set -u
REPO=belljeffj/pokedaisy-h700
PAK_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TOOLS=$(dirname -- "$PAK_DIR")
SD="${SDCARD_PATH:-/mnt/SDCARD}"
PLAT="${PLATFORM:-h700}"
WORK="$SD/PokeDaisy/.update"
LOG_DIR="${LOGS_PATH:-$PAK_DIR}"
mkdir -p "$LOG_DIR" "$WORK"
LOG="$LOG_DIR/PokeDaisy Updater.txt"
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then mv -f "$LOG" "$LOG.previous"; fi
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# --- on-screen messages -----------------------------------------------------------------------------------
PRESENTER="$PAK_DIR/bin/$PLAT/minui-presenter"
[ -f "$PRESENTER" ] && chmod 755 "$PRESENTER" 2>/dev/null
UI_PID=""
ui_clear() {   # minui-presenter can ignore SIGTERM: ask, wait up to 2 s, then force it (never block on it)
  if [ -n "$UI_PID" ]; then
    kill "$UI_PID" 2>/dev/null
    for _i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$UI_PID" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$UI_PID" 2>/dev/null
    UI_PID=""
  fi
  killall -9 minui-presenter > /dev/null 2>&1 || true
}
show() {     # <message>: stays up while work continues
  ui_clear
  [ -x "$PRESENTER" ] || return 0
  "$PRESENTER" --message "$1" --timeout -1 > /dev/null 2>&1 &
  UI_PID=$!
}
finish() {   # <message>: waits for A, then the updater exits
  ui_clear
  [ -x "$PRESENTER" ] || return 0
  "$PRESENTER" --message "$1" --timeout 0 --confirm-show --confirm-text "OK" > /dev/null 2>&1
}
trap 'ui_clear' EXIT
bar() {      # <percent> -> [#####-----] 50%
  n=$(( $1 / 5 )); b=""; i=0
  while [ $i -lt 20 ]; do if [ $i -lt $n ]; then b="$b#"; else b="$b-"; fi; i=$((i + 1)); done
  echo "[$b] $1%"
}

fetch() {   # <url> <file>
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 20 --speed-limit 1024 --speed-time 60 --max-time 1800 -o "$2" "$1" 2>> "$LOG" && return 0
  fi
  if command -v wget > /dev/null 2>&1; then
    wget -q -T 60 -O "$2" "$1" 2>> "$LOG" && return 0
  fi
  return 1
}
download() {   # <url> <file> <expected bytes> <title>: fetch in the background, show a percentage
  rm -f "$2"
  fetch "$1" "$2" &
  dl=$!; last=-1
  while kill -0 "$dl" 2>/dev/null; do
    if [ "${3:-0}" -gt 0 ]; then
      got=$(stat -c %s "$2" 2>/dev/null || echo 0)
      pct=$(( got * 100 / $3 )); [ $pct -gt 100 ] && pct=100
      if [ $pct -ne $last ]; then show "$4\nDownloading\n$(bar $pct)"; last=$pct; fi
    elif [ $last -lt 0 ]; then
      show "$4\nDownloading..."; last=0
    fi
    sleep 1
  done
  wait "$dl"
}

# First, update this updater itself from the repo and re-run it, so a fixed updater always takes over before
# it does anything else (even if this copy has a bug further down). A download only counts if it is complete
# (ends with the marker line) and parses; the presenter binary is fetched only if it is missing.
RAW="${POKEDAISY_RAW_URL:-https://raw.githubusercontent.com/$REPO/main/pak/updater}"   # override: testing
if [ -z "${POKEDAISY_UPDATER_RERUN:-}" ]; then
  show "PokeDaisy Updater\nChecking for updates..."
  rm -f "$WORK/self.sh"
  if fetch "$RAW/launch.sh" "$WORK/self.sh" && tail -n 1 "$WORK/self.sh" | grep -qx '# end of PokeDaisy Updater' \
     && sh -n "$WORK/self.sh" 2>/dev/null && ! cmp -s "$WORK/self.sh" "$PAK_DIR/launch.sh"; then
    cp "$WORK/self.sh" "$PAK_DIR/.launch.sh.new" && mv -f "$PAK_DIR/.launch.sh.new" "$PAK_DIR/launch.sh" \
      && chmod 755 "$PAK_DIR/launch.sh" && log "PokeDaisy Updater: updated itself; running the new one"
    SELF_UPDATED=1
  fi
  if [ ! -f "$PRESENTER" ]; then
    mkdir -p "$PAK_DIR/bin/$PLAT"
    fetch "$RAW/bin/h700/minui-presenter" "$PAK_DIR/bin/$PLAT/.minui-presenter.new" \
      && mv -f "$PAK_DIR/bin/$PLAT/.minui-presenter.new" "$PRESENTER" && chmod 755 "$PRESENTER"
  fi
  rm -f "$WORK/self.sh"
  if [ -n "${SELF_UPDATED:-}" ]; then
    ui_clear; trap - EXIT
    POKEDAISY_UPDATER_RERUN=1; export POKEDAISY_UPDATER_RERUN
    exec sh "$PAK_DIR/launch.sh" "$@"
  fi
fi

log "=== checking $REPO"
[ -n "$UI_PID" ] || show "PokeDaisy Updater\nChecking for updates..."
rm -rf "$WORK/x" "$WORK/updater" "$WORK/shortcut" "$WORK"/*.zip "$WORK/releases.json" "$WORK/assets.txt" "$WORK/urls.txt" 2>/dev/null
API="${POKEDAISY_RELEASES_URL:-https://api.github.com/repos/$REPO/releases?per_page=30}"   # override: testing
if ! fetch "$API" "$WORK/releases.json"; then
  log "Could not reach GitHub. Is Wi-Fi on?"
  finish "Could not reach GitHub.\nIs Wi-Fi on?"
  exit 1
fi
# "<size> <download link>" per file, newest release first (the API's order). In each asset the size comes
# just before the link.
grep -oE '"size": *[0-9]+|"browser_download_url": *"[^"]*"' "$WORK/releases.json" \
  | awk '/"size"/ { sub(/.*: */, ""); s = $0; next } { sub(/.*: *"/, ""); sub(/"$/, ""); print (s == "" ? 0 : s), $0; s = "" }' \
  > "$WORK/assets.txt"
if [ ! -s "$WORK/assets.txt" ]; then
  log "GitHub answered, but listed no downloads (repo private, or rate-limited?):"
  head -c 300 "$WORK/releases.json" >> "$LOG"; echo >> "$LOG"
  finish "GitHub listed no downloads.\nTry again later."
  exit 1
fi

SUMMARY=""
[ -n "${POKEDAISY_UPDATER_RERUN:-}" ] && SUMMARY="Updater: updated itself"
note() { if [ -z "$SUMMARY" ]; then SUMMARY="$1"; else SUMMARY="$SUMMARY\n$1"; fi; }
build_of() { b=${1##*-b}; echo "b${b%.zip}"; }
label() {   # <pak dir> <zip name> -> "1.5.0.1 (b14)", or "b14" for builds without VERSION.txt
  v=$(head -n 1 "$1/VERSION.txt" 2>/dev/null)
  if [ -n "$v" ]; then echo "$v ($(build_of "$2"))"; else build_of "$2"; fi
}

update_pak() {   # <pak name> <zip name prefix>
  name=$1; prefix=$2; pak="$TOOLS/$name.pak"
  [ -d "$pak" ] || return 0
  line=$(grep "/$prefix[0-9a-f]\{7\}-b[0-9]*\.zip$" "$WORK/assets.txt" | head -n 1)
  if [ -z "$line" ]; then log "$name: no release found"; note "$name: no release found"; return 0; fi
  size=${line%% *}; url=${line#* }; zip=${url##*/}
  have=$(cat "$pak/RELEASE.txt" 2>/dev/null)
  if [ "$have" = "$zip" ]; then log "$name: up to date ($zip)"; note "$name: up to date, $(label "$pak" "$zip")"; return 0; fi
  log "$name: ${have:-unknown build} -> $zip"
  if ! download "$url" "$WORK/$zip" "$size" "Updating $name"; then
    log "$name: download failed"; note "$name: download failed"; return 0
  fi
  show "Updating $name\nInstalling..."
  rm -rf "$WORK/x"; mkdir -p "$WORK/x"
  if ! unzip -o -q "$WORK/$zip" -d "$WORK/x" >> "$LOG" 2>&1; then log "$name: could not unzip"; note "$name: could not unzip"; return 0; fi
  new="$WORK/x/Tools/h700/$name.pak"
  if [ ! -f "$new/pokedaisy-linux" ] || [ ! -f "$new/launch.sh" ]; then log "$name: zip has no $name.pak"; note "$name: bad download"; return 0; fi
  rm -rf "$pak.old"
  if mv "$pak" "$pak.old" && mv "$new" "$pak"; then
    rm -rf "$pak.old"
    chmod 755 "$pak/launch.sh" "$pak/pokedaisy-linux" 2>/dev/null
    log "$name: updated to $zip"; note "$name: updated to $(label "$pak" "$zip")"
  else
    log "$name: could not swap in the new pak; keeping the old one"; note "$name: update failed"
    [ -d "$pak" ] || mv "$pak.old" "$pak"
    rm -f "$WORK/$zip"
    return 0
  fi
  rm -f "$WORK/$zip"
  # Keep this zip's main-menu shortcut for the end.
  if [ -d "$WORK/x/Emus/h700/PKDAISY.pak" ]; then
    rm -rf "$WORK/shortcut"; mkdir -p "$WORK/shortcut"
    mv "$WORK/x/Emus" "$WORK/shortcut/Emus"; [ -d "$WORK/x/Roms" ] && mv "$WORK/x/Roms" "$WORK/shortcut/Roms"
  fi
}

update_pak "PokeDaisy" "PokeDaisy-h700-"
update_pak "PokeDaisy 1-Screen" "PokeDaisy-one-screen-h700-"

# The main-menu shortcut, only if it is installed (Emus/h700/PKDAISY.pak exists).
EMU="$SD/Emus/$PLAT/PKDAISY.pak"
if [ -d "$EMU" ] && [ -f "$WORK/shortcut/Emus/h700/PKDAISY.pak/launch.sh" ]; then
  changed=""
  for f in "$WORK/shortcut/Emus/h700/PKDAISY.pak"/*; do
    [ -f "$f" ] || continue
    cmp -s "$f" "$EMU/${f##*/}" && continue
    cp "$f" "$EMU/.${f##*/}.new" && mv -f "$EMU/.${f##*/}.new" "$EMU/${f##*/}" && changed=1
  done
  chmod 755 "$EMU/launch.sh" 2>/dev/null
  for d in "$WORK/shortcut/Roms"/*; do
    [ -d "$d" ] || continue
    dst="$SD/Roms/${d##*/}"; mkdir -p "$dst"
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      [ -f "$dst/${f##*/}" ] || { cp "$f" "$dst/${f##*/}" && changed=1; }
    done
    [ -f "$dst/Open PokeDaisy.pkd" ] && rm -f "$dst/Open PokeDaisy.pkd" && changed=1   # replaced by one entry per version
  done
  if [ -n "$changed" ]; then log "Main-menu shortcut: updated"; note "Main-menu shortcut: updated"; fi
fi

rm -rf "$WORK/x" "$WORK/updater" "$WORK/shortcut" "$WORK"/*.zip 2>/dev/null
sync
log "=== done"
finish "PokeDaisy Updater\n\n$SUMMARY"
exit 0
# end of PokeDaisy Updater
