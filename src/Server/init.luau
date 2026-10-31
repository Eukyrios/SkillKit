--!strict
-- SkillKit server: the adapter, casting, characters, stats, previews.
-- Adapter (all optional; defaults work for a plain game):
--   canHit(user, target) -> bool               who may be hurt (teams, safe zones)
--   candidates(user) -> { Model }              models to consider when aiming (Travel, Projectile toTarget)
--   applyHit(cast, victim, hit) -> killed      hit = { damage, stun, knockback (world Vector3), canKill, node, from }
--   push(model, velocity, time)                knockback / release impulses
--   isBlocking(model) -> bool                   breakBlock(model)
--   isStunned(model) -> bool                    (cancels the user's cast unless skill.cancelOnStun == false)
--   canCast(user, skill) -> bool
--   isHolding(model, cast) -> bool              is the skill key held (Check "Holding"); default: SkillKit.setHolding
--   aimTarget(model, cast) -> Model?            what the player aims at (Check "Aiming"); default: the client's mouse
--   heal(model, amount)                         Heal nodes
--   getMeter(model, name) -> number?  setMeter(model, name, value)   game meters (awakening, evasion, ...)
--   limits = { maxSpeed, scale = {min,max}, walkSpeed = {min,max}, jumpPower = {min,max}, health = {min,max} }
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Codec = require(script.Parent.Codec)
local DebugLog = require(script.Parent.DebugLog)
local Motion = require(script.Parent.Motion)
local Net = require(script.Parent.Net)
local Registry = require(script.Parent.Registry)
local Rig = require(script.Parent.Rig)
local Schema = require(script.Parent.Schema)
local Executor = require(script.Executor)
local Nodes = require(script.Nodes)
local StateStore = require(script.StateStore)
local TagStore = require(script.TagStore)

local Server = {}
Server.Tags = TagStore
Server.States = StateStore
Server.Nodes = Nodes

local adapter: any = nil
-- what each player's client reports: { holding = bool, aim = Model? } (SkillKit.setHolding / aim tracking)
Server.input = {} :: { [Player]: { holding: boolean, aim: Model? } }
local characters: { [string]: any } = {}
local running: { [Model]: { any } } = {}

-- defaults ----------------------------------------------------------------------------------------------------------
local DEFAULT_LIMITS = {
	maxSpeed = 250,
	scale = { 0.5, 2 },
	walkSpeed = { 4, 40 },
	jumpPower = { 0, 120 },
	health = { 1, 10000 },
	cameraOffset = 3,
}

local function defaultCandidates(user: Model): { Model }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p.Character ~= user then
			table.insert(out, p.Character)
		end
	end
	for _, folderName in ipairs({ "NPCs", "SkillKitDummies", "Enemies" }) do
		local f = Workspace:FindFirstChild(folderName)
		if f then
			for _, m in ipairs(f:GetChildren()) do
				if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and m ~= user then
					table.insert(out, m)
				end
			end
		end
	end
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m ~= user and m:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(m) then
			table.insert(out, m)
		end
	end
	return out
end

local function defaultPush(model: Model, velocity: Vector3, time: number?)
	local root = Rig.root(model)
	if not root then
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		Net.to(player, "Push", { velocity = velocity, time = time or 0.2 })
	else
		Motion.push(root, velocity, time or 0.2)
	end
end

local function defaultApplyHit(cast: any, victim: Model, hit: any): boolean
	local hum = Rig.humanoid(victim)
	if not hum then
		return false
	end
	local dmg = hit.damage or 0
	if not hit.canKill and hum.Health - dmg < 1 then
		dmg = math.max(0, hum.Health - 1)
	end
	hum:TakeDamage(dmg)
	if (hit.stun or 0) > 0 then
		StateStore.apply(victim, { category = "Disable", sub = { "Movement", "Jump", "Skill" }, duration = hit.stun })
		Net.all("Keyframes", { model = victim, node = { anim = "stagger", speed = 1, weight = 1 }, castId = 0 })
	end
	if hit.knockback and hit.knockback.Magnitude > 0 then
		adapter.push(victim, hit.knockback, 0.2)
	end
	Net.all("HitFlash", { model = victim, damage = dmg })
	return hum.Health <= 0
end

local function withDefaults(a: any?): any
	a = a or {}
	local out = table.clone(a)
	out.canHit = out.canHit or function(user, target)
		return target ~= user and Rig.alive(target) and target:GetAttribute("SK_NoTarget") ~= true
	end
	out.candidates = out.candidates or defaultCandidates
	out.push = out.push or defaultPush
	out.applyHit = out.applyHit or defaultApplyHit
	out.isBlocking = out.isBlocking or function(model)
		return model:GetAttribute("Blocking") == true or model:GetAttribute("SK_Blocking") == true
	end
	out.breakBlock = out.breakBlock or function(model)
		model:SetAttribute("Blocking", nil)
		model:SetAttribute("SK_Blocking", nil)
	end
	out.isStunned = out.isStunned or function(model)
		return StateStore.stunned(model)
	end
	out.canCast = out.canCast or function()
		return true
	end
	out.isHolding = out.isHolding or function(model)
		local p = Players:GetPlayerFromCharacter(model)
		local inp = p and Server.input[p]
		return (inp and inp.holding) or model:GetAttribute("SK_Holding") == true
	end
	out.aimTarget = out.aimTarget or function(model)
		local p = Players:GetPlayerFromCharacter(model)
		local inp = p and Server.input[p]
		local t = inp and inp.aim
		if t and t.Parent and t ~= model and Rig.alive(t) and out.canHit(model, t) then
			local a, b = Rig.root(model), Rig.root(t)
			if a and b and (a.Position - b.Position).Magnitude <= 300 then
				return t
			end
		end
		return nil
	end
	out.heal = out.heal or function(model, amount)
		local hum = Rig.humanoid(model)
		if hum and hum.Health > 0 then
			hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
		end
	end
	out.getMeter = out.getMeter or function(model, name)
		return tonumber(model:GetAttribute("SK_Meter_" .. tostring(name))) or 0
	end
	out.setMeter = out.setMeter or function(model, name, value)
		model:SetAttribute("SK_Meter_" .. tostring(name), value)
	end
	local limits = table.clone(DEFAULT_LIMITS)
	for k, v in pairs(a.limits or {}) do
		limits[k] = v
	end
	out.limits = limits
	return out
end

-- API ---------------------------------------------------------------------------------------------------------------
function Server.init(a: any?)
	adapter = withDefaults(a)
	if a and a.registry then
		Registry.load(a.registry)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(c)
			TagStore.onCharacter(p, c)
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		Server.input[p] = nil
	end)
	-- the only messages clients send: input state for Check "Holding" / "Aiming"
	Net.remote().OnServerEvent:Connect(function(p, kind, value)
		local inp = Server.input[p] or { holding = false }
		Server.input[p] = inp
		if kind == "Holding" then
			inp.holding = value == true
		elseif kind == "Aim" then
			inp.aim = (typeof(value) == "Instance" and value:IsA("Model")) and value or nil
		end
	end)
	return Server
