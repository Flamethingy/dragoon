# Rules automation: overview and plan

Written by Tamago on 2026-11-02 at Nico's request. Based on:
- the code (state after TASK-49 was created),
- all docs in backlog/docs,
- a scan of all package data (12,127 creature features, 1,402 spells, 29 classes, 224 subclasses,
  90 races, 120 subraces, 116 feats, 79 items),
- the 5e rules (SRD 5.1 / PHB).

Goal: know what can be automated, where, and how far it makes sense, so play keeps flowing
without the VTT getting in the way of the players and the DM.

## 1. The guiding rule

> **Automate the bookkeeping, never the decisions.**

The VTT counts, rolls, adds up, reminds and remembers. People decide who is hit, whether
something works narratively, whether cover applies, whether a rule is bent. Every automated step
is an event: visible in the log, undoable, overridable. The VTT **warns, it never blocks** (e.g.
"no level 3 slots left. Cast anyway?").

This is consistent with "explicit, not automatic" and "the DM is the authority" in the
concept, and with existing precedents (temp HP absorbs damage first, a long rest resets
resources in Replay, encounters are saved automatically). Those precedents are exactly the
"bookkeeping" kind.

### Automation levels

| Level | Name | What the VTT does | Example |
| --- | --- | --- | --- |
| 0 | Reference | shows the text, dice in the text are clickable | "The dragon's roar frightens..." |
| 1 | Roll | rolls with the right modifiers, adv/dis, crit | Perception check, Longbow attack |
| 2 | Assist | rolls and **proposes** the result per target, one click applies it | "Goblin 2: hit (17 vs AC 15), 9 slashing. Apply?" |
| 3 | Track | keeps a counter or a state up to date by itself | spell slots, concentration, durations, recharge |

Each **category** (damage application, conditions, resources, durations, movement ...) gets a
table setting: Off / Assist / Auto. Default is Assist. Nico decides once per table; it is a
house setting, not a settings jungle.

## 2. What we have today (code)

**Works:**
- Dice: formulas, kh/kl, advantage, crit marking, named rolls ("roll Perception", saves,
  initiative, "attack with Longbow" from feature data).
- HP and temp HP: temp is used first, clamped 0..max, as events.
- AC and other fields via `sheet.changed`.
- Spell slot pips: computed from classes, including multiclass and pact magic.
- Combat turn order: start, next turn, end.
- Encounters saved and replayable.
- Token movement: ownership and placement check, planned paths, facing.
- Rollable tables.

**Exists in the data model and in Replay, but nothing writes it yet:**
- `condition.applied/removed`, `initiative.rolled`, `resource.used/restored`
- `rest.taken`, `death_save.rolled`, `currency.changed`, `item.gained/lost`
- `level.gained`, `time.advanced`

The foundation is there; the buttons and rules that write these events are missing.

**Gaps and inconsistencies to clean up first:**
- Two schemes for spell slots: `spell_slots_used` via `sheet.changed` vs `resource.used spell_slots.N`.
- `level.gained` writes `levels{}`, but slot math reads `classes[].level`.
- Inventory changes replace the whole list via `sheet.changed` instead of `item.gained/lost`.
- `feature.save` and `feature.damage` are parsed but never used.
- Resistances, immunities and vulnerabilities are never applied.
- No crit damage, no targets, no hit-vs-AC comparison.
- `combat.started` puts everyone at initiative 0.
- 0 HP does nothing (no unconscious, no death saves).
- Players may set any value on their own sheet. That's fine (trust), but changes should show up
  in the DM's log.

## 3. What our data looks like

### Creature features (12,127)

| Pattern | Share | Already structured? |
| --- | --- | --- |
| damage dice | 42% | yes, `damage` (4,451) |
| attack roll | 33% | yes, `attack` (3,370) |
| saving throw (DC) | 22% | yes, `save` (2,802) |
| applies a condition | 21% | no, text only |
| advantage/disadvantage | 13% | no |
| forced movement / speed | 7% | no |
| multiattack | 6% | no (text lists the attacks) |
| start/end of turn effects | 6% | no |
| half damage on save | 5% | no |
| recharge / per day | 5% | `uses` as text (1,219) |
| resistances | 5% | no |
| areas (cone 2.7%, sphere 1.7%, line 0.8%, aura 1.4%) | ~6% | no |
| spellcasting | 4% | no (spell lists in the text, the creature `spells` field is empty) |
| legendary (147 creatures), reactions (301), bonus actions (235) | | yes, separate lists |

