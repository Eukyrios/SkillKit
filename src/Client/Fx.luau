--!strict
-- Client presentation: preset VFX, particles, mesh visuals, highlights, sounds, projectile visuals, debug hitboxes.
-- Everything is parented to one folder, owned by a cast, capped (MAX_LIVE) and culled by distance.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Curves = require(script.Parent.Parent.Curves)
local Registry = require(script.Parent.Parent.Registry)
local Rig = require(script.Parent.Parent.Rig)

local Fx = {}
Fx.MAX_LIVE = 300
Fx.CULL = 400

local player = Players.LocalPlayer
-- outside a game (the SkillKit editor plugin) there is no LocalPlayer and RenderStepped is unreliable in Edit mode
Fx.config = {
	localCharacter = nil :: Model?, -- whose screen effects / fov play (default: LocalPlayer.Character)
	screenParent = nil :: Instance?, -- where screen effects go (default: a ScreenGui in PlayerGui)
}
local Frame = RunService:IsRunning() and RunService.RenderStepped or RunService.Heartbeat
local live: { Instance } = {}
local castTags: { [number]: { [string]: Instance } } = {}

local function folder(): Folder
	local f = Workspace:FindFirstChild("SkillKitFx")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SkillKitFx"
		f.Parent = Workspace
	end
	return f :: Folder
end

local function track(inst: Instance, lifetime: number)
	table.insert(live, inst)
	if #live > Fx.MAX_LIVE then
		local old = table.remove(live, 1)
		if old then
			old:Destroy()
		end
	end
	Debris:AddItem(inst, lifetime)
end

local function color(v: any, fallback: Color3): Color3
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, v)
		if ok then
			return c
		end
	elseif type(v) == "table" and v[1] then
		return color(v[1][2] or v[1], fallback)
	end
	return fallback
end

-- a ColorSequence from a hex / Color3 / gradient list { {t, hex}, ... }
local function colorSeq(v: any, fallback: Color3): ColorSequence
	if type(v) == "table" and type(v[1]) == "table" then
		local keys = {}
		for _, s in ipairs(v) do
			table.insert(keys, ColorSequenceKeypoint.new(math.clamp(s[1], 0, 1), color(s[2], fallback)))
		end
		table.sort(keys, function(a, b)
			return a.Time < b.Time
		end)
		if keys[1].Time > 0 then
			table.insert(keys, 1, ColorSequenceKeypoint.new(0, keys[1].Value))
		end
		if keys[#keys].Time < 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, keys[#keys].Value))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(color(v, fallback))
end
Fx.colorSeq = colorSeq

local function offsetCF(cf: CFrame, v: Vector3?): CFrame
	v = v or Vector3.zero
	return cf + cf.RightVector * v.X + cf.UpVector * v.Y + cf.LookVector * v.Z
end

-- where an effect plays: the subject now (model root / part), else the frame the server sent
function Fx.frame(payload: any): CFrame?
	local s = payload.subject
	if typeof(s) == "Instance" and s.Parent then
		if s:IsA("Model") then
			local r = Rig.root(s)
			return r and r.CFrame or s:GetPivot()
		elseif s:IsA("BasePart") then
			return s.CFrame
		end
	end
	return payload.cf
end

local function nearMe(pos: Vector3, radius: number): boolean
	local cam = Workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - pos).Magnitude <= radius
end

local function isMine(payload: any): boolean
	local c = Fx.config.localCharacter or (player and player.Character)
	return c ~= nil and (payload.subject == c or payload.user == c)
end

local function part(props: any): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = folder()
	return p
end

local function tweenThen(inst: Instance, info: TweenInfo, goal: any)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- PRESETS -------------------------------------------------------------------------------------------------------------
-- params from the node: color, color2, size, duration, position (offset), plus anything preset-specific
local Presets: { [string]: (any, any, CFrame?) -> () } = {}
Fx.Presets = Presets