end

-- has the game called init yet? (test runners use this so they don't replace the game's adapter)
function Server.isReady(): boolean
	return adapter ~= nil
end

local function ensureInit()
	if not adapter then
		Server.init(nil)
	end
end

function Server.defineCharacter(def: any): any
	assert(type(def) == "table" and type(def.id) == "string", "CharacterDef needs an id")
	def.slots = def.slots or {}
	for slot, skill in pairs(def.slots) do
		skill.id = skill.id or (def.id .. ":" .. slot)
		local _, errors = Schema.normalize(skill)
		for _, e in ipairs(errors) do
			warn(("[SkillKit] %s.%s: %s"):format(def.id, slot, e))
		end
	end
	characters[def.id] = def
	return def
end

function Server.getSkill(charId: string, slot: string): any
	local c = characters[charId]
	return c and c.slots[slot] or nil
end

function Server.getCharacter(charId: string): any
	return characters[charId]
end

-- skillOrRef: a Skill table, an "SK1:" code, or "charId:slot"
local function resolveSkill(skillOrRef: any): any
	if type(skillOrRef) == "table" then
		local s, errors = Schema.normalize(skillOrRef)
		for _, e in ipairs(errors) do
			warn("[SkillKit] " .. e)
		end
		return s
	elseif type(skillOrRef) == "string" then
		if string.sub(skillOrRef, 1, 4) == "SK1:" then
			local decoded, err = Codec.decode(skillOrRef)
			if not decoded then
				warn("[SkillKit] " .. tostring(err))
				return nil
			end
			return (Schema.normalize(decoded))
		end
		local charId, slot = string.match(skillOrRef, "^(.-):(.+)$")
		if charId then
			return Server.getSkill(charId, slot :: string)
		end
	end
	return nil
