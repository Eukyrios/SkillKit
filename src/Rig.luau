--!strict
-- Rig helpers: find a character's parts, and map logical joint names (used by keyframe data) to the joints of an
-- R15 or R6 rig (Motor6Ds, or AnimationConstraints on Roblox's newer avatars).
-- Keyframe rotations are authored in TORSO space (X right, Y up, -Z forward) for every joint; Rig.toTransform
-- converts them into each joint's own frame, so one animation drives R15 and R6 alike.
local Rig = {}

Rig.Joints = { "Root", "Waist", "Neck", "RightArm", "RightForearm", "LeftArm", "LeftForearm", "RightLeg", "RightShin", "LeftLeg", "LeftShin" }

local R15 = {
	Root = "Root", Waist = "Waist", Neck = "Neck",
	RightArm = "RightShoulder", RightForearm = "RightElbow", LeftArm = "LeftShoulder", LeftForearm = "LeftElbow",
	RightLeg = "RightHip", RightShin = "RightKnee", LeftLeg = "LeftHip", LeftShin = "LeftKnee",
}
local R6 = {
	Root = "RootJoint", Neck = "Neck",
	RightArm = "Right Shoulder", LeftArm = "Left Shoulder", RightLeg = "Right Hip", LeftLeg = "Left Hip",
}
Rig.Mirror = {
	RightArm = "LeftArm", LeftArm = "RightArm", RightForearm = "LeftForearm", LeftForearm = "RightForearm",
	RightLeg = "LeftLeg", LeftLeg = "RightLeg", RightShin = "LeftShin", LeftShin = "RightShin",
}

function Rig.humanoid(model: Instance?): Humanoid?
	return model and model:FindFirstChildOfClass("Humanoid") or nil
end

function Rig.root(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	return nil
end

function Rig.part(model: Model, which: string): BasePart?
	local names = ({
		HRP = { "HumanoidRootPart" },
		Torso = { "UpperTorso", "Torso" },
		Head = { "Head" },
		RightHand = { "RightHand", "Right Arm" },
		LeftHand = { "LeftHand", "Left Arm" },
	} :: any)[which] or { which }
	for _, n in ipairs(names) do
		local p = model:FindFirstChild(n, true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return Rig.root(model)
end

-- the owning character model of any descendant (nil if none)
function Rig.modelOf(inst: Instance): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return m
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Rig.alive(model: Instance?): boolean
	local h = Rig.humanoid(model)
	return h ~= nil and h.Health > 0 and model ~= nil and model.Parent ~= nil
end

-- a joint the animator drives: a Motor6D, or an AnimationConstraint (Roblox's newer avatar joints). Both have
-- a Transform; the joint's own frame is Motor6D.C0 or AnimationConstraint.Attachment0.CFrame.
export type Joint = Motor6D | AnimationConstraint
function Rig.isJoint(d: Instance): boolean
	return d:IsA("Motor6D") or d:IsA("AnimationConstraint")
end

-- logical joint name -> joint on this character (cached per model; rebuilt if a joint went away)
local cache: { [Model]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
function Rig.motors(model: Model): { [string]: any }
	local c = cache[model]
	if c then
		local stale = next(c) == nil
		for _, j in pairs(c) do
			if not j.Parent then
				stale = true
				break
			end
		end
		if not stale then
			return c
		end
	end
	c = {}
	local hum = Rig.humanoid(model)
	local map = hum and hum.RigType == Enum.HumanoidRigType.R6 and R6 or R15
	local byName: { [string]: any } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			byName[d.Name] = d -- preferred over a leftover Motor6D of the same name
		elseif d:IsA("Motor6D") and not byName[d.Name] then
			byName[d.Name] = d
		end
	end
	for logical, real in pairs(map) do
		if byName[real] then
			c[logical] = byName[real]
		end
	end
	cache[model] = c
	return c
end

-- a torso-space pose (CFrame) -> this joint's Transform
function Rig.toTransform(joint: any, pose: CFrame): CFrame
	local frame: CFrame
	if joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		frame = a0 and a0.CFrame or CFrame.identity
	else
		frame = joint.C0
	end
	local r = frame - frame.Position
	return r:Inverse() * pose * r
end

-- pose an anchored rig from its joints' Transforms (Edit mode / no physics): every part is placed from its parent part
-- through the joint, starting at the HumanoidRootPart
function Rig.solveFK(model: Model)
	local root = Rig.root(model)
	if not root then
		return
	end
	local children: { [BasePart]: { any } } = {}
	for _, j in ipairs(model:GetDescendants()) do
		local p0: BasePart?
		if j:IsA("AnimationConstraint") then
			p0 = j.Attachment0 and j.Attachment0.Parent :: any
		elseif j:IsA("Motor6D") then
			p0 = j.Part0
		end
		if p0 then
			children[p0] = children[p0] or {}
			table.insert(children[p0], j)
		end
	end
	local queue = { root }
	local seen: { [BasePart]: boolean } = { [root] = true }
	while #queue > 0 do
		local part = table.remove(queue, 1) :: BasePart
		for _, j in ipairs(children[part] or {}) do
			local child: BasePart?, cf: CFrame?
			if j:IsA("AnimationConstraint") then
				local a0, a1 = j.Attachment0, j.Attachment1
				child = a1 and a1.Parent :: any
				if child and a0 and a1 then
					cf = part.CFrame * a0.CFrame * j.Transform * a1.CFrame:Inverse()
				end
			else
				child = j.Part1
				if child then
					cf = part.CFrame * j.C0 * j.Transform * j.C1:Inverse()
				end
			end
			if child and cf and not seen[child] then
				seen[child] = true
				child.CFrame = cf
				table.insert(queue, child)
			end
		end
	end
end

return Rig