-- screen
Presets.shake = function(n, payload, cf)
	if not cf or not nearMe(cf.Position, 80) then
		return
	end
	local cam = Workspace.CurrentCamera
	local strength = (n.size or 1) * 0.6
	local t0 = os.clock()
	local dur = n.duration or 0.4
	local name = "SkillKitShake" .. tostring(t0)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
		local t = os.clock() - t0
		if t >= dur then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local k = strength * (1 - t / dur)
		cam.CFrame *= CFrame.new(math.noise(t * 30, 1) * k, math.noise(t * 30, 2) * k, 0) * CFrame.Angles(0, 0, math.noise(t * 25, 3) * k * 0.03)
	end)
end
local function screenGui(): Instance
	if Fx.config.screenParent then
		return Fx.config.screenParent :: Instance
	end
	local pg = player:WaitForChild("PlayerGui")
	local g = pg:FindFirstChild("SkillKitScreen") :: ScreenGui?
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "SkillKitScreen"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 5
		g.Parent = pg
	end
	return g :: ScreenGui
end
Presets.flash = function(n, payload, cf)
	if not cf or not nearMe(cf.Position, 120) then
		return
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color(n.color, Color3.new(1, 1, 1))
	f.BackgroundTransparency = 0.2
	f.Parent = screenGui()
	tweenThen(f, TweenInfo.new(n.duration or 0.3), { BackgroundTransparency = 1 })
	track(f, (n.duration or 0.3) + 0.1)
end
Presets.vignette = function(n, payload, cf)
	if not isMine(payload) and not (cf and nearMe(cf.Position, 40)) then
		return
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Parent = screenGui()
	local edges = {}
	for i, rot in ipairs({ 0, 90, 180, 270 }) do
		local e = Instance.new("Frame")
		e.BorderSizePixel = 0
		e.BackgroundColor3 = color(n.color, Color3.new(0, 0, 0))
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromScale(0.5, 0.5)
		e.Size = UDim2.fromScale(i % 2 == 1 and 1 or 1.8, i % 2 == 1 and 1.8 or 1)
		e.Rotation = rot
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = e
		e.Parent = f
		table.insert(edges, e)
	end
	local dur = n.duration or 0.6
	task.delay(dur * 0.5, function()
		for _, e in ipairs(edges) do
			tweenThen(e, TweenInfo.new(dur * 0.5), { BackgroundTransparency = 1 })
		end
	end)
	track(f, dur + 0.1)
end
Presets.blur = function(n, payload, cf)
	if not cf or not nearMe(cf.Position, 60) then
		return
	end
	local b = Instance.new("BlurEffect")
	b.Size = 12 * (n.size or 1)
	b.Parent = Lighting
	tweenThen(b, TweenInfo.new(n.duration or 0.4), { Size = 0 })
	track(b, (n.duration or 0.4) + 0.1)
end
Presets.tint = function(n, payload, cf)
	if not cf or not nearMe(cf.Position, 80) then
		return
	end
	local c = Instance.new("ColorCorrectionEffect")
	c.TintColor = color(n.color, Color3.fromRGB(255, 200, 200))
	c.Contrast = 0.1
	c.Parent = Lighting
	tweenThen(c, TweenInfo.new(n.duration or 0.5), { TintColor = Color3.new(1, 1, 1), Contrast = 0 })
	track(c, (n.duration or 0.5) + 0.1)
end
Presets.fov = function(n, payload, cf)
	if not isMine(payload) then
		return
	end
	local cam = Workspace.CurrentCamera
	local base = cam.FieldOfView
	cam.FieldOfView = base + 12 * (n.size or 1)
	tweenThen(cam, TweenInfo.new(n.duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base })
end

-- body
local function bodyTarget(payload: any): Instance?
	local s = payload.applyTarget or payload.subject
	if typeof(s) == "Instance" and s.Parent then
		return s
	end
	return nil
