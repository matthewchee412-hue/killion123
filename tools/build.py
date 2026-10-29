"""Build Shrimpillion answer banks from WordNet + corpora + country data.

Output: out/banks.json  (category -> list of entries)
Each entry: {"d": display, "a": [aliases], "z": zipf, "t": tier}
"""
import json, re, sys, unicodedata
from collections import defaultdict
from pathlib import Path
from nltk.corpus import wordnet as wn
from wordfreq import zipf_frequency

DATA = Path("/home/claude/data")
CORP = DATA / "corpora" / "data"
OUT = Path("/home/claude/shrimpillion/out")
OUT.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- filtering
BAD = set()
for line in (DATA / "ext" / "badwords.txt").read_text().splitlines():
    w = line.strip().lower()
    if w:
        BAD.add(w)
# extra words that are fine in a dictionary but not in a kids' party game
BAD |= {
    "strip poker", "bastard", "bitch", "ass", "arse", "crap", "damn", "hell", "slut", "whore", "tit", "tits",
    "titty", "booby", "boob", "boobs", "nipple", "teat", "udder", "buttock", "buttocks", "butt",
    "rump", "bum", "fanny", "crotch", "groin", "pubis", "scrotum", "testicle", "testis",
    "ovary", "uterus", "womb", "vulva", "vagina", "penis", "clitoris", "foreskin", "prepuce",
    "glans", "perineum", "anus", "rectum", "sphincter", "nymph", "harlot", "concubine",
    "mistress", "gigolo", "pimp", "hooker", "stripper", "escort", "hitman", "executioner",
    "hangman", "torturer", "assassin", "gunman", "terrorist", "bomber", "kamikaze", "dope",
    "marijuana", "cannabis", "hashish", "heroin", "cocaine", "opium", "meth", "crack",
    "ganja", "hemp", "weed", "pot", "joint", "spliff", "reefer", "lsd", "ecstasy",
    "beer", "wine", "vodka", "whisky", "whiskey", "rum", "gin", "brandy", "liqueur", "liquor",
    "cocktail", "lager", "ale", "stout", "sake", "tequila", "champagne", "cider", "mead",
    "bourbon", "scotch", "absinthe", "schnapps", "cigarette", "cigar", "tobacco", "snuff",
    "pipe bomb", "noose", "gallows", "guillotine", "electric chair", "swastika",
    "slave", "slaver", "negro", "coolie", "gypsy", "eskimo", "redskin", "squaw", "jap",
    "chink", "gook", "spic", "wop", "kraut", "dago", "kike", "wetback", "honky", "cracker",
    "mammy", "pickaninny", "darky", "darkie", "nigga", "nigger", "faggot", "fag", "dyke",
    "tranny", "retard", "spastic", "midget", "cripple", "lunatic", "loony", "nutcase",
    "fairy", "pansy", "queer", "homo", "lesbian", "gay", "bisexual", "transsexual",
    "sex", "sexual", "erotic", "porn", "orgy", "bondage", "condom", "contraceptive",
    "diaphragm", "pessary", "dildo", "vibrator", "lingerie", "thong", "g-string", "jockstrap",
    "brassiere", "bra", "panties", "knickers", "codpiece", "garter", "corset", "negligee",
    "bikini", "nightie", "teddy", "breast", "breasts", "bottom", "butt", "bum", "booty",
    "nipples", "bust", "cleavage"
}
# whole phrases (normalised keys) to drop
BAD_KEYS = set()

BAD_SUBSTR = ("testicul", "vagin", "scrot", "bitch", "murder", "hangover", "cannibal", "tobacc",
              "grenade", "pissab", "terrorcore", "slavey", "penis", "penile", "pubic", "pubes",
              "prostat", "uterin", "ovarian", "cervix", "cervical canal", "labia", "mammary",
              "nipple", "clitor", "phallus", "phallic", "seminal", "sperm", "ejacul", "urethr",
              "rectal", "anal canal", "anal sphincter", "perine", "vulv", "gonad", "erotic",
              "brothel", "harem", "nazi", "hitler", "swastika", "suicid", "opium", "hashish",
              "marijuana", "cocaine", "heroin", "absinth", "liqueur", "moonshine", "shooter")

def is_bad(text):
    t = text.lower().replace("_", " ")
    if any(b in t for b in BAD_SUBSTR):
        return True
    toks = re.findall(r"[a-z']+", t)
    if any(tok in BAD for tok in toks):
        return True
    if t in BAD:
        return True
    joined = " ".join(toks)
    for b in BAD:
        if " " in b and b in joined:
            return True
    return False

GENERIC = {
    # role / generic words that would make passes too easy
    "female", "male", "young", "adult", "baby", "pet", "pest", "predator", "prey", "game",
    "stray", "mate", "parent", "offspring", "hybrid", "mutant", "specimen", "creature",
    "beast", "brute", "critter", "varmint", "herbivore", "carnivore", "omnivore",
    "insectivore", "scavenger", "migrant", "feeder", "swimmer", "flier", "flyer", "walker",
    "runner", "grazer", "stock", "livestock", "work animal", "pack animal", "domestic animal",
    "draft animal", "racer", "pedigree", "purebred", "giant", "dwarf", "runt", "peeper",
    "biped", "quadruped", "invertebrate", "vertebrate", "chordate", "larva", "pupa", "imago",
    "nestling", "fledgling", "hatchling", "young bird", "young mammal", "young fish",
    "kid", "fry", "fingerling", "spawner", "breeder", "stud", "dam", "sire", "bitch",
    "cock", "jack", "jenny", "tom", "queen",
    "drone", "worker", "soldier", "nymph", "thing", "object", "item", "part", "piece",
    "unit", "whole", "member", "type", "kind", "sort", "form", "variety", "model",
    "person", "individual", "someone", "somebody", "mortal", "human", "soul", "being",
    "organism", "animal", "plant", "food", "fare", "dish", "meal", "foodstuff", "nutriment",
    "edible", "eatable", "comestible", "produce", "vegetable", "fruit", "drink", "beverage",
    "tool", "device", "implement", "instrument", "machine", "vehicle", "conveyance",
    "craft", "vessel", "container", "receptacle", "clothing", "garment", "wear", "apparel",
    "attire", "dress", "outfit", "covering", "structure", "building", "edifice", "weapon",
    "arm", "fabric", "cloth", "material", "textile", "shape", "form", "figure", "worker",
    "employee", "professional", "pro", "specialist", "expert", "hand", "help", "staff",
    "body part", "organ", "tissue", "toy", "plaything", "furniture", "furnishing",
    "emotion", "feeling", "sport", "athletics", "flower", "bloom", "blossom", "tree", "shrub",
    "bush", "herb", "bird", "fish", "mammal", "reptile", "insect", "bug", "dog", "cat",
    "seafood", "shellfish", "candy", "sweet", "sweets", "confection", "dessert", "bread",
    "cheese", "nut", "sauce", "condiment", "pasta", "noodle", "hat", "shoe", "footwear",
    "city", "town", "country", "nation", "state", "land", "river", "mountain", "island",
    "lake", "gem", "gemstone", "stone", "rock", "jewel", "color", "colour", "hue", "shade",
    "tint", "god", "goddess", "deity", "monster", "element", "metal", "planet", "star",
    "boat", "ship", "car", "auto", "automobile", "machine", "motorcar", "transport",
    "slider", "bottom", "top", "front", "back", "side", "end", "head", "base", "tip",
}

def norm_key(s):
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace("&", "and").replace("ø", "o").replace("æ", "ae").replace("ß", "ss")
    return re.sub(r"[^a-z0-9]", "", s)

def tidy_display(s):
    s = s.replace("_", " ").strip()
    s = re.sub(r"\s+", " ", s)
    if s and s[0].islower():
        s = s[0].upper() + s[1:]
    return s

_genus_cache = {}
def looks_binomial(lemma):
    """Latin binomial/genus names such as 'Quercus_robur' or 'Felis'."""
    parts = lemma.split("_")
    first = parts[0]
    if not first[:1].isupper():
        return False
    if first in _genus_cache:
        return _genus_cache[first]
    res = bool(wn.synsets("genus_" + first))
    _genus_cache[first] = res
    return res

def ok_name(name, allow_codes=False, generic_ok=False):
    disp = tidy_display(name)
    k = norm_key(disp)
    if len(k) < 2 or len(k) > 40:
        return False
    if len(k) < 3 and not allow_codes:
        return False
    if k.isdigit():
        return False
    if is_bad(disp):
        return False
    if disp.lower() in GENERIC and not generic_ok:
        return False
    if k in BAD_KEYS:
        return False
    if re.search(r"[()\[\]/]", disp):
        return False
    return True

# ---------------------------------------------------------------- sources
class G(list):
    """A group of names for one answer. cur=True means hand-checked (skip homonym filters)."""
    def __init__(self, names, cur=False, sense_checked=False):
        super().__init__(names)
        self.cur = cur
        self.sense_checked = sense_checked  # WordNet names already passed the homonym guard

JUNK_PAT = re.compile(r"^(genus|family|order|class|subclass|suborder|superfamily|phylum|capital of|"
                      r"state capital|national capital)\b|\byear old\b|-like$|\b(game|play)$", re.I)
JUNK = {k for k in """world entire grade royal modern man solo man true cat true seal true frog
two-year-old three-year-old big game small white large white kitty tabby calico cat dwarf cat
chips snap murphy pulse cole cos must cooler irish coffee coffee royal cafe royale wish-wash
butter sour cream milk skin double cream triple cream single cream clotted cream cream
host stick spread line of life love line laugh line line of fate depression pocket score scratch
birds fossil turtle crocodile mollusc cetacea dinosaur
""".split("\n") for k in [k.strip()] if k}
JUNK = set()
JUNK_KEYS = set()
for line in """world|entire|grade|royal|modern man|solo man|true cat|true seal|true frog|big game|small white|large white|kitty|tabby|calico cat|dwarf cat|chips|snap|murphy|pulse|cole|cos|must|cooler|irish coffee|coffee royal|cafe royale|wish-wash|butter|sour cream|milk skin|double cream|triple cream|single cream|clotted cream|cream|host|stick|spread|line of life|love line|laugh line|line of fate|depression|pocket|score|scratch|birds|fossil|turtle|crocodile|mollusc|cetacea|dinosaur|not|just|off|right|left|want|used|let|heard|matter|fact|important|different|small|old|full|open|united|sure|free|late|special|close|clear|fine|strong|security|dead|private|high|great|wrong|mean|lost|control|down|good|bad|earth color|road metal|pit run|pay dirt|concentrate|matrix|plasma|ore|crushed rock|bone|ivory|the bottom|the valley|state capital|national capital|home port|free port|port of call|point of entry|legendary creature|character|hero|protagonist|composite|conditions|elements|atmosphere|breath|blow|draft|quiet|wave|air|low|trade|fair|smoke|light air|air current|air mass|air hole|piece of material|remainder|patch|screening|dust cover|drop cloth|ground cloth|chicken wire|safety net|network|web|panel|print|flash|tag|sheet|train|stuff|hair|main course|save-all|c change|set|guest|extension|white goods|field kitchen|off-line equipment|power tool|hand tool|tea bag|tea|sugar|corn sugar|brown sugar|black tea|green tea|english breakfast tea|rose|olive|black olive|green olive|lemon oil|dip|dressing|salt and pepper|breakfast|egg|cake|special|club|western|denver|mother-in-law|red hot|poor boy|st. paul|hot brown|british rail|polish boy|italian beef|fight|running|walking|round|ball|trial|cast|floor|chicago|town ball|hot box|shooting|team play|keep away|three-ball|four-ball|match play|in-fighting|perfect game|no-hit game|day game|night game|field game|court game|ball game|wall game|time attack|ice|water ice|split|kiss|whip|pie shell|snap|overcast|plunge|indigo|clans|evo|vinci|lotto|sucker|royal casino|strafer|poser|wrecker|cooky|attender|lather|salter|mender""".split("|"):
    JUNK.add(line.strip())
    JUNK_KEYS.add(norm_key(line.strip()))

GLOBAL_PRUNE = ["genitalia.n.01", "sex_organ.n.01", "reproductive_organ.n.01",
                "erogenous_zone.n.01", "alcohol.n.01", "drug_of_abuse.n.01", "prison.n.01",
                "brothel.n.01", "gambling_house.n.01", "gambling.n.01", "game_of_chance.n.01",
                "instrument_of_execution.n.01", "instrument_of_punishment.n.01",
                "sexual_desire.n.01", "lust.n.01", "coffin.n.01", "urn.n.01", "body_bag.n.01",
                "slaughterhouse.n.01", "morgue.n.01", "barroom.n.01", "cigarette.n.01",
                "cigar.n.01", "tobacco.n.01", "pipe.n.01", "breast.n.01", "buttocks.n.01",
                "female_internal_reproductive_organ.n.01", "spittoon.n.01", "chamber_pot.n.01",
                "bedpan.n.01", "undergarment.n.01", "nightwear.n.01", "swimsuit.n.01"]
MISSING = set()

def _syn(name):
    try:
        return wn.synset(name)
    except Exception:
        MISSING.add(name)
        return None

_prune_cache = None
def global_prune():
    global _prune_cache
    if _prune_cache is None:
        _prune_cache = set()
        for n in GLOBAL_PRUNE:
            s = _syn(n)
            if s:
                _prune_cache.add(s)
                _prune_cache.update(s.closure(lambda t: t.hyponyms() + t.instance_hyponyms()))
    return _prune_cache

LIVING = {"noun.animal", "noun.food", "noun.plant"}

