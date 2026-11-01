# Data layout: core, world, timeline

Decided by Nico on 2026-11-01: **JSON everywhere, the VTT is the editor.** Text fields stay
Markdown (including `<reveal>` tags, see reveal-visibility.md). Obsidian is only an import source
(`tools/import_obsidian.py`, `tools/import_characters.py`).

## Layers

| Layer | Stored as | Example |
| --- | --- | --- |
| Core | source packages in `data/packages/<id>/` (package-format.md) | Goblin, Fireball |
| World | world package in `data/worlds/<world-id>/` | Thornwick, Red Fang Clan, Mira the smith |
| Timeline | `data/worlds/<world-id>/timelines/<id>/`: events, notes, encounters | Mira as she is in our Tuesday group |

Campaigns and "send into campaign" were replaced by timelines on 2026-11-01. The folder layout,
forks, `entity.created` and promote are described in **timelines.md**. A whole world can be
exported and imported like a book.

## World

```text
data/worlds/<world-id>/
  package.json       kind: "world", plus "calendar": "<calendar id>"
  characters.json  creatures.json  places.json  factions.json  items.json  maps.json  lore.json  features.json
  assets/            token art, map images, portraits
  timelines/<id>/    timeline.json, events.jsonl, notes.json, encounters.json
```

- Kind files: `creatures.json` (stat blocks, formerly `monsters.json`) and `characters.json` (PCs
  and NPCs together, formerly `pcs.json` and `npcs.json`). Old files are migrated on load
  (`scripts/data/kind_migration.gd`).
- Play state is never written into these files. It comes from the timeline's event log
  (state at a moment = entries + events up to that moment).
- Session notes are entries in the timeline's `notes.json`.

## Entry schema (TASK-1, updated TASK-43)

Defined by Mochi. Same rules as the packages: one JSON array per kind, every key has one type
(empty values are `""`, `[]`, `{}` or `0`, never `null`), all text fields are Markdown and may
contain `<reveal>` tags. The editor's field list per kind is `scripts/data/schema.gd`.
Example world: `data/worlds/westmarch/`.

### References

A **ref** points at another entry as `"<kind>/<id>"`, e.g. `"places/thornwick"`. It resolves
timeline-created entries → world → core (first match wins). A qualified ref skips the search:
`"world:<kind>/<id>"` or `"core:<package>/<kind>/<id>"`. Event `entity` fields use the plain ref
(`"characters/aria"`). Wikilinks `[[Name]]` in text resolve by name in the same order.

### Fields every entry has

| Field | Type | |
| --- | --- | --- |
| `id` | string | **required**, slug, unique within its kind in this package/world |
| `name` | string | **required** |
| `description` | Markdown | what the entry is; `<reveal>` for hidden parts |
| `image` | string | picture/portrait, path relative to the package/world folder (`"assets/mira.png"`) |
| `tags` | string[] | free labels |
| `draft` | bool | not finished, hidden from lists and players (package-format.md) |
| `origin` | object | where it was imported from (`vault`, `path` or `import`, `file`/`url`, `page`) |

### Characters and creatures (on the map)

Shared fields: `token` (token image, empty = `image`), `size` (`Tiny` … `Gargantuan`, sets the
squares), `ac`, `hp` (maximum; current HP comes from `hp.changed` events),
`speed{walk,swim,fly,burrow,climb}` (metres), `stats{str..cha}`, `saves{}` and `skills{}` (total
bonus, only proficient ones), `passive_perception`, `senses`, `languages`.

**Character** (`characters.json`): PCs and NPCs in one kind (TASK-43).

| Field | Type | |
| --- | --- | --- |
| `owners` | string[] | player ids who control it (the DM always does); empty = NPC |
| `race` | ref | e.g. `"races/half-elf"`; plain name if the race isn't in any package |
| `classes` | object[] | `{class: ref, subclass: ref or "", level: int}`; total level = sum |
| `background`, `alignment`, `role` | string | role: "Smith", "Innkeeper" |
| `attitude` | string | towards the party: `friendly`, `neutral`, `hostile` |
| `proficiency_bonus` | int | |
| `proficiencies` | string[] | armor, weapons, tools |
| `traits` | feature ids | manual traits (NPCs without a class) |
| `features` | ref[] | class features, feats |
| `spells` | ref[] | known/prepared spells, e.g. `"spells/hunters-mark"` |
| `inventory` | object[] | starting kit `{item: ref, qty: int, equipped: bool}`; changes are `item.*` events |
| `factions` | ref[] | |
| `location` | ref | starting place; travel is events |
| `stat_block` | ref | creature to fight with, e.g. `"core:5e-core-rules/creatures/commoner"`; fields set on the character override it |

**Creature** (`creatures.json`): the package creature schema (package-format.md, formerly
"monster") plus `token`. Its feature ids point into `features.json` of the same package/world.
Dropping a creature on a map makes numbered timeline copies (`copy_of`, `copy_number`) with their
own HP.

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

### Note (`notes.json`, per timeline)

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

### Timeline (`timeline.json`)

See timelines.md: `name`, `players: [{id, name, color}]` (color as `"#rrggbb"`, the account color
used for reveal frames), `dm: {name, color}`, `parent`, `fork_at`, `next_session`, `created`.