end
Presets.highlight = function(n, payload, cf)
	local target = bodyTarget(payload)
	if not target then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = color(n.color, Color3.fromRGB(255, 220, 160))
	h.OutlineColor = color(n.color2, Color3.new(1, 1, 1))
	h.FillTransparency = 0.5
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = target
	h.Parent = folder()
	local dur = n.duration or 0.5
	task.delay(dur * 0.4, function()
		tweenThen(h, TweenInfo.new(dur * 0.6), { FillTransparency = 1, OutlineTransparency = 1 })
	end)
	track(h, dur + 0.1)
end
Presets.glow = function(n, payload, cf)
	local target = bodyTarget(payload)
	local root = target and (target:IsA("Model") and Rig.root(target) or (target :: any))
	if not root then
		return
	end
	local l = Instance.new("PointLight")
	l.Color = color(n.color, Color3.fromRGB(255, 220, 160))
	l.Range = 14 * (n.size or 1)
	l.Brightness = 3
	l.Parent = root
	tweenThen(l, TweenInfo.new(n.duration or 0.6), { Brightness = 0 })
	track(l, (n.duration or 0.6) + 0.1)
	local h = Instance.new("Highlight")
	h.FillColor = l.Color
	h.FillTransparency = 0.75
	h.OutlineTransparency = 1
	h.Adornee = target
	h.Parent = folder()
	tweenThen(h, TweenInfo.new(n.duration or 0.6), { FillTransparency = 1 })
	track(h, (n.duration or 0.6) + 0.1)
end
Presets.afterimage = function(n, payload, cf)
	local target = bodyTarget(payload)
	if not target or not target:IsA("Model") then
		return
	end
	for _, p in ipairs(target:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "HumanoidRootPart" then
			local g = part({ Size = p.Size, CFrame = p.CFrame, Color = color(n.color, Color3.fromRGB(140, 180, 255)), Material = Enum.Material.Neon, Transparency = 0.5 })
			tweenThen(g, TweenInfo.new(n.duration or 0.4), { Transparency = 1 })
			track(g, (n.duration or 0.4) + 0.1)
		end
	end
end

-- beam / hit / wind
Presets.beam = function(n, payload, cf)
	if not cf then
		return
	end
	local length = 40 * (n.size or 1)
	local width = 2.5 * (n.size or 1)
	local start = offsetCF(cf, n.position)
	local b = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, width, width),
		CFrame = start * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0),
		Color = color(n.color, Color3.fromRGB(255, 220, 160)),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	local core = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, width * 0.45, width * 0.45), CFrame = b.CFrame, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon })
	local dur = n.duration or 0.6
	for _, p in ipairs({ b, core }) do
		tweenThen(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(length, 0.05, 0.05), Transparency = 1 })
		track(p, dur + 0.1)
	end
end
Presets.impact = function(n, payload, cf)
	if not cf then
		return
	end
	local at = offsetCF(cf, n.position)
	local holder = part({ Size = Vector3.one, CFrame = at, Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = Registry.id("texture", "sparkle") or ""
	e.Color = colorSeq(n.color, Color3.fromRGB(255, 230, 180))
	e.LightEmission = 1
	e.Speed = NumberRange.new(20, 40)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.2, 0.45)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2 * (n.size or 1)), NumberSequenceKeypoint.new(1, 0) })
	e.Drag = 6
	e.Rate = 0
	e.Parent = holder
	e:Emit(math.floor(24 * (n.size or 1)))
	track(holder, 1)
	Presets.ring(n, payload, at)
end
Presets.ring = function(n, payload, cf)
	if not cf then
		return
	end
	local s = 2 * (n.size or 1)
	local r = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, s, s),
		CFrame = cf * CFrame.Angles(0, 0, math.pi / 2),
		Color = color(n.color, Color3.new(1, 1, 1)),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	tweenThen(r, TweenInfo.new(n.duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, s * 5, s * 5), Transparency = 1 })
	track(r, (n.duration or 0.35) + 0.1)
