--!strict
-- Spatial queries for hitboxes: a box, a sphere or a cylinder (along its local X, Roblox's cylinder axis; rotate it to
-- point it). Returns the character models inside, nearest first.
local Workspace = game:GetService("Workspace")

local Rig = require(script.Parent.Parent.Rig)

local Hitbox = {}

local probe: Part? = nil
local function probePart(): Part
	if probe and probe.Parent then
		return probe
	end
	local p = Instance.new("Part")
	p.Name = "SkillKitProbe"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Shape = Enum.PartType.Cylinder
	p.Parent = Workspace
	probe = p
	return p
end

function Hitbox.query(cf: CFrame, size: Vector3, shape: string?, params: OverlapParams): { Model }
	local parts: { BasePart }
	if shape == "Sphere" then
		parts = Workspace:GetPartBoundsInRadius(cf.Position, math.max(size.X, size.Y, size.Z) / 2, params)
	elseif shape == "Cylinder" then
		local p = probePart()
		p.Size = size
		p.CFrame = cf
		parts = Workspace:GetPartsInPart(p, params)
	else
		parts = Workspace:GetPartBoundsInBox(cf, size, params)
	end
	local seen: { [Model]: boolean } = {}
	local out: { Model } = {}
	for _, part in ipairs(parts) do
		local m = Rig.modelOf(part)
		if m and not seen[m] then
			seen[m] = true
			table.insert(out, m)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Rig.root(a), Rig.root(b)
		local da = ra and (ra.Position - cf.Position).Magnitude or math.huge
		local db = rb and (rb.Position - cf.Position).Magnitude or math.huge
		return da < db
	end)
	return out
end

-- the box's frame for a node on a cast: attach part * offset * rotation
function Hitbox.frame(base: CFrame, position: Vector3?, rotation: Vector3?): CFrame
	local p = position or Vector3.zero
	local r = rotation or Vector3.zero
	local cf = base + base.RightVector * p.X + base.UpVector * p.Y + base.LookVector * p.Z
	return cf * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

-- is `victim` facing the attack (for blocking)? within 100 degrees of facing the attacker
function Hitbox.facing(victim: Model, from: Vector3): boolean
	local r = Rig.root(victim)
	if not r then
		return false
	end
	local to = (from - r.Position) * Vector3.new(1, 0, 1)
	if to.Magnitude < 0.01 then
		return true
	end
	return r.CFrame.LookVector:Dot(to.Unit) > math.cos(math.rad(100))
end

return Hitbox
