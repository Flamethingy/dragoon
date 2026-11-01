---
id: TASK-30
title: Drafts for the whole compendium
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 14:49'
updated_date: '2026-11-01 15:17'
labels:
  - compendium
  - editor
  - import
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From Nico. Every entry gets a `draft` flag (bool, all kinds, packages and campaigns). The Obsidian importer already writes `draft: false` everywhere. Spec: package-format.md, "Drafts", and the change note in import-agent.md.

**Saving**
- New entry: **Save as draft** or **Save** (published).
- A draft shows a **Publish** button. A published entry can go **Back to draft**.
- Features and tables created along with a draft are drafts too and get published with it.

**Seeing**
- Drafts are hidden by default: compendium lists, search, wikilinks, send into campaign, anything sent to players (host filter).
- Every overview (kind lists, package card overview) gets a **Show drafts** tickbox. Drafts then show with a "Draft" badge or dashed frame.
- New **Drafts** page: card overview of all drafts across packages and campaigns, grouped by package, then kind. Each card shows name, kind, last edit and a hint when required fields are empty. Includes a count badge in the navigation.

**Import agent (TASK-28 rework)**
- Finished import jobs merge their entries straight into the target package as drafts. Drafts no longer stay in a separate draft package.
- Review happens in the normal editor and Drafts page. Source page and crop view stay for entries with `source_page`.
- **Publish** replaces "accept". The duplicate question (replace, keep both, skip) comes at publish time. "Publish all" on the Drafts page per import job or package.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Entries without the flag load as published; saving always writes draft
- [x] #2 New entries can be saved as draft or published; drafts can be published and published entries set back to draft
- [x] #3 Drafts are hidden everywhere by default and never reach players
- [x] #4 Every overview has a Show drafts tickbox and marks drafts visibly
- [x] #5 A Drafts page shows all drafts as cards grouped by package and kind
- [x] #6 Import jobs land as drafts in the target package; publishing handles duplicates
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Commit e64b509.
- **EntryStore:** `draft` is always written (missing = published) and drafts get `edited`. New entries start as drafts.
  - `publish` takes the draft's own features and tables along and asks replace / keep both / skip when a published entry has the same name. Replace takes the old id; skip throws the draft away.
  - Also `unpublish` and `crop_picture`.
- **PackageDB:** keeps drafts apart, reachable by id only, so they stay out of lists, search, wikilinks, refs and suggestions.
- **Players:** never get drafts (`entry_view`, PC choices, draft tables in play). Send world skips them; Send is hidden.
- **Book:**
  - Show drafts tickbox in the binder and in package contents, with a Draft tag and dashed frame.
  - Drafts bookmark with the count, opening the Drafts page: grouped by package and kind, with last edit and missing required fields; Publish all per package and per import job.
- **Editor:** Save as draft / Save (publish), Publish, Back to draft. Imported entries show their source page with the crop box.
- **Import:** finished jobs land as drafts in the target package (by the import window, or at book start). DraftReview is removed.
- **Docs:** import-agent.md contract updated. package-format.md "Drafts" was already written (left as is, not committed by me).
- **Tests:** `tools/test_drafts.gd` and the reworked `tools/test_import_ui.gd`. All 24 suites pass.
<!-- SECTION:FINAL_SUMMARY:END -->
