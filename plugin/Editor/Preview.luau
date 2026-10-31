--!strict
-- Edit-mode preview: plays a skill on a caster dummy against a target dummy, right in the viewport, without Play.
-- Physics doesn't run in Edit mode, so the dummies are anchored and moved kinematically (velocity, travel, knockback),
-- posed by forward kinematics (keyframes, Roblox animations stepped by hand), and hits are found by distance.
-- Presentation uses SkillKit's own client modules (Fx, KeyframePlayer), so effects look as they do in game.
-- Nothing it creates is saved with the place (Archivable = false), and Stop / clear removes it all.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Preview = {}
Preview.__index = Preview

export type Event = { t: number, kind: string, msg: string, nodeId: string? }

function Preview.new(SK: any)
	local self = setmetatable({
		SK = SK,
		folder = nil :: Folder?,
		caster = nil :: Model?,
		dummy = nil :: Model?,
		running = nil :: any,
		listeners = {} :: { (Event) -> () },
		speed = 1,
		home = nil :: CFrame?,
		conns = {} :: { RBXScriptConnection },
	}, Preview)
	return self
end

function Preview:on(fn: (Event) -> ())
	table.insert(self.listeners, fn)
end

function Preview:emit(kind: string, msg: string, node: any?)
	local e = { t = self.running and (os.clock() - self.running.t0) * self.speed or 0, kind = kind, msg = msg, nodeId = node and node.id }
	for _, fn in ipairs(self.listeners) do
		task.spawn(fn, e)
	end
end

local function noArchive(inst: Instance)
	inst.Archivable = false
	for _, d in ipairs(inst:GetDescendants()) do
		d.Archivable = false
	end
end

-- rigs -----------------------------------------------------------------------------------------------------------------
local function makeRig(name: string, torso: Color3): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(214, 214, 220)
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor = torso
	desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(56, 60, 70), Color3.fromRGB(56, 60, 70)
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = name
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	return model
end

function Preview:ensureRigs()
	if self.caster and self.caster.Parent and self.dummy and self.dummy.Parent then
		return
	end
	self:clear()
	local folder = Instance.new("Folder")
	folder.Name = "SkillKitPreview"
	folder.Archivable = false
	folder.Parent = Workspace
	self.folder = folder
	self.caster = makeRig("Caster", Color3.fromRGB(70, 110, 190))
	self.dummy = makeRig("Target", Color3.fromRGB(170, 70, 70))
	self.caster.Parent = folder
	self.dummy.Parent = folder
	self:placeHere()
	noArchive(folder)
	local KP = self.SK.KeyframePlayer
	KP.fkModels[self.caster] = true
	KP.fkModels[self.dummy] = true
	self.SK.Rig.solveFK(self.caster)
	self.SK.Rig.solveFK(self.dummy)
	self.SK.Fx.config.localCharacter = self.caster
end

-- puts the two dummies on the floor in front of the camera, facing each other side-on
function Preview:placeHere()
	if not (self.caster and self.dummy) then
		return
	end
	local cam = Workspace.CurrentCamera
	local camPos = cam.CFrame.Position
	local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.folder :: Instance }
	-- 1) where the camera is looking, if that's a floor within reach
	local ground: Vector3? = nil
	local hit = Workspace:Raycast(camPos, cam.CFrame.LookVector * 120, params)
	if hit and hit.Normal.Y > 0.7 and (hit.Position - camPos).Magnitude > 8 then
		ground = hit.Position
	end
	-- 2) otherwise ~20 studs ahead (stopping before walls), straight down from camera height (never from the roof)
	if not ground then
		local dist = 20
		local wall = Workspace:Raycast(camPos, look * 24, params)
		if wall then
			dist = math.max((wall.Position - camPos).Magnitude - 4, 4)
		end
		local at = camPos + look * dist
		local down = Workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -300, 0), params)
		ground = down and down.Position or (at - Vector3.new(0, 4, 0))
	end
	local g = ground :: Vector3
	local right = look:Cross(Vector3.yAxis)
	local function place(m: Model, pos: Vector3, face: Vector3)
		local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
		local up = Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0)
		m:PivotTo(CFrame.lookAt(pos + up, pos + face + up))
	end
	-- 6 studs apart: close enough for melee hitboxes, far enough to see both
	place(self.caster, g - right * 3, right)
	place(self.dummy, g + right * 3, -right)
	self.home = self.caster:GetPivot()
	self.dummyHome = self.dummy:GetPivot()
	self:resetPositions()
end

