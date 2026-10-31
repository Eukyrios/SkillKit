--!strict
-- What the editor knows about each node type: its category (colour + Add menu group), a one-letter badge, a short
-- description, and its fields in display order with the kind of editor each one gets.
-- Kinds: number, bool, text, enum (opts), vector, color, curve, branch, asset (registry kind), preset, range,
-- multi (opts), homing, nodes, cframe
local Meta = {}

Meta.Categories = {
	{ name = "Combat", color = Color3.fromRGB(226, 86, 86), types = { "Hitbox", "Projectile", "Grab", "Debris", "Counter" } },
	{ name = "Animation", color = Color3.fromRGB(160, 110, 240), types = { "Keyframes", "Animation" } },
	{ name = "Audio", color = Color3.fromRGB(236, 190, 70), types = { "Sound" } },
	{ name = "Motion", color = Color3.fromRGB(80, 160, 250), types = { "Velocity", "Travel", "Teleport" } },
	{ name = "Visual", color = Color3.fromRGB(236, 110, 180), types = { "PresetVFX", "Particle", "MeshVisual", "Highlight" } },
	{ name = "Logic", color = Color3.fromRGB(90, 200, 160), types = { "Check", "Tags", "State", "Heal", "Meter", "Group" } },
}
Meta.FlowColor = Color3.fromRGB(150, 156, 170)

Meta.Badge = {
	Wait = "W", Branch = "B", Loop = "L", Group = "G", Tags = "#", State = "S", Check = "If", Counter = "Ct", Heal = "+", Meter = "Me",
	Hitbox = "H", Projectile = "P", Grab = "Gr", Debris = "D",
	Velocity = "V", Travel = "T", Teleport = "Tp",
	Animation = "A", Keyframes = "K", Sound = "♪",
	PresetVFX = "Fx", Particle = "Pa", MeshVisual = "M", Highlight = "Hl",
}

Meta.Describe = {
	Wait = "pauses this branch",
	Branch = "runs another branch (Switch leaves this one, Continue runs both)",
	Loop = "repeats its inner nodes",
	Group = "a bundle of nodes run together",
	Tags = "number tags: add / subtract / set / check",
	Check = "runs a branch if every condition passes: in air, jumping, holding the key, aiming at someone, health, a meter",
	Counter = "for a moment, a hit on you is cancelled: the attacker is stunned and the counter branch runs",
	Heal = "gives health back (an amount, or % of max health)",
	Meter = "adds to / sets a game meter (awakening, evasion, ...): your game decides what it means",
	State = "stun, multipliers, locks, ragdoll, body freeze",
	Hitbox = "damages what's inside a box, sphere or cylinder",
	Projectile = "a flying hitbox: speed curve, gravity, homing",
	Grab = "holds a target in front of you",
	Debris = "breaks parts tagged SkillKitBreakable",
	Velocity = "pushes the user or the target",
	Travel = "moves to the target in a set time",
	Teleport = "instantly moves someone",
	Animation = "a Roblox animation asset",
	Keyframes = "a SkillKit keyframe animation (no upload)",
	Sound = "plays a sound",
	PresetVFX = "screen / body / beam / hit / wind effects",
	Particle = "a particle emitter",
	MeshVisual = "a mesh that tweens to its alt values",
	Highlight = "a highlight on the target or a visual tag",
}

local SUBJECT = { "user", "lastHit", "target" }
local MODE = { "Continue", "Switch" }

local function f(key: string, kind: string, opts: any?, label: string?)
	return { key = key, kind = kind, opts = opts, label = label }
end

