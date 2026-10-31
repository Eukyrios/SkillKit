--!strict
-- Server-simulated projectiles: raycast each step (no physics parts), optional gravity, speed curve, homing, stick,
-- pierce. Clients draw them from the same spawn data; position corrections are sent for homing ones.
--   Projectile.fire(cast, node, origin: CFrame, aim: Vector3, onHit(model, position), onEnd(reason)) -> proj
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Curves = require(script.Parent.Parent.Curves)
local Net = require(script.Parent.Parent.Net)
local Rig = require(script.Parent.Parent.Rig)

local Projectile = {}

local nextId = 0
local live: { [number]: any } = {}

function Projectile.fire(cast: any, node: any, origin: CFrame, aim: Vector3, target: Model?, onHit: (Model, Vector3) -> (), onEnd: (string, Vector3) -> ())
	nextId += 1
	local id = nextId
	local rng = Random.new(cast.seed + id)
	local homing = node.homing
	local homes = homing and rng:NextNumber() <= (homing.chance or 1)
	local proj = {
		id = id,
		pos = origin.Position,
		dir = aim.Unit,
		fall = 0,
		vel = aim.Unit * (node.speed or 80),
		t = 0,
		travelled = 0,
		hitSet = {} :: { [Model]: boolean },
		done = false,
		target = homes and target or nil,
		part = nil :: BasePart?,
	}
	-- a hidden anchor part so other nodes can follow it (Teleport to projectile, attach a hitbox / visual)
	local anchor = Instance.new("Part")
	anchor.Name = "SkillKitProjectile"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.lookAt(proj.pos, proj.pos + aim)
	anchor.Parent = Workspace
	proj.part = anchor
	if node.projectileTag then
		cast.projectiles[node.projectileTag] = proj
	end
	Net.all("Projectile", {
		id = id,
		castId = cast.id,
		node = node,
		origin = origin.Position,
		aim = aim.Unit,
		target = proj.target,
		homes = homes,
		t0 = workspace:GetServerTimeNow(),
	})
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cast.user, anchor, Workspace:FindFirstChild("SkillKitDebris") :: any }
	local radius = node.radius or 2
	local lifetime = node.lifetime or 3
	local range = node.range or 0
	local function finish(reason: string)
		if proj.done then
			return
		end
		proj.done = true
		live[id] = nil
		Net.all("ProjectileEnd", { id = id, pos = proj.pos, reason = reason })
		local stick = (reason == "hit" or reason == "wall") and (node.stick or 0) or 0
		task.delay(stick, function()
			anchor:Destroy()
		end)
		onEnd(reason, proj.pos)
	end
	live[id] = proj
	local lastSync = 0
	cast:spawn(function()
		while not proj.done do
			local dt = RunService.Heartbeat:Wait()
			if not cast.alive and not node.outlive then
				finish("cancelled")
				break
			end
			proj.t += dt
			if proj.t >= lifetime then
				finish("timeout")
				break
			end
			-- homing
			if proj.target and homing and proj.t >= (homing.delay or 0) and Rig.alive(proj.target) then
				local r = Rig.root(proj.target)
				if r and (r.Position - proj.pos).Magnitude <= (homing.range or 60) then
					local want = (r.Position - proj.pos).Unit
					local k = math.clamp((homing.turnSpeed or 6) * dt, 0, 1)
					local d = proj.dir:Lerp(want, k)
					proj.dir = d.Magnitude > 0 and d.Unit or want
					proj.fall = 0
				end
			end
			local speedMul = Curves.mult(node.speedCurve, proj.t / lifetime)
			local base = node.speed or 80
			proj.fall += (node.gravity or 0) * dt
			proj.vel = proj.dir * base * speedMul - Vector3.new(0, proj.fall, 0)
			local dir = proj.vel.Magnitude > 0 and proj.vel.Unit or proj.dir
			local step = proj.vel * dt
			-- the world
			local wall = step.Magnitude > 0 and Workspace:Raycast(proj.pos, step, params)
			-- targets along the step
			local mid = proj.pos + step / 2
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = { cast.user, anchor }
			local stopped = false
			for _, part in ipairs(Workspace:GetPartBoundsInRadius(mid, radius + step.Magnitude / 2, op)) do
				local m = Rig.modelOf(part)
				if m and not proj.hitSet[m] and m ~= cast.user and cast.adapter.canHit(cast.user, m) then
					proj.hitSet[m] = true
					onHit(m, mid)
					if not node.pierce then
						proj.pos = mid
						anchor.CFrame = CFrame.lookAt(mid, mid + dir)
						finish("hit")
						stopped = true
						break
					end
				end
			end
			if stopped then
				break
			end
			if wall then
				proj.pos = wall.Position
				anchor.CFrame = CFrame.lookAt(proj.pos, proj.pos + dir)
				finish("wall")
				break
			end
			proj.pos += step
			proj.travelled += step.Magnitude
			anchor.CFrame = CFrame.lookAt(proj.pos, proj.pos + dir)
			if range > 0 and proj.travelled >= range then
				finish("range")
				break
			end
			if proj.target and os.clock() - lastSync > 0.1 then
				lastSync = os.clock()
				Net.all("ProjectileSync", { id = id, pos = proj.pos, vel = proj.vel })
			end
		end
	end)
	return proj
end

return Projectile
