-- SkillKit Studio plugin. Built by plugin/build_plugin.py into SkillKit.rbxmx (a local plugin).
-- The plugin carries a copy of the SkillKit add-on (child module "SkillKit") and its test scripts, and gives a panel to:
--   * install or update SkillKit in the open place (ReplicatedStorage.SkillKit + a client starter + a server init if
--     the place has none)
--   * add / remove the test runner (press Play: every node type runs against a dummy; report in the Output;
--     chat /sk <Test>, /sk all, /sk log)
--   * drop a breakable test wall in front of the camera (for Debris nodes)
-- It never touches anything outside the instances it names, and every change is undoable (ChangeHistoryService).
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

if RunService:IsRunning() then
	return -- the panel is for Edit mode; the test runner does the work during Play
end

local bundled = script:WaitForChild("SkillKit")
local files = script:WaitForChild("Files")
local VERSION = string.match((bundled :: any).Source, 'Version = "([%d%.]+)"') or "?"

-- UI -------------------------------------------------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("SkillKit")
local button = toolbar:CreateButton("SkillKitPanel", "SkillKit: install, test, tools", "rbxasset://textures/AnimationEditor/icon_checkmark.png", "SkillKit")
button.ClickableWhenViewportHidden = true

-- Skill Editor: a full-screen overlay over the viewport (node list, settings, branches, timeline, preview dummies)
local editorButton = toolbar:CreateButton("SkillKitEditor", "SkillKit Skill Editor: build and preview skills", "rbxasset://textures/AnimationEditor/icon_checkmark.png", "Skill Editor")
editorButton.ClickableWhenViewportHidden = true
local app: any = nil
local function getApp(): any
	if app then
		return app
	end
	local SK = {
		Schema = require(bundled:WaitForChild("Schema")),
		Curves = require(bundled:WaitForChild("Curves")),
		Registry = require(bundled:WaitForChild("Registry")),
		Codec = require(bundled:WaitForChild("Codec")),
		Rig = require(bundled:WaitForChild("Rig")),
		Fx = require(bundled:WaitForChild("Client"):WaitForChild("Fx")),
		KeyframePlayer = require(bundled:WaitForChild("Client"):WaitForChild("KeyframePlayer")),
		TestSkills = require(bundled:WaitForChild("Dev"):WaitForChild("TestSkills")),
	}
	app = require(script:WaitForChild("Editor"):WaitForChild("App")).new(plugin, SK)
	return app
end
editorButton.Click:Connect(function()
	local ok, err = pcall(function()
		local a = getApp()
		if a.gui and a.gui.Enabled then
			a:close()
		else
			a:open()
			print("[SkillKit editor] Opened. It draws over the 3D viewport: switch to the place tab (not a script tab) to see it.")
		end
		editorButton:SetActive(a.gui ~= nil and a.gui.Enabled)
	end)
	if not ok then
		warn("[SkillKit editor] " .. tostring(err))
	end
end)
RunService.Heartbeat:Connect(function()
	if app and app.gui then
		editorButton:SetActive(app.gui.Enabled)
	end
	if app and app.gui and app.gui.Enabled then
		local ok, err = pcall(app.tick, app)
		if not ok then
			warn("[SkillKit editor] " .. tostring(err))
		end
	end
end)
plugin.Unloading:Connect(function()
	if app and app.gui then
		pcall(app.close, app)
	end
end)

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 460, 260, 320)
local widget = plugin:CreateDockWidgetPluginGui("SkillKitPanel", info)
widget.Title = "SkillKit " .. VERSION
widget.Name = "SkillKitPanel"
button:SetActive(widget.Enabled)
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

local function themeColor(c: Enum.StudioStyleGuideColor, m: Enum.StudioStyleGuideModifier?): Color3
	return settings().Studio.Theme:GetColor(c, m)
end

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.CanvasSize = UDim2.new()
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
root.ScrollBarThickness = 6
root.BorderSizePixel = 0
root.Parent = widget
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12)
pad.Parent = root
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = root