So about two thirds of creature actions are already rollable at level 1–2. The rest is
conditions, areas and turn effects.

### Spells (1,402)

| Pattern | Share |
| --- | --- |
| saving throw | 55% |
| damage dice | 40% |
| upcasting ("At Higher Levels") | 38% |
| concentration (field) | 37% (525) |
| applies a condition | 29% |
| advantage/disadvantage | 22% |
| area: sphere/radius 14%, cube/cylinder/aura 9%, cone 3%, line 1% | ~27% |
| forced movement / teleport | 14% |
| attack roll | 14% |
| start/end of turn effects | 12% |
| half damage on save | 11% |
| resistance | 11% |
| summons | 10% |
| pure utility (no numbers) | ~19% |

**Spells have no structured mechanics yet.** Only `level`, `school`, `range_m`, `duration`,
`concentration`, `ritual` and `components` are fields. Attack, save, damage, area and scaling are
prose. This is the biggest data gap.

### Classes, subclasses, races, feats

- **Classes** have only hit dice, proficiencies and spell ability as fields. All features (Second
  Wind, Action Surge, Rage, Ki ...) are **one Markdown text with headings**. The level table was
  a Dataview table and is lost, so features have **no level** and **no resource data**.
  - 100% mention rest-based resources.
  - 69% mention advantage.
  - 59% have reactions.
- **Subclasses (224):** 75% have rest-based resources, 57% reactions, 64% advantage.
- **Races:** 98% have speed or movement rules, 61% advantage, 50% per-rest abilities.
- **Feats:** 37% purely narrative, 31% resources, 28% advantage.
- **Items:** all mechanics are prose. Only 10% have a plain "+N bonus".
- **Conditions:** no core definitions exist in the data (one stray entry). We need our own
  built-in table.

## 4. Rules inventory: what, how far, how

★ = value for flow, ⚙ = effort. Level = the target automation level.

### Checks and saves

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Ability checks, skills, saves with proficiency/expertise | 1 | ★★★ | done | add expertise (double prof) and Jack of All Trades as sheet flags |
| Advantage/disadvantage | 1–2 | ★★★ | low | Shift/Ctrl exists. Later: auto-suggest from conditions (poisoned → dis on attacks/checks) shown as a toggle, never forced |
| Passive scores | 3 | ★★ | low | passive Perception/Insight/Investigation computed and shown to the DM |
| Group checks ("everyone roll Stealth") | 2 | ★★★ | med | DM requests, players get a prompt, results visible only to the DM |
| Hidden DM rolls | 1 | ★★ | done | |
| Contests (grapple, shove) | 1 | ★ | low | roll both sides, show the winner, DM applies |

### Attacks and damage

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Attack roll vs AC | 2 | ★★★ | med | select targets (click tokens) → roll → "hit/miss" per target. Cover is a toggle on the roll card (+2/+5) |
| Critical hits | 1 | ★★★ | low | natural 20 doubles the damage dice |
| Damage types + resistance/immunity/vulnerability | 2 | ★★★ | low | the apply button already shows the adjusted value ("9 → 4, resistant") |
| Save-based effects (DC, half on save) | 2 | ★★★ | med | targets roll (players get a prompt, the DM rolls creatures in bulk), the result is applied per target |
| Multiattack | 1 | ★★ | low | one button rolls the listed attacks in a row |
| Weapon attacks from inventory | 3 | ★★ | med | equipped weapon + ability + proficiency = to-hit/damage, finesse/versatile/ranged |
| Reach, range | 2 | ★ | med | warning when the target is out of range, never blocking |
| Opportunity attacks | 0–2 | ★ | high | optional reminder only ("Goblin 1 leaves Haku's reach") |

### HP, dying, death

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Damage/heal, temp HP | 3 | ★★★ | done | |
| 0 HP → unconscious, death saves | 3 | ★★★ | low | PC at 0 gets Unconscious plus a death save button on their turn; creatures at 0 are marked defeated (DM chooses: dead or knocked out) |
| Damage at 0 HP = failed save, crit = 2 | 3 | ★★ | low | |
| Massive damage (instant death) | 2 | ★ | low | warning only |
| Healing removes unconscious | 3 | ★★ | low | |

