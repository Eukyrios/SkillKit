--!strict
-- SkillKit: a runtime for node-based skills (hitboxes, motion, animation, sound, VFX, tags, states). No builder UI:
-- skills are data (Luau tables, or SK1: codes) and SkillKit runs them. The game plugs in through an adapter.
--
-- Server:  SkillKit.init(adapter?)                       start the runtime (once)
--          SkillKit.defineCharacter(def)                 register a CharacterDef { id, name, stats?, slots = { [slot] = Skill } }
--          SkillKit.cast(user, skillOrRef, opts?) -> Cast?  run a skill (user = character Model; opts.player for a player)
--          SkillKit.cancel(user, reason?)                cancel the user's running casts
--          SkillKit.applyStats(character, stats)         scale, walk speed, jump, hip height, camera offset, health
--          SkillKit.preview(skill, { player, on = "player" | "dummy" })   run a skill against a fresh target dummy
--          SkillKit.playEffect(name, cframe)             play a registered Effect group anywhere
--          SkillKit.debug.dump(userOrPlayer)             the debug log, newest last
-- Client:  SkillKit.initClient()                         presentation (animations, keyframes, VFX, sound, own motion)
-- Shared:  SkillKit.Curves, .Registry, .Schema, .Codec, .DebugLog
local RunService = game:GetService("RunService")

local SkillKit = {}
SkillKit.Version = "0.1.0"
SkillKit.Curves = require(script.Curves)
SkillKit.Registry = require(script.Registry)
SkillKit.Schema = require(script.Schema)
SkillKit.Codec = require(script.Codec)
SkillKit.DebugLog = require(script.DebugLog)

if RunService:IsServer() then
	local Server = require(script.Server) :: any
	SkillKit.init = Server.init
	SkillKit.isReady = Server.isReady
	SkillKit.defineCharacter = Server.defineCharacter
	SkillKit.getSkill = Server.getSkill
	SkillKit.cast = Server.cast
	SkillKit.cancel = Server.cancel
	SkillKit.applyStats = Server.applyStats
	SkillKit.preview = Server.preview
	SkillKit.spawnDummy = Server.spawnDummy
	SkillKit.playEffect = Server.playEffect
	SkillKit.Tags = Server.Tags
	SkillKit.States = Server.States
	SkillKit.debug = Server.debug
	SkillKit.dev = require(script.Dev) :: any
else
	local Client = require(script.Client) :: any
	SkillKit.initClient = Client.init
	SkillKit.Keyframes = Client.Keyframes
end

return SkillKit