def main_sense(lemma, syn):
    """Homonym guard: a common word only counts if this category is one of its main
    noun senses ("Red" isn't a river, "Page" isn't a job). For living things the
    meat/plant sense often ranks first ("goose", "lamb", "salmon"), so senses of
    those kinds ahead of it don't count against it."""
    senses = wn.synsets(lemma, "n")
    if syn in senses[:2]:
        return True
    if syn.lexname() in LIVING and syn in senses[:4]:
        lname = lemma.lower()
        for other in senses[: senses.index(syn)]:
            used = sum(l.count() for l in other.lemmas() if l.name().lower() == lname)
            if used > 0 and other.lexname() not in LIVING:
                return False
        return True
    return False

def wordnet_groups(roots, exclude=(), include_root=False, lexnames=None, instances=True,
                   allow_binomial=False, prune=()):
    """exclude: drop just these synsets (generic/role nodes, their children stay).
    prune: drop these synsets AND everything under them."""
    ex = set(global_prune())
    for e in exclude:
        s = _syn(e)
        if s:
            ex.add(s)
    for e in prune:
        s = _syn(e)
        if s:
            ex.add(s)
            ex.update(s.closure(lambda t: t.hyponyms() + t.instance_hyponyms()))
    groups = []
    seen = set()
    for r in roots:
        root = _syn(r)
        if root is None:
            continue
        rel = (lambda t: t.hyponyms() + t.instance_hyponyms()) if instances else (lambda t: t.hyponyms())
        syns = list(root.closure(rel))
        if include_root:
            syns.append(root)
        for s in syns:
            if s in ex or s in seen:
                continue
            seen.add(s)
            if lexnames and s.lexname() not in lexnames:
                continue
            names = []
            for l in s.lemma_names():
                if not allow_binomial and looks_binomial(l):
                    continue
                if not ok_name(l):
                    continue
                disp = tidy_display(l)
                if zipf_frequency(disp, "en") >= 3.6 and not main_sense(l, s):
                    continue
                names.append(disp)
            if names:
                groups.append(G(names, sense_checked=True))
    return groups

def corp(path, key=None, field=None, cur=True):
    d = json.loads((CORP / path).read_text())
    if key is not None:
        d = d[key]
    out = []
    if isinstance(d, dict):
        d = list(d.keys())
    for x in d:
        if isinstance(x, dict):
            x = x[field]
        out.append(G([tidy_display(x)], cur))
    return [g for g in out if ok_name(g[0])]

def corp_nested(path, key):
    d = json.loads((CORP / path).read_text())[key]
    out = []
    for fam in d:
        for m in fam["members"]:
            if ok_name(m):
                out.append(G([tidy_display(m)], True))
    return out

def plain(*names):
    return [G([n], True) for n in names]

def curated(groups):
    return [G(list(g), True) for g in groups]

COUNTRIES = json.loads((DATA / "ext" / "countries.json").read_text())
KNOWN_CODES = {"USA", "UAE", "DRC", "PNG", "PRC", "ROC", "ROK", "DPRK", "KSA", "CAR", "BiH"}

def country_groups():
    out = []
    for c in COUNTRIES:
        if c["name"]["common"] in ("Antarctica",):
            continue
        names = [c["name"]["common"], c["name"]["official"]]
        for a in c.get("altSpellings", []):
            if len(a) <= 3 and a not in KNOWN_CODES:
                continue
            names.append(a)
        if c["name"]["common"] == "United Kingdom":
            names += ["Britain", "Great Britain", "England"]  # England accepted as UK for play
        if c["name"]["common"] == "United States":
            names += ["America", "USA", "US", "United States of America"]
        if c["name"]["common"] == "New Zealand":
            names += ["NZ", "Aotearoa"]
        if c["name"]["common"] == "Australia":
            names += ["Aus", "Oz"]
        if c["name"]["common"] == "United Kingdom":
            names += ["UK"]
        out.append(G([tidy_display(n) for n in dict.fromkeys(names)], True))
    return out

def capital_groups():
    out = []
    for c in COUNTRIES:
        if not (c.get("unMember") or c.get("independent")):
            continue
        for cap in c.get("capital", []):
            out.append(G([tidy_display(cap)], True))
    out += plain("Taipei", "Pristina", "Jerusalem", "Canberra", "Washington DC", "Washington D.C.")
    return out

def element_groups():
    d = json.loads((CORP / "science/elements.json").read_text())["elements"]
    out = []
    for e in d:
        names = [e["name"]]
        if e["name"] == "Aluminum":
            names.append("Aluminium")
        if e["name"] == "Aluminium":
            names.append("Aluminum")
        if e["name"] == "Sulfur":
            names.append("Sulphur")
        if e["name"] == "Cesium":
            names.append("Caesium")
        out.append(G(names, True))
    return out

def planet_groups():
    d = json.loads((CORP / "science/planets.json").read_text())["planets"]
    out = []
    for p in d:
        out.append(G([p["name"]], True))
        for m in p.get("moons", []):
            out.append(G([m], False))
    return out

def colors_groups():
    out = []
    for x in json.loads((CORP / "colors/wikipedia.json").read_text()):
        out.append(G([x["name"]], False))
    for x in json.loads((CORP / "colors/crayola.json").read_text())["colors"]:
        out.append(G([x["color"]], True))
    for x in json.loads((CORP / "colors/xkcd.json").read_text())["colors"]:
        n = x["color"]
        # xkcd survey names are often silly; keep only 1-2 word, non-joke names
        if len(n.split()) <= 2 and not re.search(r"(ish|y)$", n.split()[-1]) \
                and not re.search(r"(again|vomit|puke|poo|poop|snot|booger|barf|diarrhea|bile|bruise|sick|blood|piss|ugly|dirt|mud|crap|shit)", n):
            out.append(G([n], False))
    out += plain("Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Brown", "Black",
                 "White", "Grey", "Gray", "Violet", "Indigo", "Cyan", "Magenta", "Turquoise",
                 "Teal", "Maroon", "Navy", "Beige", "Lavender", "Gold", "Silver", "Crimson",
                 "Scarlet", "Lime", "Olive", "Peach", "Coral", "Salmon", "Mint", "Tan")
    out = [G([tidy_display(g[0])], g.cur) for g in out if ok_name(g[0])]
    return out + [G(["Grey", "Gray"], True)]

def gods_groups():
    out = []
    out += corp("mythology/greek_gods.json", "greek_gods")
    nd = json.loads((CORP / "mythology/norse_gods.json").read_text())["norse_deities"]
    for k in nd:
        for g in nd[k]:
            out.append(G([tidy_display(g)], True))
    out += corp("mythology/egyptian_gods.json", "egyptian_gods", cur=False)
    out += corp("mythology/roman_deities.json", "roman_deities")
    out += curated([["Odin", "Woden", "Wotan"], ["Thor"], ["Ra", "Re"], ["Anubis"], ["Horus"],
            ["Osiris"], ["Isis"], ["Set", "Seth"], ["Thoth"], ["Bastet", "Bast"], ["Sekhmet"],
            ["Ganesha", "Ganesh"], ["Shiva", "Siva"], ["Vishnu"], ["Brahma"], ["Lakshmi"],
            ["Kali"], ["Krishna"], ["Rama"], ["Hanuman"], ["Indra"], ["Agni"],
            ["Amaterasu"], ["Susanoo"], ["Inari"], ["Raijin"], ["Fujin"],
            ["Quetzalcoatl"], ["Huitzilopochtli"], ["Tlaloc"], ["Pele"], ["Maui"],
            ["Tangaroa"], ["Tane"], ["Papatuanuku"], ["Ranginui"], ["Lugh"], ["Dagda"],
            ["Morrigan"], ["Brigid"], ["Perun"], ["Veles"], ["Inti"], ["Viracocha"],
            ["Pachamama"], ["Marduk"], ["Ishtar"], ["Inanna"], ["Enlil"], ["Anu"], ["Ea", "Enki"],
            ["Baal"], ["Mithras"], ["Ahura Mazda"], ["Sun Wukong", "Monkey King"],
            ["Guanyin"], ["Jade Emperor"], ["Nuwa"], ["Pangu"], ["Zeus"], ["Hera"], ["Poseidon"],
            ["Hades"], ["Athena"], ["Apollo"], ["Artemis"], ["Ares"], ["Aphrodite"], ["Hermes"],
            ["Hephaestus"], ["Demeter"], ["Dionysus"], ["Hestia"], ["Persephone"], ["Eros"],
            ["Nike"], ["Pan"], ["Gaia"], ["Kronos", "Cronus"], ["Atlas"], ["Prometheus"],
            ["Jupiter"], ["Juno"], ["Neptune"], ["Pluto"], ["Mars"], ["Venus"], ["Mercury"],
            ["Minerva"], ["Diana"], ["Vulcan"], ["Ceres"], ["Bacchus"], ["Cupid"], ["Janus"],
            ["Saturn"], ["Aurora"], ["Loki"], ["Freya", "Freyja"], ["Frigg"], ["Baldur", "Baldr"],
            ["Tyr"], ["Heimdall"], ["Hel"], ["Njord"], ["Bragi"], ["Idun"], ["Sif"]])
    for r in ["greek_deity.n.01", "roman_deity.n.01", "norse_deity.n.01", "egyptian_deity.n.01",
              "hindu_deity.n.01", "celtic_deity.n.01", "semitic_deity.n.01", "teutonic_deity.n.01",
              "chinese_deity.n.01", "japanese_deity.n.01", "anglo-saxon_deity.n.01",
              "aztec_deity.n.01", "persian_deity.n.01", "phrygian_deity.n.01"]:
        try:
            out += wordnet_groups([r], allow_binomial=True)
        except Exception:
            pass
    return out

def monster_groups():
    out = corp("mythology/monsters.json", "names") + corp("mythology/greek_monsters.json", "greek_monsters")
    out += wordnet_groups(["mythical_monster.n.01", "mythical_being.n.01", "fairy.n.01",
                           "evil_spirit.n.01", "ghost.n.01", "giant.n.03", "dragon.n.02",
                           "spirit.n.04"], allow_binomial=True,
                          prune=["deity.n.01", "angel.n.01"])
    out += plain("Kraken", "Leviathan", "Hydra", "Basilisk", "Griffin", "Phoenix", "Unicorn",
                 "Pegasus", "Minotaur", "Medusa", "Sphinx", "Cerberus", "Banshee", "Werewolf",
                 "Vampire", "Zombie", "Mummy", "Yeti", "Bigfoot", "Sasquatch", "Wendigo", "Kitsune",
                 "Tengu", "Kappa", "Oni", "Yokai", "Bunyip", "Yowie", "Drop bear", "Mermaid",
                 "Merman", "Siren", "Selkie", "Kelpie", "Golem", "Ghoul", "Ghost", "Poltergeist",
                 "Wraith", "Lich", "Gargoyle", "Troll", "Ogre", "Goblin", "Hobgoblin", "Imp",
                 "Gremlin", "Pixie", "Sprite", "Leprechaun", "Elf", "Gnome", "Dragon", "Wyvern",
                 "Chupacabra", "Mothman", "Jersey Devil", "Loch Ness Monster", "Nessie",
                 "Thunderbird", "Roc", "Manticore", "Chimera", "Cyclops", "Centaur", "Satyr",
                 "Harpy", "Scylla", "Charybdis", "Behemoth", "Jormungandr", "Fenrir", "Sleipnir",
                 "Naga", "Garuda", "Rakshasa", "Jinn", "Djinn", "Genie", "Ifrit", "Qilin",
                 "Baku", "Nue", "Tanuki", "Bakeneko", "Nekomata", "Jiangshi", "Draugr",
                 "Wight", "Banshee", "Dullahan", "Headless Horseman", "Bogeyman", "Krampus",
                 "Tikbalang", "Aswang", "Manananggal", "Taniwha", "Bunyip", "Min Min light")
    return out

def sport_groups():
    out = corp("sports/sports.json", "sports", cur=False)
    out += wordnet_groups(["sport.n.01"])
    out += wordnet_groups(["martial_art.n.01"])
    out += [G(["Australian rules football", "AFL", "Aussie rules"], True)]
    out += plain("Australian rules football", "AFL", "Netball", "Rugby league", "Rugby union",
                 "Cricket", "Soccer", "Football", "Basketball", "Tennis", "Golf", "Surfing",
                 "Skateboarding", "Snowboarding", "Esports", "Pickleball", "Padel", "Parkour",
                 "Dodgeball", "Kickball", "Ultimate frisbee", "Disc golf", "Lacrosse", "Hurling",
                 "Gaelic football", "Sepak takraw", "Kabaddi", "Bouldering", "Rock climbing",
                 "Bowling", "Darts", "Snooker", "Pool", "Billiards", "Curling", "Bobsleigh",
                 "Skeleton", "Luge", "Biathlon", "Triathlon", "Marathon", "Water polo")
    return out

def jobs_groups():
    out = corp("humans/occupations.json", "occupations")
    out += wordnet_groups(["worker.n.01", "professional.n.01"], lexnames={"noun.person"},
                          instances=False, exclude=["weekend_warrior.n.01"])
    out += plain("YouTuber", "Streamer", "Influencer", "Game developer", "Programmer",
                 "Software engineer", "Barista", "Firefighter", "Police officer", "Paramedic",
                 "Lifeguard", "Astronaut", "Chef", "Teacher", "Nurse", "Doctor", "Vet",
                 "Veterinarian", "Dentist", "Pilot", "Plumber", "Electrician", "Carpenter",
                 "Lawyer", "Judge", "Scientist", "Farmer", "Fisherman", "Zookeeper",
                 "Marine biologist", "Shrimp farmer")
    return out