Meta.Fields = {
	Wait = { f("time", "number") },
	Branch = { f("target", "branch"), f("mode", "enum", { "Switch", "Continue" }) },
	Loop = { f("count", "number", nil, "count (0 = forever)"), f("interval", "number"), f("blocking", "bool", nil, "wait for it"), f("nodes", "nodes") },
	Group = { f("groupId", "text", nil, "saved effect id"), f("nodes", "nodes") },
	Check = {
		f("subject", "enum", SUBJECT), f("conds", "conds", nil, "conditions (all must pass)"),
		f("passBranch", "branch"), f("failBranch", "branch"), f("stopOnFail", "bool", nil, "stop if it fails"), f("mode", "enum", MODE),
	},
	Counter = {
		f("subject", "enum", SUBJECT), f("time", "number", nil, "window (s)"), f("stun", "number", nil, "stun the attacker (s)"),
		f("counterBranch", "branch"), f("removeOnHit", "bool", nil, "only the first hit"), f("mode", "enum", MODE),
	},
	Heal = { f("subject", "enum", SUBJECT), f("amount", "number"), f("percent", "bool", nil, "amount is % of max") },
	Meter = { f("subject", "enum", SUBJECT), f("meter", "text", nil, "meter name"), f("op", "enum", { "Add", "Subtract", "Set" }), f("value", "number") },
	Tags = {
		f("subject", "enum", SUBJECT), f("tag", "text"), f("op", "enum", { "Add", "Subtract", "Set", "Check" }), f("value", "number"),
		f("time", "number", nil, "expires after"), f("keep", "bool", nil, "keep after death"),
		f("compare", "enum", { ">=", ">", "==", "~=", "<", "<=" }), f("passBranch", "branch"), f("failBranch", "branch"), f("mode", "enum", MODE),
	},
	State = {
		f("subject", "enum", SUBJECT), f("category", "enum", { "Disable", "Multiplier", "Lock", "Ragdoll", "Body" }),
		f("sub", "multi", { "Movement", "Jump", "Skill", "Sprint", "Regeneration", "Collision", "PlayerCollision", "Speed", "Damage", "DamageTaken", "Cooldown", "Direction", "Camera" }),
		f("value", "number"), f("duration", "number"), f("stateTag", "text"), f("op", "enum", { "Add", "Subtract", "Remove" }),
	},
	Hitbox = {
		f("time", "number", nil, "time (0 = one tick)"), f("position", "vector"), f("rotation", "vector"), f("size", "vector"),
		f("shape", "enum", { "Box", "Sphere", "Cylinder" }), f("attach", "enum", { "HRP", "Torso", "Head" }),
		f("damage", "number"), f("stun", "number"), f("knockback", "vector"), f("radial", "bool"),
		f("singleTarget", "bool"), f("rehit", "number", nil, "rehit every (s)"), f("visible", "bool"),
		f("blockable", "bool"), f("block360", "bool"), f("blockCancel", "bool"), f("canKill", "bool"),
		f("canRagdoll", "bool"), f("ragdollTime", "number"), f("canCancelRagdoll", "bool"),
		f("hitRagdoll", "bool"), f("hitUser", "bool"), f("hitOnlyUser", "bool"),
		f("victimBranch", "branch"), f("finisherBranch", "branch"), f("missBranch", "branch"), f("mode", "enum", MODE),
	},
	Projectile = {
		f("shape", "enum", { "Ball", "Block" }), f("size", "number"), f("color", "color"), f("material", "enum", { "Neon", "SmoothPlastic", "ForceField", "Glass" }),
		f("position", "vector"), f("direction", "enum", { "look", "toTarget", "up" }), f("speed", "number"), f("speedCurve", "curve"),
		f("gravity", "number"), f("lifetime", "number"), f("range", "number"), f("stick", "number"), f("pierce", "bool"),
		f("homing", "homing"), f("projectileTag", "text"), f("radius", "number", nil, "hit radius"),
		f("damage", "number"), f("stun", "number"), f("knockback", "vector"), f("blockable", "bool"), f("canKill", "bool"),
		f("hitBranch", "branch"), f("expireBranch", "branch"), f("mode", "enum", MODE),
	},
	Grab = {
		f("position", "vector"), f("size", "vector"), f("duration", "number"), f("holdOffset", "vector"),
		f("victimAnimation", "asset", "keyframes"), f("releaseKnockback", "vector"), f("damage", "number"),
		f("grabBranch", "branch"), f("missBranch", "branch"), f("mode", "enum", MODE),
	},
	Debris = {
		f("type", "enum", { "SinglePoint", "Radial", "Line" }), f("position", "vector"), f("size", "vector"), f("visible", "bool"),
		f("count", "number"), f("force", "number"), f("canCollide", "bool"), f("lifetime", "number"),
		f("settleAfter", "number"), f("rebuildAfter", "number"),
	},
	Velocity = {
		f("subject", "enum", { "user", "lastHit" }), f("direction", "vector"), f("speed", "number"), f("space", "enum", { "Local", "World" }),
		f("time", "number"), f("fade", "curve"), f("holdHeight", "bool"), f("track", "bool"), f("ragdoll", "bool"),
	},
	Travel = {
		f("subject", "enum", { "user", "lastHit" }), f("target", "enum", { "lastHit", "look" }), f("time", "number"),
		f("stopDistance", "number"), f("height", "number"), f("arc", "number"), f("curve", "curve"),
		f("follow", "bool"), f("wallStop", "bool"), f("collision", "bool"), f("range", "number"),
		f("arriveBranch", "branch"), f("mode", "enum", MODE),
	},
	Teleport = {
		f("who", "enum", { "user", "lastHit" }), f("to", "enum", { "lastHit", "user", "global" }), f("offset", "vector"),
		f("rotation", "vector"), f("facing", "enum", { "keep", "target" }), f("keepVelocity", "bool"),
	},
	Animation = {
		f("anim", "asset", "animation", "animation id"), f("speed", "number"), f("fadeIn", "number"), f("fadeOut", "number"),
		f("weight", "number"), f("looped", "bool"), f("stopAfter", "number"),
		f("priority", "enum", { "Action", "Action2", "Action3", "Action4", "Movement", "Idle", "Core" }), f("subject", "enum", SUBJECT),
	},
	Keyframes = { f("anim", "asset", "keyframes", "animation"), f("speed", "number"), f("weight", "number"), f("looped", "bool"), f("mirror", "bool"), f("subject", "enum", SUBJECT) },
	Sound = {
		f("sound", "asset", "sound", "sound id"), f("volume", "number"), f("pitch", "number"), f("speed", "number"),
		f("subject", "enum", SUBJECT), f("looped", "bool"), f("stopAfter", "number"), f("rollOff", "range", nil, "roll-off min / max"),
	},
	PresetVFX = {
		f("preset", "preset"), f("subject", "enum", SUBJECT), f("position", "vector"), f("duration", "number"),
		f("color", "color"), f("color2", "color", nil, "second colour"), f("size", "number"), f("applyTo", "text", nil, "apply to visual tag"),
	},
	Particle = {
		f("subject", "enum", SUBJECT), f("position", "vector"), f("texture", "asset", "texture"), f("color", "color"),
		f("emitCount", "number"), f("enabled", "bool", nil, "keep emitting"), f("duration", "number"),
		f("lifetime", "range"), f("speed", "range"), f("spread", "number"), f("size", "number"),
		f("sizeCurve", "curve"), f("transparencyCurve", "curve"), f("lightEmission", "number"),
		f("rotSpeed", "range"), f("acceleration", "vector"), f("drag", "number"),
	},
	MeshVisual = {
		f("mesh", "asset", "mesh", "mesh (Sphere, Block, Cylinder or id)"), f("material", "enum", { "Neon", "SmoothPlastic", "ForceField", "Glass", "Metal" }),
		f("subject", "enum", SUBJECT), f("attach", "bool", nil, "follow the subject"),
		f("position", "vector"), f("altPosition", "vector", nil, "→ position"), f("rotation", "vector"), f("altRotation", "vector", nil, "→ rotation"),
		f("size", "vector"), f("altSize", "vector", nil, "→ size"), f("color", "color"), f("altColor", "color", nil, "→ colour"),
		f("transparency", "number"), f("altTransparency", "number", nil, "→ transparency"), f("time", "number"),
		f("moveCurve", "curve"), f("sizeCurve", "curve"), f("fadeCurve", "curve"), f("colorCurve", "curve"), f("visualTag", "text"),
	},
	Highlight = {
		f("subject", "enum", SUBJECT), f("applyTo", "text", nil, "apply to visual tag"), f("fill", "color"), f("outline", "color"),
		f("fillTransparency", "number"), f("outlineTransparency", "number"), f("duration", "number"), f("fadeCurve", "curve"),
	},
}

