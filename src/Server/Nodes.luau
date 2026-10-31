--!strict
-- Node handlers (server). Each is handler(cast, node, cursor) and must not yield: anything that lasts goes on
-- cast:spawn. Presentation (animation, keyframes, sound, VFX) is sent to clients; the server keeps the rules.
local Players = game:GetService("Players")

local Curves = require(script.Parent.Parent.Curves)
local Motion = require(script.Parent.Parent.Motion)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)
local Rig = require(script.Parent.Parent.Rig)
local Debris = require(script.Parent.Debris)
local Executor = require(script.Parent.Executor)
local Hitbox = require(script.Parent.Hitbox)
local Projectile = require(script.Parent.Projectile)
local StateStore = require(script.Parent.StateStore)
local TagStore = require(script.Parent.TagStore)

local H = Executor.Handlers
local Nodes = {}

local function playerOf(inst: Instance?): Player?
	if inst and inst:IsA("Model") then
		return Players:GetPlayerFromCharacter(inst)
	end
	return nil
end

local function modelOf(inst: Instance?): Model?
	if not inst then
		return nil
	end
	if inst:IsA("Model") then
		return inst
	end
	return Rig.modelOf(inst)
end

-- open counter windows: victim -> { cast, node, cursor, untilTime }
local counters: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any
Nodes.counters = counters

-- HIT: counters, blocking, damage multipliers, knockback, ragdoll, last hit, log -----------------------------------
function Nodes.hit(cast: any, victim: Model, n: any, from: CFrame): (boolean, boolean)
	local adapter = cast.adapter
	local c = counters[victim]
	if c and c.cast.alive and os.clock() < c.untilTime and cast.user ~= victim then
		-- countered: the hit does nothing, the attacker is stunned and becomes the counter's last hit
		if c.node.removeOnHit ~= false then
			counters[victim] = nil
		end
		local attacker = cast.user
		c.cast.lastHit = attacker
		table.insert(c.cast.hits, attacker)
		if (c.node.stun or 0) > 0 then
			StateStore.apply(attacker, { category = "Disable", sub = { "Movement", "Jump", "Skill" }, duration = c.node.stun })
		end
		cast:log(n, "info", ("countered by %s"):format(victim.Name), { code = "countered" })
		c.cast:log(c.node, "info", ("countered %s"):format(attacker.Name))
		c.cast:branch(c.node.counterBranch, c.node.mode, c.cursor, c.node)
		return false, true
	end
	if n.blockable ~= false and adapter.isBlocking(victim) and (n.block360 or Hitbox.facing(victim, from.Position)) then
		if n.blockCancel then
			adapter.breakBlock(victim)
		end
		cast:log(n, "info", "blocked by " .. victim.Name, { code = "blocked" })
		return false, true
	end
	if n.canCancelRagdoll and StateStore.ragdolled(victim) then
		StateStore.endRagdoll(victim)
		cast:log(n, "info", "ended the ragdoll on " .. victim.Name)
	end
	local damage = (n.damage or 0) * StateStore.mult(cast.user, "Damage") * StateStore.mult(victim, "DamageTaken")
	local kb: Vector3 = n.knockback or Vector3.zero
	local velocity = Vector3.zero
	if kb.Magnitude > 0 then
		if n.radial then
			local r = Rig.root(victim)
			local away = r and (r.Position - from.Position) * Vector3.new(1, 0, 1) or Vector3.zero
			away = away.Magnitude > 0.1 and away.Unit or from.LookVector
			velocity = away * kb.Z + Vector3.new(0, kb.Y, 0)
		else
			velocity = Executor.dir(from, kb)
		end
	end
	local killed = adapter.applyHit(cast, victim, {
		damage = damage,
		stun = n.stun or 0,
		knockback = velocity,
		canKill = n.canKill ~= false,
		node = n,
		from = from,
	})
	if n.canRagdoll then
		StateStore.apply(victim, { category = "Ragdoll", sub = {}, duration = n.ragdollTime or 1.5, canCancel = true })
	end
	cast.lastHit = victim
	table.insert(cast.hits, victim)
	cast:log(n, "info", ("hit %s for %.1f%s"):format(victim.Name, damage, killed and " (finisher)" or ""))
	return killed == true, false