-- what Check nodes see in the preview (the editor's Dummies menu changes these)
function Preview:conditions(): any
	self.cond = self.cond or { inAir = false, jumping = false, holding = false, aiming = true, health = 1, counterHit = true }
	return self.cond
end

-- the preview's tags, minus expired ones (kept between plays; Reset clears them)
function Preview:liveTags(): { [string]: number }
	self.tags = self.tags or {}
	self.tagExpire = self.tagExpire or {}
	local now = os.clock()
	for tag, at in pairs(self.tagExpire) do
		if at <= now then
			self.tags[tag] = nil
			self.tagExpire[tag] = nil
		end
	end
	return self.tags
end

function Preview:resetPositions(keepTags: boolean?)
	if not keepTags then
		self.tags = {}
		self.tagExpire = {}
		self.meters = {}
	end
	self.ragdolling = {}
	self.lie = {}
	if self.caster and self.home then
		self.caster:PivotTo(self.home)
	end
	if self.dummy and self.dummyHome then
		self.dummy:PivotTo(self.dummyHome)
	end
	for _, m in ipairs({ self.caster, self.dummy }) do
		if m then
			for _, j in ipairs(m:GetDescendants()) do
				if j:IsA("AnimationConstraint") or j:IsA("Motor6D") then
					(j :: any).Transform = CFrame.identity
				end
			end
			self.SK.Rig.solveFK(m)
		end
	end
end

function Preview:clear()
	self:stop()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.caster, self.dummy = nil, nil
	local fx = Workspace:FindFirstChild("SkillKitFx")
	if fx then
		fx:Destroy()
	end
end

function Preview:stop()
	local r = self.running
	if r then
		r.alive = false
		for _, c in ipairs(r.conns) do
			c:Disconnect()
		end
		for _, fn in ipairs(r.cleanups) do
			pcall(fn)
		end
		self.running = nil
		self:emit("info", "preview stopped")
	end
end

-- simulation helpers ------------------------------------------------------------------------------------------------------
local function root(m: Model?): BasePart?
	return m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function dir(cf: CFrame, v: Vector3): Vector3
	return cf.RightVector * v.X + cf.UpVector * v.Y + cf.LookVector * v.Z
end
local function offset(cf: CFrame, v: Vector3?): CFrame
	return cf + dir(cf, v or Vector3.zero)
end

-- move a rig kinematically along a velocity function for `time` seconds (scaled by preview speed)
function Preview:drive(r: any, model: Model, time: number, velocityAt: (number) -> Vector3)
	local t = 0
	local conn
	-- the newest motion wins (same as the game's Motion)
	self.driving = self.driving or {}
	local token = {}
	self.driving[model] = token
	conn = RunService.Heartbeat:Connect(function(dt)
		if not r.alive or not model.Parent or self.driving[model] ~= token then
			conn:Disconnect()
			return
		end
		dt *= self.speed
		t += dt
		if t >= time then
			conn:Disconnect()
			return
		end
		local v = velocityAt(t)
		model:PivotTo(model:GetPivot() + v * dt)
	end)
	table.insert(r.conns, conn)
end

-- a short knockback with gravity, landing back on the ground height
function Preview:groundY(model: Model): number
	local home = (model == self.caster and self.home) or (model == self.dummy and self.dummyHome) or model:GetPivot()
	return home.Y - ((self.lie and self.lie[model]) or 0)
end

-- a fake ragdoll for the anchored preview rigs: limbs go limp, the body falls on its back, then gets up
local LIMP = {
	Neck = CFrame.Angles(math.rad(-25), math.rad(10), 0),
	Waist = CFrame.Angles(math.rad(12), 0, math.rad(6)),
	LeftShoulder = CFrame.Angles(math.rad(-30), 0, math.rad(-65)),
	RightShoulder = CFrame.Angles(math.rad(-20), 0, math.rad(70)),
	LeftElbow = CFrame.Angles(math.rad(35), 0, 0),
	RightElbow = CFrame.Angles(math.rad(25), 0, 0),
	LeftHip = CFrame.Angles(math.rad(25), 0, math.rad(-14)),
	RightHip = CFrame.Angles(math.rad(10), 0, math.rad(18)),
	LeftKnee = CFrame.Angles(math.rad(-30), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-15), 0, 0),
}
function Preview:ragdoll(r: any, model: Model, seconds: number)
	local SK = self.SK
	pcall(SK.KeyframePlayer.stopModel, model)
	self.lie = self.lie or {}
	self.ragdolling = self.ragdolling or {}
	local token = {}
	self.ragdolling[model] = token
	local joints = {}
	for _, j in ipairs(model:GetDescendants()) do
		if (j:IsA("AnimationConstraint") or j:IsA("Motor6D")) and LIMP[j.Name] then
			table.insert(joints, j)
		end
	end
	local look = model:GetPivot().LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.zAxis
	local yaw = CFrame.lookAt(Vector3.zero, look)
	local drop = 2.3 -- root height above the floor when lying flat
	local fall, getUp = 0.3, 0.45
	local total = math.max(seconds, 0.2) + getUp
	local t, prevLie = 0, 0
	local function apply(a: number)
		local p = model:GetPivot().Position
		local lie = drop * a
		local y = p.Y + prevLie - lie
		prevLie = lie
		self.lie[model] = lie
		model:PivotTo(CFrame.new(p.X, y, p.Z) * yaw * CFrame.Angles(math.rad(85) * a, 0, 0))
		for _, j in ipairs(joints) do
			(j :: any).Transform = CFrame.identity:Lerp(LIMP[j.Name], a)
		end
		SK.Rig.solveFK(model)
	end
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or self.ragdolling[model] ~= token then
			conn:Disconnect()
			return
		end
		t += dt * self.speed
		local a
		if t < fall then
			a = math.sin(t / fall * math.pi / 2)
		elseif t < total - getUp then
			a = 1
		else
			a = 1 - math.clamp((t - (total - getUp)) / getUp, 0, 1)
		end
		apply(a)
		if t >= total then
			self.lie[model] = 0
			self.ragdolling[model] = nil
			conn:Disconnect()
		end
	end)
	-- not tied to the cast: the body keeps falling / getting up after the skill ends (Stop and Reset cancel it)
