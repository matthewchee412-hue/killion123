"""Line-for-line Python mirror of AnswerMatcher.luau, run against the exported
bank modules, to check matching behaviour on real data (typos, plurals,
nicknames, used answers, false positives)."""
import re, sys, time, unicodedata
from pathlib import Path

SRC = Path("/home/claude/shrimpillion/out/ShrimpillionAnswers")

def normalize(text):
    s = text.lower()
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("ß", "ss").replace("æ", "ae").replace("œ", "oe").replace("ø", "o")
    s = s.replace("&", "and")
    return re.sub(r"[^a-z0-9]", "", s)

def strip_article(t):
    for art in ("the ", "a ", "an "):
        if t.lower().startswith(art):
            return t[len(art):]
    return t

def load_bank(cid):
    entries, by_key, by_len, by_head = [], {}, {}, {}
    files = sorted(SRC.glob(f"Banks/Bank_{cid}.luau")) or sorted(
        SRC.glob(f"Banks/Bank_{cid}_*.luau"), key=lambda p: int(p.stem.rsplit("_", 1)[1]))
    for f in files:
        body = f.read_text().split("[==[\n", 1)[1].rsplit("\n]==]", 1)[0]
        for line in body.split("\n"):
            if not line:
                continue
            tier = int(line[0]); names = line[1:].split("|")
            idx = len(entries)
            keys = []
            for ni, n in enumerate(names):
                k = normalize(n)
                if not k or k in keys:
                    continue
                keys.append(k)
                if k not in by_key:
                    by_key[k] = []
                    by_len.setdefault(len(k), []).append(k)
                lst = by_key[k]
                if ni == 0:
                    pos = 0
                    while pos < len(lst) and entries[lst[pos]]["keys"][0] == k:
                        pos += 1
                    lst.insert(pos, idx)
                else:
                    lst.append(idx)
            for n in names:
                words = n.replace("-", " ").split(" ")
                if len(words) > 1:
                    head = normalize(words[0])
                    if len(head) >= 5 and not is_common(head):
                        hl = by_head.setdefault(head, [])
                        if idx not in hl: hl.append(idx)
            entries.append({"display": names[0], "tier": tier, "keys": keys})
    return {"entries": entries, "by_key": by_key, "by_len": by_len, "by_head": by_head}

def edit_distance(a, b, maxd):
    la, lb = len(a), len(b)
    if abs(la - lb) > maxd:
        return maxd + 1
    pp, prev = None, list(range(lb + 1))
    for i in range(1, la + 1):
        cur = [i] + [0] * lb
        rowmin = i
        for j in range(1, lb + 1):
            cost = 0 if a[i-1] == b[j-1] else 1
            v = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            if i > 1 and j > 1 and a[i-1] == b[j-2] and a[i-2] == b[j-1]:
                v = min(v, pp[j-2] + 1)
            cur[j] = v
            rowmin = min(rowmin, v)
        if rowmin > maxd:
            return maxd + 1
        pp, prev = prev, cur
    return prev[lb]

def allowed(n):
    return 2 if n >= 10 else 1 if n >= 6 else 0

IRREG = dict(mice="mouse", geese="goose", teeth="tooth", feet="foot", oxen="ox", children="child",
    people="person", men="man", women="woman", lice="louse", octopi="octopus", cacti="cactus",
    fungi="fungus", hippopotami="hippopotamus", platypi="platypus", fish="fish", sheep="sheep",
    deer="deer", moose="moose", squid="squid", shrimps="shrimp", prawns="prawn", dice="die",
    larvae="larva", antennae="antenna", vertebrae="vertebra", phenomena="phenomenon")
def variants(k, common):
    out = []
    def add(v):
        if len(v) >= 3: out.append(v)
    for pl, si in IRREG.items():
        if k.endswith(pl) and pl != si: add(k[:len(k)-len(pl)] + si)
    if k.endswith("ves"): add(k[:-3] + "f"); add(k[:-3] + "fe")
    if k.endswith("ies"): add(k[:-3] + "y")
    if k.endswith("es"):
        stem = k[:-2]
        if stem[-1:] in ("s", "x", "z", "o") or stem[-2:] in ("ch", "sh"): add(stem)
    if k.endswith("s") and not k.endswith("ss"): add(k[:-1])
    if not common:
        if k.endswith("y"): add(k[:-1] + "ies")
        add(k + "s"); add(k + "es")
    return out

_COMMON = None
def is_common(k):
    global _COMMON
    if _COMMON is None:
        blob = (SRC / "CommonWords.luau").read_text().split("[==[", 1)[1].rsplit("]==]", 1)[0]
        _COMMON = set(blob.split(" "))
    return k in _COMMON