def premodern_weapons():
    d = json.loads((CORP / "objects/premodern_weapons.json").read_text())
    out = []
    def walk(x):
        if isinstance(x, str):
            out.append([tidy_display(x)])
        elif isinstance(x, list):
            for y in x: walk(y)
        elif isinstance(x, dict):
            for k, v in x.items():
                if k not in ("description", "source"): walk(v)
    walk(d)
    return [g for g in out if ok_name(g[0])]

def suffixed(path, key, suffix):
    """'Red' alone is too easy for a river; it only counts as 'Red River'."""
    out = []
    for x in json.loads((CORP / path).read_text())[key]:
        n = tidy_display(x["name"])
        full = n if n.lower().endswith(suffix.lower()) else f"{n} {suffix}"
        names = [full]
        if zipf_frequency(n, "en") < 3.6:
            names.append(n)
        out.append(G(names, True))
    return out

def sandwich_groups():
    d = json.loads((CORP / "foods/sandwiches.json").read_text())["sandwiches"]
    out = []
    for x in d:
        n = tidy_display(x["name"])
        if not ok_name(n):
            continue
        low = n.lower()
        if "sandwich" in low or "burger" in low or "roll" in low or "sub" in low.split():
            out.append(G([n], True))
        elif zipf_frequency(n, "en") >= 3.0:
            # "Club" alone is too easy; it only counts as "Club sandwich"
            out.append(G([n + " sandwich"], True))
        else:
            out.append(G([n, n + " sandwich"], True))
    return out

# ---------------------------------------------------------------- categories
# (id, display name, prompt shown to players, builder)
C = []
def cat(cid, name, prompt, build):
    C.append((cid, name, prompt, build))

cat("animals", "Animals", "Name an animal", lambda:
    wordnet_groups(["animal.n.01"], lexnames={"noun.animal"},
                   exclude=["young.n.01", "pest.n.04", "predator.n.02", "game.n.04", "female.n.01",
                            "male.n.01", "domestic_animal.n.01", "work_animal.n.01", "pet.n.01",
                            "stray.n.01", "mate.n.06", "hybrid.n.02", "mutant.n.01", "biped.n.01",
                            "larva.n.01", "pupa.n.01", "embryo.n.02", "feeder.n.06", "migrator.n.02",
                            "molter.n.01", "pureblood.n.01", "racer.n.03", "range_animal.n.01",
                            "creepy-crawly.n.01", "giant.n.04", "scavenger.n.03", "herbivore.n.01",
                            "insectivore.n.02", "omnivore.n.02", "peeper.n.03", "stunt.n.03",
                            "survivor.n.03", "metazoan.n.01", "zooplankton.n.01", "fictional_animal.n.01",
                            "marine_animal.n.01", "flightless_bird.n.01", "night_bird.n.01",
                            "bird_of_passage.n.02", "domestic_cat.n.01", "breeder.n.02"])
    + corp("animals/common.json", "animals") + corp("animals/dogs.json", "dogs", cur=False)
    + corp("animals/cats.json", "cats", cur=False) + corp_nested("animals/birds_north_america.json", "birds")
    + plain("Quokka", "Numbat", "Echidna", "Fossa", "Saiga", "Okapi", "Axolotl", "Tardigrade"))

cat("sea_creatures", "Sea creatures", "Name a sea creature", lambda:
    wordnet_groups(["fish.n.01", "crustacean.n.01", "mollusk.n.01", "cetacean.n.01",
                    "echinoderm.n.01", "coelenterate.n.01", "pinniped_mammal.n.01",
                    "sea_cow.n.01", "sea_turtle.n.01", "sea_snake.n.01", "seabird.n.01",
                    "sponge.n.04", "sea_squirt.n.01", "sea_otter.n.01", "polar_bear.n.01"],
                   lexnames={"noun.animal"},
                   exclude=["young_fish.n.01", "food_fish.n.01", "game_fish.n.01",
                            "freshwater_fish.n.01", "spawner.n.01", "bottom-feeder.n.02",
                            "land_snail.n.01", "garden_snail.n.01", "slug.n.07"])
    + corp("foods/shellfish.json", "fish")
    + plain("Shrimp", "Prawn", "Krill", "Pufferfish", "Blowfish", "Clownfish", "Seahorse",
            "Octopus", "Squid", "Jellyfish", "Starfish", "Sea star", "Sea urchin", "Sea cucumber",
            "Manta ray", "Stingray", "Great white shark", "Hammerhead shark", "Whale shark",
            "Blue whale", "Orca", "Killer whale", "Narwhal", "Beluga", "Dolphin", "Porpoise",
            "Sea turtle", "Sea lion", "Walrus", "Dugong", "Manatee", "Anglerfish", "Moray eel",
            "Barracuda", "Swordfish", "Marlin", "Tuna", "Lobster", "Crab", "Hermit crab",
            "Coral", "Anemone", "Nudibranch", "Mantis shrimp", "Pistol shrimp", "Axolotl",
            "Blobfish", "Vampire squid", "Giant squid", "Colossal squid", "Gulper eel",
            "Lanternfish", "Oarfish", "Sunfish", "Mola mola", "Leafy sea dragon", "Sea pig",
            "Barreleye", "Goblin shark", "Frilled shark", "Yeti crab", "Dumbo octopus",
            "Mimic octopus", "Blue-ringed octopus", "Box jellyfish", "Portuguese man o' war",
            "Sea otter", "Penguin", "Pelican", "Albatross", "Puffin", "Seagull"))

cat("birds", "Birds", "Name a bird", lambda:
    wordnet_groups(["bird.n.01"], lexnames={"noun.animal"},
                   exclude=["young_bird.n.01", "nester.n.02", "night_bird.n.01", "cock.n.04",
                            "hen.n.02", "dickeybird.n.01", "bird_of_passage.n.02",
                            "flightless_bird.n.01", "nonpasserine_bird.n.01", "passerine.n.01",
                            "oscine.n.01", "bird_of_prey.n.01", "game_bird.n.01", "aquatic_bird.n.01",
                            "wading_bird.n.01", "seabird.n.01", "dinornis.n.01"])
    + corp_nested("animals/birds_north_america.json", "birds")
    + plain("Kookaburra", "Galah", "Cockatoo", "Magpie", "Emu", "Cassowary", "Lyrebird",
            "Rainbow lorikeet", "Budgie", "Budgerigar", "Ibis", "Kiwi", "Kea",
            "Pigeon", "Dove", "Sparrow", "Crow", "Raven", "Eagle", "Hawk", "Falcon", "Owl",
            "Parrot", "Flamingo", "Peacock", "Penguin", "Ostrich", "Toucan", "Hummingbird"))

cat("mammals", "Mammals", "Name a mammal", lambda:
    wordnet_groups(["mammal.n.01"], lexnames={"noun.animal"},
                   exclude=["young_mammal.n.01", "female_mammal.n.01", "male.n.01",
                            "placental.n.01", "eutherian_mammal.n.01", "prototherian.n.01",
                            "metatherian.n.01", "pachyderm.n.01", "pest.n.04", "stray.n.01",
                            "mouser.n.01", "lapdog.n.01", "toy_dog.n.01", "hunting_dog.n.01",
                            "working_dog.n.01", "watchdog.n.02", "pooch.n.01", "cur.n.01",
                            "mongrel.n.01", "domestic_cat.n.01"])
    + corp("animals/common.json", "animals")
    + plain("Kangaroo", "Koala", "Wombat", "Platypus", "Echidna", "Quokka", "Wallaby",
            "Tasmanian devil", "Bilby", "Numbat", "Possum", "Sugar glider", "Dingo"))

cat("insects", "Bugs & insects", "Name a bug or insect", lambda:
    wordnet_groups(["insect.n.01", "arachnid.n.01", "centipede.n.01", "millipede.n.01",
                    "woodlouse.n.01", "worm.n.01"], lexnames={"noun.animal"},
                   exclude=["imago.n.01", "queen.n.07", "worker.n.03", "drone.n.03",
                            "soldier.n.02", "nymph.n.03", "defoliator.n.01", "pollinator.n.01",
                            "gallfly.n.03", "social_insect.n.01", "collembolan.n.01"])
    + plain("Ant", "Bee", "Wasp", "Hornet", "Beetle", "Ladybug", "Ladybird", "Butterfly",
            "Moth", "Dragonfly", "Grasshopper", "Cricket", "Cicada", "Cockroach", "Termite",
            "Mosquito", "Fly", "Firefly", "Stick insect", "Praying mantis", "Spider",
            "Tarantula", "Huntsman", "Redback", "Funnel-web", "Scorpion", "Tick", "Mite",
            "Flea", "Louse", "Earwig", "Silverfish", "Weevil", "Aphid", "Centipede",
            "Millipede", "Slater", "Pill bug", "Roly poly", "Earthworm", "Caterpillar", "Christmas beetle",
            "Bogong moth"))

cat("reptiles", "Reptiles & amphibians", "Name a reptile or amphibian", lambda:
    wordnet_groups(["reptile.n.01", "amphibian.n.03"], lexnames={"noun.animal"},
                   exclude=["anapsid.n.01", "diapsid.n.01", "synapsid.n.01", "dinosaur.n.01",
                            "archosaur.n.01", "ornithischian.n.01", "saurischian.n.01",
                            "pterosaur.n.01", "ichthyosaur.n.01", "plesiosaur.n.01"])
    + plain("Frog", "Toad", "Axolotl", "Salamander", "Newt", "Gecko", "Iguana", "Chameleon",
            "Komodo dragon", "Bearded dragon", "Frill-necked lizard", "Thorny devil",
            "Blue-tongue lizard", "Goanna", "Monitor lizard", "Skink", "Crocodile", "Alligator",
            "Caiman", "Gharial", "Turtle", "Tortoise", "Terrapin", "Python", "Cobra", "King cobra",
            "Rattlesnake", "Taipan", "Brown snake", "Tiger snake", "Death adder", "Black mamba",
            "Anaconda", "Boa constrictor", "Viper", "Tuatara", "Cane toad", "Poison dart frog"))

cat("dog_breeds", "Dog breeds", "Name a dog breed", lambda:
    wordnet_groups(["dog.n.01"], lexnames={"noun.animal"},
                   exclude=["puppy.n.01", "pooch.n.01", "cur.n.01", "mongrel.n.01",
                            "lapdog.n.01", "toy_dog.n.01", "hunting_dog.n.01", "working_dog.n.01",
                            "watchdog.n.02", "hound.n.01", "terrier.n.01", "sporting_dog.n.01",
                            "spaniel.n.01", "setter.n.01", "retriever.n.01", "pointer.n.04",
                            "shepherd_dog.n.01", "sled_dog.n.01", "guide_dog.n.01",
                            "police_dog.n.01", "attack_dog.n.01", "bird_dog.n.01",
                            "coach_dog.n.01", "housedog.n.01", "hearing_dog.n.01",
                            "seizure-alert_dog.n.01", "sniffer_dog.n.01", "toy_spaniel.n.01",
                            "toy_terrier.n.01", "wolfhound.n.01", "bulldog.n.01"])
    + corp("animals/dogs.json", "dogs", cur=False)
    + plain("Labrador", "Golden retriever", "German shepherd", "Kelpie", "Australian kelpie",
            "Blue heeler", "Cattle dog", "Australian cattle dog", "Border collie", "Poodle",
            "Cavoodle", "Labradoodle", "Groodle", "Cavalier King Charles Spaniel", "Pug",
            "French bulldog", "Frenchie", "Bulldog", "Beagle", "Dachshund", "Sausage dog",
            "Corgi", "Shih tzu", "Maltese", "Chihuahua", "Pomeranian", "Husky", "Siberian husky",
            "Rottweiler", "Doberman", "Great Dane", "Staffy", "Staffordshire bull terrier",
            "Jack Russell", "Greyhound", "Whippet", "Shiba inu", "Akita", "Samoyed",
            "Bernese mountain dog", "Saint Bernard", "Boxer", "Dalmatian", "Schnauzer"))

cat("cat_breeds", "Cat breeds", "Name a cat breed", lambda:
    corp("animals/cats.json", "cats", cur=False)
    + wordnet_groups(["domestic_cat.n.01"], lexnames={"noun.animal"},
                     exclude=["kitten.n.01", "mouser.n.01", "alley_cat.n.01", "tom.n.02",
                              "tabby.n.02", "gib.n.02"])
    + plain("Ragdoll", "Maine Coon", "Persian", "Siamese", "Bengal", "Sphynx", "British Shorthair",
            "Scottish Fold", "Burmese", "Russian Blue", "Devon Rex", "Cornish Rex", "Abyssinian",
            "Norwegian Forest Cat", "Birman", "Tonkinese", "Savannah", "Munchkin", "Himalayan",
            "Exotic Shorthair", "Oriental", "Bombay", "Manx", "Turkish Van", "Turkish Angora"))

cat("dinosaurs", "Dinosaurs", "Name a dinosaur", lambda:
    corp("animals/dinosaurs.json", "dinosaurs", cur=False)
    + wordnet_groups(["dinosaur.n.01", "pterosaur.n.01", "ichthyosaur.n.01", "plesiosaur.n.01"],
                     lexnames={"noun.animal"}, allow_binomial=True)
    + [["Tyrannosaurus rex", "T rex", "Tyrannosaurus", "T-rex", "Trex"], ["Triceratops"],
       ["Stegosaurus"], ["Velociraptor", "Raptor"], ["Brachiosaurus"], ["Diplodocus"],
       ["Ankylosaurus"], ["Spinosaurus"], ["Pteranodon"], ["Pterodactyl"],
       ["Parasaurolophus"], ["Iguanodon"], ["Allosaurus"], ["Brontosaurus"], ["Apatosaurus"],
       ["Pachycephalosaurus"], ["Carnotaurus"], ["Giganotosaurus"], ["Dilophosaurus"],
       ["Mosasaurus"], ["Plesiosaurus"], ["Compsognathus"], ["Gallimimus"], ["Therizinosaurus"],
       ["Muttaburrasaurus"], ["Australovenator"], ["Diamantinasaurus"], ["Leaellynasaura"],
       ["Minmi"], ["Kunbarrasaurus"]])

