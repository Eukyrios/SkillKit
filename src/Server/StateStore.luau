--!strict
-- States on characters: Disable (Movement Jump Skill Sprint Regeneration Collision PlayerCollision), Multiplier
-- (Speed Damage DamageTaken Cooldown), Lock (Direction Camera), Ragdoll, Body (freeze the current pose).
-- Every state is time-boxed. States with the same stateTag stack (op Add / Subtract / Remove).
-- Mirrors to attributes for the game's own code and UI: SK_Stunned, SK_Ragdoll, SK_Disable_<sub>, SK_Mult_<sub>.
--   StateStore.apply(model, spec) -> id
--   StateStore.has(model, "Disable", "Movement") -> bool       StateStore.mult(model, "Damage") -> number
--   StateStore.stunned(model) -> bool                            StateStore.ragdolled(model) -> bool
--   StateStore.endRagdoll(model)                                 StateStore.clear(model)
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Parent.Net)

local StateStore = {}

type Entry = { id: number, category: string, sub: { string }, value: number, untilT: number, tag: string?, canCancel: boolean? }
local states: { [Model]: { Entry } } = {}
local base: { [Model]: { walk: number, jump: number, useJumpPower: boolean } } = {}
local nextId = 0

pcall(function()
	PhysicsService:RegisterCollisionGroup("SkillKitGhost")
end)
pcall(function()
	-- ghosts pass through each other; a game can also make them pass through its player group
	PhysicsService:CollisionGroupSetCollidable("SkillKitGhost", "SkillKitGhost", false)
end)

local function list(model: Model): { Entry }
	local l = states[model]
	if not l then
		l = {}
		states[model] = l
	end
	return l
end

function StateStore.has(model: Model, category: string, sub: string?): boolean
	for _, e in ipairs(states[model] or {}) do
		if e.category == category and (sub == nil or table.find(e.sub, sub)) then
			return true
		end
	end
	return false
end

function StateStore.mult(model: Model, sub: string): number
	local m = 1
	for _, e in ipairs(states[model] or {}) do
		if e.category == "Multiplier" and table.find(e.sub, sub) then
			m *= e.value
		end
	end
	return m
end

function StateStore.stunned(model: Model): boolean
	return StateStore.has(model, "Disable", "Skill")
end

function StateStore.ragdolled(model: Model): boolean
	return StateStore.has(model, "Ragdoll")
end

