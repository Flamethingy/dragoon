---
id: TASK-8
title: 'Session lobby: DM host, players join'
status: To Do
assignee: []
created_date: '2026-11-01 11:17'
labels:
  - mvp
  - network
dependencies:
  - TASK-5
documentation:
  - Dragoon Concept
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MVP: a simple start screen where the DM hosts a campaign session and players join over the network and pick their PC. The host only sends each player what they may see; DM-only sections are stripped before sending.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 DM can host with a chosen port; players join by address
- [ ] #2 Players pick their PC on joining
- [ ] #3 Disconnect and rejoin work without restarting the host
- [ ] #4 DM-only content never reaches player clients
<!-- AC:END -->
