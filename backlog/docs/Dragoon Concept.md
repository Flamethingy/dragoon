# Custom Godot VTT: Concept

Nov 1, 2026 · @Nico

> **Decisions since writing (2026-11-01):** the VTT is the editor, and all data is JSON with
> Markdown text fields, so there is no vault program and no markdown entity files. Core data is in
> source packages (package-format.md), worlds are packages too, and campaigns are folders
> (data-layout.md). DM secrets are per-passage `<reveal>` tags (reveal-visibility.md). The
> sections below still describe the original idea where they mention markdown files. Campaigns were
> later replaced by timelines inside a world (timelines.md), and rules automation is planned in
> rules-automation.md.

## Vision

A virtual tabletop built in Godot for one table only: our DnD campaign. Foundry tries to support every system, so setup drowns in settings, modules and compendium work. Our VTT hardcodes our ruleset, homebrew and house rules, so there is nothing to configure.

It reads campaign data straight from the vault program's markdown files. That replaces the planned Foundry export script entirely.

Godot lets it feel more like a game than a form: smooth token movement, spell shaders, ambient particles and good performance.

## Core principles

- **Built for our table.** One ruleset, our homebrew, our sheet layout. No settings screens.
- **Markdown for what humans write.** Entities, lore and notes live as markdown files.
- **Events for what the game writes.** Every change is an event on one world timeline, so everything can be rewound.
- **Explicit, not automatic.** Data is sent into a campaign on purpose; nothing silently overwrites campaign state.
- **The DM is the authority.** Players send requests, the DM instance validates and broadcasts.
- **Small first.** Only the features our group actually uses in a session; everything else waits or never happens.

## Architecture

```text
Vault program --writes--> Campaign folder (core, world, campaign)
Campaign folder --reads--> DM client (Godot host)
DM client --logs events--> Campaign event log (append-only, rewindable)
DM client <--ENet--> Player clients (send requests, get updates)
```

Both programs point at one shared folder, so no export step exists. The DM's Godot client hosts over ENet and owns all game state; players only send requests. Desktop builds, not web export, to keep full shader power.

## Data model

Each entity (NPC, monster, PC, location, item) is one markdown file. Structured data goes in frontmatter, free text in the body.

| Part | Holds | Used by the VTT for |
| --- | --- | --- |
| Frontmatter (YAML) | HP, AC, stats, token image, size, faction | Sheets, dice, token setup |
| Body | Lore, descriptions, DM notes | Info panel (markdown to BBCode in a RichTextLabel) |
| Wikilinks `[[Name]]` | References between entities | Click a token to open its page, page links to its location |
| Event log (not markdown) | Every change: moves, items, HP, level-ups, notes | Timeline, rewind, travel paths |

Data is not live-synced from the vault. Core and world entries are sent into a campaign on purpose (see Campaign layers).

Example frontmatter:

```yaml
type: monster
name: Goblin Chief
hp: 21
ac: 15
stats: { str: 12, dex: 14, con: 12, int: 10, wis: 8, cha: 10 }
token: tokens/goblin_chief.png
size: medium
faction: "[[Red Fang Clan]]"
```

## Campaign layers

Data is split into three layers, so one character can exist as different variants in different campaigns.

| Layer | Holds | Example |
| --- | --- | --- |
| Core | Rules, base stat blocks, imported books | Goblin, Fireball, Longsword |
| World | A setting with its places, factions and NPCs | Thornwick, Red Fang Clan, Mira the smith |
| Campaign | What is actually in play, plus its event log | Mira as she is in campaign A |

- The DM **sends** a single NPC or a whole world into the active campaign. That creates a campaign copy that remembers its origin.
- Campaign copies drift freely. Pulling later changes from core or world is a deliberate action, like merging a git branch.
- Two campaigns can hold two different versions of the same character without conflict.

## Timeline and calendars

Everything that changes is an event on one shared world timeline, so a single time slider can rewind characters, map positions and the world together.

- **Character history.** Sheets are never overwritten. "Gained Flame Tongue" or "reached level 5" are events with an in-world date. The sheet at any moment = all events up to that moment, so jumping back to the start is free.
- **Travel tracking.** Every token move is an event with time and position. Drawing them shows the route, back and forth included; scrubbing time makes tokens walk it again.
- **Custom calendars.** Events store a plain day number plus time of day. A calendar only formats that number (months, weekdays, moons, holidays, eras), so editing or swapping a calendar never breaks data.
- **Two clocks.** Each event also carries the real date and session number, so history can be browsed by story time or by session.
- **Storage.** The event log is an append-only file or SQLite, not markdown. Markdown pages only display the history.

## World map and party groups

- **Party token.** On the world map, members are grouped into one token. Dragging it moves everyone, and a travel event is still recorded per member so individual timelines stay correct.
- **Splitting.** Split the party and the group becomes two tokens; merge them again later.
- **Local maps.** Entering a town or dungeon map unfolds the group into individual tokens.