-- recompute the humanoid from the current states
local function refresh(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local b = base[model]
	if not b then
		b = { walk = hum.WalkSpeed, jump = hum.UseJumpPower and hum.JumpPower or hum.JumpHeight, useJumpPower = hum.UseJumpPower }
		base[model] = b
	end
	local noMove = StateStore.has(model, "Disable", "Movement")
	local noJump = StateStore.has(model, "Disable", "Jump")
	local speed = StateStore.mult(model, "Speed")
	local wantWalk = noMove and 0 or b.walk * speed
	if hum.WalkSpeed ~= wantWalk then
		hum.WalkSpeed = wantWalk
	end
	if b.useJumpPower then
		hum.JumpPower = noJump and 0 or b.jump
	else
		hum.JumpHeight = noJump and 0 or b.jump
	end
	local ragdoll = StateStore.ragdolled(model)
	if hum.PlatformStand ~= ragdoll then
		hum.PlatformStand = ragdoll
	end
	local ghost = StateStore.has(model, "Disable", "PlayerCollision")
	local noCollide = StateStore.has(model, "Disable", "Collision")
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if ghost and p.CollisionGroup ~= "SkillKitGhost" then
				p:SetAttribute("SK_Group", p.CollisionGroup)
				p.CollisionGroup = "SkillKitGhost"
			elseif not ghost and p.CollisionGroup == "SkillKitGhost" then
				p.CollisionGroup = p:GetAttribute("SK_Group") or "Default"
			end
			if p.Name ~= "HumanoidRootPart" then
				if noCollide and p:GetAttribute("SK_Collide") == nil then
					p:SetAttribute("SK_Collide", p.CanCollide)
					p.CanCollide = false
				elseif not noCollide and p:GetAttribute("SK_Collide") ~= nil then
					p.CanCollide = p:GetAttribute("SK_Collide")
					p:SetAttribute("SK_Collide", nil)
				end
			end
		end
	end
	model:SetAttribute("SK_Stunned", StateStore.stunned(model) or nil)
	model:SetAttribute("SK_Ragdoll", ragdoll or nil)
	for _, sub in ipairs({ "Movement", "Jump", "Skill", "Sprint", "Regeneration" }) do
		model:SetAttribute("SK_Disable_" .. sub, StateStore.has(model, "Disable", sub) or nil)
	end
	for _, sub in ipairs({ "Speed", "Damage", "DamageTaken", "Cooldown" }) do
		local m = StateStore.mult(model, sub)
		model:SetAttribute("SK_Mult_" .. sub, m ~= 1 and m or nil)
	end
end
StateStore.refresh = refresh

local function owner(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

function StateStore.apply(model: Model, spec: any): number?
	local l = list(model)
	local duration = spec.duration or 1
	local sub = type(spec.sub) == "table" and spec.sub or { spec.sub }
	-- stacking by tag
	if spec.stateTag then
		for i, e in ipairs(l) do
			if e.tag == spec.stateTag then
				if spec.op == "Remove" then
					table.remove(l, i)
				elseif spec.op == "Subtract" then
					e.value -= spec.value or 0
					e.untilT = os.clock() + duration
				else
					e.value += spec.value or 0
					e.untilT = os.clock() + duration
				end
				refresh(model)
				return e.id
			end
		end
		if spec.op == "Remove" then
			return nil
		end
	end
	nextId += 1
	local entry: Entry = { id = nextId, category = spec.category, sub = sub, value = spec.value or 1, untilT = os.clock() + duration, tag = spec.stateTag, canCancel = spec.canCancel }
	table.insert(l, entry)
	-- client-side parts
	local player = owner(model)
	if spec.category == "Lock" then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local yaw = root and select(2, root.CFrame:ToEulerAnglesYXZ()) or 0
		if player then
			Net.to(player, "Lock", { duration = duration, yaw = yaw, direction = table.find(sub, "Direction") ~= nil, camera = table.find(sub, "Camera") ~= nil })
		else
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.AutoRotate = false
				task.delay(duration, function()
					if not StateStore.has(model, "Lock", "Direction") then
						hum.AutoRotate = true
					end
				end)
			end
		end
	elseif spec.category == "Body" then
		Net.all("Freeze", { model = model, duration = duration })
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			if player then
				Net.to(player, "Anchor", { duration = duration })
			else
				root.Anchored = true
				task.delay(duration, function()
					if root.Parent and not StateStore.has(model, "Body") then
						root.Anchored = false
					end
				end)
			end
		end
	elseif spec.category == "Ragdoll" then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not player then
			root:ApplyAngularImpulse(root.CFrame.RightVector * root.AssemblyMass * 40)
		end
	end
	refresh(model)
	return entry.id
end

function StateStore.endRagdoll(model: Model): boolean
	local l = states[model]
	local ended = false
	if l then
		for i = #l, 1, -1 do
			if l[i].category == "Ragdoll" then
				table.remove(l, i)
				ended = true
			end
		end
	end
	if ended then
		refresh(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	return ended
end

function StateStore.clear(model: Model)
	states[model] = nil
	refresh(model)
	base[model] = nil
end

-- expiry
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, l in pairs(states) do
		if not model.Parent then
			states[model] = nil
			base[model] = nil
			continue
		end
		local changed = false
		for i = #l, 1, -1 do
			if l[i].untilT <= now then
				table.remove(l, i)
				changed = true
			end
		end
		if changed then
			refresh(model)
		end
		if #l == 0 then
			states[model] = nil
			base[model] = nil -- the next state captures the speed the game has then
		end
	end
end)

-- the game changed the walk speed while no state was on: take it as the new base
function StateStore.setBase(model: Model, walk: number?, jump: number?)
	local b = base[model]
	if b then
		b.walk = walk or b.walk
		b.jump = jump or b.jump
	end
	refresh(model)
end

return StateStore