end

function Preview:knock(r: any, model: Model, velocity: Vector3)
	local v = velocity
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not r.alive or not model.Parent then
			conn:Disconnect()
			return
		end
		dt *= self.speed
		t += dt
		v = Vector3.new(v.X * (1 - 3 * dt), v.Y - 120 * dt, v.Z * (1 - 3 * dt))
		local p = model:GetPivot() + v * dt
		local groundY = self:groundY(model)
		if p.Y < groundY then
			p = p + Vector3.new(0, groundY - p.Y, 0)
			v = Vector3.new(v.X * 0.5, 0, v.Z * 0.5)
		end
		model:PivotTo(p)
		if t > 1.2 then
			conn:Disconnect()
		end
	end)
	table.insert(r.conns, conn)
end

local function label(model: Model, text: string, color: Color3, seconds: number)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 28)
	bb.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.6 + math.random() * 0.6, 0)
	bb.AlwaysOnTop = true
	bb.Archivable = false
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.Parent = bb
	bb.Parent = head
	task.delay(seconds, function()
		bb:Destroy()
	end)
end

-- is `model` inside a hit volume?
local function inside(cf: CFrame, size: Vector3, shape: string?, model: Model): boolean
	local r = root(model)
	if not r then
		return false
	end
	local margin = 1.2 -- the body has width
	local p = cf:PointToObjectSpace(r.Position)
	if shape == "Sphere" then
		return p.Magnitude <= math.max(size.X, size.Y, size.Z) / 2 + margin
	end
	return math.abs(p.X) <= size.X / 2 + margin and math.abs(p.Y) <= size.Y / 2 + margin * 2 and math.abs(p.Z) <= size.Z / 2 + margin
end

