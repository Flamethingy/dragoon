---
id: TASK-27
title: 'Import agent tool: PDF/image/link to draft package (Python + Claude API)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-01 14:26'
updated_date: '2026-11-01 15:36'
labels:
  - import
  - data
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Mochi builds this** (Nico, 2026-11-01). Earlier versions said "data side (Tamago)"; that's no longer true. Build tools/import_agent.py so it follows the contract in import-agent.md ("VTT <-> tool contract"), exactly like tools/fake_import_agent.py. Final drafts land in the target package via ImportJobs, as already built in TASK-30.

**Steps**
1. **Prepare (no AI)**
   - pdf: open it with PyMuPDF (`import pymupdf`, installed), render every page to `pages/<n>.png` (~110 dpi) and chunk it into ~20 pages per request (API limit: 32 MB / 600 pages per request).
   - Art boxes: per page, use `art_regions(page, decor_images(doc))` from tools/extract_pdf_art.py (it skips backgrounds and repeated ornaments and merges tiles). Draw the box numbers onto the image you send so Claude can name them.
   - image: send it as is.
   - url: fetch it with urllib, strip the HTML to text and keep `<img>` URLs. Download those images as possible art.
2. **Extract (Claude API)**
   - Use the official `anthropic` SDK (`pip install anthropic`) with model `claude-opus-5-5`, `thinking: {type: "adaptive"}` and streaming (`client.messages.stream(...).get_final_message()`).
   - Input is the PDF chunk as a `document` block (base64), or page images, plus the system prompt.
   - Output: structured output (`output_config: {format: {type: "json_schema", schema}}`) of entries per kind, with the package schema from package-format.md. Monster features come inline as `{name, text}`, and every entry has `art_box` (the box number or -1) and `page`.
   - For single images (no boxes): ask for `crop: [x, y, w, h]` in image pixels.
   - Check `stop_reason` (handle `refusal` and `max_tokens`). Retries are built into the SDK.
3. **Normalize:** import from tools/import_obsidian.py: `slug`, `unique_ids`, `extract_features` (turns the inline features into features.json with ids), `extract_tables` (rollable tables) and `fix_units` (ft→m on all text). Set `draft: true` and `origin: {import, file|url, page}`, plus `source_page` and `crop`.
4. **Art:** crop each box from the page render into `art/<id>.jpg` (or use the crop from step 2) and set `image`.
5. Write `progress.log` lines per chunk ("Pages 1-20: 14 monsters, 3 spells") and set `job.json` status to done/failed.

**Key:** only from the env var ANTHROPIC_API_KEY, which ImportJobs already sets. Nico pastes the key from the vault note (TamagoVault/secrets/Dragoon API key.md) into the import settings once. Never log it.

**Test without spending much:** first a single stat block screenshot (about 1-3 cents), then 10 pages of Monsters of the Multiverse (data/packages/monsters-of-the-multiverse/docs, pages 60-70 have Barghest to Bodak with art).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A dropped stat block screenshot becomes a correct monster draft with features and a cropped image
- [x] #2 A PDF chunk of Monsters of the Multiverse gives monster drafts with matching art
- [x] #3 A web page link (e.g. a Homebrewery page) gives drafts
- [x] #4 Output passes audit_packages.py
- [x] #5 API key read from local settings, never written to data or git
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nico (2026-11-01): Mochi does this too, after his current work (together with TASK-28). The Anthropic API key is in the user's vault: C:\Users\nico1\TamagoVault\secrets\Dragoon API key.md. Read it at runtime or via the ANTHROPIC_API_KEY env var, and never copy it into the repo, data/ or logs. Reusable code: tools/import_obsidian.py (unique_ids, extract_features, extract_tables, fix_units) and tools/extract_pdf_art.py (art boxes, decor filter, crops).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
tools/import_agent.py (commits 3db7a55, 076aa22) follows the VTT contract like fake_import_agent.py, with an optional --pages flag for tests.

- **PDF:** pages are rendered to pages/<n>.png at 110 dpi and sent 20 per request as images. The art_regions boxes are drawn and numbered on them, and the page's text layer goes along. I used page images instead of a document block so Claude can name the boxes.
- **Image:** scaled to at most 1568 px, so Claude's crop coordinates match ours.
- **URL:** urllib text plus up to 20 pictures. Homebrewery share/edit links are read from /source/. The fetch follows 308 redirects by hand (Python 3.10 doesn't).
- **Schema:** the first schema was rejected ("compiled grammar is too large"), so stat block lines (speed, saves, skills, senses, damage lists, components) come back as strings and are parsed locally. Features come as one list with a section field.
- **Normalize:** import_obsidian's helpers (parse_feature, unique_ids, extract_features, extract_tables, fix_units).
- **Errors:** a refusal skips and logs the chunk. A cut-off answer (max_tokens) is asked again in two halves. Rarely a ’ or — arrives broken (U+FFFD) and is repaired.
- **Key:** only from the env var and scrubbed from every log and job line.

Tests:
- Boggle page as image: correct stats, 4 features, clean crop. About 3.7k tokens in and 1.6k out.
- MotM pages 60-70: 11 monsters (Bard to Canoloth), all art matching, 66 features, 2 tables. About 31k tokens in and 15k out, 2 min.
- dnd5e.wikidot.com Fireball: 1 spell.
- audit_packages finds no leftovers, and no key turns up in any output.
- tools/check_real_import.gd merges each job via ImportJobs.merge: all drafts, files present, features resolved.
- Not tested on a real Homebrewery brew (no public link at hand).
<!-- SECTION:FINAL_SUMMARY:END -->
