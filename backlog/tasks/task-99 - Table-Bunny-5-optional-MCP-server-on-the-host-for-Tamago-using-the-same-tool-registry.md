---
id: TASK-99
title: >-
  Table Bunny 5 (optional): MCP server on the host for Tamago, using the same
  tool registry
status: Done
assignee: []
created_date: '2026-11-04 14:30'
updated_date: '2026-11-04 15:12'
labels:
  - ai
  - mcp
dependencies:
  - TASK-96
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**On hold until Nico approves the design: [[doc-3]] Table Bunny design.**

Dragoon offers `BunnyTools` over MCP:
- localhost only, with a token;
- off by default, switched on in the host's settings.

Then Tamago on Nico's PC can work with the DM's rights: prepare encounters, write session notes, look things up.

Rules:
- the same permission checks as the bunny;
- no extra tools;
- changes go through the event log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MCP server lists the registry tools and runs them as the DM
- [x] #2 Only localhost + token; off by default
- [ ] #3 Tamago can connect and call a tool
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit 2eb5b66.

`scripts/bunny/bunny_mcp.gd` (BunnyMcp) is an MCP server: Streamable HTTP with JSON responses, protocol 2025-06-18.
- It handles initialize, ping, tools/list and tools/call. Notifications get 202.
- It only listens on 127.0.0.1 and needs `Authorization: Bearer <token>`. A missing or wrong token gets 401. An Origin that isn't localhost gets 403.
- tools/list is exactly the BunnyTools registry. tools/call runs `BunnyTools.run(..., 1)`, which means the DM's rights and the same checks and paths as the bunny. No extra tools.
- It is off by default. The Table Bunny settings (Esc > Table Bunny) have:
  - a checkbox;
  - the port (default 8770);
  - a field with the address and token. The token is made once and kept in user://bunny_settings.cfg.
- NetTable.apply_bunny_mcp() starts or stops the server when hosting and when the settings are saved.

Test: `tools/test_bunny_mcp.gd` covers off by default, 401/403/404, initialize, notification, tools/list, sheet_read as DM, a note_write note "by dm", unknown tool/method, not reachable from the LAN address, and switching off again.

AC3 is still open. I tested with a local client that speaks the same protocol, not with Tamago itself. To connect Tamago, the MCP config needs URL `http://127.0.0.1:8770/mcp` and header `Authorization: Bearer <token from the settings>`; Nico or Tamago has to set that up.

Note: test_minimal crashes at exit (139) after "all good". This happens without these changes too.
<!-- SECTION:FINAL_SUMMARY:END -->