cat("fruits", "Fruits", "Name a fruit", lambda:
    wordnet_groups(["edible_fruit.n.01", "berry.n.01", "citrus.n.01", "melon.n.01",
                    "drupe.n.01", "pome.n.01"],
                   lexnames={"noun.food", "noun.plant"},
                   exclude=["crab_apple.n.01", "cooking_apple.n.01", "eating_apple.n.01"])
    + corp("foods/fruits.json", "fruits")
    + plain("Date", "Apple", "Banana", "Orange", "Pear", "Grape", "Strawberry", "Blueberry",
            "Raspberry", "Mango", "Pineapple", "Peach", "Nectarine", "Plum", "Cherry", "Lemon",
            "Lime", "Coconut", "Avocado", "Tomato", "Olive", "Fig", "Apricot", "Kiwi fruit",
            "Dragon fruit", "Pitaya", "Lychee", "Rambutan", "Durian", "Mangosteen", "Jackfruit",
            "Passionfruit", "Feijoa", "Kiwifruit", "Kiwi", "Persimmon", "Pomegranate", "Quince",
            "Finger lime", "Quandong", "Davidson plum", "Lilly pilly", "Muntries", "Kakadu plum",
            "Rockmelon", "Cantaloupe", "Honeydew", "Watermelon", "Mandarin", "Tangerine",
            "Clementine", "Grapefruit", "Pomelo", "Yuzu", "Kumquat", "Calamansi", "Starfruit",
            "Carambola", "Guava", "Papaya", "Pawpaw", "Custard apple", "Cherimoya", "Soursop",
            "Longan", "Loquat", "Salak", "Snake fruit", "Tamarind", "Jabuticaba", "Acai",
            "Goji berry", "Elderberry", "Gooseberry", "Mulberry", "Boysenberry", "Cloudberry"))

cat("vegetables", "Vegetables", "Name a vegetable", lambda:
    wordnet_groups(["vegetable.n.01"], lexnames={"noun.food", "noun.plant"},
                   exclude=["raw_vegetable.n.01", "greens.n.01", "root_vegetable.n.01",
                            "solanaceous_vegetable.n.01", "cruciferous_vegetable.n.01",
                            "legume.n.03", "squash.n.02", "summer_squash.n.02",
                            "winter_squash.n.02", "julienne.n.02", "crudites.n.01"])
    + corp("foods/vegetables.json", "vegetables")
    + plain("Capsicum", "Zucchini", "Eggplant", "Aubergine", "Courgette", "Bok choy",
            "Pak choi", "Gai lan", "Choy sum", "Daikon", "Lotus root", "Bamboo shoot",
            "Kohlrabi", "Kale", "Silverbeet", "Snow pea", "Sugar snap pea", "Edamame",
            "Jerusalem artichoke", "Sweet potato", "Kumara", "Taro", "Cassava", "Yam",
            "Okra", "Fennel", "Leek", "Shallot", "Spring onion", "Scallion", "Warrigal greens"))

cat("food_dishes", "Foods & dishes", "Name a food or dish", lambda:
    wordnet_groups(["dish.n.02", "sandwich.n.01", "soup.n.01", "pizza.n.01", "stew.n.02",
                    "salad.n.01", "casserole.n.01", "dumpling.n.01", "sausage.n.01",
                    "pasta.n.01"], lexnames={"noun.food"},
                   exclude=["course.n.07", "side_dish.n.01", "entree.n.01", "main_course.n.01",
                            "special.n.03", "dessert.n.01", "leftovers.n.01", "fare.n.04"])
    + sandwich_groups()
    + plain("Sushi", "Sashimi", "Ramen", "Pho", "Laksa", "Pad thai", "Fried rice",
            "Dumplings", "Dim sum", "Bao", "Gyoza", "Bibimbap", "Kimchi", "Tteokbokki",
            "Butter chicken", "Biryani", "Curry", "Dal", "Samosa", "Naan", "Tacos", "Burrito",
            "Quesadilla", "Nachos", "Enchilada", "Paella", "Risotto", "Lasagne", "Lasagna",
            "Spaghetti bolognese", "Spag bol", "Carbonara", "Pizza", "Burger", "Hamburger",
            "Hot dog", "Fish and chips", "Meat pie", "Sausage roll", "Chicken parmi",
            "Parmigiana", "Schnitzel", "Snag", "Sausage sizzle", "Pie floater", "Fritz",
            "Kebab", "Yiros", "Gyros", "Souvlaki", "Falafel", "Shawarma", "Hummus",
            "Poke bowl", "Mac and cheese", "Fried chicken", "Chicken nuggets", "Fries", "Chips",
            "Poutine", "Croque monsieur", "Ratatouille", "Bouillabaisse", "Shepherd's pie",
            "Cottage pie", "Roast", "Sunday roast", "Bangers and mash", "Haggis", "Pierogi",
            "Borscht", "Goulash", "Jollof rice", "Injera", "Bunny chow", "Nasi goreng",
            "Rendang", "Satay", "Adobo", "Sisig", "Lumpia", "Banh mi", "Okonomiyaki",
            "Takoyaki", "Tempura", "Katsu", "Udon", "Soba", "Congee", "Peking duck",
            "Mapo tofu", "Kung pao chicken", "Sweet and sour pork", "Spring rolls",
            "Prawn crackers", "Garlic prawns", "Shrimp cocktail", "Prawn cocktail",
            "Shrimp fried rice", "Coconut shrimp", "Shrimp scampi", "Gumbo", "Jambalaya"))

cat("desserts", "Desserts & sweets", "Name a dessert or sweet", lambda:
    wordnet_groups(["dessert.n.01", "cake.n.03", "cookie.n.01", "candy.n.01", "pastry.n.02",
                    "pudding.n.01", "frozen_dessert.n.01", "pie.n.01", "tart.n.02"],
                   lexnames={"noun.food"})
    + corp("foods/breads_and_pastries.json", "pastries")
    + plain("Pavlova", "Lamington", "Tim Tam", "Anzac biscuit", "Fairy bread", "Vanilla slice",
            "Neenish tart", "Frog cake", "Golden gaytime", "Splice", "Weet-Bix slice",
            "Chocolate crackle", "Honey joys", "Caramel slice", "Brownie", "Cheesecake",
            "Tiramisu", "Panna cotta", "Creme brulee", "Gelato", "Ice cream", "Sorbet",
            "Macaron", "Eclair", "Churros", "Donut", "Doughnut", "Cupcake", "Muffin", "Mochi",
            "Baklava", "Gulab jamun", "Bubble tea", "Sticky date pudding", "Apple crumble",
            "Trifle", "Banana split", "Sundae", "Fudge", "Toffee", "Marshmallow", "Lollipop",
            "Fairy floss", "Cotton candy", "Jelly", "Jelly beans", "Gummy bears", "Licorice",
            "Halva", "Turkish delight", "Lollies", "Waffle", "Pancake", "Crepe", "Scone", "Pastel de nata",
            "Portuguese tart", "Egg tart", "Mango pudding", "Mooncake", "Daifuku", "Dorayaki"))

cat("drinks", "Drinks (non-alcoholic)", "Name a drink", lambda:
    wordnet_groups(["beverage.n.01"], lexnames={"noun.food"},
                   exclude=["alcohol.n.01", "drug_of_abuse.n.01", "potion.n.01",
                            "concoction.n.01", "mixer.n.02", "draft.n.08", "refresher.n.02",
                            "nightcap.n.02", "chaser.n.03", "hard_cider.n.01", "punch.n.02",
                            "brew.n.01"])
    + plain("Water", "Milk", "Juice", "Orange juice", "Apple juice", "Lemonade", "Iced tea",
            "Iced coffee", "Coffee", "Tea", "Flat white", "Long black", "Latte", "Cappuccino",
            "Espresso", "Mocha", "Macchiato", "Chai", "Chai latte", "Matcha", "Hot chocolate",
            "Milo", "Milkshake", "Smoothie", "Bubble tea", "Boba", "Coconut water", "Kombucha",
            "Soda", "Soft drink", "Cola", "Ginger beer", "Ginger ale", "Lemon squash",
            "Lemon lime and bitters", "Cordial", "Sparkling water", "Mineral water", "Kefir",
            "Lassi", "Horchata", "Thai iced tea", "Teh tarik", "Yakult", "Iced chocolate",
            "Babyccino", "Sports drink", "Energy drink", "Slushie", "Frappe", "Affogato"))

cat("cheeses", "Cheeses", "Name a cheese", lambda:
    corp("foods/curds.json", "curds", cur=False)
    + wordnet_groups(["cheese.n.01"], lexnames={"noun.food"})
    + plain("Cheddar", "Mozzarella", "Parmesan", "Brie", "Camembert", "Feta", "Halloumi",
            "Gouda", "Edam", "Swiss", "Emmental", "Gruyere", "Blue cheese", "Gorgonzola",
            "Roquefort", "Stilton", "Ricotta", "Mascarpone", "Cream cheese", "Cottage cheese",
            "Paneer", "Manchego", "Pecorino", "Burrata", "Provolone", "Havarti", "Jarlsberg",
            "Colby", "Monterey Jack", "Pepper Jack", "Bocconcini", "Haloumi", "Tasty cheese"))

cat("breads", "Breads & baked goods", "Name a bread or baked good", lambda:
    wordnet_groups(["bread.n.01", "quick_bread.n.01", "roll.n.04", "bun.n.01", "cracker.n.01",
                    "biscuit.n.01"], lexnames={"noun.food"})
    + corp("foods/breads_and_pastries.json", "breads")
    + plain("Sourdough", "Damper", "Turkish bread", "Pita", "Naan", "Roti", "Paratha",
            "Chapati", "Tortilla", "Bagel", "Croissant", "Brioche", "Ciabatta", "Focaccia",
            "Baguette", "Rye bread", "Pumpernickel", "Challah", "Pretzel", "English muffin",
            "Crumpet", "Garlic bread", "Cornbread", "Banana bread", "Hot cross bun",
            "Finger bun", "Scroll", "Milk bread", "Melon pan", "Bao", "Injera", "Lavash",
            "Sangak", "Pide", "Simit", "Matzo", "Damper"))

cat("herbs_spices", "Herbs & spices", "Name a herb or spice", lambda:
    corp("foods/herbs_n_spices.json", "herbs") + corp("foods/herbs_n_spices.json", "spices")
    + corp("foods/herbs_n_spices.json", "mixtures")
    + wordnet_groups(["spice.n.02", "herb.n.02"], lexnames={"noun.food"})
    + plain("Salt", "Pepper", "Black pepper", "Chilli", "Chili flakes", "Paprika",
            "Smoked paprika", "Cumin", "Coriander", "Cilantro", "Turmeric", "Ginger", "Garlic",
            "Cinnamon", "Nutmeg", "Cloves", "Cardamom", "Saffron", "Vanilla", "Oregano",
            "Basil", "Thyme", "Rosemary", "Sage", "Parsley", "Dill", "Mint", "Chives",
            "Lemongrass", "Kaffir lime leaves", "Makrut lime", "Curry leaves", "Bay leaves",
            "Star anise", "Five spice", "Garam masala", "Za'atar", "Sumac", "Wattleseed",
            "Lemon myrtle", "Mountain pepper", "Native thyme", "Saltbush", "Bush tomato"))

cat("sauces", "Sauces & condiments", "Name a sauce or condiment", lambda:
    corp("foods/condiments.json", "condiments")
    + wordnet_groups(["sauce.n.01", "condiment.n.01", "dressing.n.01", "dip.n.04", "relish.n.02",
                      "spread.n.05"], lexnames={"noun.food"},
                     exclude=["spice.n.02", "herb.n.02", "flavorer.n.01", "alcohol.n.01"])
    + plain("Tomato sauce", "Ketchup", "Barbecue sauce", "BBQ sauce", "Mayonnaise", "Mayo",
            "Mustard", "Soy sauce", "Fish sauce", "Oyster sauce", "Hoisin", "Sriracha",
            "Sweet chilli sauce", "Hot sauce", "Tabasco", "Gravy", "Vegemite", "Peanut butter",
            "Nutella", "Jam", "Honey", "Maple syrup", "Golden syrup", "Aioli", "Pesto",
            "Salsa", "Guacamole", "Tzatziki", "Tahini", "Hummus", "Gochujang", "Miso",
            "Teriyaki", "Ranch", "Thousand island", "Caesar dressing", "Vinaigrette",
            "Worcestershire sauce", "Sambal", "XO sauce", "Chilli oil", "Chimichurri",
            "Harissa", "Chutney", "Relish", "Pickles", "Kewpie mayo", "Tartare sauce",
            "Hollandaise", "Bearnaise", "Gravy", "Apple sauce", "Mint sauce", "Cranberry sauce"))

