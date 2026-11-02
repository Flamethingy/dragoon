"""The AI pass for missing effects (TASK-66): Claude proposes the `effects` (package-format.md,
"Effects") of entries the regex parser (tools/parse_effects.gd) could not structure. Proposals
are written as drafts next to their entry (`draft_of`), the DM reviews them on the compendium's
Drafts page (now vs proposed) and publishes them into the entry, or discards them.

One package and kind at a time; the cost estimate always comes first:

    python tools/ai_effects.py estimate --package 5e-core-rules --kind spells [--limit N]
    python tools/ai_effects.py run      --package 5e-core-rules --kind spells --limit 5 --yes
    python tools/ai_effects.py submit   --package 5e-core-rules --kind spells --yes   (Batch API, half price)
    python tools/ai_effects.py collect  --package 5e-core-rules --kind spells [--batch ID]
    python tools/ai_effects.py fake     --package ... --kind ... --limit N   (no API: a stand-in proposal, for tests)

`run` asks directly (for small tests), `submit` sends a Message Batch and remembers its id in
<package>/ai_effects_batches.json; `collect` writes the results once it has ended.
The API key comes only from ANTHROPIC_API_KEY. It is never printed, logged or written.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

MODEL = "claude-opus-5-5"
EFFORT = "low"
MAX_TOKENS = 4000
# Claude Opus 5.5, USD per million tokens (standard; the Batch API is half)
PRICE_IN = 4.0
PRICE_OUT = 20.0
OUT_PER_ENTRY = 700  # tokens per answer incl. thinking, a rough guess
KINDS = ["spells", "features", "items"]
EFFECT_KEYS = {"roll", "apply", "heal", "modifier", "resource"}

SYSTEM = """You turn tabletop RPG (D&D 5e) rules text into structured effects for a virtual tabletop.
You get one entry (a spell, a creature feature or an item) as JSON. Answer with JSON only:
{"effects": [...], "notes": "one short sentence on anything left out"}.

The effects format (all optional parts may be left out; sizes in metres, 1 square = 1.5 m):
- {"roll": "attack", "to_hit": "spell" | <number>, "range": "melee" | "ranged", "damage": [{"dice": "1d10", "type": "fire"}],
   "scaling": {...}}
- {"roll": "save", "ability": "str|dex|con|int|wis|cha", "dc": "spell" | <number>,
   "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}], "conditions": ["frightened"]}, "on_success": "half" | "none",
   "area": {"shape": "sphere|cone|line|cube|cylinder|emanation", "size_m": 6, "width_m": 1.5},
   "duration": {"rounds": 10, "ends": "turn_end", "save_ends": true}, "scaling": {...}}
- {"apply": "condition", "condition": "<5e condition id>", "duration": {"rounds": 10},
   "save_ends": {"ability": "wis", "when": "end_of_turn"}}
