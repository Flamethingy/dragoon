---
id: TASK-65
title: 'Rules P3: effects format and parser for spells and features'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 02:33'
labels:
  - rules
  - phase-3
  - data
dependencies:
  - TASK-53
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rules-automation.md, section 5.2.
- Define the optional `effects` list (roll attack/save/check, damage, heal, apply condition with duration and save_ends, modifier, resource, area, scaling) in package-format.md and the Schema. The text stays the source of truth.
- Regex parser in tools/import_obsidian.py (and the import agent) for the clear cases:
  - spell attack, save ability + DC/"spell", half on save, damage dice and types
  - area shape + size (sphere/radius, cone, line, cube, cylinder)
  - "At Higher Levels" dice per slot, cantrip scaling
  - conditions ("must succeed ... or be frightened"), durations
- Report the coverage per kind; entries without effects keep the text fallback.
- Effects editor with presets in the entry editor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 effects format documented and in the Schema
- [x] #2 Parser fills effects for spells and creature features; coverage reported
- [x] #3 Effects editor in the entry editor
- [x] #4 Audit passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- The parser is GDScript (Effects.parse in scripts/rules/effects.gd). The runtime, the editor ("From the text") and the CLI tools/parse_effects.gd all share it.
- I did NOT edit tools/import_obsidian.py: it has uncommitted changes that aren't mine. Instead, after an Obsidian re-import, run `godot --headless --path . -s tools/parse_effects.gd -- --write` (re-import rebuilds the packages and drops the effects).
- Parsed entries carry effects_parsed: true. `--strip` removes them; entries that already have effects (hand edits, the AI pass) are kept.
- Rules.save_effect and spell_attack_of prefer the effects; the text path stays as the fallback.
- Format documented in package-format.md (the Effects section). It follows rules-automation.md 5.2, with scaling as {per_slot, above} / {cantrip} / {targets_per_slot}.
- Coverage (written into the local data/packages, gitignored):
  - spells 780/1402 (55.6%): attack 110, save 694, heal 15, area 95, scaling 210
  - creature features 5751/12127 (47.4%): attack 3534, save 2895, area 365
  - items 11/79
- The audit (tools/audit_packages.py) reports no leftovers.
- Editor: Schema type "effects" on spells, features and items: a JSON field with "Add preset" (spell attack, save for half, save or condition, condition, heal, modifier, resource) and "From the text".
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Effects format and parser (commit b39d42f): Effects class, rules prefer effects, Schema field and editor, parse_effects CLI with coverage; the packages are filled locally. Test tools/test_effects.gd; suite 46/46 green.
<!-- SECTION:FINAL_SUMMARY:END -->
