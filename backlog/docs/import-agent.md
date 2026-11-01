---
updated_date: '2026-11-01 15:04'
---

# Import agent (PDF, image, web link → package entries)

Proposal 2026-11-01, from Nico's idea: drop a PDF or image into the VTT, or paste a link, and an
AI agent turns it into normal package entries (monsters, spells, items, tables ...) with all
functions (features, rollable tables, dice data, images). Replaces the concept's "Import agents".

## Flow

1. **Input in the VTT:** drag & drop a PDF/image onto the window, or "Import from link" in the
   Packages menu. Pick the target package (or "new package").
2. **The VTT starts the import tool** (`tools/import_agent.py`, Python, launched as a separate
   process) with the file/URL and target package. Progress goes to a log file the VTT shows.
3. **Prepare (code, no AI):**
   - PDF: PyMuPDF splits it into chunks of ~20 pages, finds the art boxes exactly (same logic
     as `extract_pdf_art.py`) and renders each page with the boxes numbered.
   - Image (screenshot of a stat block, a token): used as is.
   - Link: the page is fetched locally, HTML turned into text plus its images.
4. **Extract (Claude API):** each chunk goes to Claude (`claude-opus-5-5`) with the package
   schema (package-format.md) as structured output. Claude returns entries and, per entry,
   the number of the art box that belongs to it. For a single image without boxes it returns an
   approximate crop rectangle.
5. **Normalize (code):** the same steps as the Obsidian importer: unique ids, features split out
   (`extract_features`), rollable tables (`extract_tables`), ft → m, art cropped to
   `art/<id>.jpg`. Every entry gets `origin: {import: "pdf"|"image"|"url", file/url, page}`.
6. **Review in the VTT (drafts):** the tool writes to `data/imports/<job>/`; the VTT merges the
   entries into the target package as **drafts** (since TASK-30). The DM checks them on the Drafts
   page and in the normal editor (source page with crop box beside it) and publishes them.
   Duplicates (same name) ask at publish time: replace, keep both, or skip.

## Why a Python tool and not GDScript

It reuses the existing importer code (normalizing, features, tables, PyMuPDF art) and the
official Anthropic Python SDK. The VTT only starts it and reads the result.

## Costs and limits

- Needs an Anthropic API key (Console, billed per use, separate from a Claude subscription).
  It is stored in the VTT's local settings, never in packages or git.
- Rough cost with Claude Opus 5.5 ($4 per million input tokens, $20 output): a single stat block
  costs about 1-3 cents; a 300-page monster book about $5-10. Big books can run as a batch
  (50% cheaper, results within hours).
- API limit per request: 32 MB and 600 pages. That's why PDFs are always chunked.

## Rules

- Only our own books, PDFs and links we have access to, or open content (SRD). Imports stay in
  git-ignored `data/` like all book content.
- Nothing becomes visible (published) without the DM publishing it.

## Change 2026-11-01: drafts live in the packages (TASK-30)

Nico wants drafts for the whole compendium (`draft` flag, package-format.md, "Drafts"). For
imports this means: after the tool finishes, its entries are merged **straight into the target
package with `draft: true`** (plus features, tables and art). The job dir stays as the tool's
raw output and log. Reviewing = the normal drafts overview and editor (source page and crop
editor stay available for entries with `source_page`); **Publish** replaces "accept", and the
duplicate question (replace, keep both, skip) is asked at publish time.

## VTT <-> tool contract (TASK-28, implemented on the VTT side)

The VTT side is `scripts/import/` (ImportJobs, ImportPanel, CropView), plus the Drafts page and editor in the compendium. `tools/fake_import_agent.py` is a working stand-in that follows this contract (used by `tools/test_import_ui.gd`); the real `tools/import_agent.py` (TASK-27) should behave the same.

**Command** (started with `OS.create_process`, no shell):

```
python tools/import_agent.py --input <file or URL> --kind pdf|image|url --target <package id | new:<name>> --job <job dir> --packages <packages root>
```

- **API key:** only in the environment variable `ANTHROPIC_API_KEY`. It is never passed as an argument and never written to any file. The tool must not log it. The VTT keeps it in `user://import_settings.cfg` (Godot's user folder, outside the project, data/ and git), together with the Python path and an optional agent script path.
- **Job dir** `data/imports/<job>/` (the VTT creates it and writes `job.json` first):
  - `job.json`: `{id, input, kind, target, status, started, error?}`. The tool sets `status` to `running`, then `done` or `failed` (with `error`). If the process exits without doing so, the VTT counts the job as failed. Cancel kills the process and sets `cancelled`.
  - `progress.log`: plain text lines, appended and flushed. The VTT shows it live.
  - **The draft package:** `package.json` with `kind: "draft"`, one `<kind>.json` per kind (monsters, spells, items, tables ...), `features.json` (referenced from the monsters as usual), `art/<id>.jpg`, `pages/<n>.png`.
- **Per draft entry**, in addition to the normal package fields:
  - `origin: {import: "pdf"|"image"|"url", file | url, page}`: this is kept when the entry is merged.
  - `source_page`: the rendered page (relative, e.g. `pages/12.png`), shown next to the editor.
  - `crop`: `[x, y, w, h]` in page pixels. Optional, it is the art box. `image` points at `art/<id>.jpg` if the tool already cut it out.
  - `source_page` and `crop` stay on the draft in the package (hidden fields), so the editor can show the page.
- **Merge (TASK-30):** as soon as a job is `done`, the VTT puts its entries into the target package as drafts (`ImportJobs.merge`; the import window does it while open, the book at start for jobs that finished while it was closed). Features and tables come along. Taken ids get new ones and references follow. Pictures and source pages are copied to `imports/<job>/` in the package. Every entry gets `draft: true` and `origin.job`. `job.json` gets `merged`, `merged_into` and `count`. A read-only source package as target is unlocked; a `new:<name>` target becomes a new world package.
- **Review:** on the Drafts page and in the normal editor. Entries with `source_page` show it below the form with the crop box ("Use selection as picture" writes `art/<id>.jpg`). **Publish** asks replace (takes the old id) / keep both / skip (throws the draft away) if a published entry of the same name exists. "Publish all" works per package or per import job. Features and tables go live with their entry, and loose ones never ask.