end

-- FLOW --------------------------------------------------------------------------------------------------------------
H.Branch = function(cast, n, cursor)
	cast:branch(n.target, n.mode or "Switch", cursor, n)
end

H.Loop = function(cast, n, cursor)
	local function body()
		local count = n.count or 2
		local i = 0
		local child = { branch = cursor.branch .. "/loop", stopped = false }
		while cast.alive and not cursor.stopped and (count <= 0 or i < count) and i < 1000 do
			i += 1
			cast:runNodes(n.nodes or {}, child)
			if child.stopped then
				break
			end
			if (n.interval or 0) > 0 then
				if not cast:wait(n.interval, cursor) then
					break
				end
			elseif count <= 0 then
				task.wait() -- an endless loop with no Wait inside still yields
			end
		end
	end
	if n.blocking then
		body()
	else
		cast:spawn(body)
	end
end

H.Group = function(cast, n, cursor)
	local list = n.nodes
	if (not list or #list == 0) and n.groupId ~= "" then
		local entry = Registry.get("effect", n.groupId)
		list = entry and entry.nodes or {}
	end
	cast:spawn(function()
		cast:runNodes(list or {}, { branch = cursor.branch .. "/" .. (n.name or "group"), stopped = false })
	end)
end

H.Tags = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject or n.tag == "" then
		cast:log(n, "warn", "no subject or empty tag name")
		return
	end
	local before = TagStore.get(subject, n.tag)
	if n.op == "Check" then
		local v = before or 0
		local target = n.value or 0
		local pass = (n.compare == ">=" and v >= target)
			or (n.compare == ">" and v > target)
			or (n.compare == "==" and v == target)
			or (n.compare == "~=" and v ~= target)
			or (n.compare == "<" and v < target)
			or (n.compare == "<=" and v <= target)
		cast:log(n, "tag", ("check %s %s %s on %s: %s is %s -> %s"):format(n.tag, n.compare, tostring(target), subject.Name, n.tag, tostring(before), pass and "passed" or "failed"), before == nil and { code = "tag_nil" } or nil)
		if pass then
			cast:branch(n.passBranch, n.mode, cursor, n)
		else
			cast:branch(n.failBranch, n.mode, cursor, n)
		end
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
	TagStore.set(subject, n.tag, v, n.time, n.keep)
	cast:log(n, "tag", ("%s %s %s on %s: %s -> %s"):format(n.op, n.tag, tostring(n.value), subject.Name, tostring(before), tostring(v)))
end

H.State = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		cast:log(n, "warn", "no subject for the state (nothing hit yet?)")
		return
	end
	StateStore.apply(subject, n)
	cast:log(n, "info", ("%s %s on %s for %.2fs"):format(n.category, table.concat(type(n.sub) == "table" and n.sub or {}, "+"), subject.Name, n.duration or 0))
end

-- COMBAT ------------------------------------------------------------------------------------------------------------
local function overlapFor(cast: any, n: any): OverlapParams
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, f in ipairs({ "SkillKitDebris" }) do
		local x = workspace:FindFirstChild(f)
		if x then
			table.insert(ignore, x)
		end
	end
	if not (n.hitUser or n.hitOnlyUser) then
		table.insert(ignore, cast.user)
	end
	p.FilterDescendantsInstances = ignore
	return p
end

local function validTarget(cast: any, n: any, m: Model): boolean
	if n.hitOnlyUser then
		return m == cast.user
	end
	if m == cast.user then
		return n.hitUser == true
	end
	if not Rig.alive(m) then
		return false
	end
	if not n.hitRagdoll and StateStore.ragdolled(m) and not n.canCancelRagdoll then
		return false
	end
	return cast.adapter.canHit(cast.user, m)
end

local function attachFrame(cast: any, attach: string?): CFrame?
	if attach == nil or attach == "HRP" or attach == "Torso" or attach == "Head" then
		local root = cast:userRoot()
		if not root then
			return nil
		end
		if attach == "Torso" or attach == "Head" then
			local p = Rig.part(cast.user, attach)
			return p and (CFrame.new(p.Position) * (root.CFrame - root.Position)) or root.CFrame
		end
		return root.CFrame
	end
	return cast:frameOf(attach)
end

H.Hitbox = function(cast, n, cursor)
	cast:spawn(function()
		local hitSet: { [Model]: number } = {}
		local any, finished, blockedAny = false, false, false
		local t0 = os.clock()
		local duration = n.time or 0
		local shown = false
		repeat
			local base = attachFrame(cast, n.attach)
			if not base then
				break
			end
			local cf = Hitbox.frame(base, n.position, n.rotation)
			if n.visible and not shown then
				shown = true
				Net.all("HitboxShow", { cf = cf, size = n.size, shape = n.shape, duration = math.max(duration, 0.15), follow = duration > 0 and cast.user or nil, offset = base:ToObjectSpace(cf) })
			end
			local found = Hitbox.query(cf, n.size, n.shape, overlapFor(cast, n))
			for _, m in ipairs(found) do
				local last = hitSet[m]
				local again = last and (n.rehit or 0) > 0 and os.clock() - last >= n.rehit
				if (not last or again) and validTarget(cast, n, m) then
					hitSet[m] = os.clock()
					local killed, blocked = Nodes.hit(cast, m, n, base)
					blockedAny = blockedAny or blocked
					if not blocked then
						if not any then
							any = true
							cast:branch(n.victimBranch, n.mode, cursor, n)
						end
						if killed and not finished then
							finished = true
							cast:branch(n.finisherBranch, n.mode, cursor, n)
						end
					end
					if n.singleTarget then
						break
					end
				end
			end
			if n.singleTarget and any then
				break
			end
			if duration <= 0 then
				break
			end
			task.wait()
		until os.clock() - t0 >= duration or not cast.alive
		if not any then
			if blockedAny then
				cast:log(n, "info", "every target blocked it")
			else
				cast:log(n, "info", "hit nobody", { code = "hitbox_miss" })
			end
			cast:branch(n.missBranch, n.mode, cursor, n)
		end
	end)
end

local function aimFor(cast: any, n: any, from: CFrame): (Vector3, Model?)
	local d = n.direction
	if d == "toTarget" then
		local t = cast:pickTarget(n.range and n.range > 0 and n.range or 120, 60)
		local r = t and Rig.root(t)
		if r then
			return (r.Position - from.Position).Unit, t
		end
		return from.LookVector, nil
	elseif d == "up" then
		return Vector3.yAxis, nil
	elseif typeof(d) == "Vector3" then
		return Executor.dir(from, d).Unit, cast:pickTarget(120, 60)
	end
	return from.LookVector, cast:pickTarget(120, 45)
end

H.Projectile = function(cast, n, cursor)
	local root = cast:userRoot()
	if not root then
		return
	end
	local origin = Executor.offset(root.CFrame, n.position)
	local aim, target = aimFor(cast, n, root.CFrame)
	local anyHit = false
	Projectile.fire(cast, n, origin, aim, target, function(m, pos)
		local from = CFrame.lookAt(pos - aim, pos)
		local killed, blocked = Nodes.hit(cast, m, n, from)
		if not blocked then
			anyHit = true
			cast:branch(n.hitBranch, n.mode, cursor, n)
		end
		if killed then
			cast:branch(n.finisherBranch, n.mode, cursor, n)
		end
	end, function(reason, pos)
		if not anyHit then
			if reason == "timeout" or reason == "range" then
				cast:log(n, "info", ("flew %.1fs and hit nobody"):format(n.lifetime or 3), { code = "projectile_timeout" })
			elseif reason == "wall" then
				cast:log(n, "info", "hit the map before a target", { code = "projectile_wall" })
			end
			cast:branch(n.expireBranch, n.mode, cursor, n)
		end
	end)
end

H.Grab = function(cast, n, cursor)
	local root = cast:userRoot()
	if not root then
		return
	end
	local cf = Executor.offset(root.CFrame, n.position)
	local victim: Model? = nil
	for _, m in ipairs(Hitbox.query(cf, n.size, "Box", overlapFor(cast, n))) do
		if validTarget(cast, n, m) then
			victim = m
			break
		end
	end
	if not victim then
		cast:log(n, "info", "grabbed nobody", { code = "hitbox_miss" })
		cast:branch(n.missBranch, n.mode, cursor, n)
		return
	end
	local vroot = Rig.root(victim)
	if not vroot then
		return
	end
	cast.lastHit = victim
	if (n.damage or 0) > 0 then
		Nodes.hit(cast, victim, { damage = n.damage, blockable = false, canKill = true }, root.CFrame)
	end
	StateStore.apply(victim, { category = "Disable", sub = { "Movement", "Jump", "Skill" }, duration = n.duration or 1.2 })
	local holdAt = Instance.new("Attachment")
	holdAt.Name = "SkillKitGrab"
	holdAt.Position = n.holdOffset or Vector3.new(0, 0, -3)
	holdAt.Parent = root
	local vAt = Instance.new("Attachment")
	vAt.Name = "SkillKitGrabbed"
	vAt.Parent = vroot
	local align = Instance.new("AlignPosition")
	align.Attachment0, align.Attachment1 = vAt, holdAt
	align.RigidityEnabled = true
	align.Parent = vroot
	local orient = Instance.new("AlignOrientation")
	orient.Attachment0, orient.Attachment1 = vAt, holdAt
	orient.RigidityEnabled = true
	orient.Parent = vroot
	pcall(function()
		vroot:SetNetworkOwner(nil)
	end)
	if n.victimAnimation then
		H.Animation(cast, { type = "Animation", anim = n.victimAnimation, subject = "lastHit", speed = 1, fadeIn = 0.1, fadeOut = 0.2, weight = 1, priority = "Action4" }, cursor)
	end
	cast:log(n, "info", "grabbed " .. victim.Name)
	cast:branch(n.grabBranch, n.mode, cursor, n)
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		align:Destroy()
		orient:Destroy()
		holdAt:Destroy()
		vAt:Destroy()
		if vroot.Parent then
			pcall(function()
				vroot:SetNetworkOwnershipAuto()
			end)
			local kb: Vector3 = n.releaseKnockback or Vector3.zero
			if kb.Magnitude > 0 then
				cast.adapter.push(victim, Executor.dir(root.CFrame, kb), 0.25)
			end
		end
	end
	cast:onCleanup(release)
	cast:spawn(function()
		cast:wait(n.duration or 1.2)
		release()
	end)
end

H.Debris = function(cast, n, cursor)
	local root = cast:userRoot()
	if not root then
		return
	end
	local cf = Executor.offset(root.CFrame, n.position)
	if n.visible then
		Net.all("HitboxShow", { cf = cf, size = n.size, shape = "Box", duration = 0.4 })
	end
	local center = n.type == "SinglePoint" and cf.Position or root.Position
	local count = Debris.breakIn(cf, n.size, n, center, { cast.user })
	if count == 0 then
		cast:log(n, "info", "nothing breakable in the box", { code = "no_breakables" })
	else
		cast:log(n, "info", ("broke %d part(s) into %d pieces each"):format(count, n.count or 5))
	end
end

-- MOTION ------------------------------------------------------------------------------------------------------------
local function motionSpec(n: any): any
	local s = table.clone(n)
	s.id = nil
	return s
end

H.Velocity = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	local root = Rig.root(subject)
	if not subject or not root then
		cast:log(n, "warn", "no subject to move")
		return
	end
	local spec = motionSpec(n)
	-- Local directions are taken from the user's facing at this moment (also when moving the last hit target)
	if n.space ~= "World" and subject ~= cast.user then
		local ur = cast:userRoot()
		if ur then
			spec.direction = Executor.dir(ur.CFrame, n.direction)
			spec.space = "World"
		end
	end
	if n.ragdoll then
		StateStore.apply(subject, { category = "Ragdoll", sub = {}, duration = n.time + 0.5, canCancel = true })
	end
	local player = playerOf(subject)
	if player then
		Net.to(player, "Motion", { kind = "velocity", spec = spec, castId = cast.id })
		cast:onCleanup(function()
			Net.to(player, "MotionStop", { castId = cast.id })
		end)
	else
		local stop = Motion.velocity(root, spec)
		cast:onCleanup(stop)
	end
	cast:spawn(function()
		cast:wait(n.time or 0.3)
	end)
end

H.Travel = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	local root = Rig.root(subject)
	if not subject or not root then
		return
	end
	local target: Instance? = nil
	if type(n.target) == "string" and string.match(n.target, "^projectile:") then
		target = cast:resolve(n.target)
	elseif n.target == "look" then
		local saved = cast.lastHit
		cast.lastHit = nil
		target = cast:pickTarget(n.range or 60, 40)
		cast.lastHit = saved
	else
		target = cast:pickTarget(n.range or 60, 40)
	end
	if not target or target == subject then
		cast:log(n, "info", "no target to travel to", { code = "travel_no_target" })
		return
	end
	local tpos = target:IsA("Model") and (Rig.root(target :: Model) or (target :: any)).Position or (target :: BasePart).Position
	if ((tpos - root.Position) * Vector3.new(1, 0, 1)).Magnitude <= (n.stopDistance or 4) then
		cast:log(n, "info", "already within stopDistance", { code = "travel_inside" })
		cast:branch(n.arriveBranch, n.mode, cursor, n)
		return
	end
	local spec = motionSpec(n)
	local player = playerOf(subject)
	if player then
		Net.to(player, "Motion", { kind = "travel", spec = spec, target = target, castId = cast.id })
		cast:onCleanup(function()
			Net.to(player, "MotionStop", { castId = cast.id })
		end)
		cast:spawn(function()
			cast:wait((n.time or 0.3) + 0.1)
			local now = target:IsA("Model") and Rig.root(target :: Model) or target
			if now and root.Parent and ((now :: any).Position - root.Position).Magnitude <= (n.stopDistance or 4) + 3 then
				cast:branch(n.arriveBranch, n.mode, cursor, n)
			end
		end)
	else
		local result: string? = nil
		local stop = Motion.travelUntilDone(root, spec, target, function(r)
			result = r
		end)
		cast:onCleanup(stop)
		cast:spawn(function()
			while result == nil and cast.alive do
				task.wait()
			end
			if result == "arrived" then
				cast:branch(n.arriveBranch, n.mode, cursor, n)
			elseif result == "wall" then
				cast:log(n, "info", "stopped at a wall")
			end
		end)
	end
end

H.Teleport = function(cast, n, cursor)
	local who = modelOf(cast:resolve(n.who)) or cast:resolve(n.who)
	if not who then
		cast:log(n, "warn", "nothing to teleport")
		return
	end
	local dest: CFrame?
	if n.to == "global" then
		dest = n.cframe
	else
		local inst = cast:resolve(n.to)
		if n.to == "lastHit" and not inst then
			inst = cast:pickTarget(80, 60)
		end
		local cf = inst and (inst:IsA("Model") and (Rig.root(inst :: Model) and (Rig.root(inst :: Model) :: BasePart).CFrame or (inst :: Model):GetPivot()) or (inst :: BasePart).CFrame)
		if cf then
			local o = n.offset or Vector3.zero
			local r = n.rotation or Vector3.zero
			dest = cf * CFrame.new(o) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		end
	end
	if not dest then
		cast:log(n, "info", "no destination", { code = "travel_no_target" })
		return
	end
	if n.facing == "target" and n.to ~= "global" then
		local inst = cast:resolve(n.to)
		local tr = inst and (inst:IsA("Model") and Rig.root(inst :: Model) or inst)
		if tr then
			dest = CFrame.lookAt(dest.Position, Vector3.new((tr :: any).Position.X, dest.Position.Y, (tr :: any).Position.Z))
		end
	end
	local finalDest = dest :: CFrame
	if who:IsA("Model") then
		local root = Rig.root(who :: Model)
		local v = root and root.AssemblyLinearVelocity
		local player = playerOf(who)
		if player then
			Net.to(player, "Teleport", { cf = finalDest, keepVelocity = n.keepVelocity })
		end
		(who :: Model):PivotTo(finalDest)
		if root and not n.keepVelocity then
			root.AssemblyLinearVelocity = Vector3.zero
		elseif root and v then
			root.AssemblyLinearVelocity = v
		end
	elseif who:IsA("BasePart") then
		(who :: BasePart).CFrame = finalDest
	end
	cast:log(n, "info", "teleported " .. who.Name)
end

-- PRESENTATION ------------------------------------------------------------------------------------------------------
H.Animation = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		return
	end
	local player = playerOf(subject)
	if player then
		-- the owner plays it; Roblox replicates its character's animations to everyone
		Net.to(player, "Anim", { model = subject, node = n, castId = cast.id })
		cast:onCleanup(function()
			if n.stopOnCancel ~= false and cast.endReason ~= "done" then
				Net.to(player, "AnimStop", { castId = cast.id })
			end
		end)
	else
		local hum = Rig.humanoid(subject)
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
		local r6 = hum and hum.RigType == Enum.HumanoidRigType.R6
		local entry = Registry.get("animation", n.anim)
		local id = Registry.id("animation", r6 and entry and entry.r6 or n.anim, r6 and entry and entry.r6 and "r6" or nil)
		if not animator or not id then
			if Registry.get("keyframes", n.anim) then
				H.Keyframes(cast, n, cursor)
				return
			end
			cast:log(n, "warn", "animation not found: " .. tostring(n.anim), { code = "asset_failed" })
			return
		end
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(a)
		end)
		if not ok or not track then
			cast:log(n, "warn", "animation failed to load: " .. id, { code = "asset_failed" })
			return
		end
		track.Priority = (Enum.AnimationPriority :: any)[n.priority or "Action"] or Enum.AnimationPriority.Action
		track.Looped = n.looped == true
		track:Play(n.fadeIn or 0.1, n.weight or 1, n.speed or 1)
		if (n.stopAfter or 0) > 0 then
			task.delay(n.stopAfter, function()
				track:Stop(n.fadeOut or 0.15)
			end)
		end
		cast:onCleanup(function()
			if cast.endReason ~= "done" or n.looped then
				track:Stop(n.fadeOut or 0.15)
			end
		end)
	end