- {"heal": "1d8+mod", "scaling": {"per_slot": "1d8", "above": 1}}   ("+mod" = the caster's spellcasting modifier)
- {"modifier": {"target": "ac|attack|damage|save|check|speed", "op": "add", "value": 2 | "1d4"}, "duration": {"rounds": 10}}
- {"resource": {"id": "<slug>", "max": <number>, "reset": "short|long|dawn"}}
- scaling: {"per_slot": "1d6", "above": 3} (more dice per slot level above the spell's level), {"cantrip": "1d10"}
  (one more die at character levels 5, 11 and 17), {"targets_per_slot": 1, "above": 2}.
- durations in rounds: 1 minute = 10, 10 minutes = 100, 1 hour = 600. Add "concentration": true to an effect of a
  concentration spell.
Damage types: acid, bludgeoning, cold, fire, force, lightning, necrotic, piercing, poison, psychic, radiant,
slashing, thunder. Conditions: blinded, charmed, deafened, frightened, grappled, incapacitated, invisible,
paralyzed, petrified, poisoned, prone, restrained, stunned, unconscious, exhaustion.

Only structure what the text clearly says; leave out choices, summons, illusions and narrative parts (say so
in notes). If nothing can be structured, answer {"effects": [], "notes": "..."}. Never invent numbers."""


def load(pkg_dir: Path, kind: str) -> list[dict]:
    f = pkg_dir / f"{kind}.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else []


def save(pkg_dir: Path, kind: str, data: list[dict]) -> None:
    f = pkg_dir / f"{kind}.json"
    tmp = f.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(f)


def todo(entries: list[dict], limit: int) -> list[dict]:
    """Published entries without effects and without a proposal yet."""
    proposed = {e.get("draft_of") for e in entries if e.get("draft_of")}
    out = []
    for e in entries:
        if e.get("draft") or e.get("draft_of") or e.get("effects") or e.get("effects_checked") or e.get("id") in proposed:
            continue
        if not str(e.get("description", e.get("text", ""))).strip():
            continue
        out.append(e)
    return out[:limit] if limit > 0 else out


def prompt_of(e: dict) -> str:
    keep = {k: e[k] for k in ("name", "level", "casting_time", "duration", "concentration", "range_m", "uses",
                              "attack", "save", "damage", "type", "rarity") if k in e and e[k] not in ("", None, [], {})}
    keep["text"] = e.get("description", e.get("text", ""))
    return json.dumps(keep, ensure_ascii=False)


def estimate(entries: list[dict]) -> dict:
    """Rough tokens and dollars (about 3.5 characters per token)."""
    tin = sum(len(SYSTEM) / 3.5 + len(prompt_of(e)) / 3.5 + 20 for e in entries)
    tout = OUT_PER_ENTRY * len(entries)
    std = tin / 1e6 * PRICE_IN + tout / 1e6 * PRICE_OUT
    return {"entries": len(entries), "input_tokens": int(tin), "output_tokens": tout, "usd": round(std, 2), "usd_batch": round(std / 2, 2)}


def show_estimate(est: dict, what: str) -> None:
    print(f"{what}: {est['entries']} entries, ~{est['input_tokens']:,} input + ~{est['output_tokens']:,} output tokens "
          f"(model {MODEL}): about ${est['usd']:.2f} directly, ${est['usd_batch']:.2f} with the Batch API")


def parse_answer(text: str) -> tuple[list, str]:
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return [], "no JSON in the answer"
    try:
        data = json.loads(m.group(0))
    except json.JSONDecodeError as err:
        return [], f"bad JSON ({err.msg})"
    return valid(data.get("effects", [])), str(data.get("notes", ""))


def valid(effects) -> list[dict]:
    """Only effects of the format (an object with one of the known keys)."""
    if not isinstance(effects, list):
        return []
    out = []
    for fx in effects:
        if isinstance(fx, dict) and EFFECT_KEYS & fx.keys():
            if "roll" in fx and fx["roll"] not in ("attack", "save", "check"):
                continue
            out.append(fx)
    return out


def write_drafts(pkg_dir: Path, kind: str, proposals: dict[str, tuple[list, str]], job: str) -> int:
    data = load(pkg_dir, kind)
    by_id = {e.get("id"): e for e in data}
    have = {e.get("draft_of") for e in data if e.get("draft_of")}
    n = 0
    for eid, (effects, notes) in proposals.items():
        orig = by_id.get(eid)
        if orig is None or eid in have:
            continue
        if not effects:  # nothing to structure: remembered, so it is not asked (and paid) again
            if notes and notes not in ("refused", "cut off (max_tokens)") and not notes.startswith(("no JSON", "bad JSON")):
                orig["effects_checked"] = "ai"
                orig["ai_notes"] = notes
            continue
        d = {k: v for k, v in orig.items() if k not in ("effects", "effects_parsed", "edited")}
        d.update({"id": f"{eid}--effects", "draft": True, "draft_of": eid, "effects": effects, "effects_source": "ai",
                  "ai_notes": notes, "origin": {"job": job, "file": "AI effects pass"},
                  "edited": datetime.now().strftime("%Y-%m-%dT%H:%M:%S")})
        data.append(d)
        n += 1
    save(pkg_dir, kind, data)
    return n


def request_params(e: dict) -> dict:
    return {"model": MODEL, "max_tokens": MAX_TOKENS, "thinking": {"type": "adaptive"}, "output_config": {"effort": EFFORT},
            "system": [{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}],
            "messages": [{"role": "user", "content": prompt_of(e)}]}


def answer_text(msg) -> tuple[str, str]:
    """(text, problem)."""
    if msg.stop_reason == "refusal":
        return "", "refused"
    if msg.stop_reason == "max_tokens":
        return "", "cut off (max_tokens)"
    return next((b.text for b in msg.content if b.type == "text"), ""), ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["estimate", "run", "submit", "collect", "fake"])
    ap.add_argument("--packages", type=Path, default=Path("data/packages"))
    ap.add_argument("--package", required=True)
    ap.add_argument("--kind", choices=KINDS, default="spells")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--batch", default="")
    ap.add_argument("--yes", action="store_true", help="really send (it costs money)")
    args = ap.parse_args()
    pkg_dir = args.packages / args.package
    if not pkg_dir.is_dir():
        print(f"no package {pkg_dir}")
        return 1
    entries = load(pkg_dir, args.kind)
    work = todo(entries, args.limit)
    job = f"ai-effects-{args.kind}-{datetime.now().strftime('%Y%m%d-%H%M')}"
    est = estimate(work)

    if args.command == "estimate":
        show_estimate(est, f"{args.package} {args.kind} without effects")
        return 0
    if args.command == "fake":  # no API: a stand-in so the drafts flow can be tested
        props = {e["id"]: ([{"heal": "1d4"}], "fake proposal") for e in work}
        print(f"wrote {write_drafts(pkg_dir, args.kind, props, job)} fake proposals")
        return 0
    if args.command in ("run", "submit"):
        show_estimate(est, f"{args.command} {args.package} {args.kind}")
        if not work:
            return 0
        if not args.yes:
            print("not sent: add --yes to send it")
            return 0

    import anthropic  # only now: estimate and fake need neither the SDK nor a key
    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY from the environment

    if args.command == "run":
        props, used_in, used_out = {}, 0, 0
        for e in work:
            msg = client.messages.create(**request_params(e))
            used_in += msg.usage.input_tokens + (msg.usage.cache_read_input_tokens or 0) + (msg.usage.cache_creation_input_tokens or 0)
            used_out += msg.usage.output_tokens
            text, problem = answer_text(msg)
            effects, notes = parse_answer(text) if not problem else ([], problem)
            print(f"  {e.get('name')}: {len(effects)} effect(s){' - ' + notes if notes else ''}")
            props[e["id"]] = (effects, notes)
        n = write_drafts(pkg_dir, args.kind, props, job)
        print(f"wrote {n} proposals as drafts; used {used_in:,} input + {used_out:,} output tokens "
              f"(~${used_in / 1e6 * PRICE_IN + used_out / 1e6 * PRICE_OUT:.2f})")
        return 0

    batches_file = pkg_dir / "ai_effects_batches.json"
    batches = json.loads(batches_file.read_text(encoding="utf-8")) if batches_file.exists() else []
    if args.command == "submit":
        from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
        from anthropic.types.messages.batch_create_params import Request
        reqs = [Request(custom_id=re.sub(r"[^a-zA-Z0-9_-]", "_", e["id"])[:64], params=MessageCreateParamsNonStreaming(**request_params(e)))
                for e in work]
        ids = {r["custom_id"]: e["id"] for r, e in zip(reqs, work)}
        batch = client.messages.batches.create(requests=reqs)
        batches.append({"id": batch.id, "kind": args.kind, "job": job, "ids": ids, "sent": datetime.now().isoformat(timespec="seconds")})
        batches_file.write_text(json.dumps(batches, indent=1), encoding="utf-8")
        print(f"sent batch {batch.id} ({len(reqs)} requests); collect it with: python tools/ai_effects.py collect --package {args.package} --kind {args.kind}")
        return 0

    # collect
    open_ones = [b for b in batches if b["kind"] == args.kind and not b.get("collected") and (not args.batch or b["id"] == args.batch)]
    if not open_ones:
        print("no batch to collect")
        return 0
    for b in open_ones:
        status = client.messages.batches.retrieve(b["id"])
        if status.processing_status != "ended":
            print(f"batch {b['id']}: {status.processing_status} ({status.request_counts.processing} still running)")
            continue
        props, failed = {}, 0
        for r in client.messages.batches.results(b["id"]):
            eid = b["ids"].get(r.custom_id)
            if r.result.type != "succeeded" or eid is None:
                failed += 1
                continue
            text, problem = answer_text(r.result.message)
            props[eid] = parse_answer(text) if not problem else ([], problem)
        n = write_drafts(pkg_dir, args.kind, props, b["job"])
        b["collected"] = datetime.now().isoformat(timespec="seconds")
        print(f"batch {b['id']}: wrote {n} proposals as drafts ({failed} failed)")
    batches_file.write_text(json.dumps(batches, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
