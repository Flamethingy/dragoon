"""The import agent (TASK-27): turns a PDF, an image or a web page into a draft package with
Claude, following the VTT <-> tool contract in backlog/docs/import-agent.md (the VTT starts it,
tools/fake_import_agent.py is the stand-in for tests):

    python tools/import_agent.py --input <file|URL> --kind pdf|image|url --target <id|new:name>
        --job <job dir> --packages <packages root> [--pages 60-70]

1. Prepare (no AI): PDF pages are rendered to pages/<n>.png and sent in chunks of CHUNK pages,
   with the art boxes (tools/extract_pdf_art.py) drawn and numbered on them and the page text.
   An image is sent as it is; a web page as text plus its pictures (numbered).
2. Extract: one Claude request per chunk with a JSON schema (monsters, spells, items). Every
   entry names its page and art box (-1 = none); for a single image Claude gives a crop.
3. Normalize with the importer's helpers (ids, features, rollable tables, feet -> metres) and
   write the drafts (draft: true, origin, source_page, crop); art boxes are cut to art/<id>.jpg.

The API key comes only from ANTHROPIC_API_KEY. It is never printed, logged or written.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import os
import re
import sys
import traceback
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from import_obsidian import (ABILITIES, FEATURE_LISTS, extract_features, extract_tables,  # noqa: E402
                             fix_units, metres, parse_feature, slug, unique_ids)

MODEL = "claude-opus-5-5"
EFFORT = "medium"
MAX_TOKENS = 64000
CHUNK = 20          # PDF pages per request
PAGE_DPI = 110      # pages/<n>.png (what Claude sees and the editor shows)
ART_DPI = 150       # art/<id>.jpg
MAX_SIDE = 1568     # images are scaled to this, so Claude's coordinates are ours
MAX_WEB_IMAGES = 20
UA = "Mozilla/5.0 (Dragoon import agent)"
KINDS = ["monsters", "spells", "items"]


# ---------------------------------------------------------------- job files

class Job:
    def __init__(self, folder: Path):
        self.dir = folder
        self.file = folder / "job.json"
        self.state = json.loads(self.file.read_text(encoding="utf-8")) if self.file.exists() else {}
        self.log_file = open(folder / "progress.log", "a", encoding="utf-8")

    def say(self, text: str) -> None:
        self.log_file.write(scrub(text) + "\n")
        self.log_file.flush()

    def set(self, **values) -> None:
        self.state.update({k: scrub(v) if isinstance(v, str) else v for k, v in values.items()})
        tmp = self.file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, ensure_ascii=False, indent=1), encoding="utf-8")
        tmp.replace(self.file)


def scrub(text: str) -> str:
    """Never let the key into a log or job file, whatever an error message contains."""
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    return text.replace(key, "***") if key else text


# ---------------------------------------------------------------- the schema

def string_list() -> dict:
    return {"type": "array", "items": {"type": "string"}}


def obj(props: dict) -> dict:
    return {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}


SECTIONS = ["trait", "action", "bonus_action", "reaction", "legendary_action"]
NUM = {"type": "number"}
INT = {"type": "integer"}
STR = {"type": "string"}


def schema(with_crop: bool) -> dict:
    """Kept small (the structured-output grammar has a size limit): what a stat block prints as
    one line is a string here and parsed below."""
    common = {"name": STR, "page": INT, "art_box": INT}
    if with_crop:
        common["crop"] = {"type": "array", "items": INT}
    monster = obj({
        **common,
        "size": STR, "type": STR, "alignment": STR, "cr": NUM, "ac": INT, "armor": STR, "hp": INT,
        "hit_dice": STR, "speed": STR, "stats": {"type": "array", "items": INT},
        "saves": STR, "skills": STR, "senses": STR, "languages": STR,
        "vulnerabilities": STR, "resistances": STR, "immunities": STR, "condition_immunities": STR,
        "features": {"type": "array", "items": obj({"section": {"type": "string", "enum": SECTIONS},
                                                    "name": STR, "text": STR})},
        "legendary_intro": STR, "description": STR,
    })
    spell = obj({**common, "level": INT, "school": STR, "casting_time": STR, "range": STR,
                 "components": STR, "duration": STR, "classes": STR, "description": STR})
    item = obj({**common, "rarity": STR, "type": STR, "attunement": STR, "description": STR})
    return obj({"monsters": {"type": "array", "items": monster},
                "spells": {"type": "array", "items": spell},
                "items": {"type": "array", "items": item}})


SYSTEM = """You turn tabletop RPG source material (D&D 5e and similar) into structured entries for a \
virtual tabletop. Extract every complete monster stat block, spell and magic item you see; skip \
anything else (rules text, adventure prose, tables of contents).