end
Presets.wind = function(n, payload, cf)
	if not cf then
		return
	end
	local at = offsetCF(cf, n.position)
	local rng = Random.new()
	for i = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = (at.RightVector * math.cos(a) + at.UpVector * math.sin(a) * 0.5 - at.LookVector * 0.4).Unit
		local len = rng:NextNumber(3, 7) * (n.size or 1)
		local l = part({
			Size = Vector3.new(0.12, 0.12, len),
			CFrame = CFrame.lookAt(at.Position + dir * 2, at.Position + dir * 4),
			Color = color(n.color, Color3.new(1, 1, 1)),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
		tweenThen(l, TweenInfo.new(n.duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = l.CFrame + dir * 10 * (n.size or 1), Transparency = 1 })
		track(l, (n.duration or 0.4) + 0.1)
	end
end
Presets.burst = function(n, payload, cf)
	if not cf then
		return
	end
	local s = 3 * (n.size or 1)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = offsetCF(cf, n.position), Color = color(n.color, Color3.fromRGB(255, 220, 160)), Material = Enum.Material.ForceField })
	tweenThen(b, TweenInfo.new(n.duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * s * 4, Transparency = 1 })
	track(b, (n.duration or 0.4) + 0.1)
end

function Fx.preset(n: any, payload: any)
	local f = Presets[n.preset]
	if not f then
		warn("[SkillKit] no preset VFX named " .. tostring(n.preset))
		return
	end
	if n.applyTo then
		payload.applyTarget = castTags[payload.castId] and castTags[payload.castId][n.applyTo]
	end
	local cf = Fx.frame(payload)
	if cf and (Workspace.CurrentCamera.CFrame.Position - cf.Position).Magnitude > Fx.CULL then
		return
	end
	f(n, payload, cf and offsetCF(cf, n.position) or nil)
end

