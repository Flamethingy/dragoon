# Dragoon

Custom virtual tabletop (VTT) for our own DnD campaign, built in **Godot 4.7** (Forward Plus,
Jolt Physics). Hardcodes our ruleset and homebrew, reads campaign data from markdown files written
by the vault program, logs every change as an event on one world timeline, and the DM client
hosts players over ENet.

## Read first
- `backlog/docs/Dragoon Concept.md`: vision, data model, campaign layers, event timeline, MVP.
- `backlog/docs/progress.md`: current status, open questions, next steps. **Update it at the end
  of every work session.**

## Layout
- `scenes/` scenes, `scripts/` GDScript, `assets/` art and sound.
- `addons/godot_ai/` Godot AI plugin (MCP bridge to the editor). Open the project in the editor
  so the godot-ai MCP tools can connect.

## Tasks (Backlog.md)
Tickets live in `backlog/tasks/`, managed with the `backlog` CLI (Backlog.md 1.53.0).
- Pick work: `backlog task list -s "To Do" --plain`, highest priority first.
- Start: `backlog task edit <id> -s "In Progress"` with a short `--plan`.
- Finish: check acceptance criteria, write `--final-summary` (what changed, commit hash), `-s Done`.
- Out-of-scope findings become new tasks.

## Conventions
- GDScript with static typing. Files `snake_case`, classes `PascalCase`.
- Commit the task file together with the change.