- Copy the text faithfully. Keep the original units (feet, pounds); do not convert them.
- Stat block lines go into their fields as printed: speed "30 ft., fly 60 ft. (hover)", saves \
"Dex +5, Wis +3", skills "Perception +4, Stealth +6", senses (with passive Perception), languages, \
damage and condition lists. `stats` are the six scores STR DEX CON INT WIS CHA in that order.
- Monster features in stat block order, each with its section (trait = before Actions), the name \
without the trailing period (keep "(Recharge 5-6)" or "(3/Day)" in it) and the text as written. \
The "can take 3 legendary actions..." paragraph goes to legendary_intro.
- Spells: components as printed ("V, S, M (a pinch of salt)"), classes comma separated.
- `description` is the lore text that belongs to the entry (Markdown, paragraphs separated by \
blank lines). Rollable tables in it are Markdown tables whose first column header is the die \
(d4, d6, d8, d10, d12, d20, d100).
- cr as a number (1/4 = 0.25).
- Empty string, 0 or [] for anything not given.
- `page` is the page number printed in the label above the page image ("Page 61").
- `art_box`: pictures are framed with red numbered boxes. Give the number of the box showing \
this entry's creature or item (normally on the same or the facing page, near its name), or -1 \
when none shows it. Never give one box to two entries."""


# ---------------------------------------------------------------- prepare: PDF

def prepare_pdf(path: str, job: Job, pages: tuple[int, int] | None):
    """Yields chunks: (label, content blocks, boxes {n: (page, rect in points)}, doc)."""
    import pymupdf
    from extract_pdf_art import art_regions, decor_images

    doc = pymupdf.open(path)
    first, last = (1, doc.page_count) if not pages else (max(1, pages[0]), min(doc.page_count, pages[1]))
    job.say(f"{Path(path).name}: {doc.page_count} pages, reading {first}-{last}")
    decor = decor_images(doc)
    (job.dir / "pages").mkdir(exist_ok=True)
    for start in range(first, last + 1, CHUNK):
        end = min(last, start + CHUNK - 1)
        blocks, boxes = [], {}
        for pno in range(start, end + 1):
            page = doc[pno - 1]
            pix = page.get_pixmap(dpi=PAGE_DPI)
            pix.save(job.dir / "pages" / f"{pno}.png")
            regions = art_regions(page, decor)
            numbered = []
            for r in regions:
                n = len(boxes) + 1
                boxes[n] = (pno, r)
                numbered.append((n, [v * PAGE_DPI / 72 for v in (r.x0, r.y0, r.x1, r.y1)]))
            blocks.append({"type": "text", "text": f"Page {pno}"})
            blocks.append(image_block(draw_boxes(pix.tobytes("png"), numbered)))
            text = page.get_text().strip()
            if text:
                blocks.append({"type": "text", "text": f"Text layer of page {pno} (may be out of order):\n{text}"})
        yield f"Pages {start}-{end}", blocks, boxes, doc


def draw_boxes(png: bytes, boxes: list[tuple[int, list[float]]]) -> bytes:
    from PIL import Image, ImageDraw, ImageFont
    img = Image.open(io.BytesIO(png)).convert("RGB")
    if not boxes:
        return to_png(img)
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 28)
    except OSError:
        font = ImageFont.load_default()
    for n, (x0, y0, x1, y1) in boxes:
        draw.rectangle([x0, y0, x1, y1], outline=(230, 0, 0), width=4)
        draw.rectangle([x0, y0, x0 + 44, y0 + 36], fill=(230, 0, 0))
        draw.text((x0 + 8, y0 + 2), str(n), fill=(255, 255, 255), font=font)
    return to_png(img)


# ---------------------------------------------------------------- prepare: image and URL

def load_image(data: bytes):
    """The picture scaled to MAX_SIDE, as RGB."""
    from PIL import Image
    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")
    if max(img.size) > MAX_SIDE:
        img.thumbnail((MAX_SIDE, MAX_SIDE))
    return img


