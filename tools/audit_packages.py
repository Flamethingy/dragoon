"""Audit converted packages: Obsidian leftovers and a field inventory per kind.

Usage: python tools/audit_packages.py data/packages [--fields KIND]
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

LEFTOVER = re.compile(r"=this\.|=choice|=link\(|`=|dataview|%%|\[!|=embed|file\.(name|path)|\bTABLE\b[^\n]*FROM")


def walk(v, path, fn):
    if isinstance(v, dict):
        for k, x in v.items():
            walk(x, path + [k], fn)
    elif isinstance(v, list):
        for x in v:
            walk(x, path + ["[]"], fn)
    else:
        fn(".".join(path), v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("packages", type=Path)
    ap.add_argument("--fields", default="", help="kind for a field inventory, or 'all'")
    args = ap.parse_args()

    hits = collections.Counter()
    examples = collections.defaultdict(list)
    fields = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    totals = collections.Counter()

    for f in sorted(args.packages.glob("*/*.json")):
        kind = f.stem
        data = json.loads(f.read_text(encoding="utf-8"))
        entries = data if isinstance(data, list) else [data]
        for e in entries:
            totals[kind] += 1
            name = e.get("name", "?")

            def check(path, v, kind=kind, name=name, pkg=f.parent.name):
                key = f"{kind}.{path}"
                if isinstance(v, str) and LEFTOVER.search(v):
                    hits[key] += 1
                    if len(examples[key]) < 2:
                        m = LEFTOVER.search(v)
                        examples[key].append(f"{pkg}/{name}: ...{v[max(0, m.start() - 50):m.start() + 90]!r}")
                fields[kind][path][repr(v)[:70]] += 1
            walk(e, [], check)

    print("== Obsidian leftovers")
    for k, n in hits.most_common():
        print(f"{n:5d} {k}")
        for x in examples[k]:
            print("        ", x)
    if not hits:
        print("none")

    kinds = list(fields) if args.fields == "all" else [args.fields] if args.fields else []
    for kind in kinds:
        print(f"\n== fields of {kind} ({totals[kind]} entries)")
        for path, values in sorted(fields[kind].items()):
            n = sum(values.values())
            empty = sum(c for v, c in values.items() if v in ("''", "0", "None", "False", "[]", "{}"))
            top = ", ".join(f"{v}×{c}" for v, c in values.most_common(4))
            print(f"  {path:40s} n={n:5d} distinct={len(values):5d} empty={empty:5d} | {top}")


if __name__ == "__main__":
    main()