end

H.Keyframes = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		return
	end
	if not Registry.get("keyframes", n.anim) and type(n.anim) ~= "table" then
		cast:log(n, "warn", "no keyframe animation named " .. tostring(n.anim), { code = "asset_failed" })
		return
	end
	Net.all("Keyframes", { model = subject, node = n, castId = cast.id })
	cast:onCleanup(function()
		if cast.endReason ~= "done" then
			Net.all("KeyframesStop", { castId = cast.id })
		end
	end)
end

local function subjectInfo(cast: any, subject: any): (Instance?, CFrame?)
	local inst = cast:resolve(subject)
	local cf = cast:frameOf(subject)
	return inst, cf
end

H.Sound = function(cast, n, cursor)
	local inst, cf = subjectInfo(cast, n.subject)
	if not Registry.id("sound", n.sound) then
		cast:log(n, "warn", "sound not found: " .. tostring(n.sound), { code = "asset_failed" })
		return
	end
	Net.all("Sound", { node = n, subject = inst, cf = cf, castId = cast.id })
end

local function vfx(kind: string)
	return function(cast, n, cursor)
		local inst, cf = subjectInfo(cast, n.subject)
		Net.all("Vfx", { kind = kind, node = n, subject = inst, cf = cf, castId = cast.id, user = cast.user, applyTo = n.applyTo })
		if not inst and not cf then
			cast:log(n, "warn", "no subject for the visual (nothing hit yet?)")
		end
	end
