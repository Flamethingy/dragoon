---
id: TASK-94
title: >-
  Drop items, spells and features onto a character anywhere (token, HUD, pages,
  tracker)
status: Done
assignee: []
created_date: '2026-11-04 13:17'
updated_date: '2026-11-04 13:21'
labels:
  - ui
  - drag-and-drop
  - sheets
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nico 2026-11-04: an item, spell or feature dragged from the Book onto a **character** joins that character's lists:
- an item goes into the inventory (`item.gained`; another copy raises the count);
- a spell goes into the spell list;
- a feature goes into the features (no duplicates).

**Already there (TASK-37):** dropping onto the **sheet panel** does exactly this (`sheet_panel.gd` `_can_drop_data` / `add_entry`, `EntryDrag.sheet_change`, `table.change_item` / `change_field`). Reuse it.

**New drop targets** (same logic, same rights: only sheets the dropper may edit, `_editable`):
- **the token on the map:** `map_drop.gd` only accepts creatures to spawn today. Items, spells and features dropped onto a token add them to that creature. While hovering, highlight the token under the mouse (and the TASK-93 card preview stays a card, no spawn ghost);
- **the HUD** (the active character's portrait or anywhere on the HUD);
- **the sheet pages 1–9**, also detached ones (TASK-92), adding to the page's character;
- **the combat tracker row** of a creature (nice to have).

**Feedback:**
- a short toast / chat line, e.g. "Longsword added to Borin's inventory" or "Borin already knows Fire Bolt";
- not allowed (a player dropping onto someone else's character, a non-creature entry): a not-allowed cursor and no drop.

Classes dropped onto a character are **out of scope** here (levelling / multiclass has its own flow).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dropping an item / spell / feature on a character's token adds it to that character (item count, no duplicate spells/features)
- [x] #2 Same when dropped on the HUD and on a sheet page (incl. detached pages)
- [x] #3 Only characters the dropper may edit accept the drop; others show not-allowed
- [x] #4 A short confirmation (toast/chat) says what was added where, or that it was already there
- [x] #5 A headless test drops each kind onto a token and checks the sheet
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 07e6165.

- **One path for adding:** `NetTable.add_entry_to(ref, entry)` (host: `_handle_add_entry`; players send `request_add_entry` by RPC) does what the sheet panel did (TASK-37):
  - items become `item.gained` (the count goes up);
  - spells and features go into their list once.

  The rights check is `_editable_sheet`. `can_take_entry(ref, e)` is the client-side pre-check: a creature or character the dropper may change (`may_change`), never the party token.
- **Feedback:** the dropper's status line says "Longsword added to Borin's inventory", "Fire Bolt added to Borin's spells" or "Borin already knows Fire Bolt" / "already has …". Players get this from the host (`entry_added` RPC).
- **Token:** `MapDrop` accepts items, spells and features on the token under the mouse (`token_ref_at`), lights it while hovering, and adds the entry on drop. Creatures still spawn as before.
- **HUD and sheet pages:** `EntryDrag.accept_on(root, table, ref_of)` sets drag forwarding on every Control under the HUD and the SheetPages, including ones added later. Controls with their own drop (layout editor) keep theirs. Drops go to the active character.
- **Sheet panel:** now goes through the same path.
- **Not allowed:** `can_drop` returns false, so Godot shows the forbidden cursor.
- **Test:** `tools/test_entry_drops.gd`. The DM drops a sword, a spell and a feature on Borin's token; then a second sword counts up and the duplicate spell is refused with the message. Bob can't drop on a creature he doesn't control, but can on Borin (it arrives on the host and he's told). Real GUI drags onto a HUD piece and onto a control added later. The sheet/HUD/casting/gear/levelling suites pass.

Not done: the combat tracker row (nice to have). Detached sheet pages come with TASK-92; they're SheetPages, so the same hook applies.
<!-- SECTION:FINAL_SUMMARY:END -->
