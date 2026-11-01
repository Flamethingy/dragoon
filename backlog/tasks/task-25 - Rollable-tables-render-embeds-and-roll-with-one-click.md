---
id: TASK-25
title: 'Rollable tables: render embeds and roll with one click'
status: To Do
assignee: []
created_date: '2026-11-01 13:52'
labels:
  - mvp
  - dice
  - ui
dependencies: []
documentation:
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The importer now extracts every rollable Markdown table (first column d4/d6/d20/d100/Roll) into a new kind `tables.json` (see package-format.md, "Rollable table"). In the source text, the table is replaced by an embed `![[tables/<id>]]`. 32 tables so far, e.g. Confusion (d10), Chaos Bolt (d8), Fools Gold chaos surges (d100), Wild Magic Tantrum (d100), Sip's Hairbrush (d10).

Needed in the VTT:
- **Embed rendering:** the Markdown renderer turns `![[tables/<id>]]` (resolved in the same package, later campaign → world → core) into the table (die column with ranges, the other columns as Markdown) plus a **Roll** button. Missing tables show a small warning instead of crashing. **Right now the embeds show up as raw text, so this is needed before the next importer data is used.**
- **Roll:** clicking Roll rolls `dice`, highlights the matching row and shows the result (die value + row text). Clicking a row picks it manually. Roll results go through the dice roller/event log as `dice.rolled` (data: table ref, value, row) so they appear in the roll log for everyone (DM can roll hidden). Results text may contain dice formulas (e.g. "2d10 acid damage") that are rollable themselves.
- **Compendium:** `tables` is a normal kind with cards (name, die badge, row count, parent link). The full view shows the table with the Roll button and links back to the parent (spell, feature, rule ...). Tables with `complete: false` show a small "gaps in table" hint.
- Later (not now): roll tables from the table toolbar during a session, and nested rolls ("roll on table X").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ![[tables/<id>]] embeds render as a table with a Roll button in every Markdown view (preview, full view, notes)
- [ ] #2 Roll rolls the table's dice, highlights the row and shows value + text; clicking a row selects it manually
- [ ] #3 Rolls are logged as dice.rolled events with table ref, value and row; the DM can roll hidden
- [ ] #4 tables is a compendium kind with cards and a full view linking to its parent entry; incomplete tables show a hint
- [ ] #5 Missing table ids render a warning, no crash
<!-- AC:END -->