end
H.PresetVFX = vfx("PresetVFX")
H.Particle = vfx("Particle")
H.MeshVisual = vfx("MeshVisual")
H.Highlight = vfx("Highlight")

-- CONDITIONS, COUNTERS, HEALTH, METERS ----------------------------------------------------------------------------
local function condition(cast: any, subject: Model, c: any): (boolean, string)
	local what = c.what or "InAir"
	local pass: boolean
	local detail = ""
	if what == "InAir" or what == "Jumping" then
		local hum = Rig.humanoid(subject)
		local state = hum and hum:GetState()
		if what == "InAir" then
			pass = hum ~= nil and (hum.FloorMaterial == Enum.Material.Air or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping)
		else
			pass = hum ~= nil and (state == Enum.HumanoidStateType.Jumping or (hum.Jump == true))
		end
	elseif what == "Holding" then
		pass = cast.adapter.isHolding(subject, cast) == true
	elseif what == "Aiming" then
		local t = cast.adapter.aimTarget(subject, cast)
		pass = t ~= nil
		if t and subject == cast.user then
			cast.target = t
			detail = " at " .. t.Name
		end
	elseif what == "Health" then
		local hum = Rig.humanoid(subject)
		local frac = hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 0
		pass = frac >= (c.value or 0.5)
		detail = (" %.0f%%"):format(frac * 100)
	elseif what == "Meter" then
		local v = cast.adapter.getMeter(subject, c.meter or "awakening") or 0
		pass = v >= (c.value or 1)
		detail = (" %s=%s"):format(tostring(c.meter), tostring(v))
	else
		pass = false
		detail = " (unknown condition)"
	end
	if c["not"] then
		pass = not pass
	end
	return pass, ((c["not"] and "not " or "") .. what .. detail)