cat("pasta", "Pasta & noodles", "Name a pasta or noodle", lambda:
    wordnet_groups(["pasta.n.02", "noodle.n.01", "pasta.n.01"], lexnames={"noun.food"})
    + plain("Spaghetti", "Penne", "Fusilli", "Farfalle", "Rigatoni", "Linguine", "Fettuccine",
            "Tagliatelle", "Pappardelle", "Orzo", "Macaroni", "Ravioli", "Tortellini",
            "Gnocchi", "Lasagne sheets", "Cannelloni", "Conchiglie", "Orecchiette", "Bucatini",
            "Ditalini", "Rotini", "Angel hair", "Capellini", "Vermicelli", "Ramen", "Udon",
            "Soba", "Rice noodles", "Glass noodles", "Hokkien noodles", "Egg noodles",
            "Lo mein", "Chow mein", "Ho fun", "Shirataki", "Somen", "Pho noodles",
            "Dangmyeon", "Biang biang noodles", "Hand-pulled noodles", "Instant noodles",
            "Mi goreng", "Maggi noodles", "Spatzle", "Pierogi", "Mezzelune", "Agnolotti",
            "Paccheri", "Casarecce", "Gemelli", "Radiatori", "Campanelle", "Cavatappi",
            "Strozzapreti", "Trofie", "Malloreddus", "Pici", "Stelline", "Alphabet pasta"))

cat("nuts_seeds", "Nuts, seeds & beans", "Name a nut, seed or bean", lambda:
    wordnet_groups(["edible_nut.n.01", "bean.n.01", "edible_seed.n.01", "legume.n.03",
                    "pea.n.01"], lexnames={"noun.food", "noun.plant"})
    + plain("Macadamia", "Almond", "Cashew", "Peanut", "Walnut", "Pecan", "Pistachio",
            "Hazelnut", "Brazil nut", "Pine nut", "Chestnut", "Coconut", "Bunya nut",
            "Chia seed", "Flaxseed", "Linseed", "Sunflower seed", "Pumpkin seed", "Pepita",
            "Sesame seed", "Poppy seed", "Hemp seed", "Quinoa", "Kidney bean", "Black bean",
            "Pinto bean", "Chickpea", "Lentil", "Edamame", "Soybean", "Mung bean",
            "Adzuki bean", "Cannellini bean", "Broad bean", "Fava bean", "Butter bean",
            "Lima bean", "Navy bean", "Green bean", "Jelly bean"))

cat("flowers", "Flowers", "Name a flower", lambda:
    wordnet_groups(["flower.n.01"], lexnames={"noun.plant"},
                   exclude=["wildflower.n.01", "bloomer.n.01", "everlasting.n.01",
                            "annual.n.01", "perennial.n.01", "biennial.n.01"])
    + corp("plants/flowers.json", "flowers")
    + plain("Rose", "Tulip", "Daisy", "Sunflower", "Lily", "Orchid", "Lotus", "Waratah",
            "Wattle", "Golden wattle", "Kangaroo paw", "Sturt's desert pea", "Banksia",
            "Bottlebrush", "Grevillea", "Flannel flower", "Hibiscus", "Frangipani",
            "Bird of paradise", "Protea", "Jacaranda", "Cherry blossom", "Sakura", "Peony",
            "Carnation", "Chrysanthemum", "Dahlia", "Marigold", "Lavender", "Lilac", "Jasmine",
            "Gardenia", "Magnolia", "Camellia", "Azalea", "Rhododendron", "Hydrangea",
            "Poppy", "Daffodil", "Iris", "Gerbera", "Snapdragon", "Pansy", "Violet", "Petunia",
            "Begonia", "Geranium", "Bluebell", "Forget-me-not", "Lily of the valley",
            "Edelweiss", "Foxglove", "Hollyhock", "Zinnia", "Cosmos", "Freesia", "Gladiolus",
            "Anemone", "Ranunculus", "Sweet pea", "Wisteria", "Bougainvillea", "Plumeria"))

cat("trees_plants", "Trees & plants", "Name a tree or plant", lambda:
    wordnet_groups(["tree.n.01", "shrub.n.01", "vine.n.01", "fern.n.01", "cactus.n.01",
                    "palm.n.03", "conifer.n.01", "grass.n.01", "succulent.n.01"],
                   lexnames={"noun.plant"},
                   exclude=["bonsai.n.01", "pollard.n.01", "sapling.n.01", "angiospermous_tree.n.01",
                            "gymnospermous_tree.n.01", "fruit_tree.n.01", "shade_tree.n.01",
                            "timber_tree.n.01", "treelet.n.01", "nut_tree.n.01",
                            "deciduous_plant.n.01", "evergreen.n.01", "ornamental.n.01",
                            "bush.n.01"])
    + plain("Gum tree", "Eucalyptus", "River red gum", "Snow gum", "Ghost gum", "Jarrah",
            "Karri", "Coolibah", "Boab", "Baobab", "Moreton Bay fig", "Bunya pine",
            "Wollemi pine", "Grass tree", "Xanthorrhoea", "Paperbark", "Melaleuca",
            "Tea tree", "Wattle", "Acacia", "Sheoak", "Casuarina", "Mallee", "Saltbush",
            "Spinifex", "Oak", "Maple", "Pine", "Birch", "Willow", "Elm", "Ash", "Beech",
            "Cedar", "Redwood", "Sequoia", "Cypress", "Fir", "Spruce", "Yew", "Palm",
            "Coconut palm", "Banyan", "Bamboo", "Bonsai", "Cactus", "Aloe vera", "Venus flytrap",
            "Monstera", "Fiddle leaf fig", "Snake plant", "Peace lily", "Pothos", "Ivy", "Fern",
            "Moss", "Seaweed", "Kelp"))

cat("instruments", "Musical instruments", "Name a musical instrument", lambda:
    wordnet_groups(["musical_instrument.n.01"],
                   exclude=["instrument_of_punishment.n.01"])
    + corp("music/instruments.json", "instruments")
    + plain("Didgeridoo", "Yidaki", "Clapsticks", "Gum leaf", "Ukulele", "Uke", "Guitar",
            "Electric guitar", "Bass guitar", "Piano", "Keyboard", "Synthesiser", "Synth",
            "Drums", "Drum kit", "Violin", "Viola", "Cello", "Double bass", "Harp", "Flute",
            "Piccolo", "Recorder", "Clarinet", "Oboe", "Bassoon", "Saxophone", "Sax",
            "Trumpet", "Trombone", "French horn", "Tuba", "Euphonium", "Cornet", "Bugle",
            "Harmonica", "Accordion", "Bagpipes", "Banjo", "Mandolin", "Sitar", "Tabla",
            "Erhu", "Guzheng", "Pipa", "Koto", "Shamisen", "Taiko", "Shakuhachi", "Gamelan",
            "Kalimba", "Mbira", "Djembe", "Bongos", "Congas", "Cajon", "Marimba", "Xylophone",
            "Glockenspiel", "Vibraphone", "Triangle", "Tambourine", "Cowbell", "Maracas",
            "Castanets", "Steel drum", "Theremin", "Kazoo", "Ocarina", "Pan flute",
            "Hurdy-gurdy", "Lute", "Lyre", "Zither", "Dulcimer", "Bodhran", "Tin whistle",
            "Melodica", "Keytar", "Turntables", "Launchpad", "Handpan", "Hang drum",
            "Gong", "Singing bowl", "Washboard", "Spoons", "Musical saw", "Otamatone"))

cat("music_genres", "Music genres", "Name a music genre", lambda:
    corp("music/genres.json", "genres", cur=False)
    + wordnet_groups(["popular_music.n.01", "jazz.n.02", "rock_'n'_roll.n.01", "folk_music.n.01",
                      "classical_music.n.01", "dance_music.n.01", "religious_music.n.01"],
                     exclude=["song.n.01"])
    + plain("Industrial", "Pop", "Rock", "Hip hop", "Rap", "R&B", "Country", "Jazz", "Blues", "Classical",
            "EDM", "House", "Techno", "Trance", "Dubstep", "Drum and bass", "DnB", "Garage",
            "Grime", "Drill", "Trap", "Phonk", "Lo-fi", "K-pop", "J-pop", "Reggaeton",
            "Afrobeats", "Amapiano", "Reggae", "Ska", "Punk", "Pop punk", "Emo", "Metal",
            "Heavy metal", "Death metal", "Metalcore", "Grunge", "Indie", "Alternative",
            "Folk", "Bluegrass", "Gospel", "Soul", "Funk", "Disco", "Motown", "Synthwave",
            "Vaporwave", "Hyperpop", "Shoegaze", "Ambient", "Opera", "Musical theatre",
            "Sea shanty", "Nightcore", "Jersey club", "Baile funk", "Bossa nova", "Salsa",
            "Tango", "Flamenco", "Cumbia", "Bachata", "Merengue", "Bhangra", "Qawwali"))

cat("sports", "Sports", "Name a sport", sport_groups)

cat("jobs", "Jobs", "Name a job", jobs_groups)

cat("clothing", "Clothing", "Name a piece of clothing", lambda:
    wordnet_groups(["clothing.n.01", "headdress.n.01", "footwear.n.02", "glove.n.02"],
                   lexnames={"noun.artifact"},
                   exclude=["nightwear.n.01", "undergarment.n.01", "swimsuit.n.01",
                            "outerwear.n.01", "neckwear.n.01", "protective_garment.n.01",
                            "sportswear.n.01", "work-clothing.n.01", "costume.n.01",
                            "attire.n.01", "civilian_clothing.n.01", "clothes.n.01",
                            "vestment.n.01", "uniform.n.01", "military_uniform.n.01",
                            "mourning.n.02", "drag.n.06", "finery.n.01", "togs.n.01",
                            "hand-me-down.n.01", "slops.n.02", "wardrobe.n.03",
                            "woman's_clothing.n.01", "menswear.n.01", "children's_clothing.n.01",
                            "knitwear.n.01", "array.n.02"],
                   prune=["seat_belt.n.01", "mask.n.04", "face_mask.n.01"])
    + corp("objects/clothing.json", "clothes")
    + plain("Hoodie", "Jumper", "Sweater", "Cardigan", "Trackies", "Trackpants", "Tracksuit",
            "Jeans", "Shorts", "Boardies", "Boardshorts", "Singlet", "T-shirt", "Tee", "Polo",
            "Shirt", "Blouse", "Skirt", "Dress", "Jacket", "Puffer jacket", "Puffer", "Raincoat",
            "Trench coat", "Coat", "Blazer", "Suit", "Tie", "Bow tie", "Scarf", "Beanie",
            "Bucket hat", "Akubra", "Cap", "Snapback", "Thongs", "Flip-flops", "Ugg boots",
            "Uggs", "Sneakers", "Runners", "Joggers", "Leggings", "Overalls", "Onesie",
            "Pyjamas", "PJs", "Dressing gown", "Robe", "Kimono", "Hanbok", "Sari", "Kilt",
            "Poncho", "Cape", "Wetsuit", "Rashie", "Rash vest", "Budgie smugglers", "Speedos",
            "Socks", "Gloves", "Mittens", "Balaclava", "Headband", "Sunglasses", "Belt",
            "Vest", "Gilet", "Crop top", "Tank top", "Turtleneck", "Parka", "Anorak",
            "Bomber jacket", "Denim jacket", "Leather jacket", "Varsity jacket", "Cargo pants",
            "Chinos", "Culottes", "Dungarees", "Jumpsuit", "Romper", "Tutu", "Sarong", "Toga"))

cat("hats_shoes", "Hats & shoes", "Name a type of hat or shoe", lambda:
    wordnet_groups(["hat.n.01", "cap.n.01", "helmet.n.02", "footwear.n.02", "shoe.n.01",
                    "boot.n.01", "sandal.n.01", "slipper.n.01"], lexnames={"noun.artifact"})
    + plain("Akubra", "Bucket hat", "Beanie", "Baseball cap", "Snapback", "Trucker cap",
            "Top hat", "Bowler hat", "Fedora", "Trilby", "Panama hat", "Cowboy hat",
            "Sombrero", "Beret", "Bonnet", "Sun hat", "Visor", "Hard hat", "Party hat",
            "Crown", "Tiara", "Turban", "Fez", "Flat cap", "Newsboy cap", "Deerstalker",
            "Balaclava", "Ushanka", "Pith helmet", "Conical hat", "Thongs", "Flip-flops",
            "Sneakers", "Runners", "Trainers", "Ugg boots", "Gumboots", "Wellies", "Crocs",
            "Slides", "Sandals", "Slippers", "Loafers", "Brogues", "Oxfords", "Heels",
            "High heels", "Stilettos", "Wedges", "Platforms", "Flats", "Ballet flats",
            "Mary Janes", "Moccasins", "Clogs", "Espadrilles", "Converse", "Vans",
            "Doc Martens", "Chelsea boots", "Cowboy boots", "Hiking boots", "Steel caps",
            "Football boots", "Cleats", "Ice skates", "Roller skates", "Flippers",
            "Snowshoes", "Ski boots", "Tap shoes", "Pointe shoes"))

cat("furniture", "Furniture", "Name a piece of furniture", lambda:
    wordnet_groups(["furniture.n.01", "seat.n.03", "table.n.02", "bed.n.01",
                    "cabinet.n.01", "shelf.n.01", "lamp.n.02"], lexnames={"noun.artifact"},
                   exclude=["furnishing.n.02", "office_furniture.n.01", "lawn_furniture.n.01",
                            "baby_bed.n.01", "seat.n.04"])
    + plain("Couch", "Sofa", "Lounge", "Armchair", "Recliner", "Beanbag", "Ottoman",
            "Footstool", "Stool", "Bar stool", "Chair", "Gaming chair", "Office chair",
            "Rocking chair", "Deck chair", "Bench", "Table", "Coffee table", "Dining table",
            "Desk", "Standing desk", "Bed", "Bunk bed", "Single bed", "Double bed",
            "Queen bed", "King bed", "Sofa bed", "Futon", "Daybed", "Hammock", "Crib", "Cot",
            "Bassinet", "Wardrobe", "Dresser", "Chest of drawers", "Tallboy", "Bedside table",
            "Nightstand", "Bookshelf", "Bookcase", "Cabinet", "Cupboard", "Sideboard",
            "Buffet", "Hutch", "TV unit", "Entertainment unit", "Shoe rack", "Hat stand",
            "Coat rack", "Vanity", "Mirror", "Lamp", "Floor lamp", "Rug", "Chaise longue",
            "Loveseat", "Pouffe", "Throne", "Pew", "Lectern", "Kitchen island", "Workbench"))

