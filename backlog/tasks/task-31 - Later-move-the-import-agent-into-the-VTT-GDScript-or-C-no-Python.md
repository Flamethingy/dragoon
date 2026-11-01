---
id: TASK-31
title: 'Later: move the import agent into the VTT (GDScript or C#, no Python)'
status: To Do
assignee: []
created_date: '2026-11-01 15:12'
labels:
  - import
  - later
dependencies:
  - TASK-27
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From Nico: the import agent (TASK-27) starts as a Python tool, but in the long run it should run inside the VTT so no Python install is needed.

Things to decide first:
- **C#:** the official Anthropic C# SDK exists (streaming, structured output), and there are PDF libraries (e.g. PDFium wrappers or PdfPig) for reading pages, finding image boxes and rendering pages. Needs the Godot .NET build for the whole project, plus exports with .NET.
- **GDScript:** Claude API calls via HTTPRequest work (raw HTTP, PDFs can be sent as base64 documents), but Godot can't read or render PDFs. That needs a GDExtension (e.g. PDFium) for chunking, art boxes and page renders.
- The normalizing steps from the Python importer (unique ids, features, rollable tables, ft→m, crops) must be ported and give identical results (compare against the Python output on the same input).

Keep the same job contract (import-agent.md), so the UI (TASK-28/30) doesn't change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision C# vs GDScript + PDF library written into import-agent.md
- [ ] #2 Import of image, PDF and link works without Python installed
- [ ] #3 Results match the Python tool on the same test inputs
- [ ] #4 Same job contract, UI unchanged
<!-- AC:END -->