local themed: { () -> () } = {}
local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function label(text: string, bold: boolean?, dim: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Font = bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
	t.TextSize = bold and 17 or 15
	t.Text = text
	t.LayoutOrder = nextOrder()
	t.Parent = root
	table.insert(themed, function()
		t.TextColor3 = themeColor(dim and Enum.StudioStyleGuideColor.DimmedText or Enum.StudioStyleGuideColor.MainText)
	end)
	return t
end

local function btn(text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 15
	b.Text = text
	b.AutoButtonColor = true
	b.LayoutOrder = nextOrder()
	b.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = b
	b.Activated:Connect(onClick)
	table.insert(themed, function()
		b.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Button)
		b.TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText)
	end)
	return b
end

local function applyTheme()
	root.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground)
	for _, f in ipairs(themed) do
		f()
	end
end

-- helpers --------------------------------------------------------------------------------------------------------------
local function record(name: string, fn: () -> ()): (boolean, string?)
	local id = ChangeHistoryService:TryBeginRecording(name)
	local ok, err = pcall(fn)
	if id then
		ChangeHistoryService:FinishRecording(id, ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
	end
	return ok, err
end

local function scriptFrom(className: string, name: string, sourceModule: string, parent: Instance): Instance
	local s = Instance.new(className)
	s.Name = name;
	(s :: any).Source = (files:FindFirstChild(sourceModule) :: any).Source
	s.Parent = parent
	return s
end

-- does any script in the place already contain this text? (finds a game's own SkillKit.init / initClient)
local function placeHas(text: string, except: Instance?): boolean
	for _, container in ipairs({ ServerScriptService, StarterPlayer, ReplicatedStorage, game:GetService("StarterGui"), game:GetService("ServerStorage") }) do
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("LuaSourceContainer") and d ~= except and not d:IsDescendantOf(ReplicatedStorage:FindFirstChild("SkillKit") or Instance.new("Folder")) then
				local ok, src = pcall(function()
					return (d :: any).Source
				end)
				if ok and type(src) == "string" and string.find(src, text, 1, true) then
					return true
				end
			end
		end
	end
	return false
end

local function installedVersion(): string?
	local sk = ReplicatedStorage:FindFirstChild("SkillKit")
	if not sk then
		return nil
	end
	local v = sk:GetAttribute("Version")
	if v then
		return v
	end
	local ok, src = pcall(function()
		return (sk :: any).Source
	end)
	return ok and type(src) == "string" and string.match(src, 'Version = "([%d%.]+)"') or "unknown"
end

-- panel ---------------------------------------------------------------------------------------------------------------
label("SkillKit " .. VERSION, true)
label("Runs node-based skills (hitboxes, motion, animation, VFX, tags, states). This panel installs it and tests it.", false, true)

local status = label("", false)
local function refresh()
	local v = installedVersion()
	local runner = ServerScriptService:FindFirstChild("SkillKitTestRunner") ~= nil
	local lines = {}
	table.insert(lines, v and ("Installed in this place: " .. v) or "Not installed in this place.")
	if v and v ~= VERSION and v ~= "unknown" then
		table.insert(lines, "The plugin has " .. VERSION .. ": press Install / update.")
	end
	table.insert(lines, runner and "Test runner: ON (press Play to test)" or "Test runner: off")
	status.Text = table.concat(lines, "\n")
end

label("Install", true)
btn("Install / update SkillKit", function()
	local ok, err = record("Install SkillKit", function()
		local old = ReplicatedStorage:FindFirstChild("SkillKit")
		if old then
			old:Destroy()
		end
		local copy = bundled:Clone()
		copy.Parent = ReplicatedStorage
		-- a client starter, unless the place already starts it
		if not placeHas("initClient") then
			local folder = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts") or Instance.new("StarterPlayerScripts", StarterPlayer)
			scriptFrom("LocalScript", "SkillKitClient", "ClientStarter", folder)
		end
		-- a server init with the default adapter, unless the place already calls SkillKit.init
		if not placeHas("SkillKit.init(") and not placeHas("SkillKit.init (") then
			scriptFrom("Script", "SkillKitInit", "ServerInit", ServerScriptService)
		end
	end)
	if not ok then
		warn("[SkillKit plugin] install failed: " .. tostring(err))
	else
		print("[SkillKit plugin] SkillKit " .. VERSION .. " installed in ReplicatedStorage.")
		print("[SkillKit plugin] If this place syncs with Rojo, also update the add-on files on disk, or Rojo will put the old copy back.")
	end
	refresh()
end)
label("Puts ReplicatedStorage.SkillKit in this place. Adds a client starter and a default server init only if the place has none.", false, true)

label("Test", true)
btn("Add test runner", function()
	record("Add SkillKit test runner", function()
		if not ServerScriptService:FindFirstChild("SkillKitTestRunner") then
			scriptFrom("Script", "SkillKitTestRunner", "TestRunner", ServerScriptService)
		end
		local folder = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		if folder and not placeHas("initClient") then
			scriptFrom("LocalScript", "SkillKitTestClient", "ClientStarter", folder)
		end
	end)
	if not ReplicatedStorage:FindFirstChild("SkillKit") then
		warn("[SkillKit plugin] SkillKit isn't installed in this place yet: press Install / update first.")
	end
	print("[SkillKit plugin] Test runner added. Press Play: results print to the Output. In chat: /sk all, /sk Hitbox, /sk log")
	refresh()
end)
btn("Remove test runner", function()
	record("Remove SkillKit test runner", function()
		for _, d in ipairs({ ServerScriptService:FindFirstChild("SkillKitTestRunner") }) do
			d:Destroy()
		end
		local folder = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		local c = folder and folder:FindFirstChild("SkillKitTestClient")
		if c then
			c:Destroy()
		end
	end)
	refresh()
end)
label("With the runner on, Play runs every node type against a dummy and prints OK / PASS lines. Remove it before you publish.", false, true)

label("Tools", true)
btn("Breakable wall at the camera", function()
	record("SkillKit test wall", function()
		local cam = Workspace.CurrentCamera
		local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, -1)
		local at = cam.CFrame.Position + look * 16
		local hit = Workspace:Raycast(at + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0))
		local y = hit and hit.Position.Y or at.Y
		local w = Instance.new("Part")
		w.Name = "BreakableWall"
		w.Size = Vector3.new(8, 8, 1.5)
		w.Anchored = true
		w.Material = Enum.Material.Brick
		w.Color = Color3.fromRGB(150, 140, 130)
		w.CFrame = CFrame.lookAt(Vector3.new(at.X, y + 4, at.Z), Vector3.new(cam.CFrame.Position.X, y + 4, cam.CFrame.Position.Z))
		w.Parent = Workspace
		CollectionService:AddTag(w, "SkillKitBreakable")
		Selection:Set({ w })
	end)
end)
btn("Tag selection as breakable", function()
	record("Tag SkillKitBreakable", function()
		for _, s in ipairs(Selection:Get()) do
			CollectionService:AddTag(s, "SkillKitBreakable")
		end
	end)
	print("[SkillKit plugin] Tagged " .. #Selection:Get() .. " instance(s) SkillKitBreakable.")
end)
btn("Select installed SkillKit", function()
	local sk = ReplicatedStorage:FindFirstChild("SkillKit")
	if sk then
		Selection:Set({ sk })
	end
end)

label("Help", true)
label("Write skills as Luau tables (see the README and Schema module). Test one quickly during Play from the server command bar:\nrequire(game.ReplicatedStorage.SkillKit).preview(mySkill, {player = game.Players:GetPlayers()[1]})", false, true)

applyTheme()
settings().Studio.ThemeChanged:Connect(applyTheme)
refresh()
ReplicatedStorage.ChildAdded:Connect(refresh)
ReplicatedStorage.ChildRemoved:Connect(refresh)
ServerScriptService.ChildAdded:Connect(refresh)
ServerScriptService.ChildRemoved:Connect(refresh)
