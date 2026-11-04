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

- 2026-11-02: Rules automation overview written (rules-automation.md, Tamago): code, docs and data scan
  (12,127 creature features, 1,402 spells, classes, races, feats), automation levels, Nico's decisions
  (auto-apply, 3D dice, initiative per creature with groups, crit = max dice + roll, 2014 + 2024), phases
  as tickets. Docs brought up to date (TASK-52): timelines instead of campaigns, characters/creatures.
- 2026-11-01: Characters package from the Obsidian notes (`tools/import_characters.py`, 18 characters).

## Open questions
See the "Open questions" section of the concept (secrets marking, event log format, YAML parsing, hosting ...).

## Next steps
- Rules automation, phases 0-5 (rules-automation.md, TASK-49 and TASK-51 to TASK-74), Mochi works through them.
- TASK-4: ask the group what they use most in Foundry.
- TASK-31 (later): import agent inside the VTT without Python. TASK-40: Live Lab for UI experiments.

- 2026-11-01: TASK-18 (Mochi): `Reveal` (`scripts/text/reveal.gd`) parses `<reveal id for>` tags (inline, block,
  nested = intersection, unclosed = hidden, `for` missing = DM) and `%% %%` (DM-only). Visibility at a moment =
  tag `for` + `reveal.changed` events up to then (`EventLog.change_reveal`, `Reveal.grants_from`), so rewinding
  hides again. The host cuts every entry (`Campaign.entry_view`, RPC `request_entry`) and every note per
  recipient; visible tags stay with the *current* `for` for the frames (TASK-19). `NetTable.change_reveal`
  logs the event and pushes new views to players who have the entry open. `secrets.gd` removed.
  Open question: players may currently request any entry by ref (they only see untagged text); whether an
  entry's existence itself is secret is for TASK-6/21. Test: `tools/test_reveal.gd`, `tools/test_net_table.gd`.