-- PARTICLE ------------------------------------------------------------------------------------------------------------
function Fx.particle(n: any, payload: any)
	local cf = Fx.frame(payload)
	if not cf then
		return
	end
	local holder = part({ Size = Vector3.one * 0.2, CFrame = offsetCF(cf, n.position), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = Registry.id("texture", n.texture) or Registry.id("texture", "sparkle") or ""
	e.Color = colorSeq(n.color, Color3.new(1, 1, 1))
	e.LightEmission = n.lightEmission or 1
	local lt, sp, rs = n.lifetime or { 0.4, 0.8 }, n.speed or { 10, 20 }, n.rotSpeed or { 0, 0 }
	e.Lifetime = NumberRange.new(lt[1], lt[2] or lt[1])
	e.Speed = NumberRange.new(sp[1], sp[2] or sp[1])
	e.RotSpeed = NumberRange.new(rs[1], rs[2] or rs[1])
	e.SpreadAngle = Vector2.new(n.spread or 180, n.spread or 180)
	e.Acceleration = n.acceleration or Vector3.zero
	e.Drag = n.drag or 0
	e.Size = n.sizeCurve and Curves.sequence(n.sizeCurve, n.size or 1, 0, "mult") or NumberSequence.new(n.size or 1)
	if n.transparencyCurve then
		e.Transparency = Curves.sequence(n.transparencyCurve, 0, 1, "ease")
	end
	local fb = n.flipbook or (Registry.get("texture", n.texture) or {}).flipbook
	if fb then
		pcall(function()
			e.FlipbookLayout = (Enum.ParticleFlipbookLayout :: any)["Grid" .. (fb.rows or 4) .. "x" .. (fb.cols or 4)] or Enum.ParticleFlipbookLayout.Grid4x4
			e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		end)
	end
	e.Rate = n.enabled and (n.rate or 30) or 0
	e.Enabled = n.enabled == true
	e.Parent = holder
	if not n.enabled then
		e:Emit(n.emitCount or 20)
	end
	-- follow the subject while it plays
	local subject = payload.subject
	if typeof(subject) == "Instance" and subject.Parent then
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local now = Fx.frame(payload)
			if not holder.Parent or not now then
				conn:Disconnect()
				return
			end
			holder.CFrame = offsetCF(now, n.position)
		end)
		task.delay(n.duration or 0.5, function()
			e.Enabled = false
			conn:Disconnect()
		end)
	else
		task.delay(n.duration or 0.5, function()
			e.Enabled = false
		end)
	end
	track(holder, (n.duration or 0.5) + lt[2] + 0.2)
end

-- MESH VISUAL ---------------------------------------------------------------------------------------------------------
function Fx.mesh(n: any, payload: any)
	local cf = Fx.frame(payload)
	if not cf then
		return
	end
	local rot = n.rotation or Vector3.zero
	local function at(pos: Vector3?, r: Vector3?): CFrame
		local base = n.attach and Fx.frame(payload) or cf
		r = r or Vector3.zero
		return offsetCF(base :: CFrame, pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	end
	local size0: Vector3 = n.size or Vector3.new(2, 2, 2)
	local size1: Vector3 = n.altSize or size0
	local p = part({ Size = Vector3.one, CFrame = at(n.position, rot), Color = color(n.color, Color3.new(1, 1, 1)), Transparency = n.transparency or 0 })
	p.Material = (Enum.Material :: any)[n.material or "Neon"] or Enum.Material.Neon
	local mesh = Instance.new("SpecialMesh")
	local reg = Registry.get("mesh", n.mesh)
	local sizeMul = Vector3.one
	if n.mesh == "Sphere" then
		mesh.MeshType = Enum.MeshType.Sphere
	elseif n.mesh == "Block" then
		mesh.MeshType = Enum.MeshType.Brick
	elseif n.mesh == "Cylinder" then
		mesh.MeshType = Enum.MeshType.Cylinder
	else
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = Registry.id("mesh", n.mesh, "meshId") or ""
		mesh.TextureId = Registry.id("mesh", n.texture or (reg and reg.textureId), "textureId") or (reg and reg.textureId and Registry.id("image", reg.textureId)) or ""
		sizeMul = reg and reg.scale or Vector3.one
	end
	mesh.Parent = p
	local tex0 = mesh.TextureId
	local flip = reg and reg.flipbook -- { textures = { id, id, ... }, fps }
	local t0 = os.clock()
	local dur = math.max(n.time or 0.5, 0.03)
	local c0 = color(n.color, Color3.new(1, 1, 1))
	local c1 = color(n.altColor or n.color, c0)
	local tr0, tr1 = n.transparency or 0, n.altTransparency == nil and 1 or n.altTransparency
	if n.visualTag then
		castTags[payload.castId] = castTags[payload.castId] or {}
		castTags[payload.castId][n.visualTag] = p
		task.delay(dur + 5, function()
			local t = castTags[payload.castId]
			if t and t[n.visualTag] == p then
				t[n.visualTag] = nil
			end
		end)
	end
	local conn
	conn = Frame:Connect(function()
		local u = math.clamp((os.clock() - t0) / dur, 0, 1)
		if not p.Parent then
			conn:Disconnect()
			return
		end
		local mu = Curves.ease(n.moveCurve, u)
		local su = Curves.ease(n.sizeCurve, u)
		local fu = Curves.ease(n.fadeCurve, u)
		local cu = Curves.ease(n.colorCurve, u)
		local pos = (n.altPosition and (n.position or Vector3.zero):Lerp(n.altPosition, mu)) or n.position
		local r = (n.altRotation and rot:Lerp(n.altRotation, mu)) or rot
		p.CFrame = at(pos, r)
		mesh.Scale = size0:Lerp(size1, su) * sizeMul
		p.Transparency = tr0 + (tr1 - tr0) * fu
		p.Color = c0:Lerp(c1, cu)
		if flip and flip.textures and #flip.textures > 0 then
			local i = math.floor((os.clock() - t0) * (flip.fps or 20)) % #flip.textures + 1
			mesh.TextureId = Registry.id("image", flip.textures[i]) or tex0
		end
		if u >= 1 then
			conn:Disconnect()
			p:Destroy()
		end
	end)
	track(p, dur + 0.2)
end

-- HIGHLIGHT -------------------------------------------------------------------------------------------------------------
function Fx.highlight(n: any, payload: any)
	local target = n.applyTo and castTags[payload.castId] and castTags[payload.castId][n.applyTo] or payload.subject
	if typeof(target) ~= "Instance" or not target.Parent then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = color(n.fill, Color3.fromRGB(255, 220, 160))
	h.OutlineColor = color(n.outline, Color3.new(1, 1, 1))
	h.FillTransparency = n.fillTransparency or 0.5
	h.OutlineTransparency = n.outlineTransparency or 0
	h.Adornee = target
	h.Parent = folder()
	local dur = n.duration or 0.5
	local t0 = os.clock()
	local conn
	conn = Frame:Connect(function()
		local u = math.clamp((os.clock() - t0) / dur, 0, 1)
		if not h.Parent then
			conn:Disconnect()
			return
		end
		local k = n.fadeCurve and Curves.ease(n.fadeCurve, u) or (u > 0.6 and (u - 0.6) / 0.4 or 0)
		h.FillTransparency = (n.fillTransparency or 0.5) + (1 - (n.fillTransparency or 0.5)) * k
		h.OutlineTransparency = (n.outlineTransparency or 0) + (1 - (n.outlineTransparency or 0)) * k
		if u >= 1 then
			conn:Disconnect()
			h:Destroy()
		end
	end)
	track(h, dur + 0.2)
end

-- SOUND ---------------------------------------------------------------------------------------------------------------
local soundsByCast: { [number]: { Sound } } = {}
function Fx.sound(n: any, payload: any)
	local id = Registry.id("sound", n.sound)
	if not id then
		return
	end
	local reg = Registry.get("sound", n.sound)
	local holder: Instance
	local subject = payload.subject
	if typeof(subject) == "Instance" and subject.Parent then
		holder = subject:IsA("Model") and (Rig.root(subject) or subject) or subject
	else
		local cf = payload.cf or CFrame.new()
		holder = part({ Size = Vector3.one * 0.2, CFrame = cf, Transparency = 1 })
		track(holder, 10)
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = (n.volume or (reg and reg.volume) or 0.6)
	s.PlaybackSpeed = n.speed or 1
	s.Looped = n.looped == true
	local ro = n.rollOff or { 8, 120 }
	s.RollOffMinDistance, s.RollOffMaxDistance = ro[1], ro[2]
	local pitch = n.pitch or (reg and reg.pitch) or 1
	if pitch ~= 1 then
		local ps = Instance.new("PitchShiftSoundEffect")
		ps.Octave = math.clamp(pitch, 0.5, 2)
		ps.Parent = s
	end
	s.Parent = holder
	s:Play()
	soundsByCast[payload.castId] = soundsByCast[payload.castId] or {}
	table.insert(soundsByCast[payload.castId], s)
	if (n.stopAfter or 0) > 0 then
		task.delay(n.stopAfter, function()
			s:Destroy()
		end)
	elseif not s.Looped then
		s.Ended:Connect(function()
			s:Destroy()
		end)
		Debris:AddItem(s, 15)
	end
end
function Fx.stopCast(castId: number)
	for _, s in ipairs(soundsByCast[castId] or {}) do
		if s.Looped then
			s:Destroy()
		end
	end
	soundsByCast[castId] = nil
	castTags[castId] = nil
end

-- DEBUG HITBOXES ------------------------------------------------------------------------------------------------------
function Fx.hitbox(payload: any)
	local shape = payload.shape
	local p = part({
		Size = payload.size,
		CFrame = payload.cf,
		Color = Color3.fromRGB(255, 70, 70),
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
	})
	if shape == "Sphere" then
		p.Shape = Enum.PartType.Ball
		local d = math.max(payload.size.X, payload.size.Y, payload.size.Z)
		p.Size = Vector3.one * d
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	if payload.follow and payload.offset then
		local conn
		conn = Frame:Connect(function()
			local r = Rig.root(payload.follow)
			if not p.Parent or not r then
				conn:Disconnect()
				return
			end
			p.CFrame = r.CFrame * payload.offset
		end)
	end
	track(p, payload.duration or 0.2)
end

function Fx.hitFlash(payload: any)
	local m = payload.model
	if typeof(m) ~= "Instance" or not m.Parent then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.fromRGB(255, 80, 80)
	h.FillTransparency = 0.4
	h.OutlineTransparency = 1
	h.Adornee = m
	h.Parent = folder()
	tweenThen(h, TweenInfo.new(0.2), { FillTransparency = 1 })
	track(h, 0.25)
end

-- PROJECTILES (visual twin of the server simulation) ------------------------------------------------------------------
local projectiles: { [number]: any } = {}
function Fx.projectile(payload: any)
	local n = payload.node
	local size = n.size or 1.5
	local p = part({ Size = Vector3.one * size, CFrame = CFrame.new(payload.origin), Color = color(n.color, Color3.fromRGB(255, 220, 160)), Transparency = 0 })
	p.Material = (Enum.Material :: any)[n.material or "Neon"] or Enum.Material.Neon
	local reg = Registry.get("mesh", n.shape)
	if n.shape == "Ball" or n.shape == nil then
		p.Shape = Enum.PartType.Ball
	elseif reg then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = Registry.id("mesh", n.shape, "meshId") or ""
		m.TextureId = reg.textureId and (Registry.id("image", reg.textureId) or "") or ""
		m.Scale = (reg.scale or Vector3.one) * size
		m.Parent = p
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.3, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.3, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.Color = colorSeq(n.color, Color3.fromRGB(255, 220, 160))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = p
	local state = { part = p, pos = payload.origin, dir = payload.aim, fall = 0, t = 0, target = payload.homes and payload.target or nil, done = false }
	projectiles[payload.id] = state
	if n.projectileTag then
		castTags[payload.castId] = castTags[payload.castId] or {}
		castTags[payload.castId][n.projectileTag] = p
	end
	local lifetime = n.lifetime or 3
	local conn
	conn = Frame:Connect(function(dt)
		if state.done or not p.Parent then
			conn:Disconnect()
			return
		end
		state.t += dt
		if state.t > lifetime + 0.5 then
			state.done = true
			p:Destroy()
			return
		end
		local homing = n.homing
		if state.target and homing and state.t >= (homing.delay or 0) then
			local r = Rig.root(state.target)
			if r then
				local want = (r.Position - state.pos).Unit
				local d = state.dir:Lerp(want, math.clamp((homing.turnSpeed or 6) * dt, 0, 1))
				state.dir = d.Magnitude > 0 and d.Unit or want
				state.fall = 0
			end
		end
		state.fall += (n.gravity or 0) * dt
		local v = state.dir * (n.speed or 80) * Curves.mult(n.speedCurve, state.t / lifetime) - Vector3.new(0, state.fall, 0)
		state.pos += v * dt
		p.CFrame = CFrame.lookAt(state.pos, state.pos + (v.Magnitude > 0 and v or state.dir))
	end)
	track(p, lifetime + (n.stick or 0) + 1)
end
function Fx.projectileSync(payload: any)
	local s = projectiles[payload.id]
	if s then
		s.pos = s.pos:Lerp(payload.pos, 0.6)
		if payload.vel.Magnitude > 0 then
			s.dir = payload.vel.Unit
		end
	end
end
function Fx.projectileEnd(payload: any)
	local s = projectiles[payload.id]
	if not s then
		return
	end
	projectiles[payload.id] = nil
	s.done = true
	s.part.CFrame = CFrame.new(payload.pos)
	if payload.reason == "hit" or payload.reason == "wall" then
		Presets.impact({ size = 0.8 }, {}, CFrame.new(payload.pos))
	end
	local stick = 0
	task.delay(stick, function()
		if s.part.Parent then
			tweenThen(s.part, TweenInfo.new(0.15), { Transparency = 1 })
			Debris:AddItem(s.part, 0.2)
		end
	end)
end

return Fx
