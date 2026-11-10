"""Scale DS screens (and the DS companion) to fit the display instead of by whole numbers only.

Upstream's Linux DS frontend scales by an integer: on the RG SP's 720x480 panel a 256x192 DS screen is drawn
at 2x (512x384) with wide borders. This patch scales to the largest size that fits with the DS's 4:3 shape kept:
640x480 there, filling the height. The stylus cursor follows the same scale. POCKET_DS_INTEGER=1 at launch
restores whole-number scaling. Fails (non-zero exit) if upstream's code no longer matches.
"""
import sys
from pathlib import Path
path = Path(sys.argv[1]) / 'linux/dsperate/frontend.cpp'
src = path.read_text()
fit = 'float scale=std::getenv("POCKET_DS_INTEGER")?float(std::max(1,std::min(ow/w,oh/h))):std::max(1.0f,std::min(float(ow)/w,float(oh)/h))'
edits = [
    # blit(): the DS screens and the companion
    ('int scale=std::max(1,std::min(ow/w,oh/h));\n  SDL_Rect dst{(ow-w*scale)/2,(oh-h*scale)/2,w*scale,h*scale};',
     fit + ';\n  SDL_Rect dst{int((ow-w*scale)/2),int((oh-h*scale)/2),int(w*scale),int(h*scale)};'),
    # the stylus cursor
    ('int scale=std::max(1,std::min(ow/w,oh/h)),x=(ow-w*scale)/2+',
     fit + ';int x=(ow-w*scale)/2+'),
]
for old, new in edits:
    n = src.count(old)
    if n != 1:
        sys.exit(f'patch_ds_fit: expected one match for "{old[:60]}..." in {path}, found {n}; upstream changed, update the patch')
    src = src.replace(old, new)
if '#include <cstdlib>' not in src:
    src = '#include <cstdlib>\n' + src
path.write_text(src)
print(f'patch_ds_fit: DS screens scale to fit ({path})')
