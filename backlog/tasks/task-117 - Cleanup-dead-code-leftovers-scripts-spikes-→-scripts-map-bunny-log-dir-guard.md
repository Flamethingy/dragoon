---
id: TASK-117
title: >-
  Cleanup: dead code, leftovers, scripts/spikes → scripts/map, bunny log dir
  guard
status: To Do
assignee: []
created_date: '2026-11-05 02:38'
updated_date: '2026-11-05 03:03'
labels:
  - cleanup
  - tech-debt
dependencies: []
priority: low
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tamago's sweep (2026-11-05). Do this **after** the current map/group work (TASK-114/116), so nothing clashes.

**Bug first:** `NetTable.bunny_log_dir` was empty once (probably a test), so the chat logs `westmarch-red-fang-{dm,ann,bob}.json` landed in the **project folder** (Tamago deleted them). Fix:
- fall back to `BUNNY_LOG_DIR` when the dir is empty;
- tests should restore the static var afterwards.

**Never called (check, then remove):**
- `timeline_view.show_range`
- `bunny_brain.end_job`
- `character_hud._roman` / `edit_pages`
- `net_table.gain_level`
- `sheet_panel._roll_list`
- `rules.dice_bonus`
- `token_grid.start_cells`
- `moments.moment_of_event`
- `timeline.encounters_path`

**Only used by tests (decide: API on purpose, or remove together with the test):**
- `dock.free_rect` / `restore_open`
- `bunny_brain.job_progress` / `start_job`
- `package_contents.set_query`
- `die_3d.value_up`
- `hud_widgets._list_bbcode`
- `character_hud.edit_hud` / `shows_app_buttons`
- `net_table.change_item` / `grant_level` / `rotate_template`
- `effects.coverage`
- `move_plans.is_dragging`
- `encounter_replay.step_of`
- `event_log.gain_item` / `lose_item`
- `moments.moment_at`
- `timeline_bar.cursor_event`

(`package_db.load_now` is meant for tests and tools, so keep it.)

**Files:**
- `scripts/data/frontmatter.gd` (`Frontmatter`): only its test uses it, a leftover from before the JSON packages. Remove it together with `tools/test_frontmatter.gd`, unless the notes/docs still need it.
- `scenes/table.tscn`, `scenes/compendium/compendium.tscn`: only screenshot tools start them. Keep them as test scenes or remove them (and their tools).
- One-time tools that are done: `tools/migrate_data.gd`, `split_class_features.gd`, `check_real_import.gd`, `check_own_windows.gd`. Old screenshot scripts for views that no longer exist.

**Structure:**
- rename `scripts/spikes/` to `scripts/map/` (token_grid, move_plans, group_stack... are core code now, not spikes);
- `net_table.gd` (5,576 lines, 374 functions): split it into parts (combat, inventory / sheets, bunny, timeline / look-back, view sync), e.g. as helper classes. Do this in its own step, with all tests green after each move.

**Not part of this:** the timeline bar and the dock system become unnecessary with TASK-112 / TASK-113; clean those up there. `addons/godot_ai` belongs to the plugin, not us.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bunny_log_dir can't be empty any more (no files in the project folder)
- [ ] #2 The never-called functions are removed (or kept with a reason)
- [ ] #3 Test-only functions decided; leftover files/tools removed
- [ ] #4 scripts/spikes renamed to scripts/map, all references updated
- [ ] #5 All tests green (test_concentration was already failing before)
<!-- AC:END -->
