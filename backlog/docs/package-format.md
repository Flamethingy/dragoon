---
updated_date: '2026-11-02 02:33'
---

# Package format (core data)

Decided 2026-11-01. Core data (monsters, spells, items ...) does **not** live as markdown files.
It is bundled into **source packages**, one per source book / PDF / homebrew collection, stored
as JSON. The VTT is the viewer and editor (compendium); packages can be imported and exported
as a whole. World and campaign data still follow the concept.

## Layout

```text
data/packages/<package-id>/
  package.json      manifest
  monsters.json     one JSON array per kind
  spells.json
  items.json ...
  assets/           images referenced by entries (relative paths)
  docs/             PDFs of the source (rulebooks, homebrew), part of import/export
  art/              monster art cut out of the PDFs (tools/extract_pdf_art.py), kept on re-import
```

## Monster images

1. The vault's image, if the file exists (`assets/...`).
2. Otherwise art from the package's PDFs: `python tools/extract_pdf_art.py data/packages
   [--package ID] [--any-package] [--dry-run]` finds pictures (not page backgrounds or
   ornaments repeated on many pages) and matches them to a monster heading on the same page
   (or the next page). The page region is rendered as `art/<id>.jpg` (150 dpi), listed in
   `art/index.json` (name → file, pdf, page), and the importer re-applies it on every run.
   Works for normal book layouts (tested on Monsters of the Multiverse). Full-page painted
   layouts (Fools Gold) can't be split. Slow: a few minutes per big PDF.
3. Otherwise the VTT shows the creature type icon from `res://assets/creature_types/<type>.svg`
   (game-icons.net, CC BY 3.0, credits in that folder; `unknown.svg` for other types). These
   icons are in git; the PDF art is not.

The big monster books (Tome of Beasts 1-3, Creature Codex, Monstrous Menagerie, Monster Manual)
have no PDF in their package yet, so for now most monsters fall back to the type icon.

`data/` is git-ignored (copyrighted book content) and has a `.gdignore`, so Godot does not
import it. The VTT loads packages at runtime with `FileAccess`.

Kinds: `monsters, spells, items, feats, races, subraces, classes, subclasses, backgrounds,
invocations, infusions, rules, conditions, diseases, features, tables (rollable)`.

## Manifest (`package.json`)

| Field | Meaning |
|---|---|
| `format` / `format_version` | `"dragoon-package"`, `1` |
| `id` | slug of the source name, e.g. `tome-of-beasts-3` |
| `name` | display name, e.g. `Tome of Beasts 3` |
| `kind` | `source` |
| `version` | package version (semver) |
| `description` | Markdown |
| `counts` | entries per kind |
| `documents` | PDFs of the package: `[{file, title, size}]`, `file` relative to the package folder (`docs/Players Handbook.pdf`), `size` in bytes |
| `created`, `imported_from` | provenance |
| `cover` | *optional* cover image for the package card, relative to the package folder |
| `dependencies` | *optional* list of package ids (empty for now) |

In the compendium (TASK-23) every installed package is a card under **Packages** (badge S/W, entry count,
on/off switch; filter: Source/World/On/Off/Has PDFs; search over name and description). Its full view shows
the manifest, the counts per kind (links to Browse filtered to the package), the `documents` (Open in the
system viewer, Show in folder, **Add PDF...** copies into `docs/` and adds the entry) and a card overview of
its contents. Export/import pack the whole folder including `docs/`; the export dialog shows the size first.

The importer takes the PDFs linked in the vault's source page (`Sources/<Source>.md`, links like
`[[Players Handbook.pdf|Player's Handbook]]`), copies them into `docs/` (only new or changed
files, stale ones are removed) and turns the links in the description into Markdown links
(`[Player's Handbook](<docs/Players Handbook.pdf>)`). Currently 42 PDFs in 13 packages, 1.7 GB.
Unlinked PDFs (e.g. the DM Tuz Vault folders, the 2024 PHB) are not imported yet.

## Entries

Every entry has `id` (slug, unique per kind in the package), `name`, `source`, `image`
(relative path or empty), `description` (Markdown) and `origin` (where it was imported from).
**All text fields are Markdown.** Wikilinks `[[Name]]` are kept for the VTT to resolve.

### Drafts

Every entry of every kind (packages and campaigns) has `draft` (bool). Decided by Nico on 2026-11-01.

- `draft: true` = not finished. A draft is hidden from compendium lists, search, wikilink
  resolution, "send into campaign" and everything players get, unless an overview has
  **Show drafts** ticked. Players never see drafts (the host filters them).
- New entries are saved with **Save as draft** or **Save** (published). A draft has a **Publish**
  button; a published entry can be set back to draft.