cat("tools", "Tools", "Name a tool", lambda:
    wordnet_groups(["tool.n.01", "hand_tool.n.01", "power_tool.n.01", "cutting_implement.n.01",
                    "garden_tool.n.01"], lexnames={"noun.artifact"},
                   exclude=["weapon.n.01", "instrument_of_execution.n.01",
                            "instrument_of_punishment.n.01"])
    + plain("Hammer", "Screwdriver", "Spanner", "Wrench", "Shifter", "Pliers", "Saw",
            "Hacksaw", "Jigsaw", "Circular saw", "Chainsaw", "Drill", "Power drill",
            "Impact driver", "Angle grinder", "Sander", "Chisel", "File", "Rasp", "Plane",
            "Level", "Spirit level", "Tape measure", "Ruler", "Square", "Clamp", "Vice",
            "Allen key", "Hex key", "Socket wrench", "Ratchet", "Crowbar", "Pry bar",
            "Mallet", "Sledgehammer", "Axe", "Hatchet", "Shovel", "Spade", "Rake", "Hoe",
            "Trowel", "Pitchfork", "Secateurs", "Pruners", "Shears", "Wheelbarrow",
            "Whipper snipper", "Lawn mower", "Leaf blower", "Pressure washer", "Soldering iron",
            "Glue gun", "Staple gun", "Nail gun", "Multimeter", "Stud finder", "Utility knife",
            "Stanley knife", "Box cutter", "Wire strippers", "Bolt cutters", "Tin snips",
            "Paintbrush", "Paint roller", "Putty knife", "Caulking gun", "Ladder", "Toolbox",
            "Multitool", "Swiss army knife", "Torch", "Flashlight", "Jack", "Tyre lever",
            "Pickaxe", "Crowbar", "Plunger", "Pipe wrench", "Dremel"))

cat("kitchen", "Things in a kitchen", "Name something in a kitchen", lambda:
    wordnet_groups(["kitchen_utensil.n.01", "cooking_utensil.n.01", "kitchen_appliance.n.01",
                    "cutlery.n.02", "crockery.n.01", "tableware.n.01", "dish.n.01"],
                   lexnames={"noun.artifact"})
    + plain("Fridge", "Refrigerator", "Freezer", "Oven", "Stove", "Cooktop", "Microwave",
            "Air fryer", "Toaster", "Kettle", "Blender", "Food processor", "Stand mixer",
            "Rice cooker", "Slow cooker", "Pressure cooker", "Thermomix", "Dishwasher",
            "Coffee machine", "Sandwich press", "Waffle iron", "Frying pan", "Saucepan", "Pot",
            "Wok", "Baking tray", "Cake tin", "Muffin tray", "Spatula", "Egg flip", "Whisk",
            "Ladle", "Tongs", "Peeler", "Grater", "Colander", "Strainer", "Sieve",
            "Chopping board", "Cutting board", "Knife", "Chef's knife", "Cleaver", "Fork",
            "Spoon", "Teaspoon", "Chopsticks", "Plate", "Bowl", "Mug", "Cup", "Glass",
            "Tupperware", "Cling wrap", "Glad wrap", "Foil", "Baking paper", "Tea towel",
            "Oven mitt", "Apron", "Rolling pin", "Measuring cup", "Scales", "Timer",
            "Can opener", "Bottle opener", "Corkscrew", "Garlic press", "Pestle and mortar",
            "Salad spinner", "Piping bag", "Thermometer", "Lunchbox", "Bin", "Sink", "Tap"))

cat("vehicles", "Vehicles", "Name a vehicle", lambda:
    wordnet_groups(["vehicle.n.01", "craft.n.02", "aircraft.n.01"], lexnames={"noun.artifact"},
                   exclude=["conveyance.n.03", "military_vehicle.n.01", "self-propelled_vehicle.n.01",
                            "wheeled_vehicle.n.01", "public_transport.n.01", "rental.n.01",
                            "renter.n.02", "trailer.n.04", "bomber.n.01"])
    + plain("Car", "Ute", "Ute", "SUV", "Four-wheel drive", "4WD", "Hatchback", "Sedan",
            "Station wagon", "Convertible", "Sports car", "Race car", "Go-kart", "Monster truck",
            "Truck", "Semi-trailer", "Road train", "Bus", "Double-decker bus", "Tram",
            "Train", "Bullet train", "Monorail", "Subway", "Metro", "Taxi", "Uber",
            "Ambulance", "Fire truck", "Fire engine", "Police car", "Garbage truck",
            "Tow truck", "Tractor", "Bulldozer", "Excavator", "Forklift", "Cherry picker",
            "Motorbike", "Motorcycle", "Scooter", "E-scooter", "Moped", "Bicycle", "Bike",
            "E-bike", "Tricycle", "Unicycle", "Skateboard", "Hoverboard", "Segway",
            "Rickshaw", "Tuk-tuk", "Jeepney", "Golf cart", "Quad bike", "Dirt bike",
            "Snowmobile", "Helicopter", "Plane", "Jet", "Glider", "Hot air balloon", "Blimp",
            "Airship", "Drone", "Rocket", "Space shuttle", "Spaceship", "Hovercraft",
            "Submarine", "Boat", "Jet ski", "Caravan", "Campervan", "Motorhome", "Limousine",
            "Hearse", "Tank", "Sleigh", "Horse and cart", "Stagecoach", "Chariot", "Wagon"))

cat("boats", "Boats & ships", "Name a type of boat or ship", lambda:
    wordnet_groups(["vessel.n.02", "boat.n.01", "ship.n.01", "small_boat.n.01"],
                   lexnames={"noun.artifact"})
    + plain("Canoe", "Kayak", "Rowboat", "Dinghy", "Tinny", "Paddle boat", "Pedalo",
            "Raft", "Sailboat", "Yacht", "Catamaran", "Trimaran", "Speedboat", "Jet ski",
            "Ferry", "Cruise ship", "Container ship", "Cargo ship", "Tanker", "Oil tanker",
            "Tugboat", "Barge", "Houseboat", "Fishing boat", "Trawler", "Shrimp boat",
            "Prawn trawler", "Lobster boat", "Pirate ship", "Galleon", "Frigate", "Destroyer",
            "Battleship", "Aircraft carrier", "Submarine", "Gondola", "Junk", "Sampan",
            "Dhow", "Longship", "Viking ship", "Trireme", "Galley", "Clipper", "Schooner",
            "Brig", "Sloop", "Ketch", "Cutter", "Lifeboat", "Rescue boat", "Coast guard cutter",
            "Hovercraft", "Hydrofoil", "Icebreaker", "Paddle steamer", "Riverboat",
            "Steamboat", "Narrowboat", "Pontoon", "Outrigger", "Dragon boat", "Surf ski",
            "Stand-up paddleboard", "SUP", "Inflatable", "Zodiac", "RIB", "Banana boat"))

cat("buildings", "Buildings & places", "Name a type of building or place", lambda:
    wordnet_groups(["building.n.01", "place_of_worship.n.01", "shop.n.01", "restaurant.n.01",
                    "school.n.02", "hospital.n.01", "dwelling.n.01"],
                   lexnames={"noun.artifact"},
                   exclude=["prison.n.01", "brothel.n.01", "gambling_house.n.01",
                            "barroom.n.01", "slaughterhouse.n.01", "morgue.n.01",
                            "crematory.n.02", "whorehouse.n.01", "opium_den.n.01",
                            "speakeasy.n.01"])
    + plain("House", "Apartment", "Unit", "Flat", "Townhouse", "Mansion", "Castle", "Palace",
            "Cottage", "Cabin", "Igloo", "Treehouse", "Skyscraper", "Tower", "Lighthouse",
            "School", "Hospital", "Library", "Museum", "Art gallery", "Cinema", "Theatre",
            "Stadium", "Arena", "Gym", "Pool", "Supermarket", "Shopping centre", "Mall",
            "Servo", "Petrol station", "Bakery", "Cafe", "Restaurant", "Fish and chip shop",
            "Milk bar", "Deli", "Takeaway", "Food court", "Bank", "Post office", "Police station",
            "Fire station", "Train station", "Airport", "Hotel", "Motel", "Hostel", "Church",
            "Mosque", "Temple", "Synagogue", "Cathedral", "Factory", "Warehouse", "Barn",
            "Shed", "Garage", "Office", "Town hall", "Parliament House", "Aquarium", "Zoo",
            "Theme park", "Water park", "Bowling alley", "Arcade", "Skate park", "Observatory",
            "Planetarium", "Greenhouse", "Windmill", "Pagoda", "Pyramid", "Colosseum",
            "Amphitheatre", "Bunker", "Fort", "Embassy", "University", "Kindergarten"))

cat("containers", "Containers", "Name a type of container", lambda:
    wordnet_groups(["container.n.01", "bag.n.01", "box.n.01", "bottle.n.01", "jar.n.01",
                    "basket.n.01", "vessel.n.03"], lexnames={"noun.artifact"},
                   prune=["wheeled_vehicle.n.01", "conveyance.n.03", "vehicle.n.01", "craft.n.02",
                          "building.n.01", "skin.n.01", "well.n.01", "bank.n.04"],
                   exclude=["coffin.n.01", "urn.n.01", "body_bag.n.01", "spittoon.n.01",
                            "chamber_pot.n.01", "bedpan.n.01", "ashtray.n.01", "humidor.n.01",
                            "snuffbox.n.01", "tobacco_pouch.n.01", "wine_bottle.n.01",
                            "beer_bottle.n.01", "keg.n.02", "hip_flask.n.01", "decanter.n.01",
                            "carafe.n.01"])
    + plain("Box", "Bag", "Backpack", "Esky", "Cooler", "Lunchbox", "Tupperware", "Jar",
            "Bottle", "Can", "Tin", "Bucket", "Bin", "Wheelie bin", "Basket", "Crate",
            "Barrel", "Chest", "Treasure chest", "Suitcase", "Briefcase", "Wallet", "Purse",
            "Pencil case", "Envelope", "Parcel", "Carton", "Milk crate", "Shipping container",
            "Tote bag", "Bum bag", "Fanny pack", "Drink bottle", "Thermos", "Vase", "Bowl",
            "Mug", "Cup", "Pot", "Kettle", "Jug", "Pitcher", "Tank", "Silo", "Vault", "Safe",
            "Locker", "Drawer", "Piggy bank", "Jewellery box", "Shoebox", "Gift box",
            "Lolly bag", "Party bag", "Snow globe", "Fishbowl", "Aquarium", "Birdcage",
            "Kennel", "Hamper", "Picnic basket", "Pinata"))

cat("weapons", "Medieval & fantasy weapons", "Name a medieval or fantasy weapon", lambda:
    wordnet_groups(["sword.n.01", "knife.n.02", "spear.n.01", "bow.n.04", "pike.n.03",
                    "battle-ax.n.01", "club.n.03", "shield.n.02", "armor.n.01",
                    "body_armor.n.01", "catapult.n.01", "crossbow.n.01", "mace.n.04",
                    "polearm.n.01", "dagger.n.01", "lance.n.01", "javelin.n.02"],
                   lexnames={"noun.artifact"})
    + premodern_weapons()
    + plain("Sword", "Longsword", "Broadsword", "Greatsword", "Claymore", "Katana",
            "Wakizashi", "Rapier", "Sabre", "Scimitar", "Cutlass", "Dagger", "Dirk", "Stiletto",
            "Kunai", "Shuriken", "Throwing star", "Nunchucks", "Bo staff", "Quarterstaff",
            "Spear", "Trident", "Pike", "Halberd", "Glaive", "Naginata", "Lance", "Javelin",
            "Axe", "Battle axe", "Tomahawk", "Mace", "Morning star", "Flail", "Warhammer",
            "Club", "Boomerang", "Woomera", "Nulla nulla", "Bow", "Longbow", "Crossbow",
            "Slingshot", "Sling", "Blowgun", "Catapult", "Trebuchet", "Ballista",
            "Battering ram", "Shield", "Buckler", "Scythe", "Sickle", "Kama", "Sai", "Tonfa",
            "Whip", "Lasso", "Bolas", "Net", "Harpoon", "Magic wand", "Staff", "Lightsaber",
            "Excalibur", "Mjolnir", "Keyblade", "Gunblade", "Chakram", "Khopesh", "Gladius",
            "Zweihander", "Estoc", "Falchion", "Kukri", "Machete", "Kris"))

cat("gems_rocks", "Gems, rocks & minerals", "Name a gem, rock or mineral", lambda:
    corp("materials/gemstones.json", "gemstones")
    + wordnet_groups(["gem.n.02", "transparent_gem.n.01", "opaque_gem.n.01", "rock.n.02",
                      "mineral.n.01"], lexnames={"noun.substance", "noun.object", "noun.artifact"},
                     exclude=["salt.n.02"])
    + plain("Opal", "Black opal", "Boulder opal", "Diamond", "Pink diamond", "Ruby", "Sapphire",
            "Emerald", "Amethyst", "Topaz", "Garnet", "Pearl", "South Sea pearl", "Jade",
            "Turquoise", "Aquamarine", "Peridot", "Citrine", "Tanzanite", "Tourmaline",
            "Moonstone", "Onyx", "Obsidian", "Quartz", "Rose quartz", "Agate", "Jasper",
            "Lapis lazuli", "Malachite", "Amber", "Coral", "Granite", "Marble", "Basalt",
            "Sandstone", "Limestone", "Slate", "Shale", "Pumice", "Chalk", "Flint", "Gold",
            "Gold nugget", "Silver", "Copper", "Iron ore", "Coal", "Crystal", "Geode",
            "Fluorite", "Pyrite", "Fool's gold", "Mica", "Talc", "Gypsum", "Halite"))

