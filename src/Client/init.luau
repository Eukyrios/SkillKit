--!strict
-- SkillKit client: receives the server's presentation and own-character messages.
-- Messages (kind, payload):
--   Anim / AnimStop                 play a Roblox animation on your own character (replicates to everyone)
--   Keyframes / KeyframesStop       keyframe animation on any character (local, every client)
--   Sound, Vfx, HitboxShow, HitFlash
--   Projectile / ProjectileSync / ProjectileEnd
--   Motion / MotionStop / Push / Teleport / Lock / Anchor   your own character's physics (you own it)
--   Freeze                          hold a character's pose (State: Body)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(script.Parent.Motion)
local Net = require(script.Parent.Net)
local Registry = require(script.Parent.Registry)
local Rig = require(script.Parent.Rig)
local Fx = require(script.Fx)
local KeyframePlayer = require(script.KeyframePlayer)

local Client = {}
Client.Keyframes = KeyframePlayer
Client.Fx = Fx

local player = Players.LocalPlayer
local started = false

local animTracks: { [number]: { AnimationTrack } } = {}
local keyframeHandles: { [number]: { any } } = {}
local motionStops: { [number]: { () -> () } } = {}

local function myRoot(): BasePart?
	return Rig.root(player.Character)
end

local handlers: { [string]: (any) -> () } = {}

handlers.Anim = function(p)
	local model = p.model
	local n = p.node
	local hum = Rig.humanoid(model)
	if not hum then
		return
	end
	-- keyframe data under that name? play it locally (server sent "Anim" because it's the owner's character)
	if Registry.get("keyframes", n.anim) then
		handlers.Keyframes(p)
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local r6 = hum.RigType == Enum.HumanoidRigType.R6
	local entry = Registry.get("animation", n.anim)
	local id = Registry.id("animation", r6 and entry and entry.r6 or n.anim, r6 and entry and entry.r6 and "r6" or nil)
	if not id then
		return
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(a)
	end)
	if not ok or not track then
		return
	end
	track.Priority = (Enum.AnimationPriority :: any)[n.priority or "Action"] or Enum.AnimationPriority.Action
	track.Looped = n.looped == true
	track:Play(n.fadeIn or 0.1, n.weight or 1, n.speed or 1)
	animTracks[p.castId] = animTracks[p.castId] or {}
	table.insert(animTracks[p.castId], track)
	if (n.stopAfter or 0) > 0 then
		task.delay(n.stopAfter, function()
			track:Stop(n.fadeOut or 0.15)
		end)
	end
end
handlers.AnimStop = function(p)
	for _, t in ipairs(animTracks[p.castId] or {}) do
		t:Stop(0.15)
	end
	animTracks[p.castId] = nil
	handlers.KeyframesStop(p)
end

handlers.Keyframes = function(p)
	local model = p.model
	local n = p.node
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local anim = type(n.anim) == "table" and n.anim or Registry.get("keyframes", n.anim)
	if not anim then
		return
	end
	if n.mirror then
		anim = KeyframePlayer.mirror(anim)
	end
	local h = KeyframePlayer.play(model, anim, { speed = n.speed, weight = n.weight, looped = n.looped })
	keyframeHandles[p.castId] = keyframeHandles[p.castId] or {}
	table.insert(keyframeHandles[p.castId], h)
end
handlers.KeyframesStop = function(p)
	for _, h in ipairs(keyframeHandles[p.castId] or {}) do
		h:stop()
	end
	keyframeHandles[p.castId] = nil
	Fx.stopCast(p.castId)
end

handlers.Sound = function(p)
	Fx.sound(p.node, p)
end
handlers.Vfx = function(p)
	local k = p.kind
	if k == "PresetVFX" then
		Fx.preset(p.node, p)
	elseif k == "Particle" then
		Fx.particle(p.node, p)
	elseif k == "MeshVisual" then
		Fx.mesh(p.node, p)
	elseif k == "Highlight" then
		Fx.highlight(p.node, p)
	end
end
handlers.HitboxShow = Fx.hitbox
handlers.HitFlash = Fx.hitFlash
handlers.Projectile = Fx.projectile
handlers.ProjectileSync = Fx.projectileSync
handlers.ProjectileEnd = Fx.projectileEnd

-- own character physics -------------------------------------------------------------------------------------------------
handlers.Motion = function(p)
	local root = myRoot()
	if not root then
		return
	end
	local stop
	if p.kind == "velocity" then
		stop = Motion.velocity(root, p.spec)
	elseif p.kind == "travel" then
		stop = Motion.travelUntilDone(root, p.spec, p.target, nil)
	end
	if stop then
		motionStops[p.castId] = motionStops[p.castId] or {}
		table.insert(motionStops[p.castId], stop)
	end
end
handlers.MotionStop = function(p)
	for _, stop in ipairs(motionStops[p.castId] or {}) do
		stop()
	end
	motionStops[p.castId] = nil
end
handlers.Push = function(p)
	local root = myRoot()
	if root then
		Motion.push(root, p.velocity, p.time)
	end
end
handlers.Teleport = function(p)
	local c = player.Character
	local root = myRoot()
	if c and root then
		local v = root.AssemblyLinearVelocity
		c:PivotTo(p.cf)
		root.AssemblyLinearVelocity = p.keepVelocity and v or Vector3.zero
	end
end
handlers.Anchor = function(p)
	local root = myRoot()
	if root then
		root.Anchored = true
		task.delay(p.duration or 0.5, function()
			if root.Parent then
				root.Anchored = false
			end
		end)
	end
end
handlers.Lock = function(p)
	local root = myRoot()
	local hum = Rig.humanoid(player.Character)
	if not root or not hum then
		return
	end
	local t0 = os.clock()
	local yaw = p.yaw or 0
	if p.direction then
		hum.AutoRotate = false
	end
	local name = "SkillKitLock" .. tostring(t0)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		if os.clock() - t0 > (p.duration or 1) or not root.Parent then
			RunService:UnbindFromRenderStep(name)
			if hum.Parent then
				hum.AutoRotate = true
			end
			return
		end
		if p.direction then
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
		end
		if p.camera then
			local cam = Workspace.CurrentCamera
			local dist = (cam.CFrame.Position - cam.Focus.Position).Magnitude
			local back = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-15), 0, 0)
			cam.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0)) * back * CFrame.new(0, 0, math.max(dist, 10))
		end
	end)
end
handlers.Freeze = function(p)
	if typeof(p.model) == "Instance" and p.model.Parent then
		KeyframePlayer.freeze(p.model, p.duration or 0.5)
	end
end

function Client.init()
	if started then
		return Client
	end
	started = true
	Net.remote().OnClientEvent:Connect(function(kind, payload)
		local h = handlers[kind]
		if h then
			local ok, err = pcall(h, payload)
			if not ok then
				warn("[SkillKit] client " .. tostring(kind) .. ": " .. tostring(err))
			end
		end
	end)
	return Client
end

return Client
