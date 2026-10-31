# JJS import coverage

How much of a Jujutsu Shenanigans (JJS) character code the SkillKit importer understands. The JJS format is not
published by JJS; the reference used here is the open-source encoder **libjjs** (github.com/FormunaGit/libjjs,
v2.0.0: every node, field default, condition, property, state, effect and enum it knows), plus fields seen in real
codes that are newer than libjjs (the `PARTICLE` node, `LINK USER`, `STATE TAG`, the Ragdoll / Wakeup / Cancel states).

## Summary

| | Mapped | Share |
| --- | --- | --- |
| Node types | 19 of 23 | **83%** (19 of 21 that are possible: **90%**) |
| Node fields | 104 of 179 | **58%** (62% without the impossible nodes) |
| Conditions | 8 of 9 | **89%** |
| Move kinds | 5 of 5 | **100%** |
| Move properties | 4 of 13 | **31%** |
| States | 10 of 12 | **83%** |
| Visual effects | 45 of 47 (approximated) | **96%** |

"Mapped" means the importer turns it into SkillKit nodes that do the same job. "Approximated" means the job is the
same but the look is SkillKit's (animations, effects). Everything that isn't mapped is listed in the editor's log on
import, grouped by message.

## Nodes

| JJS node | SkillKit | Status | Fields used | Notes |
| --- | --- | --- | --- | --- |
| `WAIT` | Wait | ✅ mapped | 1/1 (100%) |  |
| `ANIM` | Keyframes | 🟡 approximated | 4/7 (57%) | JJS animations are swapped for the closest built-in one; preview window and fades ignored |
| `SFX` | Sound | 🟡 partly | 3/10 (30%) | id, volume, speed; start/end, fades, global, projectile tag, cancel ignored. JJS's own sound ids may not load in other games |
| `VELO` | Velocity | ✅ mapped | 7/8 (88%) | relative-from-branch ignored |
| `HITBOX` | Hitbox (+ Debris) | ✅ mapped | 15/21 (71%) | stun animation, attack type, cancel enemy, clear knockback, projectile tag, ignore wakeup ignored |
| `BRANCH` | Branch / Check | ✅ mapped | 2/3 (67%) | random: the first option is used |
| `VISUAL` | PresetVFX / MeshVisual | 🟡 approximated | 15/24 (62%) | 45 of 47 effects swapped for the closest preset; texture, body part, tags, amount, server/collide ignored |
| `GRAB` | Grab | 🟡 partly | 2/6 (33%) | limbs ignored |
| `PROJECTILE` | Projectile | 🟡 partly | 14/28 (50%) | speed scale is a guess (x60); reflect, filter interval, cache, wakeup ignored |
| `COUNTER` | Counter | ✅ mapped | 5/7 (71%) | attack-type filter and cancel-enemy ignored |
| `TAG` | Tags | ✅ mapped | 8/8 (100%) |  |
| `STATE` | State / Velocity | 🟡 partly | 4/8 (50%) | 10 of 12 states (+ Ragdoll, self Cancel); state checks and burst/cancel-on-end ignored |
| `TELEPORT` | Teleport | 🟡 partly | 3/5 (60%) | projectile tag, relative-from-branch ignored |
| `HPGIB` | Heal | ✅ mapped | 1/1 (100%) |  |
| `ULTGIB` | Meter (awakening) | ✅ mapped | 1/1 (100%) | the game decides what the meter does |
| `EVGIB` | Meter (evasion) | ✅ mapped | 1/1 (100%) | the game decides what the meter does |
| `HITCNCL` | Hitbox miss branch | 🟡 partly | 2/4 (50%) | time and end lag ignored |
| `LOOP` | Loop | ✅ mapped | 3/3 (100%) | 'while held' becomes a fixed count |
| `PARTICLE` | Particle | 🟡 partly | 13/18 (72%) | shape, part size, rotation, flipbook mode ignored (node seen in real codes, newer than libjjs) |
| `SETCD` | - | ❌ not yet | 0/2 (0%) | set another skill's cooldown: not in SkillKit yet |
| `CONNECT` | - | ❌ not yet | 0/3 (0%) | signals between moves: not in SkillKit yet |
| `SKILL` | - | ⛔ can't | 0/6 (0%) | plays one of JJS's 170 built-in moves (JJS's own code) |
| `SPECIAL` | - | ⛔ can't | 0/4 (0%) | plays one of JJS's 28 built-in specials (JJS's own code) |

## Everything else

| What | Mapped | Share | Notes |
| --- | --- | --- | --- |
| Move kinds (SKILL, SPECIAL, MELEE, CHASE, AWAKENING) | 5/5 | 100% | MELEE moves are merged into one M1 combo; each kind goes to a character slot |
| Conditions (AIR, JUMP, AIM, HOLD, HP, ULT, BAR, DOMAIN, DUR) | 8/9 | 89% | Check node; DUR (move durability) is missing. ULT / BAR / DOMAIN read game meters |
| Move properties (DMG, KNOCK, INV, NOCANCEL, REP, REP2, AWK, AWK2, KEEP, USE, USEONDEATH, NOSTUN, VAR) | 4/13 | 31% | damage / knockback multipliers, invincible, no-cancel; the rest are JJS moveset-menu settings |
| States (libjjs list of 12) | 10/12 | 83% | Block and Scale missing; NoDash / DisableChase become a movement lock |
| Visual effects (47) | 45/47 | 96% | all approximated with SkillKit presets or meshes; Visibility missing, Cancel not needed |
| Easing styles (6) and directions (3) | 9/9 | 100% | used for mesh visuals |
| Attack types (Melee, Bullet, Explosion, Swarm, Domain) | 0/5 | 0% | SkillKit treats every hit the same |
| Body parts (VISUAL / GRAB limbs) | 0/7 | 0% | effects attach to the root |
| JJS animations (character x animation table) | 0/- | approx. | approximated: swapped for one of 8 built-in keyframe animations |
| JJS built-in moves (170) and specials (28) | 0/198 | 0% | JJS's own code: can't be imported |

## Can't be imported

- **JJS's built-in moves and specials** (`SKILL`, `SPECIAL` nodes): they run JJS's own code.
- **JJS's own animations, sounds and effects**: they are JJS's uploads; Roblox won't play another creator's animations
  in your game. The importer swaps them for SkillKit's built-ins and lists every swap.

## Next candidates

`SETCD` (set a cooldown), `CONNECT` (signals between moves), the `DUR` condition, attack types (for counters), body
parts for effects and grabs, the remaining hitbox fields (attack type, cancel enemy, clear knockback), the `Block` and
`Scale` states, and the moveset-menu properties.