def pick(bank, key, used):
    lst = bank["by_key"].get(key)
    if not lst:
        return None, False
    if key in used:
        return lst[0], True
    for i in lst:
        if i not in used:
            return i, False
    return lst[0], True

def fuzzy(bank, key):
    md = allowed(len(key))
    if md == 0:
        return None
    best, bd, tie = None, md + 1, False
    for L in range(len(key) - md, len(key) + md + 1):
        for c in bank["by_len"].get(L, []):
            if c[0] == key[0]:
                d = edit_distance(key, c, md)
                if d < bd:
                    best, bd, tie = c, d, False
                elif d == bd and best is not None and bank["by_key"][c][0] != bank["by_key"][best][0]:
                    tie = True
    return None if tie else best

def check(bank, text, used=frozenset()):
    key = normalize(strip_article(text))
    if not key:
        return ("empty", None, None, False)
    def fin(k, corr):
        i, all_used = pick(bank, k, used)
        if i is None:
            return None
        e = bank["entries"][i]
        tier = e["tier"]
        return ("used" if all_used else "ok", e["display"], tier, corr, i, k)
    r = fin(key, False)
    if r: return r
    common = is_common(key)
    for v in variants(key, common):
        r = fin(v, True)
        if r: return r
    fk = None if common else fuzzy(bank, key)
    if fk:
        r = fin(fk, True)
        if r: return r
    if not common:
        used_hit = None
        for k in [key] + variants(key, False):
            for i in bank["by_head"].get(k, []):
                e = bank["entries"][i]
                if i not in used:
                    return ("ok", e["display"], e["tier"], True, i, e["keys"][0])
                used_hit = used_hit if used_hit is not None else i
        if used_hit is not None:
            e = bank["entries"][used_hit]
            return ("used", e["display"], e["tier"], True, used_hit, e["keys"][0])
    return ("unknown", None, None, False)

TN = ["Shallows", "Reef", "Twilight", "Midnight", "Abyss"]

CASES = {
    "sea_creatures": ["jelly fish", "seahorse", "jellyfish", "Octopus", "octopuss", "OCTOPI", "The Blobfish", "jelly fish", "jellyfishes",
                      "killer whale", "orca", "Mantis Shrimp", "dumbo octopus", "sharks", "whale",
                      "pufferfish", "puffer fish", "blowfish", "nemo", "seahorse", "sea horse",
                      "narwhal", "narwal", "car", "bob", "ocean", "water", "fish"],
    "animals": ["anteater", "anteater", "scaly anteater", "goose", "lamb", "salmon", "wolves", "geese", "dog", "dogs", "doggo", "cat", "aardvark", "anteater", "pangolin", "tardigrade",
                "quokka", "elefant", "giraffe", "giraf", "unicorn", "dragon", "table", "world", "asian"],
    "countries": ["Australia", "aus", "USA", "america", "UK", "england", "Brasil", "Kiribati",
                  "Eswatini", "Swaziland", "New Zeland", "NZ", "Korea", "Antarctica", "Atlantis"],
    "fruits": ["apple", "apples", "banana", "bannana", "berries", "strawberries", "kakadu plum",
               "quandong", "tomato", "pizza"],
    "metals_elements": ["aluminium", "aluminum", "sulphur", "oganesson", "unobtainium", "gold"],
    "shrimp_things": ["shrimp", "prawns", "king prawn", "spencer gulf king prawn", "yabbies",
                      "moreton bay bug", "crab", "lobsters", "krill", "sea monkey"],
    "food_dishes": ["pizza", "club", "club sandwich", "sushi", "spag bol", "chicken parmi", "taco"],
    "colours": ["red", "colour", "teal", "periwinkle", "dark", "earth", "seafoam green"],
    "rivers_lakes": ["nile", "red", "red river", "murray", "murray river", "pacific", "pacific ocean"],
    "sports": ["netball", "footy", "soccer", "afl", "padel", "plunge", "overcast", "sepak takraw", "e sports"],
}

if __name__ == "__main__":
    for cid, words in CASES.items():
        t0 = time.time(); bank = load_bank(cid); t1 = time.time()
        print(f"## {cid}  ({len(bank['entries'])} answers, {len(bank['by_key'])} spellings, load {1000*(t1-t0):.0f} ms)")
        used = set()
        for w in words:
            t0 = time.time()
            r = check(bank, w, used)
            ms = 1000 * (time.time() - t0)
            if r[0] == "ok":
                used.add(r[4]); used.add(r[5]); used.add(bank["entries"][r[4]]["keys"][0])
                print(f"   {w!r:28} -> {r[1]!r:30} {TN[r[2]]:13}{' (forgiven)' if r[3] else ''}  [{ms:.1f} ms]")
            else:
                extra = f" (was {r[1]!r})" if r[1] else ""
                print(f"   {w!r:28} -> {r[0].upper()}{extra}  [{ms:.1f} ms]")
