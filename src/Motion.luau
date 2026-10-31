--!strict
-- The motion solver, shared by the server (NPCs, dummies) and each client (its own character, which it simulates).
-- Every motion is a LinearVelocity on the root's attachment, driven each frame and removed when done.
--   Motion.velocity(root, spec) -> stop()   spec: direction (Vector3), speed, space Local|World, time, fade, holdHeight,
--                                            track (re-aim along the look every frame)
--   Motion.travel(root, spec, target) -> stop()   target: Model | BasePart | Vector3 (moves to it in spec.time)
--   Motion.push(root, velocity, time) -> stop()    a short knockback
--   Motion.onFinished: optional callback(spec, result) per motion ("arrived" | "timeout" | "wall" | "inside" | "stopped")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Curves = require(script.Parent.Curves)

local Motion = {}

local function attachmentOf(root: BasePart): Attachment
	local a = root:FindFirstChild("SkillKitMotion")
	if a and a:IsA("Attachment") then
		return a
	end
	local n = Instance.new("Attachment")
	n.Name = "SkillKitMotion"
	n.Parent = root
	return n
end

local function makeVelocity(root: BasePart, allAxes: boolean): LinearVelocity
	-- the newest motion wins: two LinearVelocities on one part fight each other
	for _, old in ipairs(root:GetChildren()) do
		if old.Name == "SkillKitVelocity" and old:IsA("LinearVelocity") then
			old:Destroy()
		end
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SkillKitVelocity"
	lv.Attachment0 = attachmentOf(root)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitsEnabled = true
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	local big = 1e6
	lv.MaxAxesForce = Vector3.new(big, allAxes and big or 0, big)
	lv.Parent = root
	return lv
end

local function run(root: BasePart, lv: LinearVelocity, duration: number, step: (number, number) -> (Vector3?, string?)): () -> ()
	local t0 = os.clock()
	local conn: RBXScriptConnection
	local done = false
	local function stop()
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
		end
		lv:Destroy()
	end
	conn = RunService.Heartbeat:Connect(function(dt)
		if not root.Parent then
			stop()
			return
		end
		local t = os.clock() - t0
		if t >= duration then
			stop()
			return
		end
		local v, finished = step(t, dt)
		if finished then
			stop()
			return
		end
		if v then
			lv.VectorVelocity = v
		end
	end)
	return stop
end

function Motion.velocity(root: BasePart, spec: any): () -> ()
	local dir: Vector3 = spec.direction or Vector3.new(0, 0, 1)
	local function worldDir(): Vector3
		if spec.space == "World" then
			return dir
		end
		local cf = root.CFrame
		return cf.RightVector * dir.X + cf.UpVector * dir.Y + cf.LookVector * dir.Z
	end
	local fixed = worldDir()
	local vertical = spec.holdHeight or math.abs(fixed.Y) > 0.01
	local lv = makeVelocity(root, vertical)
	local speed = spec.speed or 50
	local duration = math.max(spec.time or 0.3, 0.03)
	if spec.holdHeight then
		local a = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(a.X, 0, a.Z)
	end
	return run(root, lv, duration, function(t)
		local d = spec.track and worldDir() or fixed
		if d.Magnitude > 0 then
			d = d.Unit
		end
		local v = d * speed * Curves.mult(spec.fade, t / duration)
		if spec.holdHeight then
			v = Vector3.new(v.X, 0, v.Z)
		end
		return v
	end)
end

function Motion.push(root: BasePart, velocity: Vector3, time: number?): () -> ()
	local lv = makeVelocity(root, true)
	local duration = time or 0.2
	return run(root, lv, duration, function(t)
		return velocity * (1 - t / duration)
	end)
end

local function targetPos(target: any): Vector3?
	if typeof(target) == "Vector3" then
		return target
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position
		elseif target:IsA("Model") then
			local r = target:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				return r.Position
			end
			return (target :: Model):GetPivot().Position
		end
	end
	return nil
end

function Motion.travel(root: BasePart, spec: any, target: any, onEnd: ((string) -> ())?): () -> ()
	local start = root.Position
	local goal0 = targetPos(target)
	if not goal0 then
		if onEnd then
			onEnd("no_target")
		end
		return function() end
	end
	local stopDist = spec.stopDistance or 4
	if ((goal0 - start) * Vector3.new(1, 0, 1)).Magnitude <= stopDist then
		if onEnd then
			onEnd("inside")
		end
		return function() end
	end
	local duration = math.max(spec.time or 0.3, 0.05)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { root.Parent :: Instance }
	if typeof(target) == "Instance" then
		table.insert(ignore, target)
	end
	params.FilterDescendantsInstances = ignore
	local result = "timeout"
	local lv = makeVelocity(root, true)
	local savedCollide: { [BasePart]: boolean } = {}
	if spec.collision == false and root.Parent then
		for _, p in ipairs((root.Parent :: Instance):GetDescendants()) do
			if p:IsA("BasePart") then
				savedCollide[p] = p.CanCollide
				p.CanCollide = false
			end
		end
	end
	local function endPoint(): Vector3
		local g = (spec.follow ~= false and targetPos(target)) or goal0 :: Vector3
		local flat = (g - start) * Vector3.new(1, 0, 1)
		local back = flat.Magnitude > 0.01 and flat.Unit * stopDist or Vector3.zero
		return g - back + Vector3.new(0, spec.height or 0, 0)
	end
	local stopper = run(root, lv, duration + 0.05, function(t, dt)
		local u = math.clamp(t / duration, 0, 1)
		local e = Curves.ease(spec.curve, u)
		local goal = endPoint()
		local desired = start:Lerp(goal, e) + Vector3.new(0, (spec.arc or 0) * math.sin(math.pi * u), 0)
		local toGoal = (goal - root.Position) * Vector3.new(1, 0, 1)
		if toGoal.Magnitude < 1 or u >= 1 then
			result = "arrived"
			return nil, "done"
		end
		local v = (desired - root.Position) / math.max(dt, 1 / 60)
		if v.Magnitude > 400 then
			v = v.Unit * 400
		end
		if spec.wallStop ~= false and v.Magnitude > 1 then
			local ahead = Workspace:Raycast(root.Position, v.Unit * 3, params)
			if ahead and ahead.Instance.CanCollide and ahead.Normal.Y < 0.5 then
				result = "wall"
				return nil, "done"
			end
		end
		return v
	end)
	return function()
		stopper()
		for p, c in pairs(savedCollide) do
			if p.Parent then
				p.CanCollide = c
			end
		end
		if onEnd then
			onEnd(result)
			onEnd = nil
		end
	end
end

-- calls stop() when the motion's own timer ends too (travel needs its onEnd)
function Motion.travelUntilDone(root: BasePart, spec: any, target: any, onEnd: ((string) -> ())?): () -> ()
	local stop
	stop = Motion.travel(root, spec, target, onEnd)
	task.delay(math.max(spec.time or 0.3, 0.05) + 0.1, function()
		stop()
	end)
	return stop
end

return Motion
