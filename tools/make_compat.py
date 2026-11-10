"""Turn upstream's website/src/data/compat.json (the compatibility page's and ROM check's data, exported from the
app's own tables) into compat.txt, the plain list the launcher reads. One fact per line:
  MAXBASE <bytes>          largest retail GBA ROM; bigger files under a retail code are hacks
  RETAIL <code> <rev>      GBA retail cart + revision, supported by header alone
  BASECODE <code>          GBA code hacks reuse (FireRed/Emerald): needs the SHA-1
  OWNCODE <code>           a hack's own GBA code: needs a hack SHA-1
  HACK <sha1>              supported GBA hack build
  TITLE <sha1>             supported retail GBA build under a base code
  GB <sha1>                supported Game Boy / Color build (retail or hack)
  DS <code> <rev>          supported DS cart + revision
  DSHACK <code> <rev> <offset> <word>   DS hack under a retail header, by a 32-bit word in its code
"""
import json, sys
d = json.load(open(sys.argv[1]))
out = [f"MAXBASE {d['maxBaseSize']}"]
out += [f"RETAIL {r['code']} {rev}" for r in d['retail'] for rev in r['revs']]
out += [f"BASECODE {c}" for c in d['baseCodes']]
out += [f"OWNCODE {c}" for c in d.get('hackCodes', {})]
out += [f"HACK {h['sha1']}" for h in d['hacks']]
out += [f"TITLE {s}" for s in d['titles']]
out += [f"GB {g['sha1']}" for g in d['gameBoy']]
out += [f"DS {g['code']} {g['rev']}" for g in d.get('ds', [])]
out += [f"DSHACK {h['code']} {h['rev']} {h['offset']} {h['word']}" for h in d.get('dsHacks', [])]
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
print(f"{len(out)} lines -> {sys.argv[2]}")
