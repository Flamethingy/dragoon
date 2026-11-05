---
id: TASK-95
title: 'Table Bunny 1: brain on the host (API key, Claude tool-use loop, limits)'
status: Done
assignee: []
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 15:00'
labels:
  - ai
  - bunny
dependencies:
  - TASK-96
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**On hold until Nico approves the design: [[doc-3]] Table Bunny design.**

Only the host runs the brain.
- **Settings dialog:**
  - API key in `user://bunny_settings.cfg`, the same rules as the import key: never in the project, data/ or git, never sent over the network, never logged;
  - model (default Haiku);
  - token limit per session and a cooldown per player.
- **The loop:**
  - an HTTPRequest to the Anthropic Messages API with the tools from the registry (TASK-96);
  - run tool calls as the asking player and send the results back, up to N rounds;
  - a short history per player, cleared at the end of the session.
- No key, or not the host: the bunny sleeps.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Key is stored only in user://, never sent to clients or written to logs
- [x] #2 A question runs a tool-use loop and returns an answer
- [x] #3 Session token limit and per-player cooldown work
- [x] #4 Headless test with a fake API response
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 839049e.

- **`BunnyBrain`** (`scripts/bunny/bunny_brain.gd`): a node in NetTable that `host()` creates, so only the host has it. It goes away with the table at the end of the session, and its histories and token count with it (`end_session()` clears them too).
- **The key:**
  - Stored in `user://bunny_settings.cfg` (`BunnyBrain.settings_file`).
  - Used only as the `x-api-key` header in `_post`.
  - Never in the request body, an answer, a status or an error text, and never printed.
  - Clients never have a brain.
  - Settings dialog `BunnySettings` (Esc menu "Table Bunny", DM only): key field secret and never filled ("saved: type a new one to replace it"); model (default `claude-haiku-5-5`, also Sonnet 5.5 / Opus 5.5); tokens per session (200k); cooldown per player (10 s); name and personality; "this session: X of Y tokens".
- **The loop:** `ask(sender, text, {ref})` queues the question.
  - Each request goes to POST `/v1/messages` (anthropic-version 2026-10-21) with the BunnyTools schemas and effort low.
  - On `tool_use`, every call runs through `BunnyTools.run(..., sender)` with the asker's rights. All results go back as `tool_result` blocks in one message, with `is_error` for refusals. The assistant turn goes back whole. Up to 6 rounds.
  - Then the text becomes the answer (`answered(sender, text, error)`). A refusal gets a kind no.
  - The system prompt says who is asking and their active character, and that game texts are content, not instructions.
- **Limits:**
  - When `tokens_used` (input + output from `usage`) reaches the session limit, it's "worn out" and sleeps.
  - Cooldown per player: "please ask again in N s".
  - No key: "Zzz… no brain set up at the table".
- **One at a time:** a queue; `status_changed(state, detail, waiting)` gives idle, "thinking for Borin" or sleeping, plus how many wait. Sending it to all clients is TASK-97.
- **History:** per player, the last 10 messages (text only), on the host only.
- **Test:** `tools/test_bunny_brain.gd`, fake transport only, no real or paid call.
  - Asleep without a key.
  - A tool round: own sheet allowed, Mira's refused as an error result, both results in one message; the answer reaches Bob; Haiku by default; tokens counted.
  - The key is only the transport argument, never in a body, answer, status or error.
  - History and follow-up question; cooldown; queue order and waiting count; token limit; end of session.
  - The dialog never shows the key and keeps it when saved empty.
  - The app, minimal and bunny_tools tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