end
Nodes.condition = condition

H.Check = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		cast:log(n, "warn", "no subject to check")
		return
	end
	local all, parts = true, {}
	for _, c in ipairs(n.conds or {}) do
		local ok, text = condition(cast, subject, c)
		table.insert(parts, text .. (ok and " ✓" or " ✗"))
		if not ok then
			all = false
		end
	end
	cast:log(n, "info", ("check %s -> %s"):format(table.concat(parts, ", "), all and "passed" or "failed"))
	if all then
		cast:branch(n.passBranch, n.mode, cursor, n)
	elseif n.failBranch then
		cast:branch(n.failBranch, n.mode, cursor, n)
	elseif n.stopOnFail then
		cursor.stopped = true
	end
end

H.Counter = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		return
	end
	local entry = { cast = cast, node = n, cursor = cursor, untilTime = os.clock() + (n.time or 1) }
	counters[subject] = entry
	cast:log(n, "info", ("counter window %.2fs on %s"):format(n.time or 1, subject.Name))
	cast:spawn(function()
		cast:wait(n.time or 1)
		if counters[subject] == entry then
			counters[subject] = nil
		end
	end)
	cast:onCleanup(function()
		if counters[subject] == entry then
			counters[subject] = nil
		end
	end)
end

H.Heal = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		return
	end
	local amount = n.amount or 10
	if n.percent then
		local hum = Rig.humanoid(subject)
		amount = hum and hum.MaxHealth * amount / 100 or 0
	end
	cast.adapter.heal(subject, amount)
	cast:log(n, "info", ("healed %s for %.1f"):format(subject.Name, amount))
end

H.Meter = function(cast, n, cursor)
	local subject = modelOf(cast:resolve(n.subject))
	if not subject then
		return
	end
	local before = cast.adapter.getMeter(subject, n.meter) or 0
	local v = n.op == "Set" and (n.value or 0) or before + (n.op == "Subtract" and -(n.value or 0) or (n.value or 0))
	cast.adapter.setMeter(subject, n.meter, v)
	cast:log(n, "info", ("meter %s on %s: %s -> %s"):format(tostring(n.meter), subject.Name, tostring(before), tostring(v)))
end

-- curves used by visuals are evaluated on clients; register custom ones on both sides (Registry / Curves.register)
Nodes.Curves = Curves

return Nodes
