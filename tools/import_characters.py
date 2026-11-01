"""Import the Obsidian character notes (C:/Obsidian/RPG/Characters) as a compendium package.

Usage:
    python tools/import_characters.py "C:/Obsidian/RPG" data/packages --media C:/Obsidian/Assets C:/Obsidian/Drawings

Writes data/packages/characters/ (package.json, characters.json, assets/, docs/), one entry of
kind "characters" per note. Sheet fields come from the frontmatter (Name, Race, Class, Level, HP,
PROF, STR..CHA, *Prof flags, skills, proficiencies, languages ...), the description is the
note's text without the Dataview sheet. Portraits and Token_*.png images are copied to assets/,
linked PDF character sheets to docs/. Notes without race and class become drafts.
Re-running rebuilds the package (the Obsidian importer never touches it).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from import_obsidian import (clean_list, clean_str, drop_empty_headings, fix_units, num,  # noqa: E402
                             read_text, slug, split_frontmatter, strip_dataview, to_bool)

ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]
SKILLS = {  # vault key -> (name, ability)
    "Acrobatics": ("acrobatics", "dex"), "AnimalHandling": ("animal handling", "wis"),
    "Arcana": ("arcana", "int"), "Athletics": ("athletics", "str"), "Deception": ("deception", "cha"),
    "History": ("history", "int"), "Insight": ("insight", "wis"), "Intimidation": ("intimidation", "cha"),
    "Investigation": ("investigation", "int"), "Medicine": ("medicine", "wis"), "Nature": ("nature", "int"),
    "Perception": ("perception", "wis"), "Performance": ("performance", "cha"),
    "Persuation": ("persuasion", "cha"), "Persuasion": ("persuasion", "cha"), "Religion": ("religion", "int"),
    "SleightOfHand": ("sleight of hand", "dex"), "Stealth": ("stealth", "dex"), "Survival": ("survival", "wis"),
}
IMG = re.compile(r"\.(png|jpe?g|webp|gif)$", re.I)


def mod(score: int) -> int:
    return (score - 10) // 2


def find_ref(kind: str, name: str, root: Path) -> str:
    """'races/half-elf' if an entry with that name exists in any package, else the plain name."""
    if not name:
        return ""
    for f in root.glob(f"*/{kind}.json"):
        for e in json.loads(f.read_text(encoding="utf-8")):
            if e["name"].lower() == name.lower() and not e.get("draft"):
                return f"{kind}/{e['id']}"
    return name


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vault", type=Path, help="vault root that contains Characters/")
    ap.add_argument("out", type=Path, help="data/packages")
    ap.add_argument("--media", type=Path, nargs="*", default=[],
                    help="extra folders with the pictures and PDFs (e.g. C:/Obsidian/Assets)")
    args = ap.parse_args()

    files: dict[str, Path] = {}
    for p in [f for d in [args.vault, *args.media] for f in d.rglob("*")]:
        if p.is_file() and (IMG.search(p.name) or p.suffix.lower() == ".pdf"):
            files.setdefault(p.name.lower(), p)

    pdir = args.out / "characters"
    if pdir.exists():
        shutil.rmtree(pdir)
    (pdir / "assets").mkdir(parents=True)
    entries, documents = [], []

    def copy(name: str, sub: str) -> str:
        src = files.get(name.lower())
        if not src:
            return ""
        (pdir / sub).mkdir(exist_ok=True)
        shutil.copy2(src, pdir / sub / src.name)
        return f"{sub}/{src.name}"

    for path in sorted((args.vault / "Characters").glob("*.md")):
        fm, body = split_frontmatter(read_text(path))
        name = clean_str(fm.get("Name")) or path.stem
        embeds = [m.split("|")[0].strip() for m in re.findall(r"!?\[\[([^\]]+)\]\]", body)]
        pics = [Path(e).name for e in embeds if IMG.search(e)]
        tokens = [p for p in pics if p.lower().startswith("token_")]
        for guess in (f"Token_{path.stem}.png", f"Token_{name.split()[0]}.png"):
            if not tokens and guess.lower() in files:
                tokens = [guess]
        portraits = [p for p in pics if not p.lower().startswith("token_")]

        # text: drop the Dataview sheet, the class list and the image link list
        text = strip_dataview(body)
        text = re.sub(r"^#{2,3} (Stats|Class|Links)\s*\n(?:(?!#).*\n?)*", "", text, flags=re.M)
        text = re.sub(r"!\[\[[^\]]+\]\]", "", text)  # images are in image/token
        text = re.sub(r"\[\[(?:[^\]|]*/)?([^\]|/]+?)(?:\.md)?\|([^\]]+)\]\]", r"[[\2]]", text)
        text = re.sub(r"\[\[[^\]/]*/([^\]|]+)\]\]", r"[[\1]]", text)
        text = fix_units(drop_empty_headings(text))
        for pdf in [e for e in embeds if e.lower().endswith(".pdf")]:
            file = copy(Path(pdf).name, "docs")
            if file:
                documents.append({"file": file, "title": f"{name}: character sheet",
                                  "size": (pdir / file).stat().st_size})
                text = (f"[Character sheet (PDF)](<{file}>)\n\n" + text).strip()

        stats = {a: int(num(fm.get(a.upper()), 10)) for a in ABILITIES}
        prof = int(num(fm.get("PROF"), 2))
        saves = {a: mod(stats[a]) + prof for a in ABILITIES if to_bool(fm.get(a.upper() + "Prof"))}
        skills = {}
        for key, (skill, ab) in SKILLS.items():
            if to_bool(fm.get(key)):
                skills[skill] = mod(stats[ab]) + prof
        race_name = clean_str(fm.get("Race")).strip()
        cls = clean_str(fm.get("Class"))
        level = int(num(fm.get("Level"), 1)) or 1
        entry = {
            "id": slug(path.stem),
            "name": name,
            "source": "Characters",
            "image": copy(portraits[0], "assets") if portraits else "",
            "token": copy(tokens[0], "assets") if tokens else "",
            "tags": ["pc"],
            "description": text,
            "owners": [],
            "race": find_ref("races", race_name, args.out),
            "classes": [{"class": find_ref("classes", cls, args.out), "subclass": "", "level": level}] if cls else [],
            "background": clean_str(fm.get("Background")),
            "alignment": clean_str(fm.get("Alignment")),
            "size": "Medium",
            "hp": int(num(fm.get("HP"), 0)),
            "ac": 10 + mod(stats["dex"]),
            "speed": {"walk": float(num(fm.get("Speed"), 0)), "swim": 0, "fly": 0, "burrow": 0, "climb": 0},
            "stats": stats,
            "saves": saves,
            "skills": skills,
            "proficiency_bonus": prof,
            "passive_perception": 10 + skills.get("perception", mod(stats["wis"])),
            "senses": clean_list(fm.get("Senses")),
            "languages": clean_list(fm.get("Languages")),
            "proficiencies": clean_list(fm.get("ArmorProficency")) + clean_list(fm.get("WeaponProficency"))
            + clean_list(fm.get("ToolProficency")),
            "resistances": clean_list(fm.get("Resistances")),
            "immunities": clean_list(fm.get("Immunities")),
            "vulnerabilities": clean_list(fm.get("Vulnerabilities")),
            "sex": clean_str(fm.get("Sex")),
            "age": clean_str(fm.get("Age")),
            "height_m": float(num(fm.get("Height", fm.get("Heigth")), 0)),
            "weight_kg": float(num(fm.get("Weight", fm.get("Weigth")), 0)),
            "draft": not (race_name and cls),
            "origin": {"vault": args.vault.name, "path": path.relative_to(args.vault).as_posix()},
        }
        entries.append(entry)
        print(f"  {name:24} {'draft' if entry['draft'] else 'ok   '} race={entry['race'] or '-'} "
              f"class={cls or '-'} img={'y' if entry['image'] else '-'} token={'y' if entry['token'] else '-'}")

    entries.sort(key=lambda e: e["name"].lower())
    (pdir / "characters.json").write_text(json.dumps(entries, ensure_ascii=False, indent=1), encoding="utf-8")
    manifest = {
        "format": "dragoon-package", "format_version": 1, "id": "characters", "name": "Characters",
        "kind": "source", "version": "1.0.0",
        "description": "Nico's player characters and their backstories, imported from the Obsidian notes.",
        "counts": {"characters": len(entries)}, "documents": documents,
        "created": dt.datetime.now().isoformat(timespec="seconds"),
        "imported_from": f"Obsidian vault {args.vault.name}/Characters",
    }
    (pdir / "package.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(entries)} characters, {sum(e['draft'] for e in entries)} drafts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