## Chronicle and shared notes

Session notes double as a living campaign chronicle.

- **Dated entries.** Every note carries the real date and the in-world date.
- **Live co-editing.** Players and DM edit the same notes during play. Start simple: the DM host owns each note and a paragraph is locked while someone types in it. Full merge editing (CRDTs) only if needed later.
- **Auto-logged arrivals.** When the party token enters a town, an event like "Party arrived in Thornwick" is written into the session log and onto the town's page. Players add notes before and after that marker.
- **Place history.** Each town page collects every visit over time.

## Assistants (MCP server)

A small separate MCP server (TypeScript or Python) lets AI assistants read campaign data and call functions. Main uses: prep formatting, and live encounter ideas.

| Kind | Tools |
| --- | --- |
| Read | Search entities, get an entity as of a date, list events in a time range, last session's notes |
| Write | Add a note, create an NPC draft, log an event, move the party token |
| Helpers | Format and clean up notes, add wikilinks and frontmatter, suggest a random encounter |

- **Writes go through the event system**, so everything an assistant does is on the timeline and can be undone.
- **Drafts.** New NPCs, lore and encounters arrive as drafts until the DM accepts them.
- **Secrets.** DM-only content is flagged and hidden from player-facing assistants.
- **Two modes.** Offline it reads the folder and event log directly; during a session it talks to the DM client over a local API.
- **Encounters that make sense.** The generator uses location, terrain, in-world date and time, season, party level and HP, local factions and recent events. One click approves it and spawns tokens linked to existing entries.

## Import agents

Agents read PDFs and websites and turn stat blocks, spells, items and NPCs into entity files in the core layer.

- Fill the agreed frontmatter schema; the clearer the schema, the better the import.
- Land as drafts with a source vs. parsed view for checking numbers (tables and multi-column PDFs are error-prone).
- Check for duplicates and offer merge or variant.
- Store a source tag (book, page or URL) on every entry.
- Only sources we own or that are openly licensed (like the SRD); imported content stays private to our table.

## Performance and data transfer

Markdown is the storage format, never the wire format, so loading and sending stay cheap.

- **Loading.** Parse all entities once at startup into an in-memory index; a cache file means later starts only re-parse changed files. Godot has no built-in YAML parser: use an addon, write a parser for our subset, or use C#.
- **Sending.** The DM host sends parsed, compact data (Godot dictionaries via RPC), only what each player may see. DM-only sections are stripped before anything leaves the host.
- **Images.** Maps and token art are the real bandwidth. Send once, cache on clients by file hash, resend only when the hash changes.

## MVP features

The first playable version covers one session on one map.

- [x] Shared map with a grid, loaded from an image
- [x] Tokens players can move (smooth tween movement), DM can move anything
- [x] DM host, players join over the network
- [x] Character sheets read from campaign entities
- [x] ~~Send an NPC or a whole world into the active campaign~~ (replaced by worlds with timelines)
- [x] Event log for moves and sheet changes (rewind comes later, but log from day one)
- [x] Party token group on the world map
- [x] Dice roller that knows the stats ("roll Perception" instead of formulas)
- [x] Session notes with real and in-world date

## Later, or never

- Time slider: rewind characters, map and world
- Travel path display on the world map
- Custom calendar editor
- Live co-editing of notes and auto-logged arrivals
- MCP server for assistants, encounter generator
- Import agents for PDFs and websites
- Fog of war and dynamic lighting
- Spell effect shaders and animations (fireball, auras, weather)
- Initiative tracker with conditions
- Measuring and area templates (cones, spheres)
- Ambient audio per scene
- Map editing inside the VTT

## Open questions

- What does the group actually use most in Foundry during a session? That is the real MVP list.
- ~~How are DM-only secrets marked?~~ `<reveal>` tags per passage (reveal-visibility.md).
- ~~Vault program or VTT as editor?~~ The VTT is the editor, all data is JSON.
- Hosting: DM machine with port forwarding, a relay, or a small dedicated server later?
- ~~Event log format?~~ JSONL, one log per timeline.
- ~~Event types?~~ doc-1; extended in TASK-17.
- When pulling core changes into a campaign copy, how are conflicts shown?
- ~~YAML parsing?~~ Not needed anymore (JSON).

## Next steps

1. Import the DnD campaign and core data into the vault program, already sorted into core, world and campaign.
2. Agree on a frontmatter schema for monsters, NPCs, PCs and places while importing.
3. Sketch the event format (type, entity, in-world day, real date, session, payload) and a first calendar definition.
4. Godot spike: load one markdown file, parse frontmatter, show a token on a grid.
5. Networking spike: DM hosts, one player joins and moves a token, the move lands in the event log.
6. Ask the group what they use most, then trim the MVP list.
