"""Extract monster art from a package's PDFs (docs/) and set it as the monster image.

Usage:
    python tools/extract_pdf_art.py data/packages [--package ID] [--any-package] [--dry-run]

For every PDF page with artwork (an image that is not the full-page background), the page
region is rendered (so flattened/scanned pages work too) and matched to a monster whose name
is a heading on the same page (big font, line text == monster name). If a page has art but no
heading, the next page's first heading is tried (lore page before the stat block).

Output per package:
    art/<monster-id>.jpg
    art/index.json   {"monsters": {"<name>": {"file": "art/<id>.jpg", "pdf": ..., "page": n}}}
The importer keeps art/ and fills empty monster images from art/index.json on every run.
Monsters that already have an image (from the vault) are left alone.

--any-package: also match monsters of other packages (art lands in the monster's package).
Only for our own books; data/ is git-ignored and never pushed.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

import pymupdf

MIN_AREA = 0.06      # art must cover at least 6% of the page
MAX_AREA = 0.85      # bigger = page background
MIN_SIDE = 60        # points
DPI = 150
JPG_QUALITY = 85


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def load_monsters(root: Path) -> dict[str, list[tuple[str, dict]]]:
    """normalized name -> [(package id, monster entry)]"""
    out: dict[str, list] = defaultdict(list)
    for f in sorted(root.glob("*/creatures.json")):
        for m in json.loads(f.read_text(encoding="utf-8")):
            out[norm(m["name"])].append((f.parent.name, m))
    return out


def page_headings(page, body_size: float, names: set[str]) -> list[tuple[str, pymupdf.Rect]]:
    """Lines in a bigger font than the body whose text is a known monster name."""
    found = []
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            spans = [s for s in line["spans"] if s["text"].strip()]
            if not spans:
                continue
            size = max(s["size"] for s in spans)
            if size < body_size * 1.05:
                continue
            key = norm("".join(s["text"] for s in spans))
            if key in names:
                found.append((key, pymupdf.Rect(line["bbox"])))
    return found


def art_regions(page, decor: set[int]) -> list[pymupdf.Rect]:
    """Artwork on the page. Images on many pages (borders, ornaments) are skipped; touching
    pieces (art sliced into tiles) are merged into one region."""
    area = page.rect.width * page.rect.height
    pieces = []
    for info in page.get_image_info(xrefs=True):
        if info["xref"] in decor:
            continue
        r = pymupdf.Rect(info["bbox"]) & page.rect
        if not r.is_empty and r.get_area() <= MAX_AREA * area:
            pieces.append(r)
    merged = True
    while merged:  # union pieces that touch or overlap
        merged = False
        for i in range(len(pieces)):
            for j in range(i + 1, len(pieces)):
                if dist(pieces[i], pieces[j]) <= 2:
                    pieces[i] = pieces[i] | pieces.pop(j)
                    merged = True
                    break
            if merged:
                break
    return [r for r in pieces
            if r.width >= MIN_SIDE and r.height >= MIN_SIDE
            and MIN_AREA <= r.get_area() / area <= MAX_AREA]


def decor_images(doc) -> set[int]:
    """xrefs of images used on more than 3 pages."""
    seen: dict[int, int] = defaultdict(int)
    for page in doc:
        for x in {i["xref"] for i in page.get_image_info(xrefs=True)}:
            seen[x] += 1
    return {x for x, n in seen.items() if n > 3 and x}


def body_font_size(doc) -> float:
    sizes = []
    for pno in range(0, doc.page_count, max(1, doc.page_count // 25)):
        for block in doc[pno].get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                sizes += [round(s["size"], 1) for s in line["spans"] if len(s["text"].strip()) > 3]
    return statistics.median(sizes) if sizes else 9.0


def dist(a: pymupdf.Rect, b: pymupdf.Rect) -> float:
    dx = max(0, a.x0 - b.x1, b.x0 - a.x1)
    dy = max(0, a.y0 - b.y1, b.y0 - a.y1)
    return (dx * dx + dy * dy) ** 0.5


def scan_pdf(pdf: Path, names: set[str]) -> list[tuple[str, int, pymupdf.Rect]]:
    """[(normalized monster name, page index, art rect)]"""
    doc = pymupdf.open(pdf)
    body = body_font_size(doc)
    decor = decor_images(doc)
    heads: dict[int, list] = {}

    def headings(p: int) -> list:  # only read text of pages that matter (slow part)
        if p not in heads:
            heads[p] = page_headings(doc[p], body, names) if p < doc.page_count else []
        return heads[p]

    hits = []
    for pno in range(doc.page_count):
        regions = art_regions(doc[pno], decor)
        if not regions:
            continue
        same = headings(pno)
        cands = same or headings(pno + 1)[:1]
        if not cands:
            continue
        taken = set()
        for r in regions:
            key, _ = min(cands, key=lambda c: dist(r, c[1]) if same else 0)
            if key in taken:
                continue
            taken.add(key)
            hits.append((key, pno, r))
    doc.close()
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("--package")
    ap.add_argument("--any-package", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    monsters = load_monsters(args.root)
    changed: dict[str, set[str]] = defaultdict(set)   # package -> monster names with new art
    indexes: dict[str, dict] = {}
    total = 0
    for pdir in sorted(p for p in args.root.iterdir() if (p / "docs").is_dir()):
        if args.package and pdir.name != args.package:
            continue
        own = {k for k, v in monsters.items() if any(pid == pdir.name for pid, _ in v)}
        names = set(monsters) if args.any_package else own
        if not names:
            continue
        for pdf in sorted((pdir / "docs").glob("*.pdf")):
            try:
                hits = scan_pdf(pdf, names)
            except Exception as e:  # broken PDF: report and go on
                print(f"  ! {pdf.name}: {e}", file=sys.stderr)
                continue
            doc = pymupdf.open(pdf)
            for key, pno, rect in hits:
                for pid, m in monsters[key]:
                    if pid != pdir.name and not args.any_package:
                        continue
                    if m["image"] and not m["image"].startswith("art/"):
                        continue  # vault image wins
                    idx = indexes.setdefault(pid, {"monsters": {}})["monsters"]
                    if m["name"] in idx:
                        continue  # first hit wins
                    file = f"art/{m['id']}.jpg"
                    idx[m["name"]] = {"file": file, "pdf": pdf.name, "page": pno + 1}
                    changed[pid].add(m["name"])
                    total += 1
                    print(f"  {pid}: {m['name']}  <- {pdf.name} p.{pno + 1}")
                    if not args.dry_run:
                        out = args.root / pid / file
                        out.parent.mkdir(exist_ok=True)
                        pix = doc[pno].get_pixmap(clip=rect, dpi=DPI)
                        pix.save(out, jpg_quality=JPG_QUALITY)
            doc.close()

    if not args.dry_run:
        for pid, idx in indexes.items():
            idx_file = args.root / pid / "art" / "index.json"
            old = json.loads(idx_file.read_text(encoding="utf-8")) if idx_file.exists() else {"monsters": {}}
            old["monsters"].update(idx["monsters"])
            idx_file.write_text(json.dumps(old, ensure_ascii=False, indent=1), encoding="utf-8")
            apply_index(args.root / pid)
    print(f"{total} monster images {'found' if args.dry_run else 'extracted'}")
    return 0


def apply_index(pdir: Path) -> int:
    """Set empty monster images from art/index.json (also called by the importer)."""
    idx_file, mfile = pdir / "art" / "index.json", pdir / "creatures.json"
    if not idx_file.exists() or not mfile.exists():
        return 0
    idx = json.loads(idx_file.read_text(encoding="utf-8"))["monsters"]
    entries = json.loads(mfile.read_text(encoding="utf-8"))
    n = 0
    for m in entries:
        art = idx.get(m["name"])
        if art and not m["image"] and (pdir / art["file"]).exists():
            m["image"] = art["file"]
            n += 1
    if n:
        mfile.write_text(json.dumps(entries, ensure_ascii=False, indent=1), encoding="utf-8")
    return n


if __name__ == "__main__":
    sys.exit(main())