-- "InAir and not Holding and Health >= 0.5"
function Meta.condsText(conds: any): string
	local parts = {}
	for _, c in ipairs(type(conds) == "table" and conds or {}) do
		local t = (c["not"] and "not " or "") .. tostring(c.what or "?")
		if c.what == "Health" then
			t ..= " >= " .. tostring(c.value or 0.5)
		elseif c.what == "Meter" then
			t ..= (" %s >= %s"):format(tostring(c.meter or "?"), tostring(c.value or 1))
		end
		table.insert(parts, t)
	end
	return #parts > 0 and table.concat(parts, " and ") or "(no conditions)"
end

function Meta.category(nodeType: string): (string, Color3)
	for _, c in ipairs(Meta.Categories) do
		if table.find(c.types, nodeType) then
			return c.name, c.color
		end
	end
	return "Flow", Meta.FlowColor
end

-- how long a node lasts on the timeline (seconds), for drawing its bar
function Meta.duration(node: any, keyframes: any?): number
	local t = node.type
	if t == "Wait" then
		return node.time or 0
	elseif t == "Hitbox" then
		return math.max(node.time or 0, 0.05)
	elseif t == "Projectile" then
		return node.lifetime or 3
	elseif t == "Keyframes" then
		local a = keyframes and keyframes[node.anim]
		return a and (a.duration or 0.5) / math.max(node.speed or 1, 0.01) or 0.5
	elseif t == "Sound" then
		return node.stopAfter and node.stopAfter > 0 and node.stopAfter or 0.6
	elseif t == "Counter" then
		return node.time or 1
	elseif t == "Loop" then
		return (node.count or 1) * math.max(node.interval or 0, 0.1)
	end
	return node.time or node.duration or 0.3
end

return Meta
