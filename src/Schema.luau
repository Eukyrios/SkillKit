--!strict
-- The skill data model, defaults and validation.
--   CharacterDef = { id, name, stats?, slots = { [slotName] = Skill } }
--   Skill        = { id?, name, cooldown?, key?, startOff?, cancelOnStun?, branches = { Default = { Node, ... }, [name] = { ... } } }
--                  (or `nodes = { ... }` as a shorthand for branches.Default)
--   Node         = { type = "<NodeType>", id?, name?, ...props }      props are flat on the node, defaults below
-- Directions and offsets are Vector3(right, up, forward) from the user unless a node says otherwise.
-- Nodes in a branch start in order; only Wait advances time. Branch fields name a branch; `mode` is "Switch"
-- (leave the current branch) or "Continue" (run both).
local Schema = {}

Schema.Version = 1

Schema.Categories = {
	Flow = { "Wait", "Branch", "Loop", "Group", "Tags", "State", "Check", "Heal", "Meter" },
	Combat = { "Hitbox", "Projectile", "Grab", "Debris", "Counter" },
	Motion = { "Velocity", "Travel", "Teleport" },
	Animation = { "Animation", "Keyframes" },
	Audio = { "Sound" },
	Visual = { "PresetVFX", "Particle", "MeshVisual", "Highlight" },
}

