"""Convert the Obsidian DnD5e vault into Dragoon source packages.

One package per source (book / PDF / homebrew), each a folder:

    <out>/<package-id>/package.json      manifest (id, name, counts, ...)
    <out>/<package-id>/monsters.json     list of entries, one file per kind
    <out>/<package-id>/spells.json
    <out>/<package-id>/assets/           images referenced by entries

All text fields (description, action text, ...) are Markdown. The vault is only read.

Usage: python tools/import_obsidian.py <vault> [<vault> ...] <out> [--limit N]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

FORMAT_VERSION = 1

# vault folder -> package kind
KINDS = {
    "NPCs": "monsters",
    "Spells": "spells",
    "Items": "items",
    "Feats": "feats",
    "Races": "races",
    "Subraces": "subraces",
    "Classes": "classes",
    "Subclasses": "subclasses",
    "Backgrounds": "backgrounds",
    "Eldritch Invocations": "invocations",
    "Infusions": "infusions",
    "Rules": "rules",
    "Conditions": "conditions",
    "Diseases": "diseases",
    # DnD5e ABDL vault
    "Tot Wildshape Forms": "monsters",
    "Traits": "feats",
    "Mechanics": "rules",
    "Tables": "tables",
}

ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]
ABILITY_NAMES = {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}
SKILLS = {
    "acrobatics": "Acrobatics", "animal_handling": "AnimalHandling", "arcana": "Arcana",
    "athletics": "Athletics", "deception": "Deception", "history": "History",
    "insight": "Insight", "intimidation": "Intimidation", "investigation": "Investigation",
    "medicine": "Medicine", "nature": "Nature", "perception": "Perception",
    "performance": "Performance", "persuasion": "Persuation", "religion": "Religion",
    "sleight_of_hand": "SleightOfHand", "stealth": "Stealth", "survival": "Survival",
}
# monster body sections -> entry field
MONSTER_SECTIONS = {
    "Actions": "actions",
    "Special Abilities": "traits",
    "Bonus Actions": "bonus_actions",
    "Reactions": "reactions",
    "Legendary Abilities": "legendary_actions",
    "Legendary Actions": "legendary_actions",
}


# ---------------------------------------------------------------- helpers

def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower().replace("'", "").replace("’", ""))
    return s.strip("-") or "unnamed"


def snake(key: str) -> str:
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", key.strip())
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1252", errors="replace")
    # C1 control chars are cp1252 smart quotes that slipped in ("\x93urk\x94")
    text = re.sub(r"[\x80-\x9f]", lambda m: bytes([ord(m.group())]).decode("cp1252", "replace"), text)
    return text.replace("\xa0", " ")


def split_frontmatter(text: str) -> tuple[dict, str]:
    text = text.replace("\r\n", "\n").lstrip("﻿")
    m = re.match(r"---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return {}, text
    raw = re.sub(r"&amp;", "&", m.group(1), flags=re.I)
    raw = re.sub(r"^(\s*-\s+)&", r"\1and", raw, flags=re.M)  # "- &Slashing" is a YAML anchor
    try:
        fm = yaml.safe_load(raw) or {}
    except yaml.YAMLError:
        fm = {}
    return fm, text[m.end():]


def clean_str(v) -> str:
    if v is None:
        return ""
    if isinstance(v, list):  # "Type: [Beast]" -> "Beast"
        return ", ".join(clean_str(x) for x in v if clean_str(x))
    return fix_units(str(v).strip())


def clean_list(v) -> list[str]:
    """Vault lists were split on ',' blindly ("Poison; Nonmagic Bludgeoning", " Piercing").
    Rejoin, then split on ';' first and on ',' only where no clause follows."""
    if v is None:
        return []
    if not isinstance(v, list):
        v = [v]
    joined = ", ".join(clean_str(x) for x in v if clean_str(x))
    out: list[str] = []
    for part in joined.split(";"):
        part = part.strip(" ,")
        if not part:
            continue
        # clauses like "Bludgeoning, Piercing, And Slashing From Nonmagical Attacks" stay whole
        if re.search(r"\b(and|from|nonmagic|that|except)\b", part, re.I):
            out.append(part)
        else:
            out.extend(p.strip() for p in part.split(",") if p.strip())
    return out


def num(v, default=0):
    if v is None or v == "":
        return default
    if isinstance(v, bool):
        return int(v)
    if isinstance(v, (int, float)):
        return v
    s = str(v).strip().replace(",", ".")  # vault uses German decimal commas ("0,25")
    m = re.match(r"^(\d+)\s*/\s*(\d+)$", s)  # CR "1/4"
    if m:
        return int(m.group(1)) / int(m.group(2))
    try:
        f = float(s)
        return int(f) if f.is_integer() else f
    except ValueError:
        return default


def to_bool(v) -> bool:
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in ("true", "yes", "1")


def strip_dataview(body: str) -> str:
    """Remove Obsidian-only render parts: %% comments %%, dataview code blocks and
    blockquote/callout blocks that contain inline dataview (`=this...`)."""
    body = re.sub(r"%%.*?%%", "", body, flags=re.S)
    body = re.sub(r"^>?\s*`{3,}\s*dataview.*?`{3,}\s*$", "", body, flags=re.S | re.M)
    lines = body.split("\n")
    out, block = [], []

    def flush():
        # drop inline dataview blocks and callout headers left empty after removing dataview
        empty = all(re.fullmatch(r">\s*(\[![^\]]*\].*)?\s*", l) for l in block)
        if block and not empty and not any("`=" in l for l in block):
            # Obsidian callout header ">[!note|style] Title" -> "> **Title**" (or dropped)
            for l in block:
                m = re.fullmatch(r">\s*\[![^\]]*\][+-]?\s*(.*)", l)
                if m:
                    if m.group(1).strip():
                        out.append(f"> **{m.group(1).strip()}**")
                else:
                    out.append(l)
        block.clear()

    for line in lines:
        if line.startswith(">"):
            block.append(line)
        else:
            flush()
            out.append(line)
    flush()
    # plain Markdown tables with inline dataview cells (class proficiency tables): drop the table
    cleaned, table = [], []
    for line in out + [""]:
        if line.lstrip().startswith("|"):
            table.append(line)
            continue
        if table and not any("`=" in l for l in table):
            cleaned.extend(table)
        table = []
        cleaned.append(line)
    md = "\n".join(cleaned[:-1])
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip()


def drop_empty_headings(md: str) -> str:
    """Remove headings whose section is empty (left over after removing dataview lists)."""
    lines = md.split("\n")
    keep = [True] * len(lines)
    next_level = -1  # what follows: -1 = end, 99 = content, n = heading of level n
    for i in range(len(lines) - 1, -1, -1):
        line = lines[i]
        if not line.strip():
            continue
        m = re.match(r"(#+)\s", line)
        if m:
            level = len(m.group(1))
            if next_level == -1 or next_level <= level:
                keep[i] = False
                continue
            next_level = level
        else:
            next_level = 99
    return re.sub(r"\n{3,}", "\n\n", "\n".join(l for l, k in zip(lines, keep) if k)).strip()


def unquote(block: str) -> str:
    return "\n".join(re.sub(r"^> ?", "", l) for l in block.split("\n")).strip()


image_index: dict = {}


def convert_embeds(md: str, images: set[str]) -> str:
    """![[img.png]] -> ![](assets/img.png); remembers the image for copying."""
    def repl(m):
        name = m.group(1).split("|")[0].strip()
        if re.search(r"\.(png|jpe?g|webp|gif)$", name, re.I) and name.lower() in image_index:
            images.add(name)
            return f"![](assets/{name})"
        return m.group(0)
    return fix_units(re.sub(r"!\[\[([^\]]+)\]\]", repl, md))


FT_TO_M = 0.3048


def metres(feet: float) -> str:
    return f"{round(feet * FT_TO_M, 1):g}"


def fix_units(text: str) -> str:
    """The vault's ft->m conversion is incomplete:
    - "range 80/97.5 m": only the long range was converted. Long range is always at least
      twice the short range, so a ratio below 2 means the first number is still feet.
    - "60'", "30 feet", "10 ft." were left in feet."""
    def fix_range(m):
        a, b = float(m.group(1).replace(",", ".")), float(m.group(2).replace(",", "."))
        if a and b / a < 2:
            return f"range {metres(a)}/{m.group(2)} m"
        return m.group(0)
    # "20 feet​【6 m】": the converted value is already given in brackets
    text = re.sub(r"\d+(?:\s|-)?(?:feet|foot|ft\.?)\s*​?\s*【([^】]+)】", r"\1", text)
    text = re.sub(r"range\s+([\d.,]+)/([\d.,]+)\s*m\b", fix_range, text)
    text = re.sub(r"range\s+(\d+)/(\d+)\s*(?:'|ft\.?|feet)",
                  lambda m: f"range {metres(int(m.group(1)))}/{metres(int(m.group(2)))} m", text)
    text = re.sub(r"\b(\d+)(?:\s*(?:-|\s)?(?:feet|foot|ft\b\.?)|')(?!\w)",
                  lambda m: f"{metres(int(m.group(1)))} m", text)
    return text


def split_sections(body: str) -> dict[str, str]:
    """'# Heading' sections of a body -> {heading: text}."""
    parts = re.split(r"^# (.+)$", body, flags=re.M)
    sections = {"": parts[0]}
    for i in range(1, len(parts) - 1, 2):
        sections[parts[i].strip()] = parts[i + 1]
    return sections


# ---------------------------------------------------------------- monsters

DAMAGE_RE = re.compile(r"(\d+)\s*\((\d+d\d+(?:\s*[+-]\s*\d+)?)\)\s*([A-Za-z]+)")


def parse_feature(name: str, text: str) -> dict:
    if name.count("(") > name.count(")"):  # vault cut names: "Entomb (While Bloodied"
        name += ")"
    feat: dict = {"name": name, "text": text}
    m = re.search(r"\((Recharge [\d–\-]+|\d+/Day(?: each)?|\d+/Turn|Costs \d+ Actions?)\)", name, re.I)
    if m:
        feat["uses"] = m.group(1).replace("–", "-")
    elif re.search(r"\((\d)\)\s*$", name):  # legendary cost "Fling (2)"
        feat["cost"] = int(re.search(r"\((\d)\)\s*$", name).group(1))
    a = re.search(r"(Melee|Ranged|Melee or Ranged) (Weapon|Spell) Attack:\s*([+-]\d+) to hit", text, re.I)
    if a:
        attack = {"kind": f"{a.group(1).lower()} {a.group(2).lower()}", "to_hit": int(a.group(3))}
        r = re.search(r"to hit,\s*(?:reach\s*|range\s*)?([\d.,/ ]+?)\s*(m|ft|')", text, re.I)
        if r:
            attack["range"] = f"{r.group(1).strip()} {r.group(2)}"
        attack["damage"] = [{"dice": d.replace(" ", ""), "average": int(avg), "type": t.lower()}
                            for avg, d, t in DAMAGE_RE.findall(text)]
        feat["attack"] = attack
    s = re.search(r"DC (\d+) (Str|Dex|Con|Int|Wis|Cha)\w*", text)
    if s:
        feat["save"] = {"dc": int(s.group(1)), "ability": s.group(2).lower()}
        if not a:
            dmg = [{"dice": d.replace(" ", ""), "average": int(avg), "type": t.lower()}
                   for avg, d, t in DAMAGE_RE.findall(text)]
            if dmg:
                feat["damage"] = dmg
    return feat


def parse_features(section: str, images: set[str], lore: list[str]) -> list[dict]:
    """Blockquotes starting with >**Name**. Fixes for the Level Up import in the vault:
    a bold line without text is a list item of the previous feature (potions, HP thresholds);
    a long bold sentence followed by text is flavour text and goes to `lore`."""
    feats = []
    for block in re.split(r"\n\s*\n", section.strip()):
        block = block.strip()
        if not block:
            continue
        text = unquote(block)
        m = re.match(r"\*\*(.+?)\*\*\s*\n?(.*)", text, re.S)
        if m:
            name = fix_units(m.group(1).strip())
            body = convert_embeds(m.group(2).strip(), images)
            if name.lower().startswith("zztitle"):  # layout junk from the source PDF
                continue
            if not body and feats:
                sep = "\n" if feats[-1]["text"].rstrip().split("\n")[-1].startswith("- ") else "\n\n"
                feats[-1]["text"] = feats[-1]["text"].rstrip() + f"{sep}- {name}"
                continue
            if len(name) > 60 and ":" not in name and "(" not in name and body:
                lore.append(f"{name}. {body}" if not name.endswith(".") else f"{name} {body}")
                continue
            feats.append(parse_feature(name, body))
        elif feats:  # continuation paragraph
            feats[-1]["text"] += "\n\n" + convert_embeds(text, images)
    return feats


def convert_monster(fm: dict, body: str, images: set[str]) -> dict:
    stats = {a: num(fm.get(ABILITY_NAMES[a]), 10) for a in ABILITIES}
    saves = {}
    for a in ABILITIES:
        extra = num(fm.get(ABILITY_NAMES[a] + "Save"))
        if extra:
            saves[a] = (stats[a] - 10) // 2 + extra  # total save bonus
    skills = {}
    for key, vk in SKILLS.items():
        v = num(fm.get(vk + "Bonus"))
        if v:
            skills[key] = v
    senses = clean_list(fm.get("Senses"))
    passive = None
    rest = []
    for s in senses:
        m = re.match(r"passive perception\s*(\d+)", s, re.I)
        if m:
            passive = int(m.group(1))
        else:
            rest.append(s)
    if passive is None:
        passive = 10 + skills.get("perception", (stats["wis"] - 10) // 2)
    sections = split_sections(body)
    entry = {
        "size": clean_str(fm.get("Size")),
        "type": clean_str(fm.get("Type")),
        "subtype": clean_str(fm.get("Subtype")),
        "group": clean_str(fm.get("Group")),
        "alignment": clean_str(fm.get("Alignment")),
        "cr": num(fm.get("CR")),
        "ac": num(fm.get("AC")),
        "armor": clean_str(fm.get("Armor")),
        "hp": num(fm.get("HP")),
        "speed": {k: num(fm.get(k.capitalize())) for k in ("walk", "swim", "fly", "burrow", "climb")},
        "hover": to_bool(fm.get("Hover", False)),
        "stats": stats,
        "saves": saves,
        "skills": skills,
        "passive_perception": passive,
        "senses": rest,
        "languages": clean_list(fm.get("Languages")),
        "vulnerabilities": clean_list(fm.get("Vulnerabilities")),
        "resistances": clean_list(fm.get("Resistances")),
        "immunities": clean_list(fm.get("Immunities")),
        "condition_immunities": clean_list(fm.get("ConditionImmunities")),
        "environments": clean_list(fm.get("Environments")),
        "spells": clean_list(fm.get("Spells")),
        "description": convert_embeds(strip_dataview(sections.get("Description", "")), images),
    }
    lore: list[str] = []
    for heading, field in MONSTER_SECTIONS.items():
        if heading in sections:
            entry.setdefault(field, []).extend(parse_features(sections[heading], images, lore))
    for field in set(MONSTER_SECTIONS.values()):
        entry.setdefault(field, [])
    # "The dragon can take 3 legendary actions..." is the rules intro, not an action
    entry["legendary_intro"] = ""
    for f in list(entry["legendary_actions"]):
        if re.search(r"can take \d+ legendary actions", f["name"], re.I):
            entry["legendary_intro"] = f"{f['name']}. {f['text']}".strip()
            entry["legendary_actions"].remove(f)
    if lore:
        entry["description"] = "\n\n".join([entry["description"]] * bool(entry["description"]) + lore)
    return entry


# ---------------------------------------------------------------- spells

def sentence_case(s: str) -> str:
    """'1 bonus Action' / '1 Minute' -> '1 bonus action' / '1 minute'."""
    return s[:1] + s[1:].lower() if s else s


def convert_spell(fm: dict, body: str, images: set[str]) -> dict:
    level = num(fm.get("Level", fm.get("SpellLevel")))
    school = clean_str(fm.get("School"))
    m = re.match(r"(\w[\w ]*?)\s*\((.+)\)$", school)  # "Evocation (Dunamancy: Graviturgy)"
    subschool = ""
    if m:
        school, subschool = m.group(1), m.group(2)
    rng = re.match(r"[\d.,]+", clean_str(fm.get("Range")))
    return {
        "level": level,
        "school": school,
        "subschool": subschool,
        "casting_time": sentence_case(clean_str(fm.get("CastingTime"))),
        "range_m": num(rng.group()) if rng else 0,  # 0 = touch / self (the vault does not say which)
        "duration": sentence_case(clean_str(fm.get("Duration"))),
        "concentration": to_bool(fm.get("Concentration", False)),
        "ritual": to_bool(fm.get("Ritual", False)),
        "components": {
            "verbal": to_bool(fm.get("VerbalComponent", False)),
            "somatic": to_bool(fm.get("SomaticComponent", False)),
            "material": to_bool(fm.get("MaterialComponent", False)),
            "material_text": clean_str(fm.get("Material")),
        },
        "classes": clean_list(fm.get("Classes")),
        "description": convert_embeds(strip_dataview(body), images),
    }


# ---------------------------------------------------------------- generic

SKIP_KEYS = {"tags", "name", "source", "image"}


def convert_generic(fm: dict, body: str, images: set[str]) -> dict:
    entry = {}
    for k, v in fm.items():
        sk = snake(str(k))
        if sk in SKIP_KEYS:
            continue
        if isinstance(v, list):
            entry[sk] = clean_list(v)
        elif isinstance(v, (int, float, bool)) or v is None:
            entry[sk] = v
        else:
            entry[sk] = num(v) if re.fullmatch(r"-?\d+([.,]\d+)?", str(v).strip()) else clean_str(v)
    desc = convert_embeds(strip_dataview(body), images)
    # leading parent link ("[[Fighter]]") of subclasses/subraces and Obsidian tag lines ("#Ark")
    desc = re.sub(r"\A(\s*(\[\[[^\]]+\]\]|#[\w/-]+)\s*\n)+", "", desc).strip()
    entry["description"] = desc
    return entry


def normalize_types(entries: list[dict]) -> None:
    """Give every key one type per kind: None -> [] / "" / 0 depending on what other entries use,
    and missing keys get the same empty value."""
    kinds: dict[str, set] = defaultdict(set)
    for e in entries:
        for k, v in e.items():
            if v is not None:
                kinds[k].add(list if isinstance(v, list) else str if isinstance(v, str)
                              else bool if isinstance(v, bool) else dict if isinstance(v, dict) else float)
    empty = {list: [], str: "", bool: False, float: 0, dict: {}}
    for e in entries:
        for k, types in kinds.items():
            if e.get(k) is None:
                t = list if list in types else str if str in types else next(iter(types))
                e[k] = empty[t] if not isinstance(empty[t], (list, dict)) else type(empty[t])()
            elif list in kinds[k] and isinstance(e[k], str):  # "Cleric" where others have lists
                e[k] = [e[k]] if e[k] else []


CONVERTERS = {"monsters": convert_monster, "spells": convert_spell}


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vaults", type=Path, nargs="+", help="one or more vault folders")
    ap.add_argument("out", type=Path)
    ap.add_argument("--limit", type=int, default=0, help="max files per folder (test runs)")
    args = ap.parse_args()

    source_docs: dict[str, Path] = {}
    for vault in args.vaults:
        image_index.update({p.name.lower(): p for p in vault.rglob("*")
                            if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".gif")})
        source_docs.update({p.stem: p for p in (vault / "Sources").glob("*.md")})

    packages: dict[str, dict] = defaultdict(lambda: defaultdict(list))
    package_names: dict[str, str] = {}
    package_images: dict[str, set] = defaultdict(set)
    package_vaults: dict[str, set] = defaultdict(set)
    report = Counter()
    missing_images = []

    for vault, folder, kind in [(v, f, k) for v in args.vaults for f, k in KINDS.items()]:
        files = sorted((vault / folder).rglob("*.md"))
        if args.limit:
            files = files[: args.limit]
        for path in files:
            fm, body = split_frontmatter(read_text(path))
            if not fm and not body.strip():
                report["skipped (empty file)"] += 1
                continue
            if not fm:
                guess = "Fools Gold" if path.stem.startswith("Chaos Surges") else (
                    "5e Core Rules" if folder == "Rules" else "Unknown")
                fm = {"Name": path.stem, "Source": guess}
                report["no frontmatter (source guessed)"] += 1
            name = clean_str(fm.get("Name")) or path.stem
            source = clean_str(fm.get("Source")) or "Unknown"
            pid = slug(source)
            package_names.setdefault(pid, source)
            images: set[str] = set()
            entry = {
                "id": slug(name),
                "name": name,
                "source": source,
                "image": "",
            }
            img = clean_str(fm.get("Image"))
            if img and img.lower() not in image_index:
                report["image missing in vault"] += 1
                img = ""
            if img:
                images.add(img)
                entry["image"] = f"assets/{img}"
            entry.update(CONVERTERS.get(kind, convert_generic)(fm, body, images))
            # subclasses/subraces live in a folder named after their class/race
            for key, k in (("class", "subclasses"), ("parent", "subraces")):
                if kind == k and not entry.get(key) and path.parent.name != folder:
                    entry[key] = path.parent.name
            entry["origin"] = {"vault": vault.name, "path": path.relative_to(vault).as_posix()}
            packages[pid][kind].append(entry)
            package_images[pid] |= images
            package_vaults[pid].add(vault.name)
            report[kind] += 1

    by_kind: dict[str, list] = defaultdict(list)
    for kinds in packages.values():
        for kind, entries in kinds.items():
            by_kind[kind].extend(entries)
    for entries in by_kind.values():
        normalize_types(entries)

    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    now = dt.datetime.now().isoformat(timespec="seconds")
    summary = []
    for pid, kinds in sorted(packages.items()):
        pdir = out / pid
        if pdir.exists():
            shutil.rmtree(pdir)
        pdir.mkdir(parents=True)
        counts = {}
        for kind, entries in sorted(kinds.items()):
            seen = Counter()
            for e in sorted(entries, key=lambda e: e["name"].lower()):
                seen[e["id"]] += 1
                if seen[e["id"]] > 1:
                    e["id"] = f"{e['id']}-{seen[e['id']]}"
            entries.sort(key=lambda e: e["name"].lower())
            (pdir / f"{kind}.json").write_text(
                json.dumps(entries, ensure_ascii=False, indent=1), encoding="utf-8")
            counts[kind] = len(entries)
        for img in sorted(package_images[pid]):
            src = image_index.get(img.lower())
            if src:
                (pdir / "assets").mkdir(exist_ok=True)
                shutil.copy2(src, pdir / "assets" / img)
            else:
                missing_images.append(f"{pid}: {img}")
        name = package_names[pid]
        desc = ""
        if name in source_docs:
            desc = drop_empty_headings(strip_dataview(split_frontmatter(read_text(source_docs[name]))[1]))
        manifest = {
            "format": "dragoon-package",
            "format_version": FORMAT_VERSION,
            "id": pid,
            "name": name,
            "kind": "source",
            "version": "1.0.0",
            "description": desc,
            "counts": counts,
            "created": now,
            "imported_from": "Obsidian vault " + ", ".join(sorted(package_vaults[pid])),
        }
        (pdir / "package.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
        summary.append((pid, sum(counts.values()), counts))

    print(f"{len(packages)} packages -> {out}")
    for pid, total, counts in sorted(summary, key=lambda s: -s[1]):
        print(f"  {total:5d}  {pid}  {dict(counts)}")
    print("entries:", dict(report))
    if missing_images:
        print(f"missing images ({len(missing_images)}):", *missing_images[:20], sep="\n  ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
