# Dragoon: progress

## Status
- 2026-11-01: Project created (Godot 4.7.2, Forward Plus, Jolt), Godot AI addon 4.3.0, Backlog.md, git.

- 2026-11-01: Concept added (`Dragoon Concept.md`, a custom DnD VTT). First tasks created: TASK-1 to TASK-14
  (decisions, spikes, MVP features).
- 2026-11-01: Core data = JSON source packages (see package-format.md). Obsidian vault converted into 33
  packages in `data/packages` (2160 monsters, 1272 spells, ...). New: TASK-15 compendium, TASK-16 package import/export.
- 2026-11-01: TASK-2 (Mochi): event format proposal in `doc-1 - Event-format.md` (JSONL per campaign, 13 MVP
  event types), placeholder calendar `calendars/default.json` + `WorldCalendar` (`scripts/timeline/calendar.gd`),
  test `tools/test_calendar.gd`. Waiting for the event type list to be confirmed.
- 2026-11-01: TASK-3 (Mochi): spike works. **YAML decision: own GDScript subset parser**
  (`scripts/data/frontmatter.gd`, class `Frontmatter`): no addon or C# dependency, and we write the files
  ourselves, so the subset is enough (block/flow maps and lists, lists of maps, scalars, quotes, comments, `|` `>`).
  Test: `tools/test_frontmatter.gd`. Spike scene `scenes/spikes/token_grid.tscn` shows the example map
  `examples/campaign/maps/forest-road.md` (image + grid from frontmatter) with tokens at their creature
  size (medium 1x1, large 2x2). Example campaign files in `examples/campaign` (`.gdignore`, loaded at runtime)
  use provisional fields until TASK-1's schema exists. `tools/screenshot_scene.gd` renders a scene to PNG.

## Open questions
See the "Open questions" section of the concept (secrets marking, event log format, YAML parsing, hosting ...).

## Next steps
- TASK-1 frontmatter schema, TASK-2 event format, TASK-3 Godot spike (markdown to token on grid).
- TASK-4: ask the group what they use most in Foundry.