### Conditions and effects

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| 15 conditions + exhaustion levels | 3 | ★★★ | med | built-in `dragoon-core` definitions: icon, rules text, mechanical flags (e.g. poisoned: disadvantage on attacks and checks). Shown on token and sheet |
| Condition immunity | 2 | ★★ | low | warning when applying |
| Durations ("1 minute", "until end of its next turn") | 3 | ★★★ | med | `until {round, turn, who}` or `{day, time}`. When it runs out: highlight, then remove with a log line (undoable) |
| "Save ends" (save at end of each turn) | 2 | ★★★ | med | prompt at the right turn moment, success removes it |
| Buffs/debuffs (Bless +d4, Shield +5 AC, Haste) | 2 | ★★ | high | small effect vocabulary (section 5), only for the common spells/features |
| Concentration | 3 | ★★★ | low | one concentration per caster; a new one ends the old; damage → CON save prompt (DC max 10 / half); dropping it removes linked effects |

### Turns and combat

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Initiative | 2 | ★★★ | low | "Roll initiative" rolls for all creatures (groups share one roll if wanted), players get a prompt or type in their physical roll |
| Turn order, rounds | 3 | ★★★ | done | |
| Action economy (action, bonus, reaction, movement, object) | 3 | ★★ | med | pips on the HUD, reset at turn start. Display only, no blocking |
| Movement budget | 2 | ★★ | med | trail shows the metres used; over speed = warning colour. Difficult terrain later (painted on the map) |
| Start/end of turn triggers | 3 | ★★ | med | recharge rolls (5–6), regeneration, ongoing damage, legendary action reset, reaction reset, durations |
| Legendary actions / resistances | 3 | ★★ | low | counters on the creature, reset on its turn |
| Lair actions | 0–2 | ★ | low | reminder at initiative 20 |
| Surprise | 1 | ★ | low | flag in the initiative dialog |

### Resources and rests

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Spell slots (incl. pact magic) | 3 | ★★★ | low | exists; unify to `resource.used`, spend on cast |
| Class resources (Rage, Ki, Sorcery Points, Bardic Inspiration, Channel Divinity, Second Wind ...) | 3 | ★★★ | high | needs per-level data (section 5) |
| Feature uses (1/Day, Recharge 5–6, X/short rest) | 3 | ★★★ | low | `uses` is already parsed as text: turn it into `{max, reset}` |
| Short rest (hit dice) | 2 | ★★ | med | rest dialog: spend hit dice, roll, heal, reset short-rest resources |
| Long rest | 3 | ★★★ | low | HP, half the hit dice, slots, uses, exhaustion −1; one click per party, advances the clock |
| Item charges (wands) | 3 | ★ | low | same resource model, reset "at dawn" |

### Spellcasting

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Spell attack / save DC | 3 | ★★★ | low | computed from class ability + proficiency (+ items) |
| Cast = spend slot + roll + apply | 2 | ★★★ | high | needs structured spell data |
| Upcasting | 2 | ★★ | med | slot level picker, damage dice scale with structured `scaling` |
| Cantrip scaling (levels 5/11/17) | 3 | ★★ | low | |
| Areas: templates, targets in area | 2 | ★★★ | high | place a cone/sphere/line/cube on the grid, tokens inside get selected, the DM can add/remove targets before rolling |
| Rituals, components, material costs | 0 | ★ | – | text only; no component tracking |
| Prepared vs known spells | 1 | ★ | low | a flag on the character's spell list |
| Summons / wild shape / polymorph | 1 | ★★ | med | drop the summoned creature from the compendium as a linked token; wild shape swaps the active sheet. Later |

### Characters and items

| Rule | Level | ★ | ⚙ | Notes |
| --- | --- | --- | --- | --- |
| Derived stats (modifiers, prof bonus by level, saves, skills, passive, spell DC) | 3 | ★★★ | med | computed, not stored; overridable field by field |
| AC from equipped armor + Dex + shield + items | 3 | ★★ | med | items need `ac` data |
| Attunement (max 3) | 2 | ★ | low | warning |
| Encumbrance | 0 | – | – | skip (optional rule, usually ignored) |
| Ammunition | 2 | ★ | low | optional counter on the weapon |
| Level up | 2 | ★★ | high | assistant: HP (roll/average), new features of the level, slots, ASI/feat. Needs per-level class data |
| XP / milestones | 1 | ★ | low | `xp.awarded` event, encounter XP from CR |

