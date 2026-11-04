---
id: TASK-108
title: 'Item and spell view with a clear "On Use" section (targets, roll, results)'
status: Done
assignee: []
created_date: '2026-11-04 22:29'
updated_date: '2026-11-04 23:00'
labels:
  - ui
  - compendium
  - rules
  - effects
dependencies:
  - TASK-107
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: after the item list (TASK-107), a proper **view for items and spells**. It shows the fields we already have in the data model and makes the effects as easy to read as possible in an **"On Use" section**.

**Fields (package-format.md):**
- **Item:** image, name, rarity, type[], gold, weight, source, description.
- **Spell:** level / cantrip, school (and subschool), casting time, range (`range_m`; 0 = touch/self), components (V/S/M plus material), duration, concentration, ritual, classes, source, description.
- Shown as a nice card / sheet: a head with the image and name, chips for the key values, then On Use, then the full text.

**On Use** is a readable, editable view of the existing `effects` list (TASK-65, rules-automation.md 5.2). It covers:
- **who** it targets: self, a creature, N creatures, an area plus range;
- **what is rolled:** an attack roll, a save, a skill/ability check, or nothing;
- **what happens:** on a hit / failed save / success / always, e.g. damage, healing, a condition, a modifier, with duration and scaling.
- Several steps are possible, e.g. "roll 2d4+2 → heal the target".
- Buttons at the table run the same steps (TASK-49).

The text stays the source of truth; entries without effects show "no automation".

**Structure:** Nico picks one of the proposed layouts (see the note). Then the ticket moves to To Do for Mochi.

Possible data additions:
- `target: {kind: self|creature|creatures|area, count, range_m}` per effect;
- `roll: "check"` with `skill` / `ability` and `dc`;
- `then` for follow-up steps.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Items and spells open in a view showing all their data-model fields
- [x] #2 On Use shows targets, the roll and the results of each effect in plain words
- [x] #3 On Use can be edited (DM / drafts) and writes the existing effects format
- [x] #4 Entries without effects show the text fallback
- [x] #5 Headless test: Potion of Healing, Fireball and a skill-check item render the right On Use
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Decided by Nico (2026-11-04): C to read, B to edit, both as coloured nodes.**

**Reading (view / sheet / card):**
- the On Use effect as a readable sentence with chips, e.g. "Target [all creatures] in a [6 m sphere] within [45 m]. Each makes a [DEX save] against [your spell DC]. Failure: [8d6 fire]; success: [half].";
- chips are coloured by type (see the colours below);
- multi-step effects become a few short sentences, one per step.

**Editing (DM / drafts): a flow of coloured nodes**, simple and friendly, not a technical graph editor:
- rounded node cards connected by short lines, top to bottom;
- branches only where needed (fail / success, hit / miss) and **side by side**;
- node colours (UISkin palette):
  - 🎯 **Target**: blue;
  - 🎲 **Roll** (attack / save / check / dice): purple;
  - 💥 **Damage**: red;
  - 💚 **Heal**: green;
  - ⚠ **Condition**: orange;
  - ✨ **Modifier / buff**: gold;
  - ⏱ **Duration / scaling**: grey (a small tag on the node, not its own node where possible);
- each node shows one short line ("DEX save · spell DC"). A click opens a small inline form with the existing presets / value tokens;
- add with a "+" under a node (choose: roll, damage, heal, condition, modifier) and remove with the node's ×;
- "From the text" (the existing parser) fills the flow.

Example (Potion of Healing): [🎯 Self or a creature · touch] → [🎲 2d4+2] → [💚 heal].

**Data:** the flow reads and writes the existing `effects` list. New: `target`, `roll: "check"` (`skill` / `ability`, `dc`) and `then` (follow-up steps). Document them in package-format.md.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 10d9985.

- **Reading:** `scripts/rules/on_use.gd` (OnUse) turns `effects` into one short sentence per step, with chips coloured by what they are:
  - target blue, roll purple, damage red, heal green, condition orange, modifier gold;
  - duration, concentration and scaling grey.
  - Example: "Targets [all creatures] in a [6.1 m sphere] within [45.7 m]. Each makes a [DEX save] against [your spell DC]. Failure: [8d6 fire]; success: [half]. [+1d6 per slot above 3rd]".
  - `EntryView` shows it as "On Use" above the text for spells, items and features. Without effects it says "No automation: the text below is what counts."
- **Fields:** CardData chips now also show:
  - spells: subschool, classes, material, source;
  - items: rarity, type, source.
- **Editing:** `scripts/compendium/on_use_flow.gd` (OnUseFlow) is the entry editor's effects field:
  - rounded coloured nodes, top to bottom, joined by short lines;
  - branches side by side only after a save (failure / success) or a check, and "On a hit" for attacks;
  - a click opens a small inline form, × removes, "+" adds a roll, damage, healing, a condition or a modifier to a branch or after a step;
  - "+ Add a step" offers presets;
  - the JSON stays available under "Show the JSON"; Presets and "From the text" still work, and the two stay in sync.
- **Data** (documented in package-format.md):
  - `target` {kind self|creature|creatures|area, count, range_m, self};
  - `roll: "check"` {skill, ability, dc, by, on_success / on_fail};
  - result dicts with damage/heal/conditions/modifier/note;
  - damage without a roll;
  - `then` with `when` (hit / miss / fail / success / always).
  - Without `target`, it's worked out from the area, range and kind.
- **Tests:** `tools/test_on_use.gd` covers:
  - Potion of Healing, Fireball, a skill-check item and a follow-up chain;
  - the view and the fallback;
  - the nodes of the flow, branches, + / × and form edits writing the effects.
  - effects, ai_effects, entry_editor, compendium, sheet_lists, character_hud, sheets and app pass. test_effects crashes on quit after "all good" (it did before too); test_concentration was already failing.
- **Not yet:** the table's buttons (TASK-49) don't run the new `roll: "check"`, `then` or no-roll damage yet. They still run attack / save / heal as before.
<!-- SECTION:FINAL_SUMMARY:END -->
