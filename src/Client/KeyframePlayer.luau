--!strict
-- Plays keyframe animations (Presets/Keyframes format) by writing each joint's Transform after Roblox's animator each
-- frame. Local only: every client runs it for every character (the server broadcasts "Keyframes").
--   KeyframePlayer.play(model, anim, { speed?, weight?, looped? }) -> handle { stop(), finished: boolean }
--   KeyframePlayer.sample(anim, joint, t) -> CFrame        (torso-space pose; for tests and tools)
--   KeyframePlayer.mirror(anim) -> anim                    swaps left/right and flips the sideways axes
--   KeyframePlayer.freeze(model, seconds)                  holds the current pose (State: Body)
-- Easing between keys: "auto" (default) = Catmull-Rom through the neighbours; any curve name = that curve.
-- fps quantises time: 24/30 give a stepped anime look, 60 is smooth.
local RunService = game:GetService("RunService")

local Curves = require(script.Parent.Parent.Curves)
local Rig = require(script.Parent.Parent.Rig)

local KeyframePlayer = {}

type Key = { t: number, r: Vector3?, p: Vector3?, ease: any? }

local function catmull(p0: number, p1: number, p2: number, p3: number, u: number): number
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
end
local function catmullV(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: number): Vector3
	return Vector3.new(catmull(a.X, b.X, c.X, d.X, u), catmull(a.Y, b.Y, c.Y, d.Y, u), catmull(a.Z, b.Z, c.Z, d.Z, u))
end

-- the pose of one joint at time t (seconds), torso space
function KeyframePlayer.sample(anim: any, joint: string, t: number): CFrame
	local keys: { Key }? = anim.joints[joint]
	if not keys or #keys == 0 then
		return CFrame.identity
	end
	local function rot(k: Key): Vector3
		return k.r or Vector3.zero
	end
	local function pos(k: Key): Vector3
		return k.p or Vector3.zero
	end
	local r: Vector3, p: Vector3
	if t <= keys[1].t then
		r, p = rot(keys[1]), pos(keys[1])
	elseif t >= keys[#keys].t then
		r, p = rot(keys[#keys]), pos(keys[#keys])
	else
		r, p = Vector3.zero, Vector3.zero
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if t >= a.t and t <= b.t then
				local u = (b.t - a.t) > 0 and (t - a.t) / (b.t - a.t) or 1
				local ease = b.ease or a.ease or anim.ease or "auto"
				if ease == "auto" then
					local k0 = keys[i - 1] or a
					local k3 = keys[i + 2] or b
					r = catmullV(rot(k0), rot(a), rot(b), rot(k3), u)
					p = catmullV(pos(k0), pos(a), pos(b), pos(k3), u)
				else
					local e = Curves.ease(ease, u)
					r = rot(a):Lerp(rot(b), e)
					p = pos(a):Lerp(pos(b), e)
				end
				break
			end
		end
	end
	return CFrame.new(p) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

function KeyframePlayer.mirror(anim: any): any
	local out = table.clone(anim)
	out.joints = {}
	for joint, keys in pairs(anim.joints) do
		local other = Rig.Mirror[joint] or joint
		local list = {}
		for _, k in ipairs(keys) do
			local r = k.r or Vector3.zero
			local p = k.p or Vector3.zero
			table.insert(list, { t = k.t, r = Vector3.new(r.X, -r.Y, -r.Z), p = Vector3.new(-p.X, p.Y, p.Z), ease = k.ease })
		end
		out.joints[other] = list
	end
	return out
end

-- playing ---------------------------------------------------------------------------------------------------------------
type Handle = { model: Model, anim: any, t: number, speed: number, weight: number, looped: boolean, stopped: boolean, finished: boolean, fadeOut: number, stop: (any) -> () }
local playing: { Handle } = {}
local frozen: { [Model]: { untilT: number, pose: { [any]: CFrame } } } = {}

function KeyframePlayer.play(model: Model, anim: any, opts: any?): Handle
	opts = opts or {}
	local h: Handle
	h = {
		model = model,
		anim = anim,
		t = 0,
		speed = opts.speed or 1,
		weight = opts.weight or 1,
		looped = opts.looped == true or anim.looped == true,
		stopped = false,
		finished = false,
		fadeOut = 0,
		stop = function(self)
			self.stopped = true
		end,
	}
	-- one keyframe animation per model at a time: the new one replaces the old
	for _, other in ipairs(playing) do
		if other.model == model then
			other.stopped = true
		end
	end
	table.insert(playing, h)
	return h
end

function KeyframePlayer.stopModel(model: Model)
	for _, h in ipairs(playing) do
		if h.model == model then
			h.stopped = true
		end
	end
end

function KeyframePlayer.freeze(model: Model, seconds: number)
	local pose = {}
	for _, m in ipairs(model:GetDescendants()) do
		if Rig.isJoint(m) then
			pose[m] = (m :: any).Transform
		end
	end
	frozen[model] = { untilT = os.clock() + seconds, pose = pose }
	local hum = Rig.humanoid(model)
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
			tr:AdjustSpeed(0)
			task.delay(seconds, function()
				tr:AdjustSpeed(1)
			end)
		end
	end
end

-- give the joints back (rigs without an Animate script would otherwise keep the last pose)
local function release(h: Handle)
	if not h.model.Parent then
		return
	end
	for _, other in ipairs(playing) do
		if other ~= h and other.model == h.model and not other.stopped then
			return
		end
	end
	local motors = Rig.motors(h.model)
	for joint in pairs(h.anim.joints) do
		local m = motors[joint]
		if m then
			m.Transform = CFrame.identity
		end
	end
end

-- rigs posed by forward kinematics (anchored preview rigs in Edit mode, where joints don't move parts)
KeyframePlayer.fkModels = setmetatable({}, { __mode = "k" }) :: { [Model]: boolean }

local function step(dt: number)
	local now = os.clock()
	for i = #playing, 1, -1 do
		local h = playing[i]
		if h.stopped or not h.model.Parent then
			table.remove(playing, i)
			release(h)
			continue
		end
		local anim = h.anim
		h.t += dt * h.speed
		local duration = anim.duration or 1
		if h.t >= duration then
			if h.looped then
				h.t %= duration
			elseif anim.hold then
				h.t = duration
			else
				h.finished = true
				table.remove(playing, i)
				release(h)
				continue
			end
		end
		-- quantise to the animation's frame rate
		local fps = anim.fps or 60
		local t = math.floor(h.t * fps + 0.5) / fps
		local motors = Rig.motors(h.model)
		for joint in pairs(anim.joints) do
			local motor = motors[joint]
			if motor then
				local pose = KeyframePlayer.sample(anim, joint, t)
				local target = Rig.toTransform(motor, pose)
				motor.Transform = h.weight >= 1 and target or motor.Transform:Lerp(target, h.weight)
			end
		end
	end
	for model, f in pairs(frozen) do
		if now > f.untilT or not model.Parent then
			frozen[model] = nil
		else
			for m, cf in pairs(f.pose) do
				m.Transform = cf
			end
		end
	end
	for model in pairs(KeyframePlayer.fkModels) do
		if model.Parent then
			Rig.solveFK(model)
		end
	end
end

if RunService:IsRunning() then
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
else
	RunService.Heartbeat:Connect(step)
end
KeyframePlayer.step = step

return KeyframePlayer
