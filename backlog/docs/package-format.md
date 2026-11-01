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
```

`data/` is git-ignored (copyrighted book content) and has a `.gdignore`, so Godot does not
import it. The VTT loads packages at runtime with `FileAccess`.

Kinds: `monsters, spells, items, feats, races, subraces, classes, subclasses, backgrounds,
invocations, infusions, rules, conditions, diseases, tables`.

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
| `created`, `imported_from` | provenance |

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

A feature: `{name, text (Markdown), uses?, cost?, attack?{kind, to_hit, range, damage[{dice,
average, type}]}, save?{dc, ability}, damage?[...]}`. The structured parts are parsed from the
text so the dice roller can roll them; `text` stays the source of truth.

### Spell

`level (0 = cantrip), school, subschool (e.g. "Dunamancy: Graviturgy"), casting_time, range_m
(0 = touch/self), duration, concentration, ritual, components{verbal, somatic, material,
material_text}, classes[]`. `casting_time` and `duration` are in sentence case ("1 bonus action").

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