### Out of combat, exploration, roleplay

| Rule | Level | ★ | Notes |
| --- | --- | --- | --- |
| Social interaction, decisions, consequences | 0 | ★★★ | **never automated**. Support only: notes, reveals, NPC attitude field, relationship events |
| Travel, time, rests, weather | 1–2 | ★★ | the timeline clock advances on rests or travel; weather and calendar exist |
| Vision, light, darkvision, fog | later | ★★ | big feature (fog of war). Only after the core loop works |
| Traps, hazards | 1 | ★ | rollable save/damage buttons in place/encounter notes |
| Encounter difficulty (XP budget from CR vs party) | 2 | ★★ | shown while prepping an encounter |
| Loot / treasure | 1 | ★ | rollable tables already exist |

## 5. Data plan: what has to be added

### 5.1 `dragoon-core` package (built-in rules data)

- Conditions with icon, rules text and flags.
- Damage types, weapon properties, armor table (base AC, Dex cap, stealth).
- Proficiency bonus by level, spell slot tables, cantrip scaling, XP by CR.
- Small, maintained by hand, versioned in git (SRD content is open, so it may live in the repo).

### 5.2 One effect format for features, spells, items and class features

An optional `effects` list on any entry. The text stays the source of truth; effects are what
the buttons do.

```json
"effects": [
  { "roll": "attack", "to_hit": "spell", "damage": [{"dice": "1d10", "type": "fire"}],
    "scaling": {"cantrip": true} },
  { "roll": "save", "ability": "dex", "dc": "spell", "on_fail": {"damage": [{"dice": "8d6", "type": "fire"}]},
    "on_success": "half", "area": {"shape": "sphere", "size_m": 6}, "scaling": {"per_slot": "1d6"} },
  { "apply": "condition", "condition": "frightened", "duration": {"rounds": 10},
    "save_ends": {"ability": "wis", "when": "end_of_turn"}, "concentration": true },
  { "modifier": {"target": "ac", "op": "add", "value": 5}, "duration": {"until": "start_of_turn"} },
  { "resource": {"id": "rage", "max": "table:rage", "reset": "long"} },
  { "heal": "2d4+2" }
]
```

- Values like `"spell"`, `"prof"`, `"cha_mod"`, `"level"` or `"table:rage"` are resolved from the
  sheet.
- Unknown or complex effects simply don't get an `effects` entry: level 0/1 fallback (clickable
  dice in the text).

**How to fill it:**
1. **Regex parser** (like the existing feature parser) for the clear cases: attack, save + DC,
   half on save, damage, area shape + size, "At Higher Levels" dice, concentration, durations,
   conditions mentioned with "be/become <condition>". Expected: most spells and creature features.
2. **Import agent / AI batch** for the rest and for class features. Results land as **drafts**
   (the existing draft system), the DM reviews, publishes. One-time cost per book.
3. **Hand editing** in the editor (an effects editor with presets) for homebrew.

### 5.3 Class features as their own entries

Split the class Markdown into features with `level`, `class`/`subclass`, `uses` and `effects`.
The level table was lost in the import: re-derive it from the vault (or the AI pass) once.
This unlocks resources, level up and the HUD's class actions.

### 5.4 Character derived stats

- One `Rules` module computes modifiers, proficiency, saves, skills (with expertise), passive
  scores, AC, spell DC and attack, slots and resource maxima from the sheet + classes + items +
  active effects.
- Stored fields become **overrides** only (shown with a small marker).
- The same module is used by the HUD, the sheet, the dice and the MCP assistants.

## 6. How it feels at the table (flow design)

**Out of combat**
- Rolls are one click; the DM can ask for checks ("Everyone: Perception"), results go to the DM
  only.
- Nothing pops up unless asked.
- Physical dice are always allowed: every roll prompt has "I rolled: __".

