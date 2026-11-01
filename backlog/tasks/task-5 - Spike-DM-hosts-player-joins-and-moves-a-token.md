---
id: TASK-5
title: 'Spike: DM hosts, player joins and moves a token'
status: Done
assignee:
  - '@Mochi'
created_date: '2026-11-01 11:17'
updated_date: '2026-11-01 12:22'
labels:
  - spike
  - network
dependencies:
  - TASK-2
  - TASK-3
documentation:
  - Dragoon Concept
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Networking spike (concept: Next steps 5, Architecture): the DM client hosts over ENet, one player client joins, sends a move request, the DM validates and broadcasts it, and the move is appended to the event log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DM instance hosts, a second instance joins via IP and port
- [x] #2 Player move is a request; only the DM changes state and broadcasts
- [x] #3 Both clients see the token move
- [x] #4 The move is written to the event log in the TASK-2 format
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TokenGrid gets reusable token cells and moves, plus a drag that emits move_requested. A NetTable scene on top of it: Host/Join bar (ENet). The host opens the campaign EventLog and rebuilds token positions from it (Replay.tokens_on). Clients send request_move RPCs to the host; the host validates (bounds, overlap), appends a token.moved event and broadcasts token_moved to everyone, and a newly joined peer gets a full sync. Headless test runs host and client in one process with two MultiplayerAPIs.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
- **Scene:** `scenes/spikes/net_table.tscn` (`NetTable`, `scripts/net/net_table.gd`). Its bar has an address field, "Host as DM", "Join" and a status line. From the command line, `-- --host[=port]` or `-- --join=ip:port` starts right away.
- **Hosting:** the DM opens the campaign's `EventLog` (`user://campaigns/example/events.jsonl`) and restores token positions from it with `Replay.tokens_on`, then listens on ENet (port 7777 by default). A player who joins gets a full token sync.
- **Moves:** dragging a token emits `TokenGrid.move_requested`. A player only sends `request_move` to the DM. The DM validates (token exists, inside the map, square not blocked), writes `token.moved` to the log in the TASK-2 format (`by` = `player:<id>` or `dm`), and broadcasts `token_moved` to everyone, itself included. Tokens glide to the new cell. A refused move tells only that player why, and nothing is logged.
- **TokenGrid** (`scripts/spikes/token_grid.gd`) is now a reusable class: tokens keyed by entity id, `set_token_cell` (animated), `can_place`, `cell_at`, and left-drag to move.
- **Test** (`tools/test_net_table.gd`): DM and player run in one process with separate MultiplayerAPIs over localhost ENet. Covered: join, player request, both see the move, event on disk with all fields, blocked move denied, DM moves directly, restarted DM restores positions from the log. All pass.
- **Spike limits:** players may move any token; ownership comes with TASK-7/8. There's no lobby or names yet (TASK-8).
<!-- SECTION:FINAL_SUMMARY:END -->
