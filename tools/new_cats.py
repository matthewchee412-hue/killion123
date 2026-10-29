"""Turns the SPECS lists in new_cats_a/b/c into builder functions for build.py.

build.py calls register(cat, helpers) after its own categories, so new ones are appended.
"""
import json, re

from new_cats_a import SPECS_A
from new_cats_b import SPECS_B
from new_cats_c import SPECS_C

SPECS = SPECS_A + SPECS_B + SPECS_C

FLAGS = {}   # category id -> {"obvious": [...], "gems": [...]}


def parse_items(text):
    """'*Name/Alias, !Gem, Plain' -> [(names, flag)] where flag is '', '*' or '!'."""
    out = []
    for raw in re.split(r",|\n", text):
        raw = raw.strip()
        if not raw:
            continue
        flag = ""
        if raw[0] in "*!":
            flag, raw = raw[0], raw[1:].strip()
        names = [n.strip() for n in raw.split("/") if n.strip()]
        if names:
            out.append((names, flag))
    return out


def register(cat, h):
    """h: dict of helpers from build.py (G, wordnet_groups, corp, tidy_display, ok_name, zipf, COUNTRIES,
    CORP, sandwich_groups, planet_groups)."""
    G = h["G"]
    zipf = h["zipf"]

    def surname_alias(names):
        """'Albert Einstein' also answers to 'Einstein' if that surname isn't a common word."""
        full = names[0]
        parts = full.replace(".", " ").split()
        if len(parts) < 2:
            return names
        last = parts[-1]
        if len(last) >= 4 and zipf(last, "en") < 3.5 and last.lower() not in {n.lower() for n in names}:
            return names + [last]
        return names

    for spec in SPECS:
        cid = spec["id"]
        items = parse_items(spec["items"])
        FLAGS[cid] = {"obvious": [n[0] for n, f in items if f == "*"],
                      "gems": [n[0] for n, f in items if f == "!"]}

        def make(spec=spec, items=items):
            builder = spec.get("builder", "")
            people = builder in ("people", "scientists")
            groups = []
            for names, _ in items:
                if people:
                    names = surname_alias(names)
                groups.append(G(names, True))
            if spec.get("wn"):
                groups += h["wordnet_groups"](spec["wn"], **spec.get("wnkw", {}))
            if builder == "sandwich":
                groups += h["sandwich_groups"]()
            elif builder.startswith("continent:"):
                region = builder.split(":", 1)[1]
                for c in h["COUNTRIES"]:
                    if c["region"] != region or not (c.get("unMember") or c.get("independent")):
                        continue
                    ns = [c["name"]["common"], c["name"]["official"]]
                    ns += [a for a in c.get("altSpellings", []) if len(a) > 3]
                    groups.append(G([h["tidy_display"](n) for n in dict.fromkeys(ns)], True))
            elif builder == "nationalities":
                groups += h["corp"]("geography/nationalities.json", "nationalities")
            elif builder == "scientists":
                for n in json.loads((h["CORP"] / "humans/scientists.json").read_text())["scientists"]:
                    groups.append(G(surname_alias([h["tidy_display"](n)]), True))
            elif builder == "cars":
                groups += h["corp"]("corporations/cars.json", "cars")
            elif builder == "planets":
                groups += h["planet_groups"]()
            elif builder == "greek":
                for key in ("greek_gods", "greek_titans", "greek_monsters"):
                    groups += h["corp"]("mythology/greek_myths_master.json", key)
            elif builder == "norse":
                nd = json.loads((h["CORP"] / "mythology/norse_gods.json").read_text())["norse_deities"]
                for k in nd:
                    for g in nd[k]:
                        groups.append(G([h["tidy_display"](g)], True))
            elif builder == "egyptian":
                eg = json.loads((h["CORP"] / "mythology/egyptian_gods.json").read_text())["egyptian_gods"]
                for g in eg:
                    groups.append(G([h["tidy_display"](g)], False))
            return groups

        cat(cid, spec["name"], spec["prompt"], make)
