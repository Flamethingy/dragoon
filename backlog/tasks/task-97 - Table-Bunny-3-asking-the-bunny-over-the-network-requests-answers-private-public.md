---
id: TASK-97
title: >-
  Table Bunny 3: asking the bunny over the network (requests, answers,
  private/public)
status: Done
assignee: []
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 15:04'
labels:
  - ai
  - bunny
  - net
dependencies:
  - TASK-95
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**On hold until Nico approves the design: [[doc-3]] Table Bunny design.**

How players ask and get answers:
- **Asking:** a player asks in the bunny chat box or with `/bunny ...` in the chat.
- **Request:** an RPC to the host with `{peer, text, active character}`.
- **Queue on the host:** one request at a time per player; a "thinking" status goes back to the player.
- **Answers:** go only to the player who asked (default), or to everyone if chosen. A short text plus a mood.
- **No brain:** if the host has no key, the bunny says so.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A client's question reaches the host and the answer comes back to that client
- [x] #2 Public answers reach all clients, private ones only the asker
- [x] #3 Thinking state is shown while waiting
- [x] #4 Two-peer headless test with a fake brain
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico 2026-11-04: **The busy status is visible to everyone.** The host sends the bunny's status to all clients whenever it changes:
- `idle`, `thinking` (for whom), `working` (job name plus progress, e.g. an import), `sleeping`;
- plus the queue length.

During important jobs, new questions wait with a hint. The DM can cancel the running job. See [[doc-3]] "Busy status".

Extra acceptance:
- the status and the queue length reach all clients;
- during a long job, questions are queued with a hint;
- the DM can cancel.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @Mochi
created: 2026-11-04 15:04

---

Mochi: the extra acceptance from Nico's note is in commit d414651.
- `BunnyBrain.start_job` / `job_progress` / `end_job`: everyone sees "working: importing Deep Magic 40%", including in the chat status line.
- Questions during a job wait; the asker gets "I'm busy right now (…), you're number N in line".
- The DM cancels with `/bunny stop` (`NetTable.cancel_bunny`). It stops the job (`job_cancelled`) or the answer being worked on, and the queue goes on.
- Tested in `test_bunny_net.gd`.
- Limit: a request already sent to the API finishes in the background, and its answer is dropped.

---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 3b8e40c.

- **Asking:** `NetTable.ask_bunny(text, public, ref)`.
  - In the chat: `/bunny …` asks privately, `/bunny! …` asks for everyone. The chat placeholder mentions it.
  - The question shows in my own chat; the request goes to the host as the `request_bunny` RPC.
  - The host only passes `ref` (the active character) on as context if the asker may see that sheet.
- **Host:** `_handle_bunny_ask` → `BunnyBrain.ask(sender, text, {ref, public})`. The brain's `answered` now carries the context.
  - `_on_bunny_answered` builds an entry {bunny, by: bunny name, text, error, mood (happy/neutral/sad/sleepy), to}.
  - Private: only to the asker (`bunny_said` RPC, or locally for the DM).
  - Public: everyone gets the answer, and the others also see the question.
  - It's a line in the chat feed (`rolls`, not the event log) plus the `bunny_message` signal for the bunny sprite (TASK-98).
- **No brain** (no key, or no host): "Zzz… no brain set up at the table" with mood sleepy.
- **Busy status for everyone:** the brain's `status_changed` goes to every client via the `bunny_status` RPC: state, detail ("thinking for Borin"), how many wait, and the name. Newcomers get it in `hello`.
  - Clients keep `bunny_state` / `bunny_detail` / `bunny_waiting` / `bunny_name` and get the `bunny_status_changed` signal.
  - The chat shows "Hops is thinking for Bob… (1 waiting)" under the feed while it is busy.
- **Test:** `tools/test_bunny_net.gd`, DM + Bob with a fake transport.
  - A newcomer learns the state and name; no key gives the sleepy answer.
  - Bob's question: he and the DM see "thinking for Bob", and so does his chat line; Mira isn't passed as context.
  - The answer reaches only Bob, in his feed.
  - `/bunny!` reaches everyone, including the question; the DM's private question stays with the DM.
  - bunny_brain, bunny_tools, app, minimal, dice and roll_tables pass.
<!-- SECTION:FINAL_SUMMARY:END -->
