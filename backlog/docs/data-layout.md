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

## Entry schema (TASK-1)

Defined by Mochi on 2026-11-01. Same rules as the packages: one JSON array per kind, every key
has one type (empty values are `""`, `[]`, `{}` or `0`, never `null`), all text fields are
Markdown and may contain `<reveal>` tags. Example: `examples/campaigns/red-fang/` (campaign) and
`examples/packages/westmarch/` (its world).

### References

A **ref** points at another entry as `"<kind>/<id>"`, e.g. `"places/thornwick"`. It resolves
campaign → world → core (first match wins), so a campaign copy hides the world/core original.
A qualified ref skips the search: `"world:<kind>/<id>"` or `"core:<package>/<kind>/<id>"`
(same form as `entity.sent`). Event `entity` fields use the plain ref of the campaign entry
(`"pcs/aria"`). Wikilinks `[[Name]]` in text resolve by name in the same order.

### Fields every entry has

| Field | Type | |
| --- | --- | --- |
| `id` | string | **required**, slug, unique within its kind in this campaign/package |
| `name` | string | **required** |
| `description` | Markdown | what the entry is; `<reveal>` for hidden parts |
| `image` | string | picture/portrait, path relative to the folder's `assets/` parent (`"assets/mira.png"`) |
| `tags` | string[] | free labels |
| `origin` | object | only on entries **sent** into a campaign (see above); entries in packages keep their importer `origin` (`vault`, `path`) |

### Creatures on the map: PC, NPC, monster

Shared token fields:

| Field | Type | |
| --- | --- | --- |
| `token` | string | token image path (`"assets/tokens/aria.png"`); empty = use `image` |
| `size` | string | `Tiny` … `Gargantuan` (package spelling); sets the squares on the grid (Large 2x2 …) |

**PC** (`pcs.json`):

| Field | Type | |
| --- | --- | --- |
| `player` | string | **required**, player id from `campaign.json` (the owner; may move the token) |
| `race` | ref | e.g. `"races/half-elf"` (core) |
| `classes` | object[] | `{class: ref, subclass: ref or "", level: int}`; total level = sum |
| `background`, `alignment` | string | |
| `hp` | int | maximum HP (current HP comes from `hp.changed` events) |
| `ac`, `speed{walk,swim,fly,burrow,climb}` (metres), `stats{str..cha}` | | as monsters |
| `saves`, `skills` | object | total bonus per ability/skill, as monsters (only proficient ones) |
| `proficiency_bonus`, `passive_perception` | int | |
| `senses`, `languages`, `proficiencies` | string[] | |
| `features` | string[] | feature ids in the campaign's `features.json` (class features, feats, attacks) |
| `spells` | ref[] | known/prepared spells, e.g. `"spells/hunters-mark"` |
| `inventory` | object[] | starting kit: `{item: ref, qty: int, equipped: bool}`; changes are `item.*` events |
| `factions` | ref[] | |
| `location` | ref | place where the character is (starting value; travel is events) |

**NPC** (`npcs.json`): a named person. All fields optional except `id`/`name`:

| Field | Type | |
| --- | --- | --- |
| `role` | string | "Smith", "Innkeeper" |
| `race`, `alignment` | string | free text |
| `location` | ref | where they live/are |
| `factions` | ref[] | |
| `stat_block` | ref | monster to fight with, e.g. `"core:5e-core-rules/monsters/commoner"`; fields set on the NPC itself (`hp`, `ac`, `stats` …, all monster fields allowed) override it |
| `attitude` | string | towards the party: `friendly`, `neutral`, `hostile` |

**Monster** (`monsters.json`): exactly the package monster schema (package-format.md) plus
`token`. Its feature ids point into the campaign's `features.json`, which gets a copy of the
features when a monster is sent.

### Places, factions, lore

**Place** (`places.json`): `type` (string: `region`, `town`, `dungeon`, `building`, `landmark` …),
`parent` (ref, the place it lies in), `map` (ref, its local map), `factions` (ref[]),
`population` (int, 0 = unknown), `world_at` (`[x, y]` cell on the world map, `[]` if none).

**Faction** (`factions.json`): `type` (string: `guild`, `clan`, `church` …), `leader` (ref),
`headquarters` (ref, place), `allies`, `enemies` (ref[]), `goals` (Markdown).

**Lore** (`lore.json`): `category` (string: `history`, `religion`, `legend`, `rumor` …),
`related` (ref[]). Its `description` is the text.

### Map (`maps.json`)

| Field | Type | |
| --- | --- | --- |
| `image` | string | **required**, map image path |
| `kind` | string | `local` (default) or `world` (the party travels as one token) |
| `grid` | object | `size` (pixels per cell in the image), `offset` (`[x, y]` pixels), `cell_m` (metres per cell, default 1.5), `cell_label` (optional text instead, e.g. `"1 day"` on world maps) |
| `party_start` | `[x, y]` | cell where PCs appear |
| `party_token` | string | image of the party token (world maps) |
| `place` | ref | the place this map shows |
| `tokens` | object[] | starting placement `{entity: ref, at: [x, y]}`; moves are events |

### Note (`notes.json`, campaign only)

Session notes and the chronicle. Written by the VTT, one entry per note:

| Field | Type | |
| --- | --- | --- |
| `id` | string | **required**, `n1`, `n2` … (in creation order) |
| `text` | Markdown | **required**; `<reveal>` works here too |
| `real` | string | real date and time, ISO 8601 local (`2026-11-01T20:15`) |
| `session` | int | 0 = between sessions |
| `day`, `time` | int | in-world day and minutes (`-1` = unknown), from the clock when written |
| `by` | string | `dm` or the player id |
| `about` | ref | optional entry the note is about |

Notes have no `name`; the VTT shows "real date · Session N · in-world date · writer".

### Campaign (`campaign.json`)

`format: "dragoon-campaign"`, `format_version: 1`, `id`, `name`, `description`, `world` (world
package id or `""`), `calendar` (calendar id, e.g. `"default"` = `calendars/default.json`),
`players: [{id, name, color}]` (color as `"#rrggbb"`, the account color used for reveal frames),
`dm: {name, color}`, `next_session` (int), `created`.
