---
id: doc-3
title: Table Bunny design
type: other
tags:
  - design
  - ai
  - bunny
project: Dragoon
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 14:44'
---

# Table Bunny: an AI helper at the table

> **Status: approved by Nico on 2026-11-04 ("Mochi can start").** Until Nico answers the open questions at the end, these defaults apply:
> - answers are private, with "to everyone" optional;
> - the bunny may change things through the tools, with the same rights as the player;
> - it lives in the Dragoon window;
> - the name and personality can be set by the host;
> - the limit is in tokens per session.

## Goal
After the showcase (2026-11-04), everyone wanted a small AI bunny at the table:
- it appears on **every client**;
- only the **host** sets up an API key, and every player can still use it;
- it can **only use VTT functions**, with no access to the PC, files, shell or internet.

## Architecture
```
Client (player)  --ask over NetTable-->  Host (DM)  --HTTPS-->  Claude API
       ^                                   |  tool use: only the VTT tool registry
       +------- answer / bubble -----------+  every call checked with the asker's rights
```
- **The brain runs only on the host.** Godot's HTTPRequest calls the Messages API with tool use: no Claude Code, no MCP client, no Python needed.
  - *Open question:* GDScript directly, or a small Python helper like the import agent? Recommendation: GDScript, since it's one HTTP call plus a tool loop.
- **API key:**
  - stored in `user://bunny_settings.cfg`, the same rules as the import key (`import-agent.md`): never in the project, data/ or git, and never sent over the network or logged;
  - the host types it into a settings dialog;
  - clients never see it.
- **Model:** a fast, cheap model by default (Haiku); the host can switch.
- **Costs:** a token limit per session plus a per-player cooldown, both set by the host. A small counter in the host's settings.

## Tools (the tool registry)
A fixed list, defined once in one place (`BunnyTools`). The same list is used by the bunny and by the optional MCP server.

| Tool | Does | Rights |
|---|---|---|
| `rules_lookup` | rules text / conditions | everyone |
| `compendium_search` / `compendium_get` | find and read entries | only revealed / non-draft entries |
| `sheet_read` | read a character | own character; DM: all |
| `add_to_sheet` | add an item / spell / feature (as in TASK-94) | own character; DM: all |
| `roll` | dice, checks, saves for a character | own character; DM: all |
| `combat_state` | order, HP (as far as revealed) | through `Reveal` |
| `note_write` | session note / player note | own notes; DM: all |

- **Every call runs as the asking player:** `Reveal`, `_editable`, `is_dm`.
- The model never decides about rights. It only gets errors back ("not allowed").
- Changes go through the normal event log, so they are visible, can be undone and are synced.
- **Prompt injection** (texts from packages or chat): harmless, because the tools can't do more than the player could do by hand.

## Chat and network
- A player asks (bunny chat box or `/bunny ...` in chat). The request goes to the host as an RPC: `{peer, text, context: active character}`.
- The host queues requests, one at a time per player. Answers go:
  - to the **player who asked**, by default;
  - to **everyone**, if the player chose that (e.g. "Bunny, explain grappling to everyone").
- Short history per player (the last N messages) only on the host, cleared at the end of the session.
- Nobody is a host, or there's no key: the bunny sleeps and says "no brain set up at the table".

### Busy status, visible to everyone (Nico 2026-11-04)
There's only **one** bunny for the whole table, so every client sees what it is doing right now.
- **Status from the host to all clients:**
  - `idle`;
  - `thinking` (for whom: "thinking for Borin");
  - `working` (a longer job: "importing *Deep Magic*… 40%", or "building an encounter");
  - `sleeping` (no key, or the limit is used up).
- **Shown on the bunny itself** (animation plus a small status bubble or badge) and in the chat box. The queue is visible too: "2 waiting".
- **Important jobs** (imports, big changes): the bunny shows that it's busy and new questions wait in the queue with a hint ("I'm busy right now, you're next in line"). The DM can cancel a job.
- Optional: rough costs or tokens for the session, visible only to the host.

## Bunny on the clients
Two variants (to decide):
1. **In the Dragoon window:** the bunny walks along the bottom edge (or above the HUD), with speech bubbles and a click opens the chat. Simple, works everywhere.
2. **Its own transparent window on the taskbar** (like Tamago): more charm, but Godot multi-window, always-on-top and click-through have to work per OS.

Recommendation: start with **1**, and **2** later as an option.

Look:
- its own pixel/sprite set (idle, walk, talk, think, sleep);
- mood from the answer (like Tamago's `mood`);
- turn it off per client (setting), mute it, small/big.

## Optional: MCP server on the host
- Dragoon offers the same tool registry over MCP: a local port, only on localhost, with a token.
- Then Tamago (on Nico's PC) can prepare encounters, write notes etc. with the **DM's rights**.
- Separate from the bunny, so it can be built later.

## Open questions for Nico
1. Should answers be private by default, or always visible to everyone at the table?
2. May the bunny change anything at all (add to a sheet, roll dice), or only read and explain in v1?
3. In the Dragoon window or on the taskbar?
4. Name / personality of the table bunny: the same for every table, or set by the host?
5. A cost limit: tokens per session, or a € amount?
