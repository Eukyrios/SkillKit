--!strict
-- The asset library, as code: nodes name assets ("impact_ring") instead of hard-coding ids, so changing an asset in
-- one place updates every skill. Kinds: animation, keyframes, sound, image, texture, mesh, effect.
--   Registry.register(kind, name, entry)      entry fields per kind:
--     animation  { id = number | "rbxassetid://..", r6 = number? }
--     keyframes  keyframe animation data (see Client/KeyframePlayer)
--     sound      { id, volume?, pitch? }
--     image      { id, use? }
--     texture    { id, flipbook = { rows, cols, fps }? }          particle / beam textures
--     mesh       { meshId, textureId?, scale = Vector3? }
--     effect     { nodes = { Node, ... } }                       a saved Group (SkillKit.playEffect)
--   Registry.get(kind, name) -> entry?
--   Registry.id(kind, nameOrId) -> "rbxassetid://..." | "rbxasset://.." | nil (raw ids and paths pass through)
--   Registry.load(module)                     a ModuleScript (or table) of { kind = { name = entry } }
local Registry = {}

local store: { [string]: { [string]: any } } = {
	animation = {},
	keyframes = {},
	sound = {},
	image = {},
	texture = {},
	mesh = {},
	effect = {},
}

function Registry.register(kind: string, name: string, entry: any)
	local bucket = store[kind]
	assert(bucket, "unknown registry kind " .. tostring(kind))
	bucket[name] = entry
end

function Registry.get(kind: string, name: any): any
	local bucket = store[kind]
	return bucket and type(name) == "string" and bucket[name] or nil
end

function Registry.list(kind: string): { string }
	local out = {}
	for k in pairs(store[kind] or {}) do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

local function asContent(v: any): string?
	if type(v) == "number" then
		return "rbxassetid://" .. v
	elseif type(v) == "string" then
		if string.match(v, "^rbxasset") or string.match(v, "^https?://") then
			return v
		end
		local n = tonumber(v)
		if n then
			return "rbxassetid://" .. n
		end
	end
	return nil
end

function Registry.id(kind: string, nameOrId: any, field: string?): string?
	if nameOrId == nil or nameOrId == "" then
		return nil
	end
	local entry = Registry.get(kind, nameOrId)
	if entry then
		return asContent(entry[field or "id"] or entry.meshId)
	end
	return asContent(nameOrId)
end

function Registry.load(source: any)
	local t = source
	if typeof(source) == "Instance" then
		t = require(source :: ModuleScript)
	end
	for kind, entries in pairs(t) do
		if store[kind] then
			for name, entry in pairs(entries) do
				store[kind][name] = entry
			end
		end
	end
end

-- built-in presets: keyframe animations that need no upload
local Keyframes = require(script.Parent.Presets.Keyframes)
for name, anim in pairs(Keyframes) do
	store.keyframes[name] = anim
end
-- a few engine sounds that always exist
store.sound.swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.6 }
store.sound.lunge = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.6 }
store.sound.impact = { id = "rbxasset://sounds/hit.wav", volume = 0.7 }
store.sound.boom = { id = "rbxasset://sounds/collide.wav", volume = 0.8 }
store.texture.sparkle = { id = "rbxasset://textures/particles/sparkles_main.dds" }
store.texture.smoke = { id = "rbxasset://textures/particles/smoke_main.dds" }
store.texture.fire = { id = "rbxasset://textures/particles/fire_main.dds" }

return Registry