cat("metals_elements", "Chemical elements", "Name a chemical element", element_groups)

cat("colours", "Colours", "Name a colour", colors_groups)

cat("fabrics", "Fabrics & materials", "Name a fabric or material", lambda:
    corp("materials/fabrics.json", "fabrics", cur=False)
    + wordnet_groups(["fabric.n.01"], lexnames={"noun.artifact"})
    + plain("Cotton", "Wool", "Merino", "Silk", "Linen", "Denim", "Leather", "Suede",
            "Velvet", "Corduroy", "Fleece", "Polyester", "Nylon", "Spandex", "Lycra",
            "Elastane", "Rayon", "Viscose", "Bamboo fabric", "Cashmere", "Mohair", "Alpaca",
            "Angora", "Satin", "Chiffon", "Lace", "Tulle", "Organza", "Tweed", "Flannel",
            "Canvas", "Hessian", "Burlap", "Felt", "Gore-Tex", "Neoprene", "Kevlar",
            "Vinyl", "Faux fur", "Sherpa", "Jersey", "Muslin", "Calico", "Gingham",
            "Chambray", "Seersucker", "Terry cloth", "Microfibre", "Oilskin", "Drizabone"))

cat("body_parts", "Body parts", "Name a body part", lambda:
    wordnet_groups(["external_body_part.n.01", "bone.n.01", "muscle.n.01", "internal_organ.n.01",
                    "gland.n.01", "joint.n.01", "digit.n.03", "tooth.n.01", "blood_vessel.n.01",
                    "nerve.n.01"],
                   lexnames={"noun.body"},
                   exclude=["genitalia.n.01", "sex_organ.n.01", "reproductive_organ.n.01",
                            "erogenous_zone.n.01", "buttocks.n.01", "breast.n.01",
                            "female_internal_reproductive_organ.n.01"])
    + corp("humans/bodyParts.json", "bodyParts")
    + plain("Head", "Face", "Eye", "Eyebrow", "Eyelash", "Eyelid", "Nose", "Nostril", "Mouth",
            "Lip", "Tongue", "Tooth", "Teeth", "Gums", "Chin", "Cheek", "Jaw", "Ear", "Earlobe",
            "Forehead", "Temple", "Neck", "Throat", "Shoulder", "Arm", "Elbow", "Forearm",
            "Wrist", "Hand", "Palm", "Finger", "Thumb", "Knuckle", "Fingernail", "Chest",
            "Stomach", "Tummy", "Belly button", "Navel", "Hip", "Waist", "Leg", "Thigh",
            "Knee", "Kneecap", "Shin", "Calf", "Ankle", "Heel", "Foot", "Toe", "Big toe",
            "Toenail", "Skin", "Hair", "Brain", "Heart", "Lungs", "Liver", "Kidney",
            "Spleen", "Pancreas", "Appendix", "Intestines", "Bladder", "Skeleton", "Skull",
            "Spine", "Rib", "Pelvis", "Femur", "Tibia", "Fibula", "Humerus", "Radius", "Ulna",
            "Collarbone", "Clavicle", "Shoulder blade", "Scapula", "Funny bone", "Biceps",
            "Triceps", "Abs", "Quads", "Hamstring", "Glutes", "Achilles tendon", "Tonsils",
            "Uvula", "Armpit", "Freckle", "Dimple", "Pinky", "Ring finger", "Index finger",
            "Infraorbital nerve", "Supraorbital nerve", "Maxillary nerve", "Mandibular nerve",
            "Trigeminal nerve", "Facial nerve", "Optic nerve", "Olfactory nerve", "Auditory nerve",
            "Vagus nerve", "Phrenic nerve", "Median nerve", "Ulnar nerve", "Radial nerve",
            "Sciatic nerve", "Femoral nerve", "Tibial nerve", "Peroneal nerve", "Spinal cord",
            "Infraorbital foramen", "Eye socket", "Orbit", "Nasal cavity", "Sinus", "Septum"))

cat("emotions", "Feelings & emotions", "Name a feeling or emotion", lambda:
    wordnet_groups(["emotion.n.01", "feeling.n.01"], lexnames={"noun.feeling"},
                   exclude=["sexual_desire.n.01", "lust.n.01", "passion.n.05", "hate.n.01",
                            "conditioned_emotional_response.n.01"])
    + corp("humans/moods.json", "moods", cur=False)
    + plain("Happy", "Sad", "Angry", "Scared", "Excited", "Nervous", "Anxious", "Bored",
            "Calm", "Proud", "Jealous", "Embarrassed", "Confused", "Surprised", "Disgusted",
            "Lonely", "Grateful", "Hopeful", "Shy", "Brave", "Grumpy", "Hangry", "Silly",
            "Curious", "Frustrated", "Overwhelmed", "Relieved", "Content", "Joy", "Fear",
            "Anger", "Sadness", "Disgust", "Surprise", "Love", "Envy", "Pride", "Shame",
            "Guilt", "Awe", "Nostalgia", "Boredom", "Excitement", "Amusement", "Hope"))

cat("toys_games", "Toys & games", "Name a toy or game", lambda:
    wordnet_groups(["plaything.n.01", "board_game.n.01", "card_game.n.01", "child's_game.n.01",
                    "outdoor_game.n.01", "parlor_game.n.01", "puzzle.n.02"],
                   exclude=["gambling.n.01", "game_of_chance.n.01", "lottery.n.02",
                            "russian_roulette.n.01", "strip_poker.n.01", "kiss.n.01"])
    + corp("games/board_games.json", "games", cur=False)
    + plain("Lego", "Teddy bear", "Doll", "Barbie", "Action figure", "Yo-yo", "Kite",
            "Frisbee", "Slinky", "Rubik's cube", "Fidget spinner", "Pop it", "Squishy",
            "Slime", "Play-Doh", "Marbles", "Jacks", "Jump rope", "Skipping rope",
            "Hula hoop", "Pogo stick", "Spinning top", "Beyblade", "Water gun", "Nerf gun",
            "Bubbles", "Jigsaw puzzle", "Rocking horse", "Dollhouse", "Toy car", "Hot Wheels",
            "Remote control car", "Drone", "Magic 8 ball", "Etch A Sketch", "Tamagotchi",
            "Chess", "Checkers", "Draughts", "Monopoly", "Scrabble", "Uno", "Jenga",
            "Connect Four", "Battleship", "Guess Who", "Snakes and ladders", "Cluedo",
            "Twister", "Hungry Hungry Hippos", "Operation", "Mouse Trap", "Pictionary",
            "Charades", "Hide and seek", "Tag", "Tiggy", "Red rover", "Hopscotch",
            "Musical chairs", "Simon says", "Duck duck goose", "Marco Polo", "Hot potato",
            "Pass the parcel", "Pin the tail on the donkey", "Spin the bottle", "Truth or dare",
            "Mahjong", "Go", "Backgammon", "Dominoes", "Solitaire", "Poker", "Go Fish",
            "Snap", "Old Maid", "Crazy eights", "Bingo", "Yahtzee", "Sudoku", "Crossword",
            "Wordle", "Tetris", "Pinball"))

cat("shapes", "Shapes", "Name a shape", lambda:
    wordnet_groups(["polygon.n.01", "polyhedron.n.01", "quadrilateral.n.01", "triangle.n.01",
                    "circle.n.01", "ellipse.n.01", "conic_section.n.01"],
                   lexnames={"noun.shape"})
    + plain("Circle", "Square", "Triangle", "Rectangle", "Oval", "Ellipse", "Pentagon",
            "Hexagon", "Heptagon", "Octagon", "Nonagon", "Decagon", "Dodecagon", "Rhombus",
            "Diamond", "Parallelogram", "Trapezium", "Trapezoid", "Kite", "Star", "Heart",
            "Crescent", "Semicircle", "Sphere", "Cube", "Cuboid", "Cone", "Cylinder",
            "Pyramid", "Prism", "Tetrahedron", "Octahedron", "Dodecahedron", "Icosahedron",
            "Torus", "Doughnut", "Spiral", "Helix", "Arrow", "Cross", "Chevron", "Zigzag",
            "Wave", "Squiggle", "Infinity", "Lemniscate", "Hemisphere", "Ellipsoid",
            "Pentagram", "Hexagram", "Annulus", "Sector", "Arc", "Teardrop", "Shield shape"))

cat("weather", "Weather", "Name a type of weather", lambda:
    wordnet_groups(["weather.n.01", "precipitation.n.03", "storm.n.01", "wind.n.01",
                    "cloud.n.02"],
                   lexnames={"noun.phenomenon", "noun.object", "noun.state"})
    + [g for g in corp("science/weather_conditions.json", "conditions", cur=False)
       if len(g[0].split()) <= 2]
    + plain("Sunny", "Rain", "Drizzle", "Shower", "Thunderstorm", "Storm", "Lightning",
            "Thunder", "Hail", "Snow", "Sleet", "Fog", "Mist", "Cloudy", "Overcast", "Windy",
            "Gale", "Cyclone", "Hurricane", "Typhoon", "Tornado", "Willy-willy", "Dust storm",
            "Heatwave", "Drought", "Flood", "Frost", "Dew", "Rainbow", "Blizzard", "Monsoon",
            "Humid", "Muggy", "Southerly buster", "Cool change", "Sea breeze", "Fremantle Doctor",
            "Haboob", "Sandstorm", "Whiteout", "Black ice", "Graupel", "Virga", "Waterspout",
            "Aurora", "Supercell", "Derecho", "Sun shower", "El Nino", "La Nina"))

cat("countries", "Countries", "Name a country", country_groups)

cat("capitals", "Capital cities", "Name a capital city", capital_groups)

cat("cities", "Cities of the world", "Name a city", lambda:
    wordnet_groups(["city.n.01", "national_capital.n.01", "state_capital.n.01", "port.n.01"],
                   lexnames={"noun.location"}, allow_binomial=True)
    + capital_groups()
    + plain("Adelaide", "Sydney", "Melbourne", "Brisbane", "Perth", "Hobart", "Darwin",
            "Canberra", "Gold Coast", "Newcastle", "Wollongong", "Geelong", "Townsville",
            "Cairns", "Toowoomba", "Ballarat", "Bendigo", "Launceston", "Mackay",
            "Rockhampton", "Bunbury", "Mount Gambier", "Whyalla", "Port Augusta",
            "Alice Springs", "Broome", "Kalgoorlie", "Coober Pedy", "Auckland", "Wellington", "Christchurch", "Queenstown",
            "Tokyo", "Osaka", "Kyoto", "Seoul", "Busan", "Shanghai", "Beijing", "Hong Kong",
            "Singapore", "Bangkok", "Kuala Lumpur", "Jakarta", "Bali", "Manila", "Hanoi",
            "Ho Chi Minh City", "Saigon", "Mumbai", "Delhi", "Bangalore", "Dubai",
            "New York", "NYC", "Los Angeles", "LA", "Chicago", "Miami", "San Francisco",
            "Las Vegas", "Seattle", "Toronto", "Vancouver", "Montreal", "Mexico City",
            "Rio de Janeiro", "Sao Paulo", "Buenos Aires", "London", "Paris", "Berlin",
            "Rome", "Madrid", "Barcelona", "Amsterdam", "Lisbon", "Vienna", "Prague",
            "Istanbul", "Cairo", "Cape Town", "Johannesburg", "Lagos", "Nairobi"))

cat("rivers_lakes", "Rivers, lakes & seas", "Name a river, lake, sea or ocean", lambda:
    suffixed("geography/rivers.json", "rivers", "River")
    + suffixed("geography/oceans.json", "oceans", "Ocean")
    + corp("geography/oceans.json", "seas", "name")
    + wordnet_groups(["river.n.01", "lake.n.01", "sea.n.01", "ocean.n.01"],
                     lexnames={"noun.object", "noun.location"}, allow_binomial=True)
    + curated([["Murray River", "Murray", "River Murray"], ["Darling River", "Darling"],
               ["Murrumbidgee", "Murrumbidgee River"], ["River Torrens", "Torrens", "Torrens River"],
               ["Yarra River", "Yarra"], ["Brisbane River"], ["Swan River"], ["Derwent River", "Derwent"],
               ["Lake Eyre", "Kati Thanda", "Kati Thanda-Lake Eyre"], ["Coorong"], ["Lake Mungo"],
               ["Lake Titicaca", "Titicaca"]])
    + plain("Lake Alexandrina", "Lake Burley Griffin", "Coral Sea", "Tasman Sea", "Great Australian Bight",
            "Southern Ocean", "Pacific Ocean", "Atlantic Ocean", "Indian Ocean", "Arctic Ocean",
            "Amazon", "Nile", "Mississippi", "Yangtze", "Mekong", "Ganges", "Thames", "Danube",
            "Rhine", "Seine", "Volga", "Lake Superior", "Lake Victoria", "Lake Baikal",
            "Caspian Sea", "Dead Sea", "Red Sea", "Black Sea", "Mediterranean", "Caribbean"))

