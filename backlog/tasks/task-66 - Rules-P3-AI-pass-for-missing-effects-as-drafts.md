---
id: TASK-66
title: 'Rules P3: AI pass for missing effects (as drafts)'
status: Done
assignee:
  - Mochi
created_date: '2026-11-02 00:45'
updated_date: '2026-11-02 02:41'
labels:
  - rules
  - phase-3
  - import
dependencies:
  - TASK-65
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For entries the regex parser can't structure: a batch run of the import agent (Claude, Batch API for half the price) proposes `effects` per entry against the format. Results land as drafts of the change, and the DM reviews and publishes them on the Drafts page (diff view: old vs proposed effects).

Do one package at a time with a cost estimate shown first. Start with the 5e core rules spells.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Batch run proposes effects for unparsed entries with a cost estimate first
- [x] #2 Proposals are reviewable drafts with a diff; publishing writes them
- [ ] #3 Run on 5e-core-rules spells
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design choices (Mochi):
- tools/ai_effects.py, one package and kind at a time. `estimate` costs nothing; `run` asks directly, for small tests; `submit` / `collect` use the Batch API at half price. `run` and `submit` always print the estimate and send nothing without --yes. The model is claude-opus-5-5 at effort low with adaptive thinking; the system prompt (the format) is cached.
- The API key comes only from ANTHROPIC_API_KEY and is never printed or written.
- Answers are plain JSON {effects, notes}, checked against the format (unknown shapes are dropped).
- Proposals become drafts next to their entry: id `<id>--effects`, draft_of, effects_source "ai", ai_notes, origin.job (so "Publish all from <job>" works).
- An empty answer marks the entry effects_checked: "ai" (with the notes), so it is not paid for again.
- Drafts page: a proposal row shows the effects now vs the proposed ones (a one-line summary; the full JSON is in the tooltip), with Publish / Discard / Open. Publishing (EntryStore.publish via draft_of) writes the effects into the original entry, sets effects_source ai and removes the draft.
- Test run (allowed ≤5 entries): `run --package 5e-core-rules --kind spells --limit 5 --yes` cost ~$0.05 (6.8k in / 0.9k out). The first 5 (Aid, Alarm, Alter Self, Animal Messenger, Animal Shapes) correctly came back empty with reasons, so 0 drafts. (These ran before the effects_checked marker existed and will be asked again once, ~$0.05.)
- FULL RUN NOT DONE (Nico starts it). Estimate for 5e-core-rules spells: 195 entries, ~$1.71 with the Batch API (~$3.43 direct); features: 540 entries, ~$4.54 batch.
  Command: `python tools/ai_effects.py submit --package 5e-core-rules --kind spells --yes`, later `... collect --package 5e-core-rules --kind spells`, then review on the Drafts page.
- AC 3 stays open for that run.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AI effects pass built (commit d17bb90): estimate/run/submit/collect, proposals as drafts with a diff on the Drafts page, publish/discard. Tested live on 5 spells (~$0.05) and offline with the fake mode (tools/test_ai_effects.gd); suite 47/47 green. The full paid batch is left to Nico (spells ~$1.71 batch).
<!-- SECTION:FINAL_SUMMARY:END -->
