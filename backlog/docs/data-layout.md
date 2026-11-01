# Data layout: core, world, campaign

Decided by Nico on 2026-11-01: **JSON everywhere, the VTT is the editor.** This replaces the
concept's "markdown files from the vault program" for world and campaign data. Text fields stay
Markdown (including `<reveal>` tags, see reveal-visibility.md). Obsidian is only an import source
now (`tools/import_obsidian.py`).

## Layers

| Layer | Stored as | Example |
| --- | --- | --- |
| Core | source packages, `kind: "source"` (package-format.md) | Goblin, Fireball |
| World | packages too, `kind: "world"` | Thornwick, Red Fang Clan, Mira the smith |
| Campaign | one campaign folder with its own entities and event log | Mira as she is in campaign A |

Worlds being packages means a whole world can be exported and imported like a book.

## World package

```text
data/packages/<world-id>/
  package.json       kind: "world", plus "calendar": "<calendar id>"
  npcs.json  places.json  factions.json  items.json  maps.json  lore.json
  assets/            token art, map images, portraits
```

## Campaign folder

```text
data/campaigns/<campaign-id>/
  campaign.json      name, world (package id), calendar, players (id, name, color), dm (name, color), next_session
  pcs.json  npcs.json  monsters.json  items.json  places.json  maps.json  notes.json
  events.jsonl       append-only event log (doc-1 Event format)
  assets/
```

- Every campaign entry that was **sent** from core or world keeps `origin`:
  `{"layer": "core"|"world", "package": "5e-core-rules", "kind": "monsters", "id": "goblin", "version": "1.0.0"}`.
  After that it drifts freely; pulling upstream changes is a deliberate action later.
- Entries created directly in the campaign have no `origin`.
- Field names are the same as in the packages (`hp`, `ac`, `stats`, `traits`/`actions` with
  feature ids, `description` ...). Sending a monster copies its features into the campaign's own
  `features.json` so the campaign is self-contained.
- Play state is never written back into these files: it comes from the event log
  (state at a moment = campaign entries + events up to that moment).
- Session notes are entries in `notes.json` (Markdown `text`, real date, session number,
  in-world day), not loose `.md` files.

## Still to define (TASK-1)

Fields per world/campaign kind: PC, NPC, place, faction, map (image, grid size, cell size,
party start), lore, note. Wikilinks `[[Name]]` in text resolve inside campaign → world → core.
