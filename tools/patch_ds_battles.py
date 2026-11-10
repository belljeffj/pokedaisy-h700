"""Turn on DS battle detection (AUTO screen switching, and PANEL where the build has it) for every DS game
PokeDaisy's shared field table knows (pk_nds_field.cpp: Platinum, HeartGold / SoulSilver, Black / White,
Black 2 / White 2), not only the one Platinum dump the Linux companion reads.

Upstream's Linux DS frontend looks the game's field entry up only when the ROM's SHA-1 is the companion's
Platinum dump. The Android app uses the same table for all these games. This patch:
  1. looks the entry up by cart code + revision for any ROM (the companion stays Platinum-only), and
  2. lets the field reader write to game memory (Android's encounter features) only for that Platinum dump,
     so for every other game battle detection only reads.
Fails (non-zero exit) if upstream's code no longer matches, so a build never silently loses it.
"""
import sys
from pathlib import Path
path = Path(sys.argv[1]) / 'linux/dsperate/frontend.cpp'
src = path.read_text()
edits = [
    ('supported?pk_nds_field_game(code,revision):nullptr', 'pk_nds_field_game(code,revision)'),
    ('pk_nds_field_state(field,read32,write32,0)', 'pk_nds_field_state(field,read32,supported?write32:nullptr,0)'),
]
for old, new in edits:
    n = src.count(old)
    if n != 1:
        sys.exit(f'patch_ds_battles: expected one "{old}" in {path}, found {n}; upstream changed, update the patch')
    src = src.replace(old, new)
path.write_text(src)
print(f'patch_ds_battles: battle detection on for every DS game in the field table ({path})')
