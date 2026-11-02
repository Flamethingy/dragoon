---
id: doc-2
title: Table wishlist (player feedback)
type: other
tags:
  - feedback
  - requirements
  - wishlist
project: Dragoon
created_date: '2026-11-02 14:36'
updated_date: '2026-11-02 14:36'
---

# Table wishlist (player feedback)

Feedback from a friend in Nico's group (2026-11-02): what they want from the tabletop. **Keep this in mind for every Dragoon feature.** The status column is a first guess from the backlog on 2026-11-02 (✅ built, 🟡 partly, ⬜ open, 🏠 house rule to define), so check the code before you rely on it.

House rules this list reveals: **Soak** (armour reduces damage, separate from AC), **1 turn = 10 seconds** (not 6), **magical vs. physical damage** matters for resistances (not for soak), and the homebrew class **Dragoon** (S2, own spell slot recovery).

## Maps

| Wish | Status |
|---|---|
| Multiple layers: one for players, one for the GM, layers for different map versions | ⬜ |
| Distance between objects (Euclidean) | 🟡 ruler (TASK-67) |
| AoE templates (cone, sphere, cube ...) that delete themselves when their uptime ends (bound to concentration or duration) | 🟡 templates TASK-67, durations TASK-63, concentration TASK-59: check the link |
| No grid, free movement (optional) | ⬜ |
| Map markers with visibility tiers: player / GM, discovered / undiscovered | ⬜ (reveal system could carry it) |
| Categories and sub-categories to sort maps | ⬜ |
| YouTube music player (like w2g, but better) | ⬜ |
| Free movement mode and turn-based mode (exploration vs. combat) | 🟡 initiative TASK-58, pips TASK-62 |
| Elevation tracking (flying) | ⬜ |
| Dragging a token shows the distance live | 🟡 movement budget TASK-62 |

## PC / characters

| Wish | Status |
|---|---|
| Character sheet: class, ability scores, skills, saves, HP, temp HP, AC, **Soak**, movement, vision types and range, level, proficiencies (weapons, armour, tools, languages), expertise, Jack of all Trades, immunities, resistances, vulnerabilities | 🟡 sheet exists; soak 🏠, vision partly TASK-73 |
| Custom extra resources (Sorcery Points, Mystic Arcanum ...) | ✅ resources TASK-51/64 |
| Inventory like Foundry, **not sorted by category** | 🟡 check the layout |
| Armour applies its soak automatically | 🏠 ⬜ |
| Shields add their AC automatically | ✅ AC from gear TASK-70 |
| Magic items with charges and their own recharge rule | ✅ dawn charges TASK-64 |
| Spell list: clerics, druids and paladins get their spells added automatically once they have the level / slots | 🟡 TASK-69/71: check |
| Spell slot recovery per class (Warlock, **Dragoon S2**) | 🟡 rests TASK-64, Dragoon 🏠 |
| Manual spell slot recovery | ✅ resource.restored |
| Abilities from species, class and other sources (feats, ASI ...) | ✅ TASK-69 |
| Character bio: backstory, age, species, height, weight, colouring | 🟡 fields to add |
| Long and short rest buttons | ✅ TASK-64 |
| Consume food and water: one click = one day, or ask how many days | ⬜ |
| Quickbar for the linked character | 🟡 HUD widgets |
| Hover over a token: quick overview (HP, AC, movement, buffs, debuffs ...) | ⬜ |
| While polymorphed / Wild Shape, physical stats are replaced when rolling | ✅ TASK-74 |

## Library

| Wish | Status |
|---|---|
| Notes for cities, NPCs, relations ... | ✅ compendium / world entries, notes |
| Quest log: players write down the jobs (main quest) | ⬜ |
| Personal goals per player (e.g. "Elisabeth wants to marry Elirenne") | ⬜ |

## GM / NPC

(nothing yet)

## General / rules

| Wish | Status |
|---|---|
| Feet → metres automatically | ✅ importer |
| Minutes / hours → turns (**1 turn = 10 s** in our system) | 🏠 ⬜ durations TASK-63 use 6 s? check |
| Spells and abilities offer a button for the save or skill check | ✅ TASK-55 |
| On a roll, apply damage by success / failure / crit, with resistances and soak | 🟡 TASK-54/55, soak 🏠 |
| Attack rolls can ask for a target and compare with its AC | ✅ TASK-54 |
| With a target: roll and apply damage with resistances, soak and other modifiers | 🟡 soak 🏠 |
| **Important:** magical vs. physical damage for resistances (not soak) | ⬜ check the damage types |
| Without a target, damage is rolled on its own | ✅ |