- Imports from the import agent always arrive as drafts in the target package (import-agent.md).
- Features and rollable tables created together with a draft entry are drafts too and are
  published together with it.
- The Obsidian importer writes `draft: false` (book data is finished).

### Monster

`size, type, subtype, group, alignment, cr, ac, armor, hp, speed{walk,swim,fly,burrow,climb}
(metres), hover, stats{str..cha}, saves{ability: total bonus}, skills{skill: total bonus},
passive_perception, senses[], languages[], vulnerabilities[], resistances[], immunities[],
condition_immunities[], environments[], spells[]`, plus feature lists `traits, actions,
bonus_actions, reactions, legendary_actions` and `legendary_intro` (the "can take 3 legendary
actions" rules text).

The feature lists hold **feature ids** (strings) that point into `features.json` of the same
package, e.g. `"actions": ["scimitar-6", "shortbow"]`.

### Feature (`features.json`)

`{id, name, source, text (Markdown), uses?, cost?, attack?{kind, to_hit, range, damage[{dice,
average, type}]}, save?{dc, ability}, damage?[...], used_by[] (monster ids)}`. The structured
parts are parsed from the text so the dice roller can roll them; `text` stays the source of truth.

Identical features (same name, text and data) are stored once and shared (e.g. one Shortbow for
goblin and skeleton). Different ones with the same name are separate entries: `bite`, `bite-2`,
... (646 Bites in total). Which section a feature is in (trait, action, reaction ...) is decided
by the monster's list, not by the feature. Shared templates across packages are only an idea for
now: see idea-shared-features-and-package-dependencies.md.

### Spell

`level (0 = cantrip), school, subschool (e.g. "Dunamancy: Graviturgy"), casting_time, range_m
(0 = touch/self), duration, concentration, ritual, components{verbal, somatic, material,
material_text}, classes[]`. `casting_time` and `duration` are in sentence case ("1 bonus action").

### Effects (`effects`, spells / features / items, TASK-65)

An optional list of what the entry's buttons do (rules-automation.md 5.2). The text stays the
source of truth; an entry without `effects` uses the text fallback.

```json
"effects": [
  {"roll": "attack", "to_hit": "spell", "range": "ranged", "damage": [{"dice": "1d10", "type": "fire"}], "scaling": {"cantrip": "1d10"}},
  {"roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}], "conditions": []},
   "on_success": "half", "area": {"shape": "sphere", "size_m": 6.1}, "duration": {"rounds": 10, "save_ends": true},
   "scaling": {"per_slot": "1d6", "above": 3}, "concentration": true},
  {"apply": "condition", "condition": "frightened", "duration": {"rounds": 10}, "save_ends": {"ability": "wis", "when": "end_of_turn"}},
  {"heal": "1d8+mod", "scaling": {"per_slot": "1d8", "above": 1}},
  {"modifier": {"target": "ac", "op": "add", "value": 5}, "duration": {"rounds": 10}},
  {"resource": {"id": "rage", "max": 3, "reset": "long"}}
]
```

- `to_hit` / `dc`: a number, or `"spell"` (the caster's spell attack / save DC). `heal`: `+mod` = the casting ability modifier.
- `on_success`: `"half"` or `"none"`. `area.shape`: sphere, cone, line (`width_m`), cube, cylinder, emanation; sizes in metres.
- `scaling`: `per_slot` dice per slot level `above` the base, `cantrip` dice at levels 5/11/17, `targets_per_slot`.
- `duration`: `rounds` (a minute = 10), `ends: "turn_end"`, `of` (whose turns count), `save_ends`.
- Filled by the regex parser `tools/parse_effects.gd` (`Effects.parse`; `--write` to save,
  `--strip` removes them again); parsed entries carry `effects_parsed: true`, so the AI pass and
  hand edits (the entry editor's effects field with presets and "From the text") can replace them.

**On Use additions (TASK-108).** All of them are optional. Without them, the view works out the target from the entry.

```json
{"heal": "2d4+2", "target": {"kind": "creature", "self": true, "range_m": 0}},
{"roll": "check", "skill": "athletics", "ability": "str", "dc": 15, "by": "self",
 "on_success": {"note": "you climb up"}, "on_fail": {"damage": [{"dice": "1d6", "type": "bludgeoning"}], "conditions": ["prone"]}},
{"damage": [{"dice": "1d4+1", "type": "force"}]},
{"roll": "attack", "to_hit": 5, "damage": [{"dice": "1d8", "type": "piercing"}],
 "then": [{"when": "hit", "roll": "save", "ability": "con", "dc": 13, "on_fail": {"conditions": ["poisoned"]}, "on_success": "none"}]}
```

- `target`: who the step affects.
  - `kind` is `self`, `creature`, `creatures` (`count`, 0 = any number) or `area` (uses the step's `area`).
  - `range_m` is the range; 0 = touch.
  - `self: true` means "you or a creature".
  - Without `target`: an area means all creatures in it; a self-range spell with a modifier means yourself; an item means "you or a creature" by touch; anything else is a creature within the entry's `range_m`.
- `roll: "check"`: an ability or skill check against `dc` (a number or `"spell"`).
  - `skill` is optional: without it, it's a plain ability check.
  - `by`: `self` (the user rolls) or `target`.
  - `on_success` / `on_fail` are result dicts.
- **Result dicts** (`on_fail`, a check's `on_success`, an attack's hit, i.e. the step itself) can hold `damage[]`, `heal`, `conditions[]`, `modifier` and `note` (plain text).
- A step without a roll that has `damage` deals it with no roll (e.g. Magic Missile).
- `then`: follow-up steps, each a normal effect plus `when`:
  - values: `hit`, `miss`, `fail`, `success` or `always` (the default);
  - they use the same target and don't repeat it.
- **Shown** (OnUse, TASK-108) as one short sentence per step, with chips coloured by what they are:
  - target blue, roll purple, damage red, heal green, condition orange, modifier gold;
  - duration and scaling grey.
- **Edited** in the entry editor as a flow of the same coloured nodes (OnUseFlow). The JSON stays available under "Show the JSON".

### Rollable table (`tables.json`)

Every Markdown table whose first column header is a die (`d4`, `1d6`, `D20`, `d100`, `d%`,
`Roll`) is extracted from the text into its own entry, so the VTT can roll it with one click:

```json
{ "id": "confusion-behavior", "name": "Confusion: Behavior", "source": "5e Core Rules",
  "dice": "d10", "columns": ["Behavior"],
  "rows": [ { "min": 1, "max": 1, "cells": ["The creature uses all its movement ..."] },
            { "min": 2, "max": 6, "cells": ["The creature doesn't move ..."] } ],
  "complete": true, "parent": "spells/confusion", "field": "description", "description": "" }
```

- `rows[].cells` are Markdown, one per entry in `columns` (the columns after the die column).
- `min`/`max`: ranges like `1–2`, `01-05`, `96-00` (`00` = 100) and `17+` are resolved.
- `complete`: the rows cover every result of the die without gaps or overlaps.
- `parent` + `field`: the entry and text field the table came from (`features/<id>` for monster
  features). At the table's place the text now holds an **embed** `![[tables/<id>]]`, which the
  VTT renders as the table with a roll button.
- Tables without a die column (class level tables, weapon lists, stat tables) stay Markdown.
- The vault's `Tables` folder (reference charts such as Da Big Diaper Chart) is imported as
  `rules`; rollable tables inside it are extracted like everywhere else.

Currently 32 rollable tables (e.g. Confusion, Chaos Bolt, the Fools Gold chaos surges d100,
Wild Magic Tantrum d100, Sip's Hairbrush). One has gaps in the vault: Tome of Beasts 2,
Cloves of Fate (d4 with 6 rows).

### Other kinds

For now generic: the vault's frontmatter keys in `snake_case` plus `description`. Dedicated
schemas follow when the VTT needs them. Within a kind every key has one type in all packages
(empty values are `[]`, `""` or `0`, never `null`). Subclasses always have `class`, subraces `parent`.

## Importer

`tools/import_obsidian.py <vault> [<vault> ...] data/packages` converts Obsidian vaults (read-only).
Current run: `python tools/import_obsidian.py C:/Obsidian/RPG/DnD5e "C:/Obsidian/RPG/DnD5e ABDL" data/packages`
(34 packages; the ABDL vault becomes the `abdl-dnd5e` package). Re-running rebuilds the packages.
Known gaps: most monster `Image` fields point to files that are not in the vault (cleared);
~5% of attack texts don't match the attack parser (text still complete).
Units: the vault's incomplete ft->m conversion is repaired (`fix_units`): half-converted ranges
("range 80/97.5 m" -> "24.4/97.5 m"), leftover `60'`, `30 feet`, `10 ft.` and "20 feet【6 m】".

Audit: `python tools/audit_packages.py data/packages [--fields <kind>|all]` lists Obsidian
leftovers (Dataview, callouts, `%%`) and a field inventory per kind. Expected result: no leftovers.

Vault data the importer cannot repair:
- Monster `ReligionBonus` does not exist in the vault, so no monster has a Religion skill.
- Spell `Range: 0` means touch *or* self; the vault does not say which.
- Level Up monsters sometimes split one feature into several bold sentences (e.g. Greater Sphinx
  "First Roar: ..."); they stay separate features with complete text.
- Magical Girl Beast has HP 0 in the vault.