-- play ---------------------------------------------------------------------------------------------------------------------
function Preview:play(skill: any, branchName: string?)
	self:stop()
	self:ensureRigs()
	self:resetPositions(true)
	local SK = self.SK
	local caster, dummy = self.caster :: Model, self.dummy :: Model
	local r = { alive = true, t0 = os.clock(), conns = {}, cleanups = {}, lastHit = nil :: Model?, tags = self:liveTags(), hp = 100, busy = 0, castId = math.random(1, 1e9) }
	self.running = r
	local Fx, KP, Registry, Curves = SK.Fx, SK.KeyframePlayer, SK.Registry, SK.Curves
	local selfRef = self

	local function wait(seconds: number, cursor: any): boolean
		local t0 = os.clock()
		while os.clock() - t0 < seconds / selfRef.speed do
			if not r.alive or cursor.stopped then
				return false
			end
			task.wait()
		end
		return r.alive and not cursor.stopped
	end
	local function resolve(subject: any): Model?
		if subject == nil or subject == "user" then
			return caster
		elseif subject == "lastHit" then
			return r.lastHit
		elseif subject == "target" then
			return r.lastHit or dummy
		end
		return nil
	end
	local function payload(model: Model?, extra: any?)
		local p = { subject = model, cf = model and model:GetPivot() or nil, castId = r.castId, user = caster }
		for k, v in pairs(extra or {}) do
			p[k] = v
		end
		return p
	end

	local runList: (list: { any }, cursor: any) -> ()
	local function spawnBranch(name: string?, mode: string?, cursor: any, from: any?)
		if not name or name == "" or not r.alive then
			return
		end
		local list = skill.branches[name]
		if not list then
			selfRef:emit("warn", ("branch %q not found"):format(name), from)
			return
		end
		if mode == "Switch" and cursor then
			cursor.stopped = true
		end
		selfRef:emit("branch", "branch " .. name .. " ran", from)
		r.busy += 1
		task.spawn(function()
			runList(list, { stopped = false, branch = name })
			r.busy -= 1
		end)
	end
	local function track(fn: () -> ())
		r.busy += 1
		task.spawn(function()
			pcall(fn)
			r.busy -= 1
		end)
	end

	local function hit(n: any, from: CFrame, target: Model, cursor: any)
		r.lastHit = target
		local dmg = n.damage or 0
		r.hp -= dmg
		Fx.hitFlash({ model = target })
		if dmg > 0 then
			label(target, "-" .. tostring(dmg), Color3.fromRGB(255, 110, 100), 0.9)
		end
		if (n.stun or 0) > 0 then
			label(target, ("STUN %.1fs"):format(n.stun), Color3.fromRGB(255, 220, 120), math.min(n.stun / selfRef.speed, 2))
			KP.play(target, Registry.get("keyframes", "stagger"), { speed = 1 })
		end
		if n.canRagdoll then
			label(target, "RAGDOLL", Color3.fromRGB(200, 160, 255), 1)
			selfRef:ragdoll(r, target, (n.ragdollTime or 1) / selfRef.speed)
		end
		local kb: Vector3 = n.knockback or Vector3.zero
		if kb.Magnitude > 0 then
			local v
			if n.radial then
				local away = (target:GetPivot().Position - from.Position) * Vector3.new(1, 0, 1)
				away = away.Magnitude > 0.1 and away.Unit or from.LookVector
				v = away * kb.Z + Vector3.new(0, kb.Y, 0)
			else
				v = dir(from, kb)
			end
			selfRef:knock(r, target, v)
		end
		selfRef:emit("hit", ("hit %s for %s%s"):format(target.Name, tostring(dmg), r.hp <= 0 and " (finisher)" or ""), n)
		return r.hp <= 0
	end

	local H: { [string]: (any, any) -> () } = {}
	H.Branch = function(n, cursor)
		spawnBranch(n.target, n.mode or "Switch", cursor, n)
	end
	H.Loop = function(n, cursor)
		local function body()
			local count = n.count or 2
			local i = 0
			while r.alive and not cursor.stopped and (count <= 0 or i < count) and i < 200 do
				i += 1
				runList(n.nodes or {}, { stopped = false })
				if (n.interval or 0) > 0 then
					if not wait(n.interval, cursor) then
						break
					end
				elseif count <= 0 then
					task.wait()
				end
			end
		end
		if n.blocking then
			body()
		else
			track(body)
		end
	end
	H.Group = function(n, cursor)
		local list = n.nodes
		if (not list or #list == 0) and n.groupId and n.groupId ~= "" then
			local e = Registry.get("effect", n.groupId)
			list = e and e.nodes or {}
		end
		track(function()
			runList(list or {}, { stopped = false })
		end)
	end
	H.Tags = function(n, cursor)
		local before = r.tags[n.tag]
		if n.op == "Check" then
			local v, target = before or 0, n.value or 0
			local c = n.compare or ">="
			local pass = (c == ">=" and v >= target) or (c == ">" and v > target) or (c == "==" and v == target) or (c == "~=" and v ~= target) or (c == "<" and v < target) or (c == "<=" and v <= target)
			selfRef:emit("tag", ("check %s %s %s: %s -> %s"):format(n.tag, c, tostring(target), tostring(before), pass and "passed" or "failed"), n)
			spawnBranch(pass and n.passBranch or n.failBranch, n.mode, cursor, n)
			return
		end
		local v = before or 0
		if n.op == "Add" then
			v += n.value or 1
		elseif n.op == "Subtract" then
			v -= n.value or 1
		else
			v = n.value or 0
		end
		r.tags[n.tag] = v
		-- tags outlive the play (like in game) so combos can be tried by pressing Play again; `time` expires them
		self.tagExpire = self.tagExpire or {}
		self.tagExpire[n.tag] = (n.time and n.time > 0) and (os.clock() + n.time / selfRef.speed) or nil
		selfRef:emit("tag", ("%s %s: %s -> %s"):format(n.op, n.tag, tostring(before), tostring(v)), n)
	end
	-- conditions come from the preview's "pretend" settings (Dummies > Preview conditions)
	local function condPass(c: any): (boolean, string)
		local cond = selfRef:conditions()
		local what = c.what or "InAir"
		local pass, detail = false, ""
		if what == "InAir" then
			pass = cond.inAir
		elseif what == "Jumping" then
			pass = cond.jumping
		elseif what == "Holding" then
			pass = cond.holding
		elseif what == "Aiming" then
			pass = cond.aiming
		elseif what == "Health" then
			pass = cond.health >= (c.value or 0.5)
			detail = (" %d%%"):format(math.floor(cond.health * 100 + 0.5))
		elseif what == "Meter" then
			local v = (selfRef.meters or {})[c.meter or "awakening"] or 0
			pass = v >= (c.value or 1)
			detail = (" %s=%s"):format(tostring(c.meter), tostring(v))
		end
		if c["not"] then
			pass = not pass
		end
		return pass, (c["not"] and "not " or "") .. what .. detail
	end
	H.Check = function(n, cursor)
		local all, parts = true, {}
		for _, c in ipairs(n.conds or {}) do
			local ok, text = condPass(c)
			table.insert(parts, text .. (ok and " yes" or " no"))
			if not ok then
				all = false
			end
		end
		selfRef:emit("info", ("check %s -> %s"):format(table.concat(parts, ", "), all and "passed" or "failed"), n)
		if all then
			spawnBranch(n.passBranch, n.mode, cursor, n)
		elseif n.failBranch then
			spawnBranch(n.failBranch, n.mode, cursor, n)
		elseif n.stopOnFail then
			cursor.stopped = true
		end
	end
	H.Counter = function(n, cursor)
		local m = resolve(n.subject) or caster
		label(m, ("COUNTER %.1fs"):format(n.time or 1), Color3.fromRGB(255, 200, 90), math.min((n.time or 1) / selfRef.speed, 2))
		if selfRef:conditions().counterHit then
			-- pretend the dummy attacks during the window
			track(function()
				wait(math.min((n.time or 1) * 0.5, 0.3), cursor)
				if not r.alive then
					return
				end
				r.lastHit = dummy
				label(dummy, "COUNTERED", Color3.fromRGB(255, 120, 90), 1)
				selfRef:emit("hit", "countered Target (pretend attack)", n)
				spawnBranch(n.counterBranch, n.mode, cursor, n)
			end)
		else
			selfRef:emit("info", ("counter window %.2fs (turn on 'Dummy attacks during counters' to see it trigger)"):format(n.time or 1), n)
		end
	end
	H.Heal = function(n, cursor)
		local m = resolve(n.subject) or caster
		label(m, ("+%s%s HP"):format(tostring(n.amount or 0), n.percent and "%" or ""), Color3.fromRGB(110, 230, 140), 1)
		selfRef:emit("info", ("heal %s for %s%s"):format(m.Name, tostring(n.amount or 0), n.percent and "%" or ""), n)
	end
	H.Meter = function(n, cursor)
		selfRef.meters = selfRef.meters or {}
		local name = n.meter or "awakening"
		local before = selfRef.meters[name] or 0
		local v = n.op == "Set" and (n.value or 0) or before + (n.op == "Subtract" and -(n.value or 0) or (n.value or 0))
		selfRef.meters[name] = v
		selfRef:emit("info", ("meter %s: %s -> %s"):format(name, tostring(before), tostring(v)), n)
	end
	H.State = function(n, cursor)
		local m = resolve(n.subject)
		if not m then
			selfRef:emit("warn", "no subject (nothing hit yet)", n)
			return
		end
		local subs = type(n.sub) == "table" and table.concat(n.sub, "+") or ""
		label(m, ("%s %s"):format(string.upper(n.category or ""), subs), Color3.fromRGB(150, 220, 255), math.min((n.duration or 1) / selfRef.speed, 2.5))
		if n.category == "Body" then
			KP.freeze(m, (n.duration or 0.5) / selfRef.speed)
		elseif n.category == "Ragdoll" then
			selfRef:ragdoll(r, m, n.duration or 1)
		end
		selfRef:emit("info", ("%s %s on %s for %.2fs"):format(n.category, subs, m.Name, n.duration or 0), n)
	end
	H.Hitbox = function(n, cursor)
		track(function()
			local any, done = false, false
			local t0 = os.clock()
			local dur = (n.time or 0) / selfRef.speed
			local hitSet = {}
			local shown = false
			repeat
				local base = (root(caster) :: BasePart).CFrame
				local p: Vector3 = n.position or Vector3.zero
				local rot: Vector3 = n.rotation or Vector3.zero
				local cf = offset(base, p) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
				if not shown then
					shown = true
					-- the editor always shows hitboxes (that's the point of previewing)
					Fx.hitbox({ cf = cf, size = n.size, shape = n.shape, duration = math.max(dur, 0.25) })
				end
				local targets = { dummy }
				if n.hitUser or n.hitOnlyUser then
					table.insert(targets, caster)
				end
				for _, m in ipairs(targets) do
					if not hitSet[m] and (not n.hitOnlyUser or m == caster) and (m ~= caster or n.hitUser or n.hitOnlyUser) and inside(cf, n.size, n.shape, m) then
						hitSet[m] = true
						if m:GetAttribute("Blocking") and n.blockable ~= false then
							selfRef:emit("info", "blocked", n)
						else
							local killed = hit(n, base, m, cursor)
							if not any then
								any = true
								spawnBranch(n.victimBranch, n.mode, cursor, n)
							end
							if killed and not done then
								done = true
								spawnBranch(n.finisherBranch, n.mode, cursor, n)
							end
						end
					end
				end
				if dur <= 0 then
					break
				end
				task.wait()
			until os.clock() - t0 >= dur or not r.alive
			if not any then
				selfRef:emit("miss", "hit nobody (check size / position)", n)
				spawnBranch(n.missBranch, n.mode, cursor, n)
			end
		end)
	end
	H.Projectile = function(n, cursor)
		local base = (root(caster) :: BasePart).CFrame
		local origin = offset(base, n.position)
		local aim = base.LookVector
		if n.direction == "toTarget" then
			local tr = root(r.lastHit or dummy)
			if tr then
				aim = (tr.Position - origin.Position).Unit
			end
		elseif n.direction == "up" then
			aim = Vector3.yAxis
		elseif typeof(n.direction) == "Vector3" then
			aim = dir(base, n.direction).Unit
		end
		local id = math.random(1, 1e9)
		local homes = n.homing ~= nil
		Fx.projectile({ id = id, castId = r.castId, node = n, origin = origin.Position, aim = aim, target = homes and dummy or nil, homes = homes })
		track(function()
			local pos, d, fall, t = origin.Position, aim, 0, 0
			local lifetime = n.lifetime or 3
			local hitAny = false
			while r.alive and t < lifetime do
				local dt = task.wait() * selfRef.speed
				t += dt
				if homes and n.homing and t >= (n.homing.delay or 0) then
					local tr = root(dummy)
					if tr then
						local want = (tr.Position - pos).Unit
						local nd = d:Lerp(want, math.clamp((n.homing.turnSpeed or 6) * dt, 0, 1))
						d = nd.Magnitude > 0 and nd.Unit or want
						fall = 0
					end
				end
				fall += (n.gravity or 0) * dt
				local v = d * (n.speed or 80) * Curves.mult(n.speedCurve, t / lifetime) - Vector3.new(0, fall, 0)
				pos += v * dt
				local tr = root(dummy)
				if tr and (tr.Position - pos).Magnitude <= (n.radius or 2) + 1.5 then
					hitAny = true
					Fx.projectileEnd({ id = id, pos = pos, reason = "hit" })
					local killed = hit(n, CFrame.lookAt(pos - d, pos), dummy, cursor)
					spawnBranch(n.hitBranch, n.mode, cursor, n)
					if killed then
						spawnBranch(n.finisherBranch, n.mode, cursor, n)
					end
					break
				end
			end
			if not hitAny then
				Fx.projectileEnd({ id = id, pos = pos, reason = "timeout" })
				selfRef:emit("miss", ("flew %.1fs and hit nobody"):format(lifetime), n)
				spawnBranch(n.expireBranch, n.mode, cursor, n)
			end
		end)
	end
	H.Grab = function(n, cursor)
		local base = (root(caster) :: BasePart).CFrame
		local cf = offset(base, n.position)
		if not inside(cf, n.size, "Box", dummy) then
			selfRef:emit("miss", "grabbed nobody", n)
			spawnBranch(n.missBranch, n.mode, cursor, n)
			return
		end
		r.lastHit = dummy
		if (n.damage or 0) > 0 then
			hit({ damage = n.damage }, base, dummy, cursor)
		end
		selfRef:emit("hit", "grabbed Target", n)
		spawnBranch(n.grabBranch, n.mode, cursor, n)
		track(function()
			local t0 = os.clock()
			local hold: Vector3 = n.holdOffset or Vector3.new(0, 0, -3)
			while r.alive and os.clock() - t0 < (n.duration or 1.2) / selfRef.speed do
				local b = (root(caster) :: BasePart).CFrame
				dummy:PivotTo(b * CFrame.new(hold) * CFrame.Angles(0, math.pi, 0))
				task.wait()
			end
			local kb: Vector3 = n.releaseKnockback or Vector3.zero
			if kb.Magnitude > 0 then
				selfRef:knock(r, dummy, dir((root(caster) :: BasePart).CFrame, kb))
			end
		end)
	end
	H.Debris = function(n, cursor)
		local base = (root(caster) :: BasePart).CFrame
		Fx.hitbox({ cf = offset(base, n.position), size = n.size, shape = "Box", duration = 0.4 })
		Fx.preset({ preset = "impact", size = 1.2 }, payload(nil, { cf = offset(base, n.position) }))
		selfRef:emit("info", "debris breaks parts tagged SkillKitBreakable: see it for real in Play", n)
	end
	H.Velocity = function(n, cursor)
		local m = resolve(n.subject)
		if not m then
			return
		end
		local base = (root(caster) :: BasePart).CFrame
		local d: Vector3 = n.space == "World" and n.direction or dir(base, n.direction or Vector3.zAxis)
		d = d.Magnitude > 0 and d.Unit or d
		local time = n.time or 0.3
		selfRef:drive(r, m, time, function(t)
			local v = d * (n.speed or 50) * Curves.mult(n.fade, t / time)
			if n.holdHeight then
				v = Vector3.new(v.X, 0, v.Z)
			end
			return v
		end)
		track(function()
			wait(time, { stopped = false })
		end)
	end
	H.Travel = function(n, cursor)
		local m = resolve(n.subject)
		local target = (n.subject == "lastHit") and caster or (r.lastHit or dummy)
		local mr, tr = root(m), root(target)
		if not m or not mr or not tr then
			selfRef:emit("miss", "no target to travel to", n)
			return
		end
		local start = mr.Position
		local flat = (tr.Position - start) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= (n.stopDistance or 4) then
			selfRef:emit("miss", "already within stopDistance", n)
			spawnBranch(n.arriveBranch, n.mode, cursor, n)
			return
		end
		local time = math.max(n.time or 0.3, 0.05)
		track(function()
			local t0 = os.clock()
			while r.alive do
				local u = math.clamp((os.clock() - t0) * selfRef.speed / time, 0, 1)
				local g = (n.follow ~= false and tr.Position or (start + flat))
				local back = ((g - start) * Vector3.new(1, 0, 1)).Unit * (n.stopDistance or 4)
				local goal = Vector3.new(g.X, start.Y, g.Z) - back + Vector3.new(0, n.height or 0, 0)
				local p = start:Lerp(goal, Curves.ease(n.curve, u)) + Vector3.new(0, (n.arc or 0) * math.sin(math.pi * u), 0)
				m:PivotTo(CFrame.lookAt(p, Vector3.new(tr.Position.X, p.Y, tr.Position.Z)))
				if u >= 1 then
					break
				end
				task.wait()
			end
			selfRef:emit("info", "arrived", n)
			spawnBranch(n.arriveBranch, n.mode, cursor, n)
		end)
	end
	H.Teleport = function(n, cursor)
		local who = resolve(n.who)
		local to = n.to == "user" and caster or (r.lastHit or dummy)
		if not who then
			return
		end
		if n.to == "global" and typeof(n.cframe) == "CFrame" then
			who:PivotTo(n.cframe)
		else
			local tcf = to:GetPivot()
			local rot: Vector3 = n.rotation or Vector3.zero
			local dest = tcf * CFrame.new(n.offset or Vector3.zero) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
			if n.facing == "target" then
				dest = CFrame.lookAt(dest.Position, Vector3.new(tcf.X, dest.Y, tcf.Z))
			end
			who:PivotTo(dest)
		end
		selfRef:emit("info", "teleported " .. who.Name, n)
	end
	H.Animation = function(n, cursor)
		local m = resolve(n.subject)
		if not m then
			return
		end
		if Registry.get("keyframes", n.anim) then
			H.Keyframes(n, cursor)
			return
		end
		local id = Registry.id("animation", n.anim)
		local hum = m:FindFirstChildOfClass("Humanoid")
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
		if not id or not animator then
			selfRef:emit("warn", "no animation id", n)
			return
		end
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, trackObj = pcall(function()
			return (animator :: Animator):LoadAnimation(a)
		end)
		if not ok or not trackObj then
			selfRef:emit("warn", "animation failed to load: " .. id, n)
			return
		end
		trackObj.Looped = n.looped == true
		trackObj:Play(n.fadeIn or 0.1, n.weight or 1, n.speed or 1)
		-- step it by hand (Edit mode) and pose the anchored rig
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			if not r.alive or not trackObj.IsPlaying then
				conn:Disconnect()
				return
			end
			pcall(function()
				(animator :: any):StepAnimations(dt * selfRef.speed)
			end)
			SK.Rig.solveFK(m)
		end)
		table.insert(r.conns, conn)
		table.insert(r.cleanups, function()
			trackObj:Stop(0)
		end)
	end
	H.Keyframes = function(n, cursor)
		local m = resolve(n.subject)
		local anim = Registry.get("keyframes", n.anim)
		if not m or not anim then
			selfRef:emit("warn", "no keyframe animation named " .. tostring(n.anim), n)
			return
		end
		if n.mirror then
			anim = KP.mirror(anim)
		end
		local h = KP.play(m, anim, { speed = (n.speed or 1) * selfRef.speed, weight = n.weight, looped = n.looped })
		table.insert(r.cleanups, function()
			h:stop()
		end)
	end
	H.Sound = function(n, cursor)
		local id = Registry.id("sound", n.sound)
		if not id then
			selfRef:emit("warn", "no sound id", n)
			return
		end
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = n.volume or 0.6
		s.PlaybackSpeed = (n.speed or 1) * selfRef.speed
		s.Archivable = false
		s.Parent = SoundService
		task.spawn(function()
			-- PlayLocalSound does nothing for a sound that hasn't loaded yet
			local t0 = os.clock()
			while not s.IsLoaded and os.clock() - t0 < 3 do
				task.wait()
			end
			if not s.IsLoaded then
				selfRef:emit("warn", "sound didn't load: " .. id, n)
				s:Destroy()
				return
			end
			if r.alive then
				SoundService:PlayLocalSound(s)
			end
			task.delay(6, function()
				s:Destroy()
			end)
		end)
	end
	H.PresetVFX = function(n, cursor)
		local m = resolve(n.subject)
		Fx.preset(n, payload(m, { applyTo = n.applyTo }))
	end
	H.Particle = function(n, cursor)
		Fx.particle(n, payload(resolve(n.subject)))
	end
	H.MeshVisual = function(n, cursor)
		Fx.mesh(n, payload(resolve(n.subject)))
	end
	H.Highlight = function(n, cursor)
		Fx.highlight(n, payload(resolve(n.subject)))
	end

	runList = function(list: { any }, cursor: any)
		for _, node in ipairs(list) do
			if not r.alive or cursor.stopped then
				return
			end
			if node.disabled then
				continue
			end
			selfRef:emit("node", node.name or node.type, node)
			if node.type == "Wait" then
				if not wait(node.time or 0, cursor) then
					return
				end
			else
				local h = H[node.type]
				if h then
					local ok, err = pcall(h, node, cursor)
					if not ok then
						selfRef:emit("error", tostring(err), node)
					end
				end
			end
		end
	end

	local start = branchName and skill.branches[branchName] and branchName or "Default"
	self:emit("info", "preview " .. (skill.name or "skill") .. " from " .. start)
	r.busy += 1
	task.spawn(function()
		runList(skill.branches[start] or {}, { stopped = false, branch = start })
		r.busy -= 1
	end)
	-- end of the preview: nothing left running
	task.spawn(function()
		task.wait(0.2)
		while r.alive and r.busy > 0 and os.clock() - r.t0 < 20 do
			task.wait(0.1)
		end
		task.wait(0.6)
		if self.running == r then
			r.alive = false
			for _, c in ipairs(r.conns) do
				c:Disconnect()
			end
			self.running = nil
			self:emit("done", ("done in %.2fs"):format((os.clock() - r.t0) * self.speed))
		end
	end)
	local fx = Workspace:FindFirstChild("SkillKitFx")
	if fx then
		fx.Archivable = false
	end
end

function Preview:time(): number?
	local r = self.running
	return r and (os.clock() - r.t0) * self.speed or nil
end

return Preview