def to_png(img) -> bytes:
    out = io.BytesIO()
    img.save(out, "PNG")
    return out.getvalue()


def image_block(png: bytes) -> dict:
    return {"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                        "data": base64.standard_b64encode(png).decode()}}


class PageText(HTMLParser):
    BLOCK = {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "pre", "table", "hr"}

    def __init__(self, base: str):
        super().__init__()
        self.base, self.parts, self.images, self._skip = base, [], [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript"):
            self._skip += 1
        if tag in self.BLOCK:
            self.parts.append("\n")
        if tag == "img":
            src = dict(attrs).get("src") or dict(attrs).get("data-src")
            if src and not src.startswith("data:"):
                self.images.append(urllib.parse.urljoin(self.base, src))
        if tag in ("td", "th"):
            self.parts.append(" | ")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript") and self._skip:
            self._skip -= 1
        if tag in self.BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)

    def text(self) -> str:
        t = re.sub(r"[ \t\r\f\v]+", " ", "".join(self.parts))
        return re.sub(r"\n\s*\n\s*(\n\s*)+", "\n\n", t).strip()


def fetch(url: str, limit: int = 30_000_000) -> tuple[bytes, str]:
    for _ in range(5):  # Python 3.10's urllib does not follow 308
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read(limit), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            if e.code not in (301, 302, 303, 307, 308) or not e.headers.get("Location"):
                raise RuntimeError(f"Could not load {url}: HTTP {e.code}")
            url = urllib.parse.urljoin(url, e.headers["Location"])
    raise RuntimeError(f"Too many redirects: {url}")


def source_url(url: str) -> str:
    """Homebrewery renders in the browser; its /source/ page has the brew's Markdown."""
    m = re.match(r"(https?://homebrewery\.naturalcrit\.com)/(?:share|edit)/([\w-]+)", url)
    return f"{m.group(1)}/source/{m.group(2)}" if m else url


def prepare_url(url: str, job: Job):
    data, ctype = fetch(source_url(url))
    html = data.decode("utf-8", errors="replace")
    parser = PageText(url)
    parser.feed(html)
    text = parser.text()
    # Markdown images in a brew's source
    found = parser.images + [urllib.parse.urljoin(url, u) for u in re.findall(r"!\[[^\]]*\]\((\S+?)(?:\s[^)]*)?\)", html)]
    job.say(f"{url}: {len(text)} characters of text, {len(set(found))} pictures")
    blocks = [{"type": "text", "text": f"Web page {url}\n\n{text[:400_000]}"}]
    pictures = {}
    for src in dict.fromkeys(found):
        if len(pictures) >= MAX_WEB_IMAGES:
            break
        try:
            raw, _ = fetch(src, 15_000_000)
            img = load_image(raw)
        except Exception:
            continue
        if min(img.size) < 120:  # icons, bullets
            continue
        n = len(pictures) + 1
        pictures[n] = img
        blocks.append({"type": "text", "text": f"Picture box {n} (from {src})"})
        blocks.append(image_block(to_png(img)))
    yield "Web page", blocks, pictures, None


def prepare_image(path: str, job: Job):
    img = load_image(Path(path).read_bytes())
    (job.dir / "pages").mkdir(exist_ok=True)
    img.save(job.dir / "pages" / "1.png")
    job.say(f"{Path(path).name}: {img.size[0]}x{img.size[1]} px")
    blocks = [{"type": "text", "text": f"Page 1 ({img.size[0]} x {img.size[1]} pixels). There are no numbered boxes: "
                                       "set art_box to -1 and give `crop` as [x, y, width, height] in these pixels "
                                       "around the entry's picture, or [] when there is none."},
              image_block(to_png(img))]
    yield "Image", blocks, {}, img


# ---------------------------------------------------------------- extract

def ask_claude(client, blocks: list[dict], with_crop: bool) -> tuple[dict | None, str, object]:
    """(data, problem, usage). Data is None on a refusal or a cut-off answer."""
    content = blocks + [{"type": "text", "text": "Extract the entries on these pages."}]
    with client.messages.stream(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        system=SYSTEM,
        thinking={"type": "adaptive"},
        output_config={"effort": EFFORT, "format": {"type": "json_schema", "schema": schema(with_crop)}},
        messages=[{"role": "user", "content": content}],
    ) as stream:
        msg = stream.get_final_message()
    if msg.stop_reason == "refusal":
        d = getattr(msg, "stop_details", None)
        why = getattr(d, "explanation", None) or getattr(d, "category", None) or "no reason given"
        return None, f"refused ({why})", msg.usage
    if msg.stop_reason == "max_tokens":
        return None, "max_tokens", msg.usage
    text = next((b.text for b in msg.content if b.type == "text"), "")
    return json.loads(repair(text)), "", msg.usage


def repair(text: str) -> str:
    """Now and then a typographic character arrives broken (U+FFFD) in long answers: between a
    word and s/t/ll/re/ve/d/m it was an apostrophe, between other words a dash."""
    text = re.sub(r"(?<=\w)\ufffd(?=(?:s|t|ll|re|ve|d|m)\b)", "\u2019", text)
    return re.sub(r"(?<=\w)\ufffd(?=\w)", "\u2014", text)


def extract(client, label: str, blocks: list[dict], with_crop: bool, job: Job) -> dict:
    """Asks for one chunk; a cut-off answer is asked again in two halves (by page)."""
    data, problem, usage = ask_claude(client, blocks, with_crop)
    if usage:
        job.tokens[0] += usage.input_tokens
        job.tokens[1] += usage.output_tokens
    if data is not None:
        return data
    pages = [i for i, b in enumerate(blocks) if b["type"] == "text" and re.fullmatch(r"Page \d+", b["text"])]
    if problem == "max_tokens" and len(pages) > 1:
        cut = pages[len(pages) // 2]
        job.say(f"{label}: answer too long, splitting")
        a = extract(client, label + " (1st half)", blocks[:cut], with_crop, job)
        b = extract(client, label + " (2nd half)", blocks[cut:], with_crop, job)
        return {k: a.get(k, []) + b.get(k, []) for k in KINDS}
    job.say(f"{label}: {problem}, skipped")
    job.skipped += 1
    return {k: [] for k in KINDS}


# ---------------------------------------------------------------- normalize

def feet_m(ft) -> float:
    return float(metres(ft)) if ft else 0


def text(s: str) -> str:
    return fix_units(s.strip())


def split(line: str) -> list[str]:
    """'poison; bludgeoning, piercing' -> parts (commas inside brackets stay)."""
    parts, depth, cur = [], 0, ""
    for ch in line:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch in ",;" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip().rstrip(".").strip() for p in parts if p.strip() not in ("", "-", "—", "–")]


def damage_list(line: str) -> list[str]:
    """'cold; bludgeoning, piercing, and slashing from nonmagical attacks' keeps the phrase whole."""
    out = []
    for group in line.split(";"):
        out += [group.strip().rstrip(".")] if re.search(r"\bfrom\b|\bthat\b", group) else split(group)
    return [x for x in out if x and x not in ("-", "—", "–")]


SKILL_KEYS = ["acrobatics", "animal_handling", "arcana", "athletics", "deception", "history", "insight",
              "intimidation", "investigation", "medicine", "nature", "perception", "performance",
              "persuasion", "religion", "sleight_of_hand", "stealth", "survival"]


def bonuses(line: str, abilities: bool) -> dict[str, int]:
    """'Dex +5, Wis +3' -> {dex: 5, wis: 3}; 'Sleight of Hand +6' -> {sleight_of_hand: 6}."""
    out = {}
    for name, bonus in re.findall(r"([A-Za-z][A-Za-z ']*?)\s*([+\-−–]\s*\d+)", line):
        key = name.strip().lower()[:3] if abilities else slug(name).replace("-", "_")
        if key in (ABILITIES if abilities else SKILL_KEYS):
            out[key] = int(re.sub(r"[−–]", "-", bonus).replace(" ", ""))
    return out


def speeds(line: str) -> tuple[dict, bool]:
    out = {k: 0 for k in ("walk", "swim", "fly", "burrow", "climb")}
    for part in split(line):
        m = re.match(r"(?:(swim|fly|burrow|climb)\s*)?(\d+)\s*(?:ft|feet|')", part, re.I)
        if m:
            out[(m.group(1) or "walk").lower()] = feet_m(int(m.group(2)))
    return out, "hover" in line.lower()


def to_monster(m: dict) -> dict:
    scores = (list(m["stats"]) + [10] * 6)[:6]
    stats = {a: int(scores[i] or 10) for i, a in enumerate(ABILITIES)}
    skills = bonuses(m["skills"], False)
    senses, pp = [], 0
    for s in split(m["senses"]):
        p = re.match(r"passive perception\s*(\d+)", s, re.I)
        if p:
            pp = int(p.group(1))
        else:
            senses.append(text(s))
    speed, hover = speeds(m["speed"])
    kind, subtype = m["type"].strip(), ""
    t = re.match(r"(.+?)\s*\((.+)\)$", kind)
    if t:
        kind, subtype = t.group(1), t.group(2)
    entry = {
        "size": m["size"], "type": kind.capitalize(), "subtype": subtype, "group": "",
        "alignment": m["alignment"], "cr": m["cr"], "ac": m["ac"], "armor": m["armor"], "hp": m["hp"],
        "speed": speed, "hover": hover, "stats": stats, "saves": bonuses(m["saves"], True),
        "skills": skills, "passive_perception": pp or 10 + skills.get("perception", (stats["wis"] - 10) // 2),
        "senses": senses, "languages": [text(s) for s in split(m["languages"])],
        **{k: damage_list(m[k]) for k in ("vulnerabilities", "resistances", "immunities", "condition_immunities")},
        "environments": [], "spells": [],
        "description": text(m["description"]), "legendary_intro": text(m["legendary_intro"]),
    }
    if m.get("hit_dice"):
        entry["hit_dice"] = m["hit_dice"]
    for field in FEATURE_LISTS:
        entry[field] = []
    for f in m["features"]:
        if f.get("name"):
            entry[f["section"] + "s"].append(parse_feature(text(f["name"]).rstrip("."), text(f["text"])))
    return entry


def to_spell(s: dict) -> dict:
    head = s["components"].split("(")[0]
    mat = re.search(r"\((.+)\)", s["components"])
    rng = re.match(r"(\d+)\s*(?:ft|feet|foot)", s["range"])
    conc = s["duration"].lower().startswith("concentration")
    return {
        "level": s["level"], "school": s["school"].capitalize(), "subschool": "",
        "casting_time": s["casting_time"], "range_m": feet_m(int(rng.group(1))) if rng else 0,
        "duration": re.sub(r"^concentration,\s*", "", s["duration"], flags=re.I).strip().capitalize() if conc else s["duration"],
        "concentration": conc, "ritual": "ritual" in s["casting_time"].lower(),
        "components": {"verbal": bool(re.search(r"\bV\b", head)), "somatic": bool(re.search(r"\bS\b", head)),
                       "material": bool(re.search(r"\bM\b", head)), "material_text": mat.group(1).strip() if mat else ""},
        "classes": split(s["classes"]), "description": text(s["description"]),
    }


def to_item(i: dict) -> dict:
    out = {"rarity": i["rarity"], "type": split(i["type"]), "gold": 0, "weight": 0, "description": text(i["description"])}
    if i["attunement"]:
        out["attunement"] = i["attunement"]
    return out


CONVERT = {"monsters": to_monster, "spells": to_spell, "items": to_item}


# ---------------------------------------------------------------- main

def page_range(s: str | None) -> tuple[int, int] | None:
    if not s:
        return None
    a, _, b = s.partition("-")
    return int(a), int(b or a)


def run(args, job: Job) -> None:
    import anthropic

    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise RuntimeError("No Anthropic API key: set it in the import settings.")
    client = anthropic.Anthropic()
    job.tokens, job.skipped = [0, 0], 0
    kind = args.kind
    origin_base = {"import": kind, ("url" if kind == "url" else "file"): args.input}
    if kind == "pdf":
        chunks = prepare_pdf(args.input, job, page_range(args.pages))
        source = re.sub(r"^[\s\-–]+", "", Path(args.input).stem)
    elif kind == "image":
        chunks = prepare_image(args.input, job)
        source = Path(args.input).stem
    else:
        chunks = prepare_url(args.input, job)
        source = urllib.parse.urlparse(args.input).netloc
    entries = {k: [] for k in KINDS}
    art = {}   # (kind, index) -> art box ref
    (job.dir / "art").mkdir(exist_ok=True)
    for label, blocks, boxes, holder in chunks:
        data = extract(client, label, blocks, kind == "image", job)
        counts = []
        for k in KINDS:
            got = [e for e in data.get(k, []) if e.get("name", "").strip()]
            if got:
                counts.append(f"{len(got)} {k if len(got) > 1 else k[:-1]}")
            for raw in got:
                e = {"id": slug(raw["name"]), "name": raw["name"].strip(), "source": source, "image": ""}
                e.update(CONVERT[k](raw))
                page = int(raw.get("page") or 1)
                if kind != "url":
                    e["origin"] = {**origin_base, "page": page}
                    e["source_page"] = f"pages/{page}.png"
                else:
                    e["origin"] = dict(origin_base)
                box = raw.get("art_box", -1)
                if kind == "image" and len(raw.get("crop") or []) == 4:
                    art[(k, len(entries[k]))] = ("crop", holder, raw["crop"])
                elif box in boxes:
                    art[(k, len(entries[k]))] = ("box", holder, boxes[box])
                    if kind == "pdf":
                        p, r = boxes[box]
                        if p == page:
                            e["crop"] = [round(v * PAGE_DPI / 72) for v in (r.x0, r.y0, r.width, r.height)]
                entries[k].append(e)
        job.say(f"{label}: {', '.join(counts) or 'nothing found'}")
    # ids, art, features, tables
    for k in KINDS:
        unique_ids(entries[k])
    used = set()
    for (k, i), (how, holder, where) in art.items():
        e = entries[k][i]
        out = job.dir / "art" / f"{e['id']}.jpg"
        if how == "crop":
            x, y, w, h = where
            if w > 8 and h > 8:
                holder.crop((x, y, x + w, y + h)).save(out, quality=88)
                e["crop"] = [x, y, w, h]
            else:
                continue
        elif isinstance(where, tuple):   # PDF box: (page, rect)
            if id(where) in used:
                continue
            used.add(id(where))
            holder[where[0] - 1].get_pixmap(clip=where[1], dpi=ART_DPI).save(out, jpg_quality=85)
        else:                            # web picture
            where.save(out, quality=88)
        e["image"] = f"art/{e['id']}.jpg"
    feats = extract_features(entries["monsters"], source)
    report = Counter()
    tables = extract_tables({k: v for k, v in entries.items() if v}, source, report)
    write(job.dir / "package.json", {"format": "dragoon-package", "format_version": 1, "id": job.state.get("id", job.dir.name),
                                     "name": f"Import: {source}", "kind": "draft", "version": "0.0.0", "target": args.target})
    total = 0
    for k, v in [*entries.items(), ("features", feats), ("tables", tables)]:
        if v:
            v.sort(key=lambda e: e["name"].lower())
            write(job.dir / f"{k}.json", v)
            if k in KINDS:
                total += len(v)
    pictures = sum(1 for k in KINDS for e in entries[k] if e["image"])
    job.say(f"{total} drafts ready ({len(feats)} features, {len(tables)} tables, {pictures} pictures)"
            + (f", {job.skipped} part(s) skipped" if job.skipped else ""))
    job.say(f"Tokens: {job.tokens[0]} in, {job.tokens[1]} out")


def write(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    for a in ["--input", "--kind", "--target", "--job", "--packages"]:
        ap.add_argument(a, required=True)
    ap.add_argument("--pages", help="PDF only: e.g. 60-70")
    args = ap.parse_args()
    job = Job(Path(args.job))
    job.set(status="running")
    job.say(f"Reading {Path(args.input).name if args.kind != 'url' else args.input} ({args.kind}) with {MODEL}")
    try:
        import anthropic
        try:
            run(args, job)
        except anthropic.AuthenticationError:
            raise RuntimeError("The API key was not accepted (import settings).")
        except anthropic.RateLimitError:
            raise RuntimeError("Rate limited by the API, try again later.")
        except anthropic.APIConnectionError:
            raise RuntimeError("No connection to the Anthropic API.")
        except anthropic.APIStatusError as e:
            raise RuntimeError(f"API error {e.status_code}: {e.message}")
    except Exception as e:
        job.say("Failed: " + str(e))
        if not isinstance(e, RuntimeError):
            job.say(traceback.format_exc(limit=3))
        job.set(status="failed", error=str(e), finished=datetime.now().isoformat(timespec="seconds"))
        return 1
    job.set(status="done", finished=datetime.now().isoformat(timespec="seconds"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