- 2026-11-01: TASK-22 (Mochi): document tabs in the compendium. "Browse" (the binder, can't be closed) sits left
  of a `TabBar`; double-click or middle-click on a card, the "Open" button on the quick card, or Ctrl+click on a
  link opens an entry in its own full-view tab (`EntryView`): title plate with an Edit button (disabled until
  TASK-21), monsters in two columns (stat block + features left, picture, chips and description right), other
  kinds picture + chips left and the full text right. Links in a full view open new tabs; an open entry is
  focused instead of duplicated. Close with x / middle-click / Ctrl+W, switch with Ctrl+Tab / Ctrl+Shift+Tab,
  drag to reorder; every tab keeps its scroll position, and the tabs (order, shown tab, scroll) come back on the
  next start (`user://compendium_tabs.json`). Test: `tools/test_compendium_tabs.gd`; screenshots:
  `tools/screenshot_compendium.gd`.

- 2026-11-01: TASK-21 (Mochi): entity editor. `EntryStore` (`scripts/data/entry_store.gd`) edits a package or
  campaign folder: create (from `Schema.blank`), save (rename-safe), duplicate, delete, atomic writes, ints stay
  ints, package `counts` kept. Source packages are read-only until unlocked (`"editable": true`); "edit a copy"
  (`copy_entry`) copies an entry, its features and images into a world package with `origin`.
  `commit()` in a campaign during a session logs creature sheet changes as `sheet.changed` events and keeps
  the file (texts are still saved); prep edits go to JSON (`EventLog.in_session()`). `Schema` lists the form
  fields per kind (data-layout.md), extra keys get a guessed type. `EntryEditor` replaces the full view in the
  same tab after "Edit": lines, numbers, choices, lists, refs, image picker (copied into assets/), ability
  scores, speeds, bonuses ("dex +4"), JSON for nested data, Markdown with live preview and `[[` suggestions
  (`PackageDB.suggest`), `FeatureList` for monsters (add by name/id = link or new feature, reorder, remove,
  Edit opens the feature in its own tab). Save (Ctrl+S), Cancel, Duplicate, Delete (confirm). "New..." in
  Browse creates an entry in a world package or a new one. The book updates in place (`PackageDB.put_entry`).
  Campaign entries open in the compendium with TASK-6 (unified index); the store side is ready and tested.
  Tests: `tools/test_entry_store.gd`, `tools/test_entry_editor.gd`; screenshots: `tools/screenshot_editor.gd`.

- 2026-11-01: TASK-19 (Mochi): "Visible for" and colored frames. `Markdown.to_bbcode` renders `<reveal>` passages
  and `%% %%` with a frame in the account colors of who may see them (`Markdown.reveal_accounts`,
  `reveal_viewer`): inline passages get a tinted background (several people = mixed color), block passages
  nested bordered cells (one ring per person); party passages have no frame. Hover hint "Only you and Ann can
  see this". `RevealPopup` (checkbox per player in their color, Party, DM only, Apply / Visible to all) opens
  when text is selected with the mouse (or Ctrl+H) in the editor's Markdown fields and the table's note input;
  `Reveal.apply` wraps the selection or edits the passage there (stable ids via `Reveal.next_id`). In a
  campaign during a session, changing an existing passage writes `reveal.changed` instead of the text.
  Account colors: `Campaign.accounts()` / `set_color()` (campaign.json); at the table a color button in the
  top bar, `NetTable.set_my_color` -> DM saves and sends `receive_accounts` to everyone (also on join).
  Tests: `tools/test_reveal_ui.gd`, `tools/test_net_table.gd`; screenshot `editor_reveal.png`.

- 2026-11-01: TASK-24 (Mochi): compendium follow-ups. Middle-click on a card or a link (full view and quick card,
  via `meta_hover_*`) opens a **background tab** right after the current one (several line up in order), marked
  with a short "✦" highlight; an open entry is only highlighted. **Back** arrow next to the title of every full
  view, Alt+Left and the mouse back button go to the previously shown tab (tab history, closed tabs skipped) and
  close the tab they leave; `back_closes_tab` (default on, saved with the tabs) switches that off. On Browse,
  Alt+Left still steps back through the quick card. **Right-click on a tab**: Close, Close all tabs, Close tabs to
  the left / right, and the "Back closes the tab" toggle. The quick card always shows the full text (no fold).
  Test: `tools/test_compendium_back.gd`.

- 2026-11-01: TASK-6 (Mochi): unified index. `PackageDB.campaign_dir` loads a campaign's kind files next to the
  packages (notes/table/campaign.json skipped); every entry has `_layer` (campaign, world, core). Wikilinks
  (`resolve`) rank campaign > the campaign's world (`campaign.json` `world`) > other worlds > core, then kind and
  package as before; `resolve_ref` handles `kind/id`, `world:kind/id` and `core:<package>/kind/id`. Measured:
  16,484 entries from 34 packages + the example campaign in ~0.4 s, so no cache. The compendium has a campaign
  picker on the cover (remembered with the tabs) and opens the campaign's `events.jsonl`, so session edits
  become events; the campaign is a writable store for New... and "edit a copy". At the table the DM has a
  "Compendium" button: the book opens over the table with the table's campaign and EventLog ("Back to the
  table"). Fix: the speed field kept zero entries it had (no spurious sheet.changed).
  Test: `tools/test_unified_index.gd`.

- 2026-11-01: TASK-11 (Mochi): send into the campaign. `EntryStore.send(from, kind, id, log)` makes a campaign
  copy of a core/world entry (features and images come along, `origin` {layer, package, kind, id, version}) and
  logs `entity.sent` {source: `core:pkg/kind/id` or `world:kind/id`, layer}; sending twice makes `goblin-2`.
  `send_world(world, log)` copies every entry the campaign doesn't have yet (same id = skipped, listed). The copy
  is independent: later changes to the original don't touch it, and two campaigns can hold different versions.
  In the compendium: "Send to campaign" next to Edit on core/world entries when a campaign is set (opens the
  copy, which then wins in the index), and "Send world..." on the cover. Test: `tools/test_send.gd`.

- 2026-11-01: TASK-10 (Mochi): character sheets at the table. A click on a token (`TokenGrid.token_clicked`, press
  and release without dragging; the party token opens my own PC) opens a `SheetPanel` on the left: our fixed
  layout with HP (current / max, temp), AC, speed, proficiency, the six abilities, saves, skills, senses,
  languages, inventory and the description. `NetTable.sheet_for(player, ref)` builds it on the host from the
  campaign copy plus its events (Replay, reveals applied). The DM sees every sheet, a player the full sheet of
  their own PC; for any other creature only the info page (name, size, type, race, description). Owners and the
  DM get Damage / Heal (damage takes temp HP first, HP stays within 0..max), Temp HP and AC: `change_hp` ->
  `hp.changed`, `change_field` -> `sheet.changed` (id/player/origin locked), checked by the host; pcs.json is
  never written. Open sheets and token hovers update for everyone who has them open. Test:
  `tools/test_sheets.gd`; screenshots `table_sheet.png`, `table_sheet_info.png`.

- 2026-11-01: TASK-12 (Mochi): dice that know the stats. `Dice` (`scripts/dice/dice.gd`): formulas (`2d6+3`, `d20`,
  `4d6kh3`, `2d20kl1+5`, max 100 dice), rolls with natural 20/1 marked, and `resolve(sheet, name, features)`:
  skills (the sheet's bonus, else ability modifier), saves ("Dex save", "dexterity saving throw"), ability checks,
  initiative, attacks by feature name ("attack with Longbow" -> to hit + damage from the feature's `attack`),
  "with advantage"/"adv"/"dis". At the table the host rolls (`NetTable.roll`), logs `dice.rolled` (doc-1 fields
  `roll`, `formula`, `result`, `dice` plus `results`, `who`, `hidden`) and sends it to everyone; players roll
  only for their own PC; the DM can roll hidden (only the DM sees it). Roll log + roll box ("Hidden" for the
  DM) under the notes; on the sheet, abilities, saves, skills, initiative and attacks are roll links. A late
  joiner / restarted host gets the session's rolls from the log. Fix: `is_online()` is false once the peer is
  disconnected (no error spam when the host closes). Test: `tools/test_dice.gd`.

- 2026-11-01: TASK-17 (Mochi): more event types (doc-1 "More event types"): conditions, combat start/turn/end
  with initiative order, resources used/restored, short/long rests, death saves, currency, relationships /
  faction standing, quest progress, party split/merge/arrived, weather, assistant drafts. Each with its data
  fields and an example in doc-1. `Replay.entity_state` rebuilds the per-entity ones (`conditions`,
  `resources_used`, `death_saves`, `currency`, `relations`, `quest_status`/`progress`, `location`);
  `Replay.world_state(events)` the world-wide ones (`combat`, `weather`, `party_groups`). Item events now keep a
  sheet's own inventory list shape (`[{item, qty}]`) instead of failing on it. The table's sheet shows
  conditions, death saves, used resources and coins. Test: `tools/test_event_types.gd`.

- 2026-11-01: TASK-25 (Mochi): rollable tables. `RollTables` (`scripts/dice/roll_tables.gd`): `![[tables/<id>]]`
  embeds (own line or inside a paragraph) render in every Markdown view (compendium quick card and full view,
  editor preview, table notes, sheets) as the table: die column with ranges, the other columns as Markdown
  (formulas like "2d10" become roll links), a **Roll d10** button and the result ("Rolled 4: ..."); the rolled
  row is highlighted, clicking a range picks a row by hand, a missing table is a warning, an incomplete table
  says it has gaps. Standalone the compendium rolls itself (into the campaign's event log when one is picked);
  at the table the host rolls (`NetTable.roll_table`, tables from every package's `tables.json` plus the
  campaign's): `dice.rolled` with `table`, `value`, `row`, shown in everyone's roll log with the row text and
  highlighted for everyone; Shift+click = hidden for the DM. `tables` cards: die badge (red if incomplete),
  "Rollable table, N rows", chips Die/Rows/From; the full view links back to the parent entry.
  Test: `tools/test_roll_tables.gd`; screenshots `compendium_table_embed.png`, `compendium_table.png`.

- 2026-11-01: TASK-23 (Mochi): packages as cards. A **Packages** bookmark lists every installed package (on or
  off) as a card: cover (`cover`/`image` in the manifest) or fallback art, badge S/W, "Source · 1,928 entries",
  an on/off switch on the card (switched-off cards are dimmed, their entries leave the book). One filter covers
  Source/World/On/Off/Has PDFs; the search covers name and description. The full view (own tab, survives
  reloads) shows version, kind, description (its PDF links open the PDFs), the counts per kind as links to Browse
  filtered to the package and kind, import origin, dependencies, "Shown in the book" switch, Export... (dialog
  title shows the size incl. PDFs, also in the Packages window), **Documents** (title, size, Open in the default
  viewer, Show in folder, Add PDF... -> `docs/` + manifest) and **Contents**: the package's entries as cards
  grouped by kind with counts, collapsible (features start collapsed), 24 at a time with "Show more", a search
  inside the package; cards open in their own tab. `PackageManager`: `manifest`, `package_size`, `documents`,
  `add_document`, `size_text`. Fixes: tag chips ("Concentration") no longer wrap letter by letter; a quick
  second reload no longer crashes the tab restore. Test: `tools/test_package_cards.gd`; screenshots
  `compendium_packages.png`, `compendium_package_view.png`, `compendium_package_docs.png`.

- 2026-11-01: TASK-26 (Mochi): monster pictures. Cards, quick card and full view show the entry's `image`
  (vault image or PDF art); `ImageCache.decode` reads images by content, so JPEGs named `.png` load and broken
  files fall back quietly (no decoder errors). Without a picture, monsters show their creature type icon
  (`res://assets/creature_types/<type>.svg`, matched inside the type text, e.g. "swarm of Tiny beasts" -> beast;
  `unknown.svg` otherwise), tinted in the card colour; other kinds keep the initial. A **Credits** button on the
  compendium cover shows `assets/creature_types/CREDITS.md` (CC BY 3.0, game-icons.net).
  Test: `tools/test_monster_art.gd`.

- 2026-11-01: TASK-28 (Mochi): import UI for the import agent. `scripts/import/`: **ImportJobs** starts
  `tools/import_agent.py` as its own process (`--input --kind --target --job --packages`; the Anthropic API key
  only as `ANTHROPIC_API_KEY` in its environment, kept in `user://import_settings.cfg`, never in data/ or git),
  follows `data/imports/<job>/` (job.json status, progress.log; a dead process = failed; cancel), crops a draft's
  picture from its source page into `art/<id>.jpg`, and merges accepted drafts into the target package (features
  and picture along, import `origin` kept, read-only target unlocked, same name: replace / keep both / skip).
  **ImportPanel**: file or link, target package or "New world package...", API key + Python settings, jobs with
  their live log, Review. **DraftReview**: drafts list, the entry editor on the draft, the source page with a
  drag-to-crop box, Accept / Discard / Accept all. Dropping a PDF or image on the compendium opens the import
  window; the Packages window has "Import from link...". The contract for TASK-27 is in import-agent.md;
  `tools/fake_import_agent.py` follows it. Test: `tools/test_import_ui.gd`; screenshots via
  `tools/screenshot_import.gd` (`import_window.png`, `import_review.png`).

- 2026-11-01: TASK-29 (Mochi): value tokens in the editor. `Schema.TOKENS` turns fields whose values repeat
  into `token` (one value: click to switch, click again to clear) or `tokens` (a list: click to toggle):
  tags, size, type, subtype, alignment, attitude, damage/condition immunities, resistances, vulnerabilities,
  languages, environments, item rarity/type, spell school/subschool/casting time/duration/classes, class
  spellcasting ability/saving throws/proficiencies, feature uses, table dice; guessed fields of other kinds
  (classes, backgrounds) too. Base lists (sizes, abilities, damage types, conditions, schools, rarities,
  alignments, dice) are always offered. `PackageDB.field_values(kind, key)` gives the known values, most used
  first, spellings merged ("Very Rare" = "very rare"), cached until entries change. **TokenField**: the
  selected tokens plus the top 12, "N more...", a search for long lists, "+" / Enter adds the typed value but
  picks an existing one in another spelling. Ref tokens (pc race, factions, location: stored as `kind/id`;
  npc race, subclass class, subrace parent: stored as names, as the data has them) offer the entries of their
  kind; Ctrl+click opens the entry in a tab. Also in the import draft review. Test: `tools/test_tokens.gd`.

- 2026-11-01: TASK-30 (Mochi): drafts for the whole compendium (package-format.md "Drafts"). `EntryStore`:
  `draft` is always written on save (missing = published), drafts get `edited`; new entries start as drafts;
  `publish(kind, id, ask|replace|keep|skip)` takes the draft's own draft features and tables along and asks
  about a published entry of the same name first (replace takes its id, skip throws the draft away);
  `unpublish`; `crop_picture` (source page -> `art/<id>.jpg`). `PackageDB` keeps drafts in `drafts` (by id
  only): out of lists, search, wikilinks, refs and suggestions; `list(kind, with_drafts)`, `kinds_with`,
  `all_drafts`, `draft_count`. Players never get drafts (`Campaign.entry_view`, PC choices), Send world skips
  them, Send is hidden on drafts. Book: a **Show drafts** tickbox in the binder and in a package's contents
  (Draft tag, dashed frame), a **Drafts** bookmark with the count opening the **Drafts page** (cards grouped by
  package and kind, kind + last edit + missing required fields, `Schema.REQUIRED`; "Publish all" per package
  and per import job, asking about same names one by one, loose features/tables never ask). Editor: new
  entries **Save as draft** / **Save** (publish), drafts **Publish**, published **Back to draft**; entries
  with `source_page` show the page with the crop box. Import rework: finished jobs are merged straight into
  the target package as drafts (`ImportJobs.merge`, by the import window or at book start; ids that are taken
  renamed with references, files under `imports/<job>/`, `origin.job`); the review screen (DraftReview) is
  gone, "Show drafts" opens the Drafts page. Tests: `tools/test_drafts.gd`, `tools/test_import_ui.gd`
  (reworked); screenshots via `tools/screenshot_import.gd`.

- **TASK-27 Import agent** (`tools/import_agent.py`): the real tool behind the import window, same contract as
  `tools/fake_import_agent.py`. PDF pages are rendered to `pages/<n>.png` (110 dpi) and sent 20 per request with
  the art boxes from `extract_pdf_art.art_regions` drawn and numbered plus the text layer; an image is sent as is
  (Claude gives a crop); a link is fetched as text plus its pictures (Homebrewery share links read `/source/`).
  Claude (`claude-opus-5-5`, adaptive thinking, streaming, JSON schema output) returns monsters, spells and items
  with page and art box; normalized with the importer's helpers (ids, features, rollable tables, feet to metres),
  drafts with origin/source_page/crop, art cut to `art/<id>.jpg`. Refusals are skipped and logged, a cut-off
  answer is retried in halves. Key only from `ANTHROPIC_API_KEY`, scrubbed from logs. Optional `--pages 60-70`.
  Tests: Boggle screenshot (1 monster, 4 features, crop), MotM pages 60-70 (11 monsters with matching art, 66
  features, 2 tables, ~31k in / 15k out tokens, 2 min), a wikidot spell page; `tools/check_real_import.gd`
  merges a real job into a scratch package.

- 2026-11-04: Table Bunny (TASK-95 to TASK-99, Mochi): BunnyTools (8 tools with per-player rights), BunnyBrain
  on the host (Claude API, key in user:// only, limits, queue, stop), `/bunny` and `/bunny!` over the network
  with the busy status for everyone, the bunny on every client, an optional MCP server for local assistants.
  TASK-101: the bunny now uses Tamago's rig, poses, recolouring and smoke puff, and the host picks its look
  and behaviour (Esc > Table Bunny). Both projects share it: see `bunny-shared-with-tamago.md`.