cat("space", "Space", "Name something in space", lambda:
    planet_groups()
    + wordnet_groups(["celestial_body.n.01", "constellation.n.02", "star.n.01", "galaxy.n.01",
                      "planet.n.01", "comet.n.01", "nebula.n.03"],
                     lexnames={"noun.object", "noun.location", "noun.group"}, allow_binomial=True)
    + plain("Sun", "Moon", "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus",
            "Neptune", "Pluto", "Ceres", "Eris", "Haumea", "Makemake", "Asteroid", "Comet",
            "Meteor", "Meteorite", "Shooting star", "Black hole", "Wormhole", "Nebula",
            "Galaxy", "Milky Way", "Andromeda", "Supernova", "Quasar", "Pulsar", "Neutron star",
            "White dwarf", "Red giant", "Exoplanet", "Asteroid belt", "Kuiper belt",
            "Oort cloud", "Halley's Comet", "Southern Cross", "Crux", "Orion", "Orion's Belt",
            "The Pot", "Emu in the Sky", "Pleiades", "Seven Sisters", "Big Dipper",
            "Sirius", "Betelgeuse", "Polaris", "Alpha Centauri", "Proxima Centauri",
            "Europa", "Io", "Ganymede", "Callisto", "Titan", "Enceladus", "Phobos", "Deimos",
            "Triton", "Charon", "International Space Station", "ISS", "Satellite",
            "Space station", "Hubble", "James Webb Space Telescope", "Voyager", "Sputnik"))

cat("gods", "Gods & goddesses", "Name a god or goddess from myth", gods_groups)

cat("myth_creatures", "Myths & legends", "Name a mythical creature or legend", monster_groups)

cat("knots", "Knots", "Name a knot", lambda:
    corp("technology/knots.json", "knots", cur=False)
    + plain("Reef knot", "Square knot", "Granny knot", "Bowline", "Clove hitch", "Figure eight",
            "Figure-eight knot", "Sheet bend", "Slip knot", "Overhand knot", "Half hitch",
            "Two half hitches", "Taut-line hitch", "Trucker's hitch", "Sheepshank",
            "Monkey's fist", "Prusik", "Butterfly knot",
            "Double fisherman's", "Water knot", "Constrictor knot", "Shoelace knot",
            "Bow", "Windsor knot", "Half Windsor", "Four-in-hand"))

cat("appliances", "Gadgets & appliances", "Name a gadget or appliance", lambda:
    corp("technology/appliances.json", "appliances")
    + wordnet_groups(["home_appliance.n.01", "electronic_equipment.n.01", "computer.n.01",
                      "telephone.n.01"], lexnames={"noun.artifact"})
    + plain("Phone", "Smartphone", "iPhone", "Tablet", "iPad", "Laptop", "Computer", "PC",
            "Gaming PC", "Console", "PlayStation", "Xbox", "Nintendo Switch", "Switch",
            "Steam Deck", "VR headset", "Smartwatch", "Fitbit", "Earbuds", "AirPods",
            "Headphones", "Speaker", "Bluetooth speaker", "Smart speaker", "TV", "Television",
            "Projector", "Monitor", "Keyboard", "Mouse", "Webcam", "Microphone", "Printer",
            "3D printer", "Router", "Modem", "Hard drive", "USB stick", "Power bank",
            "Charger", "Camera", "GoPro", "Drone", "E-reader", "Kindle", "Calculator",
            "Fan", "Heater", "Air conditioner", "Aircon", "Dehumidifier", "Air purifier",
            "Vacuum cleaner", "Robot vacuum", "Washing machine", "Dryer", "Iron",
            "Hair dryer", "Straightener", "Electric toothbrush", "Shaver", "Alarm clock"))

cat("shrimp_things", "Shrimp, crabs & lobsters", "Name a shrimp, crab or lobster", lambda:
    wordnet_groups(["shrimp.n.03", "prawn.n.01", "decapod_crustacean.n.01"],
                   lexnames={"noun.animal", "noun.food"})
    + plain("Tiger prawn", "Banana prawn", "King prawn", "Spencer Gulf king prawn",
            "Western king prawn", "Eastern king prawn", "Endeavour prawn", "School prawn",
            "Greasyback prawn", "Bay prawn", "Freshwater prawn", "Giant river prawn",
            "Redclaw", "Yabby", "Marron", "Moreton Bay bug", "Balmain bug", "Bug",
            "Langoustine", "Scampi", "Krill", "Antarctic krill", "Mantis shrimp",
            "Pistol shrimp", "Snapping shrimp", "Cleaner shrimp", "Peppermint shrimp",
            "Harlequin shrimp", "Ghost shrimp", "Glass shrimp", "Cherry shrimp",
            "Red cherry shrimp", "Amano shrimp", "Crystal red shrimp", "Bamboo shrimp",
            "Vampire shrimp", "Brine shrimp", "Sea monkey", "Fairy shrimp", "Tadpole shrimp",
            "Triops", "Skeleton shrimp", "Bumblebee shrimp", "Candy cane shrimp",
            "Shrimp", "Prawn", "Coral banded shrimp", "Blood red fire shrimp", "Anemone shrimp",
            "Rock shrimp", "Pink shrimp", "Brown shrimp", "White shrimp", "Gulf shrimp",
            "Spot prawn", "Spot shrimp", "Sidestripe shrimp", "Northern shrimp",
            "Cold-water shrimp", "Grass shrimp", "Sand shrimp", "Mud shrimp",
            "Opossum shrimp", "Mysid", "Shrimp cocktail", "Prawn cocktail", "Popcorn shrimp",
            "Coconut shrimp", "Tempura prawn", "Prawn toast", "Har gow", "Shrimp chips",
            "Prawn crackers", "Shrimp paste", "Belacan", "Dried shrimp", "Prawn on the barbie",
            "Shrimp on the barbie", "Garlic prawns", "Salt and pepper prawns", "Butterfly prawn",
            "Black tiger shrimp", "Whiteleg shrimp", "Pacific white shrimp", "Kuruma prawn",
            "Botan shrimp", "Amaebi", "Sweet shrimp", "Royal red shrimp", "Carabinero",
            "Scarlet prawn", "Argentine red shrimp", "Deep-sea shrimp", "Glass prawn",
            "Mud crab", "Blue swimmer crab", "Sand crab", "Spanner crab", "King crab",
            "Snow crab", "Dungeness crab", "Coconut crab", "Fiddler crab", "Ghost crab",
            "Hermit crab", "Horseshoe crab", "Japanese spider crab", "Christmas Island red crab",
            "Soldier crab", "Rock lobster", "Southern rock lobster", "Crayfish", "Crawfish",
            "Tasmanian giant freshwater crayfish", "Spiny lobster", "Slipper lobster",
            "Painted crayfish", "Squat lobster", "Maine lobster", "Lobster", "Crab"))

# ---------------------------------------------------------------- new categories (new_cats*.py)
import new_cats
new_cats.register(cat, dict(G=G, wordnet_groups=wordnet_groups, corp=corp, tidy_display=tidy_display,
                            ok_name=ok_name, zipf=zipf_frequency, COUNTRIES=COUNTRIES, CORP=CORP,
                            sandwich_groups=sandwich_groups, planet_groups=planet_groups))

# ---------------------------------------------------------------- build
# per-category answers that are technically in a source but play badly
CAT_JUNK = {
    "jobs": "man men regular independent federal lovely familiar daniel johnny don fed temporary ordinary hire domestic better separate",
    "clothing": "blue separate formal gray grey overall single double",
    "emotions": "despite kick taste affect mood defeat information",
    "sports": "steal stops five seven single double",
    "toys_games": "stops steal parliament seven stop",
    "furniture": "lower upper",
    "containers": "well empty flat deck package",
    "vehicles": "technical electric sam semi",
    "buildings": "architecture",
    "gods": "here ran weird ate are had",
    "rivers_lakes": "red pool canadian mobile gang green white peace james indian southern fly milk orange don deep",
    "trees_plants": "may",
    "currencies": "pesewa sent",
    "units": "sellbydate bbl kos are today tomorrow yesterday date",
    "birds_of_prey": "aegypiidae buteonine",
    "landforms": "deep sanitarylandfill wormhole twilightzone gopherhole sawpit oceanfront waterside",
    "sewing_crafts": "hypodermicneedle",
    "aircraft": "cruisemissile hangarqueen",
    "trains": "nonsmoker",
    "bones": "lanternjaw",
    "organs": "biauriculateheart athletesheart megacolon",
    "card_games": "strippoker",
    "languages": "same northern",
    "art_styles": "eight",
}
CAT_JUNK = {k: set(v.split()) for k, v in CAT_JUNK.items()}

NONCUR_ZIPF = 3.6   # uncurated single-word names this common are probably homonym traps

def keep_name(n, cur, cid, sense_checked=False):
    if norm_key(n) in JUNK_KEYS or n.lower() in JUNK:
        return False
    if norm_key(n) in CAT_JUNK.get(cid, ()):
        return False
    if JUNK_PAT.search(n) and not cur:
        return False
    if re.search(r"monetary unit$", n, re.I):
        return False
    if not cur and not sense_checked:
        z = zipf_frequency(n, "en")
        words = n.split()
        if len(words) == 1 and z >= NONCUR_ZIPF:
            return False
        if len(words) > 1 and z >= 4.3:
            return False
    return True

MERGE_ON_ANY_OVERLAP = {"rivers_lakes", "space", "cities", "capitals", "countries", "gods",
                        "metals_elements", "colours", "myth_creatures"}

def build():
    """Each group (a WordNet synset or a list item) becomes one answer.
    A group joins an existing answer only if its *main* name is already an answer
    (the same thing from two sources). Shared nicknames such as "Anteater"
    (aardvark AND pangolin) stay on both answers instead of merging them."""
    banks = {}
    for cid, name, prompt, fn in C:
        groups = fn()
        entries = []        # {"names": [...], "keys": set(), "cur": set()}
        by_main = {}        # main name key -> entry index
        by_any = {}         # any name key -> entry index
        for g in groups:
            cur = getattr(g, "cur", False)
            handmade = cur and cid in new_cats.FLAGS   # lists written for the new categories
            names = [tidy_display(n) for n in g
                     if ok_name(n, allow_codes=(cid.startswith("countries") or handmade), generic_ok=handmade)]
            names = [n for n in names if keep_name(n, cur, cid, getattr(g, "sense_checked", False))]
            if not names:
                continue
            main = norm_key(names[0])
            target = by_main.get(main)
            if target is None:
                # "Oysters" is the same answer as "Oyster"
                for alt in (main[:-1] if main.endswith("s") else None,
                            main[:-2] if main.endswith("es") else None):
                    if alt and alt in by_main:
                        target = by_main[alt]
                        break
            if target is None and cur and len(names) == 1 and main in by_any:
                # a lone name that is already some answer's nickname ("Orca") is that answer
                target = by_any[main]
            if target is None and main in by_any and main in entries[by_any[main]]["cur"]:
                # a word-list entry whose main name we hand-listed as a nickname of an answer
                # ("Baking" for Bake) is that answer, so it can't be cashed in twice
                target = by_any[main]
            if target is None and cid in MERGE_ON_ANY_OVERLAP:
                # place/name categories: "Pacific" and "Pacific Ocean" are one answer
                hits = [by_any[norm_key(n)] for n in names if norm_key(n) in by_any]
                if hits:
                    target = hits[0]
            if target is None and len(names) > 1:
                # every name already belongs to one single existing answer -> same thing
                hits = {by_any[norm_key(n)] for n in names if norm_key(n) in by_any}
                if len(hits) == 1 and all(norm_key(n) in by_any for n in names):
                    target = hits.pop()
            if target is None:
                entries.append({"names": [], "keys": set(), "cur": set()})
                target = len(entries) - 1
            e = entries[target]
            for n in names:
                k = norm_key(n)
                if k not in e["keys"]:
                    e["keys"].add(k)
                    e["names"].append(n)
                if cur:
                    e["cur"].add(k)
                    # curated spelling wins for display
                    e["names"] = [n if norm_key(x) == k else x for x in e["names"]]
                by_any.setdefault(k, target)
            by_main.setdefault(main, target)
        out = []
        for e in entries:
            names = e["names"]
            zs = [zipf_frequency(n, "en") for n in names]
            curs = [norm_key(n) in e["cur"] for n in names]
            keyset = {norm_key(n) for n in names}
            def plural_of_other(n):
                k = norm_key(n)
                return k.endswith("s") and (k[:-1] in keyset or k[:-2] in keyset)
            best = max(range(len(names)), key=lambda i: (not plural_of_other(names[i]), curs[i], -i))
            out.append({"d": names[best], "a": [n for i, n in enumerate(names) if i != best],
                        "z": round(max(zs), 2), "c": any(curs)})
        # drop answers whose every name is just a shared nickname of another answer
        out.sort(key=lambda e: (-e["z"], e["d"].lower()))
        banks[cid] = {"name": name, "prompt": prompt, "entries": out}
        fl = new_cats.FLAGS.get(cid)
        if fl:
            # hand-flagged obvious answers and gems; filtered like any other answer
            ok = lambda n: ok_name(n, allow_codes=True, generic_ok=True) and keep_name(tidy_display(n), True, cid)
            banks[cid]["obvious"] = [tidy_display(n) for n in fl["obvious"] if ok(n)]
            banks[cid]["gems"] = [tidy_display(n) for n in fl["gems"] if ok(n)]
        print(f"{cid:16} {len(out):6}", file=sys.stderr)
    return banks

if __name__ == "__main__":
    banks = build()
    if MISSING:
        print("MISSING SYNSETS:", sorted(MISSING), file=sys.stderr)
    (OUT / "banks_raw.json").write_text(json.dumps(banks, ensure_ascii=False))
