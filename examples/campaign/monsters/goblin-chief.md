---
# Example campaign entity for the TASK-3 spike. The fields follow the concept's example;
# the real schema comes from TASK-1. Paths are relative to the campaign folder.
type: monster
name: Goblin Chief
source: "core:monsters/goblin-boss"   # where this campaign copy came from
hp: 21
ac: 15
speed: { walk: 9 }
stats: { str: 12, dex: 14, con: 12, int: 10, wis: 8, cha: 10 }
token: tokens/goblin-chief.png
size: medium
faction: "[[Red Fang Clan]]"
tags: [goblinoid, leader]
actions:
  - name: Scimitar
    text: "Melee Weapon Attack: +4 to hit, reach 1.5 m, one target. Hit: 5 (1d6 + 2) slashing damage."
  - name: Redirect Attack
    text: >
      When a creature the chief can see targets it with an attack,
      the chief chooses another goblin within 1.5 m.
dm_notes: |
  Knows where the stolen caravan went.
  Will trade that for his life.
---
# Goblin Chief

Leader of the [[Red Fang Clan]] war band on the forest road. Wears a wolf pelt and a
dented crown he claims to have taken from a knight.