end

-- run a skill. opts: { player?, target? (preferred target), force? (skip canCast) }. Returns the Cast or nil.
function Server.cast(user: Model, skillOrRef: any, opts: any?): any
	ensureInit()
	opts = opts or {}
	local skill = resolveSkill(skillOrRef)
	if not skill or not Rig.alive(user) then
		return nil
	end
	if not opts.force and not adapter.canCast(user, skill) then
		return nil
	end
	if skill.cancelOthers then
		Server.cancel(user, "replaced")
	end
	local cast = Executor.new({ user = user, player = opts.player, skill = skill, adapter = adapter, target = opts.target })
	local list = running[user] or {}
	running[user] = list
	table.insert(list, cast)
	cast.finished.Event:Connect(function()
		local l = running[user]
		if l then
			local i = table.find(l, cast)
			if i then
				table.remove(l, i)
			end
			if #l == 0 then
				running[user] = nil
			end
		end
	end)
	cast:start()
	return cast
end

function Server.cancel(user: Model, reason: string?)
	for _, c in ipairs(table.clone(running[user] or {})) do
		c:cancel(reason or "cancelled")
	end
end

function Server.running(user: Model): { any }
	return running[user] or {}
end

-- stats: scale, walkSpeed, jumpPower, hipHeight, cameraOffset, health, maxHealth (clamped by adapter.limits)
function Server.applyStats(character: Model, stats: any)
	ensureInit()
	local hum = Rig.humanoid(character)
	if not hum or not stats then
		return
	end
	local L = adapter.limits
	local function clamp(v: number, r: { number }): number
		return math.clamp(v, r[1], r[2])
	end
	if stats.scale then
		pcall(function()
			character:ScaleTo(clamp(stats.scale, L.scale))
		end)
	end
	if stats.walkSpeed then
		hum.WalkSpeed = clamp(stats.walkSpeed, L.walkSpeed)
		StateStore.setBase(character, hum.WalkSpeed, nil)
	end
	if stats.jumpPower then
		hum.UseJumpPower = true
		hum.JumpPower = clamp(stats.jumpPower, L.jumpPower)
	end
	if stats.hipHeight then
		hum.HipHeight = stats.hipHeight
	end
	if stats.maxHealth then
		hum.MaxHealth = clamp(stats.maxHealth, L.health)
	end
	if stats.health then
		hum.Health = math.min(clamp(stats.health, L.health), hum.MaxHealth)
	end
	if stats.cameraOffset then
		local c = L.cameraOffset
		local o: Vector3 = stats.cameraOffset
		hum.CameraOffset = Vector3.new(math.clamp(o.X, -c, c), math.clamp(o.Y, -c, c), math.clamp(o.Z, -c, c))
	end
end

