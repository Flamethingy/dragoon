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
invocations, infusions, rules, conditions, diseases`.

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
bonus_actions, reactions, legendary_actions`.

A feature: `{name, text (Markdown), uses?, cost?, attack?{kind, to_hit, range, damage[{dice,
average, type}]}, save?{dc, ability}, damage?[...]}`. The structured parts are parsed from the
text so the dice roller can roll them; `text` stays the source of truth.

### Spell

`level (0 = cantrip), school, casting_time, range_m (0 = touch/self), duration, concentration,
ritual, components{verbal, somatic, material, material_text}, classes[]`.

### Other kinds

For now generic: the vault's frontmatter keys in `snake_case` plus `description`. Dedicated
schemas follow when the VTT needs them.

## Importer

`tools/import_obsidian.py <vault> data/packages` converts the Obsidian vault
`C:\Obsidian\RPG\DnD5e` (read-only). Re-running it rebuilds the packages.
Known gaps: most monster `Image` fields point to files that are not in the vault (cleared);
~5% of attack texts don't match the attack parser (text still complete).
