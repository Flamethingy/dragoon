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
```

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

The importer takes the PDFs linked in the vault's source page (`Sources/<Source>.md`, links like
`[[Players Handbook.pdf|Player's Handbook]]`), copies them into `docs/` (only new or changed
files, stale ones are removed) and turns the links in the description into Markdown links
(`[Player's Handbook](<docs/Players Handbook.pdf>)`). Currently 42 PDFs in 13 packages, 1.7 GB.
Unlinked PDFs (e.g. the DM Tuz Vault folders, the 2024 PHB) are not imported yet.

## Entries

Every entry has `id` (slug, unique per kind in the package), `name`, `source`, `image`
(relative path or empty), `description` (Markdown) and `origin` (where it was imported from).
**All text fields are Markdown.** Wikilinks `[[Name]]` are kept for the VTT to resolve.

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
