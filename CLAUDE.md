# Dragoon

Custom virtual tabletop (VTT) for our own DnD campaign, built in **Godot 4.7** (Forward Plus,
Jolt Physics). Hardcodes our ruleset and homebrew. All data is JSON with Markdown text fields and
the VTT is the editor. Every change during play is an event on a timeline, and the DM client hosts
players over ENet.

## Read first
- `backlog/docs/Dragoon Concept.md`: vision and principles. The header note lists what has changed since then.
- `backlog/docs/package-format.md`: core data as JSON packages (`data/packages`, git-ignored), drafts, importer `tools/import_obsidian.py`.
- `backlog/docs/data-layout.md`: the entry schema per kind (characters, creatures, places, maps ...) and refs.
- `backlog/docs/timelines.md`: worlds with git-like timelines (these replace campaigns), maps and encounters.
- `backlog/docs/doc-1 - Event-format.md`: the event record and all event types.
- `backlog/docs/reveal-visibility.md`: `<reveal>` tags, per-player visibility.
- `backlog/docs/rules-automation.md`: which rules are automated and how far, Nico's decisions, phases.
- `backlog/docs/import-agent.md`: AI import of PDFs, images and links as drafts.
- `backlog/docs/progress.md`: current status, open questions, next steps. **Update it at the end
  of every work session.**

Terms: creatures (book stat blocks, formerly monsters), characters (PCs and NPCs), world (a package),
timeline (one history of play in a world, formerly campaign).

## Layout
- `scenes/` scenes, `scripts/` GDScript, `assets/` art and sound.
- `addons/godot_ai/` Godot AI plugin (MCP bridge to the editor). Open the project in the editor
  so the godot-ai MCP tools can connect.

## Tasks (Backlog.md)
Tickets live in `backlog/tasks/`, managed with the `backlog` CLI (Backlog.md 1.53.0).
- Pick work: `backlog task list -s "To Do" --plain`, highest priority first.
- Start: `backlog task edit <id> -s "In Progress"` with a short `--plan`. **Always do this before
  writing any code, also when you get several tickets at once (one at a time).** Nico follows
  progress on the board.
- Finish: check acceptance criteria, write `--final-summary` (what changed, commit hash), `-s Done`.
- Out-of-scope findings become new tasks.

## Conventions
- GDScript with static typing. Files `snake_case`, classes `PascalCase`.
- Commit the task file together with the change.