-- dummies and previews ------------------------------------------------------------------------------------------------
function Server.spawnDummy(at: CFrame, opts: any?): Model
	opts = opts or {}
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(200, 200, 205)
	desc.HeadColor, desc.TorsoColor = skin, Color3.fromRGB(90, 96, 110)
	desc.LeftArmColor, desc.RightArmColor = skin, skin
	desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(60, 64, 74), Color3.fromRGB(60, 64, 74)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local dummy: Model
	if ok and model then
		dummy = model
	else
		dummy = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = dummy
		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Size = Vector3.new(2, 2, 1)
		torso.Parent = dummy
		local w = Instance.new("Motor6D")
		w.Part0, w.Part1 = root, torso
		w.Parent = root
		Instance.new("Humanoid").Parent = dummy
		dummy.PrimaryPart = root
	end
	dummy.Name = opts.name or "SkillKitDummy"
	for _, d in ipairs(dummy:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hum = Rig.humanoid(dummy) :: Humanoid
	hum.MaxHealth = opts.health or 300
	hum.Health = hum.MaxHealth
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.BreakJointsOnDeath = false
	if opts.blocking then
		dummy:SetAttribute("SK_Blocking", true)
	end
	local folder = Workspace:FindFirstChild("SkillKitDummies") or Instance.new("Folder")
	folder.Name = "SkillKitDummies"
	folder.Parent = Workspace
	local root = Rig.root(dummy) :: BasePart
	dummy:PivotTo(at + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0))
	dummy.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if opts.lifetime ~= 0 then
		task.delay(opts.lifetime or 30, function()
			dummy:Destroy()
		end)
	end
	hum.Died:Connect(function()
		task.delay(2, function()
			dummy:Destroy()
		end)
	end)
	return dummy
end

-- run a skill against a fresh dummy. opts: { player (required for on = "player"), on = "player" | "dummy",
-- distance = 8, dummyHealth } -> cast, dummy
function Server.preview(skill: any, opts: any): (any, Model?)
	ensureInit()
	opts = opts or {}
	local player: Player? = opts.player
	local userModel = opts.user or (player and player.Character)
	local base: CFrame
	local root = userModel and Rig.root(userModel)
	if root then
		base = root.CFrame
	else
		base = opts.at or CFrame.new(0, 5, 0)
	end
	local flat = CFrame.lookAt(base.Position, base.Position + base.LookVector * Vector3.new(1, 0, 1))
	local groundY = base.Position.Y - (root and (Rig.humanoid(userModel) :: Humanoid).HipHeight + root.Size.Y / 2 or 0)
	local spot = flat * CFrame.new(0, 0, -(opts.distance or 8))
	local target = Server.spawnDummy(CFrame.lookAt(Vector3.new(spot.X, groundY, spot.Z), Vector3.new(base.X, groundY, base.Z)), { health = opts.dummyHealth, blocking = opts.dummyBlocking, lifetime = opts.dummyLifetime })
	local cast
	if opts.on == "dummy" or not userModel then
		cast = Server.cast(target, skill, { target = userModel, force = true })
	else
		cast = Server.cast(userModel, skill, { player = player, target = target, force = true })
	end
	return cast, target
end

-- a saved Effect group, anywhere (no user needed: a dummy anchor is the subject)
function Server.playEffect(name: string, at: CFrame): any
	local entry = Registry.get("effect", name)
	if not entry then
		warn("[SkillKit] no effect named " .. name)
		return nil
	end
	local anchor = Instance.new("Model")
	anchor.Name = "SkillKitEffect"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = false
	root.Transparency = 1
	root.CFrame = at
	root.Parent = anchor
	local hum = Instance.new("Humanoid")
	hum.Parent = anchor
	anchor:SetAttribute("SK_NoTarget", true)
	anchor.Parent = Workspace
	local cast = Server.cast(anchor, { name = name, nodes = Schema.copy(entry.nodes), cancelOnStun = false }, { force = true })
	if cast then
		cast.finished.Event:Connect(function()
			task.delay(3, function()
				anchor:Destroy()
			end)
		end)
	else
		anchor:Destroy()
	end
	return cast
end

-- debug ---------------------------------------------------------------------------------------------------------------
Server.debug = {
	dump = function(owner: any, count: number?)
		DebugLog.print(owner, count)
	end,
	get = DebugLog.get,
	clear = DebugLog.clear,
}

return Server