local V3 = Vector3.new
Schema.Defaults = {
	Wait = { time = 0 },
	Branch = { target = "", mode = "Switch" },
	Loop = { count = 2, interval = 0, blocking = false, nodes = {} },
	Group = { groupId = "", nodes = {} },
	Tags = {
		subject = "user", -- user | lastHit
		tag = "",
		op = "Add", -- Add | Subtract | Set | Check
		value = 1,
		time = 0, -- seconds before it expires (0 = until the cast's owner dies or it's changed)
		keep = false, -- survives death
		compare = ">=", -- for op = Check: >= | == | < | > | <= | ~=
		passBranch = nil,
		failBranch = nil,
		mode = "Switch",
	},
	State = {
		subject = "user",
		category = "Disable", -- Disable | Multiplier | Lock | Ragdoll | Body
		sub = { "Movement" }, -- Disable: Movement Jump Skill Sprint Regeneration Collision PlayerCollision
		-- Multiplier: Speed Damage DamageTaken Cooldown | Lock: Direction Camera
		value = 1,
		duration = 1,
		stateTag = nil, -- states with the same tag stack (op)
		op = "Add", -- Add | Subtract | Remove
		canCancel = false, -- Ragdoll: can a hitbox with canCancelRagdoll end it
	},
	Hitbox = {
		time = 0, -- 0 = one tick
		position = V3(0, 0, 3),
		rotation = V3(0, 0, 0), -- degrees
		size = V3(5, 5, 5),
		shape = "Box", -- Box | Sphere | Cylinder
		attach = "HRP", -- HRP | Torso | Head | a visual/projectile tag
		singleTarget = false,
		rehit = 0, -- >0: seconds before the same target can be hit again (time > 0 only)
		visible = false,
		damage = 0,
		stun = 0,
		knockback = V3(0, 0, 0),
		radial = false,
		blockable = true,
		block360 = false,
		blockCancel = false,
		canKill = true,
		canRagdoll = false,
		ragdollTime = 1.5,
		canCancelRagdoll = false,
		hitRagdoll = false,
		hitUser = false,
		hitOnlyUser = false,
		victimBranch = nil,
		finisherBranch = nil,
		missBranch = nil,
		mode = "Continue",
	},
	Projectile = {
		shape = "Ball", -- Ball | Block | a registry mesh name
		size = 1.5,
		color = Color3.fromRGB(255, 220, 160),
		material = "Neon",
		position = V3(0, 0, 3),
		direction = "look", -- look | toTarget | up | V3 (local)
		speed = 80,
		speedCurve = nil,
		gravity = 0,
		lifetime = 3,
		range = 0, -- 0 = no range limit
		stick = 0,
		pierce = false,
		homing = nil, -- { chance = 1, turnSpeed = 6, range = 60, delay = 0 }
		projectileTag = nil,
		damage = 0,
		stun = 0,
		knockback = V3(0, 0, 0),
		radius = 2, -- hit radius
		blockable = true,
		canKill = true,
		hitBranch = nil,
		expireBranch = nil,
		mode = "Continue",
	},
	Grab = {
		position = V3(0, 0, 3),
		size = V3(5, 5, 5),
		duration = 1.2,
		holdOffset = V3(0, 0, -3), -- where the victim is held, local to the user (forward is -Z here)
		victimAnimation = nil,
		releaseKnockback = V3(0, 10, 30),
		damage = 0,
		grabBranch = nil,
		missBranch = nil,
		mode = "Continue",
	},
	Debris = {
		type = "SinglePoint", -- SinglePoint | Radial | Line
		position = V3(0, 0, 5),
		size = V3(8, 8, 8),
		visible = false,
		count = 5,
		force = 40,
		canCollide = true,
		lifetime = 3,
		settleAfter = 0,
		rebuildAfter = 30,
		tags = nil, -- only parts with one of these CollectionService tags (default: SkillKitBreakable)
	},
	Velocity = {
		subject = "user", -- user | lastHit
		direction = V3(0, 0, 1),
		speed = 50,
		space = "Local", -- Local | World
		time = 0.3,
		fade = nil, -- true / curve: multiplier over time
		holdHeight = false,
		track = false,
		ragdoll = false,
	},
	Travel = {
		subject = "user",
		target = "lastHit", -- lastHit | look | projectile:<tag>
		time = 0.3,
		stopDistance = 4,
		height = 0,
		arc = 0,
		curve = nil,
		follow = true,
		wallStop = true,
		collision = true,
		holdHeight = false,
		range = 60,
		arriveBranch = nil,
		mode = "Continue",
	},
	Teleport = {
		who = "user", -- user | lastHit | projectile:<tag>
		to = "lastHit", -- lastHit | user | projectile:<tag> | global
		offset = V3(0, 0, -4), -- local to the destination (forward = -Z, behind = +Z)
		rotation = V3(0, 0, 0),
		cframe = nil, -- global destination
		facing = "keep", -- keep | target
		keepVelocity = false,
	},
	Animation = { anim = "", speed = 1, fadeIn = 0.1, fadeOut = 0.15, weight = 1, looped = false, stopAfter = 0, priority = "Action", subject = "user" },
	Keyframes = { anim = "", speed = 1, weight = 1, looped = false, subject = "user" },
	Sound = { sound = "", volume = 0.6, pitch = 1, speed = 1, subject = "user", looped = false, stopAfter = 0, rollOff = { 8, 120 } },
	PresetVFX = { preset = "", subject = "user", position = V3(0, 0, 0), duration = 0.6, color = nil, color2 = nil, size = 1, applyTo = nil, visualTag = nil },
	Particle = {
		subject = "user",
		position = V3(0, 0, 0),
		texture = "",
		color = Color3.new(1, 1, 1),
		emitCount = 20,
		enabled = false,
		duration = 0.5,
		lifetime = { 0.4, 0.8 },
		speed = { 10, 20 },
		spread = 180,
		size = 1,
		sizeCurve = nil,
		transparencyCurve = nil,
		lightEmission = 1,
		rotSpeed = { 0, 0 },
		acceleration = V3(0, 0, 0),
		drag = 0,
		flipbook = nil, -- { rows, cols, fps }
	},
	MeshVisual = {
		mesh = "Sphere", -- Sphere | Block | Cylinder | a registry mesh name
		texture = nil,
		material = "Neon",
		subject = "user",
		attach = false, -- follow the subject while it plays
		position = V3(0, 0, 0),
		rotation = V3(0, 0, 0),
		altPosition = nil,
		altRotation = nil,
		size = V3(2, 2, 2),
		altSize = nil,
		color = Color3.fromRGB(255, 220, 160),
		altColor = nil,
		transparency = 0,
		altTransparency = 1,
		time = 0.5,
		moveCurve = nil,
		sizeCurve = nil,
		fadeCurve = nil,
		colorCurve = nil,
		visualTag = nil,
	},
	-- Check: every condition in `conds` must pass (each can be inverted with `not = true`).
	--   what: InAir | Jumping | Holding (the skill key is held) | Aiming (the mouse is on a valid target; it becomes
	--   the cast's target) | Health (fraction of max health, compared with `value`) | Meter (a game meter, `meter`)
	Check = {
		subject = "user",
		conds = { { what = "InAir" } },
		passBranch = nil,
		failBranch = nil,
		stopOnFail = false, -- leave the current branch when the check fails (and there's no failBranch)
		mode = "Switch",
	},
	-- Counter: for `time` seconds, a hit on the subject is cancelled; the attacker becomes the last hit, is stunned
	-- for `stun`, and `counterBranch` runs
	Counter = { subject = "user", time = 1, stun = 1, counterBranch = nil, removeOnHit = true, mode = "Switch" },
	Heal = { subject = "user", amount = 10, percent = false },
	-- Meter: a named game meter (awakening, evasion, ...). The game's adapter decides what it is; by default it's an
	-- attribute "SK_Meter_<name>" on the model
	Meter = { subject = "user", meter = "awakening", op = "Add", value = 5 },
	Highlight = { subject = "user", applyTo = nil, fill = Color3.fromRGB(255, 220, 160), outline = Color3.new(1, 1, 1), fillTransparency = 0.5, outlineTransparency = 0, duration = 0.5, fadeCurve = nil },
}

-- deep copy of plain tables (Vector3/Color3/etc are values already)
local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end
Schema.copy = copy

local idCounter = 0
local function nextId(): string
	idCounter += 1
	return "n" .. idCounter
end

-- fill defaults and ids in place on a node list (recurses into Loop/Group)
local function normalizeList(list: { any }, errors: { string }, branches: { [string]: any }, path: string)
	for i, node in ipairs(list) do
		if type(node) ~= "table" or type(node.type) ~= "string" then
			table.insert(errors, ("%s[%d]: not a node"):format(path, i))
			continue
		end
		local defaults = Schema.Defaults[node.type]
		if not defaults then
			table.insert(errors, ("%s[%d]: unknown node type %q"):format(path, i, node.type))
			continue
		end
		for k, v in pairs(defaults) do
			if node[k] == nil then
				node[k] = copy(v)
			end
		end
		node.id = node.id or nextId()
		for _, field in ipairs({ "target", "victimBranch", "finisherBranch", "missBranch", "hitBranch", "expireBranch", "passBranch", "failBranch", "arriveBranch", "grabBranch", "counterBranch" }) do
			local b = node[field]
			if type(b) == "string" and b ~= "" and not branches[b] and not (node.type == "Travel" and field == "target") then
				table.insert(errors, ("%s[%d] %s (%s): no branch named %q"):format(path, i, node.type, node.id, b))
			end
		end
		if node.type == "Loop" or node.type == "Group" then
			normalizeList(node.nodes, errors, branches, path .. "[" .. i .. "]")
		end
	end
end

-- normalize a skill in place; returns it and a list of problems (empty = valid)
function Schema.normalize(skill: any): (any, { string })
	local errors = {}
	if type(skill) ~= "table" then
		return skill, { "skill is not a table" }
	end
	if skill.__normalized then
		return skill, {}
	end
	if not skill.branches then
		skill.branches = { Default = skill.nodes or {} }
		skill.nodes = nil
	end
	if not skill.branches.Default then
		table.insert(errors, "skill has no Default branch")
		skill.branches.Default = {}
	end
	skill.name = skill.name or "Skill"
	skill.cooldown = skill.cooldown or 1
	for name, list in pairs(skill.branches) do
		normalizeList(list, errors, skill.branches, (skill.name :: string) .. "." .. name)
	end
	skill.__normalized = true
	skill.version = skill.version or Schema.Version
	return skill, errors
end

-- total time of the Default branch's Waits (a rough cast time, for cooldown UIs)
function Schema.castTime(skill: any): number
	local t = 0
	local list = skill.branches and skill.branches.Default or skill.nodes or {}
	for _, n in ipairs(list) do
		if n.type == "Wait" then
			t += n.time or 0
		end
	end
	return t
end

return Schema
