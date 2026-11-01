# Idea: shared features and package dependencies

Status: **idea, revisit later** (2026-11-01). Not planned yet; for now every package holds its own
features (see package-format.md).

## Problem

Many monsters have features that are the same or nearly the same: Magic Resistance (349 monsters),
Amphibious (139), False Appearance (101), Pack Tactics, Keen Smell, Undead Nature, Legendary
Resistance. Attacks like Bite (708) or Claw (330) share their shape (melee, piercing, reach 1.5 m)
but differ in to-hit and damage. Today each package stores its own copies.

## Idea

1. **Shared features as templates.** A feature has default values and text with placeholders
   (`{name} has advantage on saving throws against spells`). A monster references it and only
   overrides what differs:
   ```json
   { "ref": "dragoon-core:bite", "to_hit": 4, "damage": "1d6+2" }
   ```
   Unique features (Multiattack, Innate Spellcasting, most of the ~2300 names) stay inline.
2. **Package dependencies, RimWorld style** in `package.json`:
   ```json
   "dependencies": [ { "id": "dragoon-core", "version": ">=1.0" } ],
   "load_after": [ "5e-core-rules" ]
   ```
   The VTT resolves load order and warns about missing dependencies. References are always
   `package:id`.
3. **Base package `dragoon-core`** with common features, later conditions, damage types and
   weapon templates. Book packages depend on it.
4. **Export** writes the dependency list; a *flatten* option resolves all references into one
   standalone package for sharing.
5. **Importer**: group features by name, merge those whose text only differs by the monster's
   name, turn Bite/Claw-style attacks into templates, and show the candidates before switching.

## Open questions

- Version ranges or just "needs package X"?
- What happens to a campaign copy when a dependency changes (ties into "pull changes" of the
  campaign layers)?
- Is the saving worth the extra complexity for one table?
