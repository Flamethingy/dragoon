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
- 2026-11-01: TASK-15 (Mochi): compendium scene `scenes/compendium/compendium.tscn`. `PackageDB`
  (`scripts/compendium/package_db.gd`) loads all packages on a worker thread (4309 entries in ~0.25 s);
  kinds list, name search (optionally full text), filters for package, CR/level and type/school, sortable
  columns; detail via `StatBlock` (monster stat block, spell header, field table for other kinds) and
  `Markdown` (ported from Tamago, with `[[wikilinks]]`: click opens the entry, Back / Alt+Left returns).
  Test: `tools/test_compendium.gd` (formats every entry; 2434 of 2888 wikilinks resolve, the rest point to
  PDFs or missing pages). Not yet: jumping to a `#Section` inside the opened page.

- 2026-11-01: TASK-15 redesign (Mochi): the compendium is now a card-collection binder using the UI sheet
  `assets/ui_sprites.png` (`UISkin`): cover with bookmark tabs per kind, a page of cards (art, name, badge),
  a detail panel with chips and ability hexes, and the full text on demand. Monster features come from
  `features.json` by id (`PackageDB.feature`, `features_of`), with a feature view listing "Used by" monsters
  and `legendary_intro` above Legendary Actions. Test: every feature id resolves (16,433 entries).
- 2026-11-01: TASK-9 (Mochi): `EventLog` (`scripts/timeline/event_log.gd`): append-only JSONL with writers
  for the MVP event types, undo events, world clock; `Replay` (`scripts/timeline/replay.gd`) rebuilds an
  entity's state up to any in-game moment. Test: `tools/test_event_log.gd`.
- 2026-11-01: TASK-5 (Mochi): network spike `scenes/spikes/net_table.tscn` (`NetTable`, ENet). The DM is
  the authority: players request moves, the DM checks, logs a `token.moved` event and broadcasts; a
  restarted DM restores tokens from the log. Run with `--host` / `--join=ip:port`.
  Test: `tools/test_net_table.gd` (two tables in one process). Spike limit: anyone may move any token.
- 2026-11-01: TASK-16 (Mochi): `PackageManager` (`scripts/compendium/package_manager.gd`): export a
  package as one `.dragoonpkg` zip (with assets), inspect (format, version, safe paths, counts), install
  with replace / keep both / cancel, enable/disable (`user://packages.cfg`), remove (moved to
  `data/removed`). "Packages..." window in the compendium (`PackagesPanel`); the book reloads on close.
  Test: `tools/test_packages.gd`; screenshot: `tools/screenshot_packages.gd`.

- 2026-11-01: TASK-14 (Mochi): session notes. `SessionNotes` (`scripts/notes/session_notes.gd`) writes one
  markdown file per session to `<campaign>/notes/session-NN.md` (`prep.md` between sessions). Each entry has a
  heading with the real date, session number, in-world moment (calendar formatted) and writer, plus a hidden
  data comment so the VTT can read it back. In the net table, a notes panel on the right: players send notes
  to the DM, who stamps, saves and shares them; "Next session" logs session.started and opens a new file.
  Tests: `tools/test_session_notes.gd`, `tools/test_net_table.gd`.

- 2026-11-01: TASK-7 + TASK-8 (Mochi): the shared table `scenes/table.tscn` (`NetTable` + `TableUI`).
  Start screen: the DM hosts a campaign folder on a port, players join with name and address and pick their PC
  (cards; taken ones greyed). The host keeps everything: players get a whitelisted view of the map and tokens
  (`Campaign.map_view` / `token_view`: name, size, image hash; HP/AC only for their own PC; never bodies or
  `dm_` keys). Images go once per SHA-256 and are cached on disk (`AssetCache`, 48 KB chunks, checked on
  arrival). Players may drag only their own PC (checked on the host too); moves glide and snap, and are
  logged. The DM switches maps in the top bar (PCs come along to `party_start`, positions per map from the
  log). Who plays whom and the map are kept in `table.json`, so rejoining by name works and a restarted host
  continues. `Secrets` (proposal for TASK-1): `dm`/`secret`/`dm_*` keys, `%% comments %%`, `> [!dm]`
  callouts and "DM..."/"Secret..." sections are stripped. Examples: 2 PCs, second map "Old Mill".
  Test: `tools/test_net_table.gd`; screenshots: `tools/screenshot_table.gd`.

- 2026-11-01: TASK-13 (Mochi): world maps (`kind: world`, provisional) show every claimed PC as one party
  token (`party_token` image, named after its members). Any member or the DM can drag it; the host logs one
  `token.moved` per member with `data.group = "party"`. Local maps show the PCs one by one at their own
  positions. Example world map "The Westmarch" (`maps/world.md`). Splitting/merging groups: later.

- 2026-11-01: TASK-1 (Mochi): JSON entry schema in `data-layout.md` (refs `kind/id` resolving campaign > world >
  core; PC, NPC, monster, place, faction, lore, map, note, campaign.json). Examples: campaign
  `examples/campaigns/red-fang/` and world package `examples/packages/westmarch/`. TASK-2 closed (types approved).
- 2026-11-01: TASK-20 (Mochi): the table runs on JSON campaigns. `Campaign` reads campaign.json + one JSON per
  kind; on first host the example is copied to `data/campaigns/red-fang`. Logins are the campaign's players
  (id or name), PCs belong to their `player`; free PCs can be picked (kept in `table.json`). Events go to the
  campaign's `events.jsonl` with `by` = player id; notes to `notes.json` (`SessionNotes`, headings with the
  players' names). `TokenGrid` only shows data now; the markdown example and spike scenes are gone
  (`Frontmatter` stays for importers, test fixtures in `tools/fixtures/`). `secrets.gd` is unused until TASK-18.

## Open questions
See the "Open questions" section of the concept (secrets marking, event log format, YAML parsing, hosting ...).

## Next steps
- TASK-1 frontmatter schema, TASK-2 event format, TASK-3 Godot spike (markdown to token on grid).
- TASK-4: ask the group what they use most in Foundry.
