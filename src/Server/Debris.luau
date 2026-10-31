--!strict
-- Destruction: parts tagged SkillKitBreakable (or a node's own tags) inside a box break into pieces that fly off,
-- settle (anchor) after a while, vanish after their lifetime, and the original comes back after rebuildAfter.
-- The original is hidden and restored, never destroyed.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Debris = {}
Debris.DefaultTag = "SkillKitBreakable"

local folder: Folder? = nil
local function pieceFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "SkillKitDebris"
	f.Parent = Workspace
	folder = f
	return f
end

local broken: { [BasePart]: boolean } = {}

local function hide(part: BasePart)
	part:SetAttribute("SK_T", part.Transparency)
	part:SetAttribute("SK_C", part.CanCollide)
	part:SetAttribute("SK_Q", part.CanQuery)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			d:SetAttribute("SK_T", d.Transparency)
			d.Transparency = 1
		end
	end
end

local function restore(part: BasePart)
	if not part.Parent then
		return
	end
	part.Transparency = part:GetAttribute("SK_T") or 0
	part.CanCollide = part:GetAttribute("SK_C") ~= false
	part.CanQuery = part:GetAttribute("SK_Q") ~= false
	for _, d in ipairs(part:GetDescendants()) do
		if (d:IsA("Decal") or d:IsA("Texture")) and d:GetAttribute("SK_T") ~= nil then
			d.Transparency = d:GetAttribute("SK_T")
		end
	end
	broken[part] = nil
end

-- break parts in a box. center: where the force comes from. Returns the number of parts broken.
function Debris.breakIn(cf: CFrame, size: Vector3, spec: any, center: Vector3, ignore: { Instance }): number
	local tags = spec.tags or { Debris.DefaultTag }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local n = 0
	local rng = Random.new()
	for _, part in ipairs(Workspace:GetPartBoundsInBox(cf, size, params)) do
		if broken[part] then
			continue
		end
		local ok = false
		for _, t in ipairs(tags) do
			if CollectionService:HasTag(part, t) or (part.Parent and CollectionService:HasTag(part.Parent, t)) then
				ok = true
				break
			end
		end
		if not ok then
			continue
		end
		broken[part] = true
		n += 1
		hide(part)
		local count = math.clamp(spec.count or 5, 1, 30)
		local pieceSize = part.Size / math.max(1, count ^ (1 / 3))
		local pieces = {}
		for i = 1, count do
			local p = Instance.new("Part")
			p.Name = "Piece"
			p.Size = Vector3.new(
				math.max(0.3, pieceSize.X * rng:NextNumber(0.6, 1.2)),
				math.max(0.3, pieceSize.Y * rng:NextNumber(0.6, 1.2)),
				math.max(0.3, pieceSize.Z * rng:NextNumber(0.6, 1.2))
			)
			p.Color = part.Color
			p.Material = part.Material
			local local3 = Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5)) * part.Size
			p.CFrame = part.CFrame * CFrame.new(local3) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
			p.CanCollide = spec.canCollide ~= false
			p.CollisionGroup = spec.canCollide == false and "SkillKitGhost" or "Default"
			p.Parent = pieceFolder()
			local away = p.Position - center
			if spec.type == "Line" then
				away = cf.LookVector + Vector3.new(0, 0.4, 0)
			elseif away.Magnitude < 0.1 then
				away = Vector3.new(0, 1, 0)
			end
			local dir = (away.Unit + Vector3.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0.2, 0.8), rng:NextNumber(-0.3, 0.3))).Unit
			p:ApplyImpulse(dir * (spec.force or 40) * p.AssemblyMass)
			p:ApplyAngularImpulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * p.AssemblyMass * 4)
			table.insert(pieces, p)
		end
		local settle = spec.settleAfter or 0
		if settle > 0 then
			task.delay(settle, function()
				for _, p in ipairs(pieces) do
					if p.Parent then
						p.Anchored = true
					end
				end
			end)
		end
		task.delay(spec.lifetime or 3, function()
			for _, p in ipairs(pieces) do
				p:Destroy()
			end
		end)
		task.delay(math.max(spec.rebuildAfter or 30, spec.lifetime or 3), function()
			restore(part)
		end)
	end
	return n
end

-- restore everything now (tests, round resets)
function Debris.rebuildAll()
	for part in pairs(broken) do
		restore(part)
	end
end

return Debris