**In combat**
1. DM: Start combat → initiative is rolled for the creatures; players roll or type theirs.
2. On a turn: the HUD shows the active creature with action pips, movement left and its
   actions/spells as buttons. Start-of-turn things happen first: recharge roll, "save ends"
   prompt, ongoing damage, durations.
3. Action: pick the button → pick targets (click tokens, or place an area template) → the roll
   card shows the results per target with **Apply** buttons. Damage already accounts for
   resistances, crits and half-on-save.
   - Per table setting, the DM can auto-apply for creatures and keep players' own results on
     Assist.
4. Concentration: if a concentrating character takes damage, a CON save prompt appears for its
   owner.
5. End turn → the next one. Expired effects are listed in the log.

**Never blocking:** everything can be done "out of order" (the DM moves anything, players act
out of turn if the DM allows). Warnings are colours and small notes, not dialogs. Every applied
change has undo in the roll card and the log.

**Reactions** (Shield, Counterspell, opportunity attacks): **no automatic interrupts** by
default; they stall play. Optional later: a small non-blocking hint for the owning player ("You
could use Shield"), off by default.

## 7. Implementation plan

Order: first make what exists consistent, then the core combat loop, then the data that unlocks
the rest. Each phase is playable on its own.

**Phase 0: clean up (small, prerequisite)**
- One slot/resource scheme (`resource.used/restored`).
- Levels from `classes[]` only.
- Inventory via `item.gained/lost`.
- Update the outdated docs: CLAUDE.md markdown wording, doc-1 refs, data-layout campaign paths.

**Phase 1: core combat loop** ← biggest win for flow
- `Rules` module (derived stats) and the `dragoon-core` package (conditions, tables).
- Targets on attacks, hit vs AC, crits, damage types with resistance, roll cards with Apply.
- Use `feature.save`: save-based actions with DC, half on save, bulk saves for creatures.
- Conditions UI (token icons, sheet, apply/remove, immunity warning).
- 0 HP → unconscious and death saves.
- Initiative rolling (with manual entry), concentration.

**Phase 2: turns, durations, resources**
- Action economy pips, movement budget display.
- Start/end of turn triggers: recharge, save-ends, ongoing damage, legendary action counters.
- Effect durations by round/turn, auto-expiry with log.
- Feature uses (`uses` text → `{max, reset}`), short/long rest dialogs (hit dice), slots spent on
  cast (finishes TASK-49).

**Phase 3: structured spells and areas**
- The effects format and the regex parser for spells and features; AI pass for the rest as
  drafts.
- Area templates (sphere, cone, line, cube, cylinder) with target selection, plus a ruler.
- Upcasting and cantrip scaling.

**Phase 4: class features and characters**
- Split class/subclass features with levels, class resources.
- Weapon attacks and AC from inventory, attunement.
- Level up assistant, XP/milestones.

**Phase 5: optional and later**
- Encounter difficulty while prepping.
- Opportunity-attack and reaction hints, lair action reminders.
- Vision/light/fog of war, difficult terrain painting.
- Summons and wild shape sheet swap.
- MCP assistants use the same `Rules` module and events.

**Table settings** (one small page, Phase 1): per category Off / Assist / Auto, for damage,
conditions, durations, resources, concentration, death saves, movement warnings and reaction
hints. Default: Assist everywhere, Auto for pure counters (slots, uses, durations display).

## 8. Decisions (Nico, 2026-11-02)

1. **Results apply right away**, for players too. The DM corrects by undo or by jumping back on
   the timeline (rewind is planned anyway). So the default for damage, conditions etc. is
   **Auto**, not Assist.
2. **No physical dice.** Everyone rolls digitally and loves **3D dice rolling across the screen**,
   which gets its own ticket. Manual entry ("I rolled: __") only sits in a small menu.
3. **Initiative per creature** by default. When building an encounter, the DM can **group**
   creatures so a group shares one roll.
4. **House rule: critical hits = maximum damage dice + a normal roll** (e.g. 2d6 crit = 12 + 2d6),
   plus modifiers once. No flanking, cover only as a manual toggle.
5. **2014 and 2024 rules both possible.** The edition is a world setting (exhaustion, conditions,
   weapon masteries, surprise ...), and entries keep their own edition (the source book).
6. **Phases 2 and 3 run in parallel** after Phase 1.
