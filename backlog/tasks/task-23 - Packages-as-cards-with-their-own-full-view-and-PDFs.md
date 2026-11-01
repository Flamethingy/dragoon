---
id: TASK-23
title: Packages as cards with their own full view and PDFs
status: To Do
assignee: []
created_date: '2026-11-01 13:20'
updated_date: '2026-11-01 13:28'
labels:
  - ui
  - data
dependencies:
  - TASK-22
documentation:
  - package-format
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Expand the compendium's **Packages** menu so packages are treated like every other kind of card:
- Packages appear as **cards** in the binder (cover image if the package has one, name, kind badge `source` / `world`, entry count). Filters: kind, enabled/disabled, has PDFs. Search over name and description.
- The existing **On/Off** toggle stays: on the card (small switch) and in the full view. Disabled packages are dimmed and their entries vanish from the other kinds, as today.
- Opening a package (TASK-22 tab system) shows a **full view**: name, version, kind, description (Markdown), counts per kind (each count clickable → Browse tab filtered to that package + kind), import origin, dependencies (empty for now) and a **Documents** section.
- **Documents**: the manifest gets a `documents` list `[{file, title, size, pages?}]` with paths relative to the package folder (`docs/Players Handbook.pdf`). Show them as a list with title, size and an **Open** button. For now, open the PDF in the system's default viewer (`OS.shell_open`). A built-in viewer can come later. Also offer "Show in folder" and **Add PDF...** (copies a file into `docs/` and adds it to the manifest).
- Export/import (TASK-16) includes `docs/`. Show the size before exporting, because PDFs can be large.

Tamago fills `documents` from the Obsidian vault via `tools/import_obsidian.py`; the field is described in package-format.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Packages show as cards in the compendium with name, kind badge, entry count and on/off switch; filter and search work
- [ ] #2 On/off still works from card and full view; disabled packages are dimmed and their entries are hidden elsewhere
- [ ] #3 The package full view (own tab) shows version, kind, description, clickable counts per kind, origin and dependencies
- [ ] #4 Documents section lists the manifest's PDFs with title and size; Open launches the default viewer, 'Show in folder' and 'Add PDF...' work
- [ ] #5 Package export/import includes docs/ and shows the total size first
- [ ] #6 The package full view has a card-style 'Contents' overview: the package's entries as cards (same card look as the binder), grouped by kind with a header and count per kind (Monsters 395, Spells 12 ...), collapsible groups, a search field inside the package, and cards open in their own tab like everywhere else
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-01 (Nico): when opening a source, show an overview in card style of all elements in that source. Added as AC6. Big packages (Tome of Beasts 3 has ~400 monsters + ~2400 features) need paging or lazy loading per group. Features are better collapsed by default, since they are mostly reached via their monsters.
<!-- SECTION:NOTES:END -->
