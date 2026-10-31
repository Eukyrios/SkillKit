# SkillKit

A Roblox add-on that **runs** node-based skills: hitboxes, projectiles, grabs, debris, velocity, travel, teleport,
Roblox and keyframe animations, sounds, preset VFX, particles, mesh visuals, highlights, tags and states.

Skills are data (Luau tables or `SK1:` codes) and SkillKit executes them; the game plugs in through a small adapter.
A Studio plugin adds a full skill editor (node list, branches, timeline, live preview on dummies, characters and
slots, branch flow view, JJS code import). Build mode (placing blocks, lights, bounce pads) is deliberately left out.

## Install

- **Rojo mount**: clone this repo into your game folder and add to the game's `default.project.json`, under ReplicatedStorage:
  `"SkillKit": { "$path": "SkillKit/src" }`
- **Wally**: `skillkit = "eukyrios/skillkit@0.1.0"` once published (`wally.toml` is in this folder).

## Start it

```lua
-- server
local SkillKit = require(ReplicatedStorage.SkillKit)
SkillKit.init({ canHit = ..., applyHit = ..., push = ..., isStunned = ..., candidates = ..., limits = {...} })
SkillKit.cast(character, skill, { player = player })

-- client
require(ReplicatedStorage.SkillKit).initClient()
```

Everything in the adapter is optional. The defaults hurt any other living Humanoid and use SkillKit's own stun.

## A skill

```lua
local V = Vector3.new
local skill = {
	name = "Rising Cut",
	cooldown = 4,
	branches = {
		Default = {
			{ type = "Keyframes", anim = "slash_right" },
			{ type = "Wait", time = 0.12 },
			{ type = "Hitbox", size = V(6, 6, 8), position = V(0, 0, 4), damage = 10, stun = 0.5,
				knockback = V(0, 20, 10), victimBranch = "Launch", mode = "Continue" },
			{ type = "Wait", time = 0.3 },
		},
		Launch = {
			{ type = "Travel", target = "lastHit", time = 0.25, stopDistance = 3, arc = 6 },
			{ type = "PresetVFX", preset = "impact", subject = "lastHit", color = "#ffd27a" },
		},
	},
}
```

Nodes in a branch start in order; only `Wait` advances time. Directions and offsets are `Vector3(right, up, forward)`.
Every node's props and defaults are listed in `src/Schema.luau`.

| Category | Nodes |
| --- | --- |
| Flow | Wait, Branch (Switch / Continue), Loop, Group, Tags, State |
| Combat | Hitbox, Projectile, Grab, Debris |
| Motion | Velocity, Travel, Teleport |
| Animation / Audio | Animation (asset), Keyframes (no upload), Sound |
| Visual | PresetVFX, Particle, MeshVisual, Highlight |

**Preset VFX**: shake, flash, vignette, blur, tint, fov, highlight, glow, afterimage, beam, impact, ring, wind, burst.

**Built-in keyframe animations**: slash_right, slash_left, punch, dash, back_dash, block, stagger, blast.

## Modules

| Path | Side | Job |
| --- | --- | --- |
| `init` | both | public API |
| `Schema` | shared | node types, defaults, validation |
| `Curves` | shared | easing presets + custom point curves (`ease`, `mult`, `sequence`) |
| `Registry` | shared | the asset library (names → ids, keyframes, effects) |
| `Codec` | shared | `SK1:` skill codes (JSON → LZW → base64) |
| `Motion` | shared | velocity / travel / push solver (server for NPCs, client for your own character) |
| `Rig` | shared | joints for R15 and R6, parts, alive checks |
| `DebugLog` | shared | per-caster event log with likely-cause hints |
| `Server/*` | server | Executor, Nodes, Hitbox, Projectile, Debris, StateStore, TagStore |
| `Client/*` | client | Fx, KeyframePlayer, message handlers |
| `Dev/*` | server | one test skill per node type, `runAll`, `selfTest` |

## Testing

During a Studio playtest, from the server command bar:

```lua
local SK = require(game.ReplicatedStorage.SkillKit)
print(table.concat(SK.dev.selfTest(), "\n"))
print(SK.dev.report(SK.dev.runAll(game.Players:GetPlayers()[1])))
SK.debug.dump(game.Players:GetPlayers()[1])
```

Parts tagged `SkillKitBreakable` (CollectionService) can be broken by Debris nodes.

## Studio plugin

`python plugin/build_plugin.py` builds `plugin/build/SkillKit.rbxmx`, a local Studio plugin that carries this add-on and
the editor. Install it from Studio's **Plugins** tab: **Plugins Folder**, copy the file there, restart Studio. It adds
two toolbar buttons:

**Skill Editor**: an overlay on the 3D view.

- **Top bar**: File (new, open, open the Explorer selection, Code: Luau / `SK1:` / import, Import JJS code), Save,
  Undo / Redo, Play (Space) and speed, Dummies (bring here, look at, reset, clear effects), Flow, View (panels).
  The right side shows the last message; click it for the log.
- **Node panel**: branch picker (+, rename, delete), Add by category, Wait / Branch / Loop, multi-select, copy, paste,
  move, group. Cards open to typed fields: vectors, colours, curve graphs, dropdowns, asset pickers; drag a number's
  label to change it; hover a card for Duplicate / Delete. **Tree** switches the panel to a tree of the skill's
  branches and nodes, characters and their slots (M1, Skill1-4, Block, Dash, Awakening, Passive, Custom), skills that
  aren't in a character, and the game's own move sets (any `Moves` folder in ReplicatedStorage, read-only).
- **Timeline** of the open branch (click a bar to jump to its card) and a **Flow** view of how branches link.
- **Preview** runs in Edit mode on two dummies placed in front of the camera: hits, knockback, ragdoll, tags,
  branches, keyframe and Roblox animations, sounds and VFX.
- **Save** writes `ReplicatedStorage.SkillKitSkills/<name>`; characters go to `ReplicatedStorage.SkillKitCharacters`
  and can be passed to `SkillKit.defineCharacter(require(module))`.
- **Import JJS code**: paste a Jujutsu Shenanigans character code (base64 of zstd JSON, the format documented by
  the open-source libjjs encoder). Each move becomes a skill; timings, hitboxes, velocities, branches, tags, states
  and loops carry over. JJS's own animations, effects and built-in moves can't be used in another game, so they are
  swapped for the closest built-in ones and every swap is listed in the log.

**SkillKit panel**: install / update SkillKit in the open place, add / remove the test runner (Play runs every node
type against a dummy; chat `/sk all`, `/sk <Test>`, `/sk log`), drop a breakable test wall, tag the selection
`SkillKitBreakable`.

For a place with no game code, `rojo serve test.project.json` serves SkillKit and the test runner together.

## Not included

- Build mode (placing blocks, lights, bounce pads).
- JJS move conditions (in air, holding the key, ...) and JJS-only nodes (built-in JJS moves, counters, hit cancel,
  awakening / health gain): the importer lists them in the log instead.
