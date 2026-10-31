--!strict
-- The SkillKit skill editor: an overlay on Studio's 3D view.
--   top bar     skill picker, New, Open selected, Save, Code (export / import), preview speed, Play / Stop, Close
--   left panel  branch picker + search + new / rename / delete branch; quick add Wait, Branch, Loop; Add menu by
--               category; Copy, Paste, Delete, Up, Down, Group / Split, Multi-select; node cards that expand to their
--               settings (numbers, toggles, vectors, live colour swatches, curves with a mini graph, branch pickers)
--   timeline    one row per node of the open list, bars at their start time for their length, Wait gaps, a playhead
--   log         what the preview did, node by node (hits, misses with a hint, tag checks, branches)
-- Skills live in ReplicatedStorage.SkillKitSkills (one ModuleScript each) or come from any ModuleScript you select.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Meta = require(script.Parent.Meta)
local Serialize = require(script.Parent.Serialize)
local Ui = require(script.Parent.Ui)
local PreviewMod = require(script.Parent.Preview)
local Tree = require(script.Parent.Tree)
local Flow = require(script.Parent.Flow)
local Jjs = require(script.Parent.Jjs)
local UserInputService = game:GetService("UserInputService")

local C = Ui.C
local TOP_H = 46

local App = {}
App.__index = App

function App.new(plugin: Plugin, SK: any)
	local self = setmetatable({
		plugin = plugin,
		SK = SK,
		gui = nil :: ScreenGui?,
		skill = nil :: any,
		source = nil :: ModuleScript?,
		sourceKey = nil :: string?,
		readOnly = false,
		branch = "Default",
		path = {} :: { any }, -- inner node lists (Loop / Group) opened from the branch
		selected = {} :: { [any]: boolean },
		expanded = {} :: { [any]: boolean },
		multi = false,
		clipboard = nil :: { any }?,
		search = "",
		dirty = false,
		logLines = {} :: { any },
		preview = PreviewMod.new(SK),
		speed = 1,
		nodeFrames = {} :: { [any]: GuiObject },
		-- which panels show; the middle of the screen is always left free for the 3D view
		undoStack = {} :: { any },
		redoStack = {} :: { any },
		lastSnap = nil :: any,
		leftMode = "nodes", -- the left panel shows the node cards ("nodes") or the tree ("tree")
		show = { left = true, timeline = true, log = nil :: boolean? },
		treeOpen = {} :: { [string]: boolean },
		slotCtx = nil :: any, -- { entry, slot } when the open skill came from a character slot
		hidden = false,
	}, App)
	self.preview:on(function(e)
		self:onPreviewEvent(e)
	end)
	self:loadPrefs()
	return self
end

-- SKILL HELPERS -------------------------------------------------------------------------------------------------------------
local function newSkill(name: string): any
	return { name = name, cooldown = 2, branches = { Default = {} } }
end

function App:list(): { any }
	local top = self.path[#self.path]
	if top then
		top.nodes = top.nodes or {}
		return top.nodes
	end
	self.skill.branches[self.branch] = self.skill.branches[self.branch] or {}
	return self.skill.branches[self.branch]
end

function App:branchNames(): { string }
	local names = {}
	for k in pairs(self.skill.branches) do
		table.insert(names, k)
	end
	table.sort(names, function(a, b)
		if a == "Default" then
			return true
		elseif b == "Default" then
			return false
		end
		return a < b
	end)
	return names
end

function App:newNode(nodeType: string): any
	local n = self.SK.Schema.copy(self.SK.Schema.Defaults[nodeType] or {})
	n.type = nodeType
	n.id = nodeType:sub(1, 2):lower() .. tostring(math.random(10000, 99999))
	-- friendlier starting values than the bare defaults
	if nodeType == "Hitbox" then
		n.damage, n.stun, n.visible = 10, 0.4, true
	elseif nodeType == "Wait" then
		n.time = 0.2
	elseif nodeType == "Keyframes" then
		n.anim = "punch"
	elseif nodeType == "Sound" then
		n.sound = "swing"
	elseif nodeType == "PresetVFX" then
		n.preset = "impact"
	elseif nodeType == "Branch" then
		n.target = ""
	elseif nodeType == "Loop" or nodeType == "Group" then
		n.nodes = {}
	end
	return n
end

function App:changed()
	if self.lastSnap then
		table.insert(self.undoStack, self.lastSnap)
		if #self.undoStack > 60 then
			table.remove(self.undoStack, 1)
		end
		table.clear(self.redoStack)
	end
	self:snapshot()
	self.dirty = true
	self:render()
end

-- the selected nodes of the open list, in list order
function App:selection(): { any }
	local out = {}
	for _, n in ipairs(self:list()) do
		if self.selected[n] then
			table.insert(out, n)
		end
	end
	return out
end

function App:insert(node: any)
	local list = self:list()
	local sel = self:selection()
	local at = #list + 1
	if #sel > 0 then
		at = (table.find(list, sel[#sel]) :: number) + 1
	end
	table.insert(list, at, node)
	self.selected = { [node] = true }
	self.expanded[node] = true
	self:changed()
end

-- ACTIONS ----------------------------------------------------------------------------------------------------------------------
function App:duplicateNode(node: any)
	local list = self:list()
	local i = table.find(list, node)
	if not i then
		return
	end
	local c = self.SK.Schema.copy(node)
	c.id = c.type:sub(1, 2):lower() .. tostring(math.random(10000, 99999))
	table.insert(list, i + 1, c)
	self.selected = { [c] = true }
	self:changed()
end

function App:deleteNode(node: any)
	local list = self:list()
	local i = table.find(list, node)
	if i then
		table.remove(list, i)
		self.selected[node] = nil
		self:changed()
	end
end

-- scroll the node list so this node's card is visible
function App:scrollTo(node: any)
	task.delay(0.05, function()
		local f = self.nodeFrames[node]
		local sc = self.listFrame
		if f and sc and f.Parent then
			local y = f.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y - 6
			sc.CanvasPosition = Vector2.new(0, math.max(0, y))
		end
	end)
end

function App:copy()
	local sel = self:selection()
	if #sel == 0 then
		return
	end
	self.clipboard = self.SK.Schema.copy(sel)
	self:log("info", ("copied %d node(s)"):format(#sel))
end

function App:paste()
	if not self.clipboard then
		return
	end
	local list = self:list()
	local sel = self:selection()
	local at = #sel > 0 and (table.find(list, sel[#sel]) :: number) + 1 or #list + 1
	self.selected = {}
	for i, n in ipairs(self.SK.Schema.copy(self.clipboard)) do
		n.id = n.type:sub(1, 2):lower() .. tostring(math.random(10000, 99999))
		table.insert(list, at + i - 1, n)
		self.selected[n] = true
	end
	self:changed()
end

function App:delete()
	local list = self:list()
	for i = #list, 1, -1 do
		if self.selected[list[i]] then
			table.remove(list, i)
		end
	end
	self.selected = {}
	self:changed()
end

function App:move(dirn: number)
	local list = self:list()
	local sel = self:selection()
	if #sel == 0 then
		return
	end
	if dirn < 0 then
		for _, n in ipairs(sel) do
			local i = table.find(list, n) :: number
			if i > 1 and not self.selected[list[i - 1]] then
				list[i], list[i - 1] = list[i - 1], list[i]
			end
		end
	else
		for k = #sel, 1, -1 do
			local n = sel[k]
			local i = table.find(list, n) :: number
			if i < #list and not self.selected[list[i + 1]] then
				list[i], list[i + 1] = list[i + 1], list[i]
			end
		end
	end
	self:changed()
end

function App:group()
	local list = self:list()
	local sel = self:selection()
	if #sel == 1 and sel[1].type == "Group" then
		-- split it back into its nodes
		local g = sel[1]
		local i = table.find(list, g) :: number
		table.remove(list, i)
		for k, n in ipairs(g.nodes or {}) do
			table.insert(list, i + k - 1, n)
		end
		self.selected = {}
		self:changed()
		return
	end
	if #sel == 0 then
		return
	end
	local first = table.find(list, sel[1]) :: number
	local g = self:newNode("Group")
	g.name = "Group"
	g.nodes = {}
	for i = #list, 1, -1 do
		if self.selected[list[i]] then
			table.insert(g.nodes, 1, table.remove(list, i))
		end
	end
	table.insert(list, math.min(first, #list + 1), g)
	self.selected = { [g] = true }
	self:changed()
end

function App:openInner(node: any)
	table.insert(self.path, node)
	self.selected = {}
	self:render()
end

function App:back()
	table.remove(self.path)
	self.selected = {}
	self:render()
end

function App:newBranch(name: string)
	if name == "" or self.skill.branches[name] then
		return
	end
	self.skill.branches[name] = {}
	self.branch = name
	self.path = {}
	self:changed()
end

function App:renameBranch(old: string, new: string)
	if old == "Default" or new == "" or self.skill.branches[new] then
		return
	end
	self.skill.branches[new] = self.skill.branches[old]
	self.skill.branches[old] = nil
	-- fix references
	local function walk(list: { any })
		for _, n in ipairs(list) do
			for _, k in ipairs({ "target", "victimBranch", "finisherBranch", "missBranch", "hitBranch", "expireBranch", "passBranch", "failBranch", "arriveBranch", "grabBranch", "counterBranch" }) do
				if n[k] == old and not (n.type == "Travel" and k == "target") then
					n[k] = new
				end
			end
			if n.nodes then
				walk(n.nodes)
			end
		end
	end
	for _, list in pairs(self.skill.branches) do
		walk(list)
	end
	self.branch = new
	self:changed()
end

-- a yes / no box before anything is deleted
function App:confirm(title: string, message: string, yes: string, onYes: () -> ())
	local body = Ui.modal(title, 420, 170)
	Ui.text(body, message, { Size = UDim2.new(1, 0, 1, -44), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.dim, TextSize = 14, ZIndex = 63 })
	Ui.button(body, "Cancel", Ui.closePopup, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, 0), Size = UDim2.fromOffset(100, 32), ZIndex = 63 })
	Ui.button(body, yes, function()
		Ui.closePopup()
		onYes()
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(140, 32), ZIndex = 63, BackgroundColor3 = C.bad })
end

function App:deleteCharacter(entry: any)
	local id = ChangeHistoryService:TryBeginRecording("Delete SkillKit character")
	if entry.module and entry.module.Parent then
		entry.module:Destroy()
	end
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
	if self.slotCtx and self.slotCtx.entry.module == entry.module then
		self.slotCtx = nil
	end
	Tree.invalidate()
	self:log("info", "deleted character " .. tostring(entry.def.name))
	self:render()
end

function App:deleteSkillModule(m: ModuleScript)
	local id = ChangeHistoryService:TryBeginRecording("Delete SkillKit skill")
	local name = m.Name
	m:Destroy()
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
	if self.source == m then
		self.source = nil
	end
	Tree.invalidate()
	self:log("info", "deleted skill " .. name)
	self:render()
end

function App:deleteBranch(name: string)
	if name == "Default" then
		return
	end
	self.skill.branches[name] = nil
	self.branch = "Default"
	self.path = {}
	self:changed()
end

-- LOADING AND SAVING ------------------------------------------------------------------------------------------------------------
local function freshRequire(m: ModuleScript): any
	return Tree.freshRequire(m)
end

function App:skillsFolder(create: boolean?): Folder?
	local f = ReplicatedStorage:FindFirstChild("SkillKitSkills")
	if not f and create then
		f = Instance.new("Folder")
		f.Name = "SkillKitSkills"
		f.Parent = ReplicatedStorage
	end
	return f :: Folder?
end

function App:load(skill: any, source: ModuleScript?, key: string?, readOnly: boolean?)
	local copy = self.SK.Schema.copy(skill)
	copy.__normalized = nil
	self.SK.Schema.normalize(copy)
	copy.__normalized = nil
	self.skill = copy
	self.source = source
	self.sourceKey = key
	self.readOnly = readOnly == true
	self.branch = "Default"
	self.path = {}
	self.selected = {}
	self.expanded = {}
	self.dirty = false
	self.slotCtx = nil
	self.openExample = nil
	-- the page to come back to: the list the skill was opened from (callers that know better set self.nav after)
	local prev = self.nav
	local parent = { level = "home" }
	if prev and (prev.level == "skill" or prev.level == "node") then
		local sk = prev.level == "node" and prev.parent or prev
		parent = (sk and sk.parent) or parent
	elseif prev and (prev.level == "character" or prev.level == "group") then
		parent = prev
	end
	self.nav = { level = "skill", parent = parent }
	self.undoStack = {}
	self.redoStack = {}
	self:snapshot()
	self:render()
end

-- every skill the editor can open: the SkillKitSkills folder, skills inside the selected / known modules, examples
function App:catalog(): { any }
	local out = {}
	local folder = self:skillsFolder(false)
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("ModuleScript") then
				table.insert(out, { group = "Saved skills", text = m.Name, open = function()
					local s, err = freshRequire(m)
					if type(s) == "table" then
						self:load(s, m, nil, false)
					else
						self:log("error", "couldn't load " .. m.Name .. ": " .. tostring(err))
					end
				end })
			end
		end
	end
	-- moves modules of a game (Moves/*.luau with `skill` fields): read-only, save makes a copy
	local moves = Tree.movesFolder()
	if moves then
		for _, m in ipairs(moves:GetChildren()) do
			if m:IsA("ModuleScript") then
				local set = freshRequire(m)
				if type(set) == "table" then
					for slot, move in pairs(set) do
						if type(move) == "table" and type(move.skill) == "table" then
							table.insert(out, { group = "Game moves (read-only)", text = m.Name .. " · " .. tostring(slot), open = function()
								self:load(move.skill, m, tostring(slot), true)
							end })
						end
					end
				end
			end
		end
	end
	for name, s in pairs(self.SK.TestSkills) do
		table.insert(out, { group = "Examples", text = name, open = function()
			self:load(s, nil, nil, false)
		end })
	end
	return out
end

function App:openMenu(at: Vector2)
	local items = {}
	local groups: { [string]: { any } } = {}
	local order = {}
	for _, e in ipairs(self:catalog()) do
		if not groups[e.group] then
			groups[e.group] = {}
			table.insert(order, e.group)
		end
		table.insert(groups[e.group], e)
	end
	for _, g in ipairs(order) do
		table.insert(items, { header = true, text = string.upper(g) })
		table.sort(groups[g], function(a, b)
			return a.text < b.text
		end)
		for _, e in ipairs(groups[g]) do
			table.insert(items, { text = e.text, onClick = e.open })
		end
	end
	if #items == 0 then
		table.insert(items, { header = true, text = "no skills yet: press New" })
	end
	Ui.menu(at, items, 300)
end

function App:openSelected()
	local sel = Selection:Get()[1]
	if not sel or not sel:IsA("ModuleScript") then
		self:log("warn", "select a ModuleScript in the Explorer first")
		return
	end
	local v, err = freshRequire(sel)
	if type(v) ~= "table" then
		self:log("error", "couldn't load " .. sel.Name .. ": " .. tostring(err))
		return
	end
	if v.branches or v.nodes then
		self:load(v, sel, nil, false)
		return
	end
	-- a set of moves: pick one
	local items = {}
	for slot, move in pairs(v) do
		local s = type(move) == "table" and (move.skill or ((move.branches or move.nodes) and move))
		if s then
			table.insert(items, { text = tostring(slot), onClick = function()
				self:load(s, sel, tostring(slot), true)
			end })
		end
	end
	if #items == 0 then
		self:log("warn", sel.Name .. " has no skills in it")
		return
	end
	Ui.menu(Vector2.new(300, 60), items, 240)
end

function App:sourceText(): string
	local compact = Serialize.compact(self.skill, self.SK.Schema.Defaults)
	return Serialize.toSource(compact, ("-- SkillKit skill \"%s\" (made with the SkillKit editor)\n"):format(self.skill.name or "Skill"))
end

-- a menu of every character slot; empty slots first in each character. onPick(entry, slot)
function App:pickSlot(title: string, onPick: (any, string) -> ())
	local items: { any } = { { header = true, text = string.upper(title) } }
	local chars = Tree.characters()
	for _, entry in ipairs(chars) do
		table.insert(items, { header = true, text = tostring(entry.def.name) })
		for _, slot in ipairs(Tree.SLOTS) do
			local cur = entry.def.skills[slot]
			table.insert(items, {
				text = slot .. (cur and ("  (replaces " .. cur .. ")") or "  (empty)"),
				color = cur and C.warn or C.good,
				onClick = function()
					onPick(entry, slot)
				end,
			})
		end
	end
	table.insert(items, { text = "+ New character", color = C.accent, onClick = function()
		self:newCharacter()
	end })
	local top = self.top :: Frame
	Ui.menu(Vector2.new(top.AbsolutePosition.X + 160, top.AbsolutePosition.Y + 44), items, 300)
end

function App:save()
	if not self.skill then
		return
	end

	local name = (self.skill.name or "Skill"):gsub("[^%w_ %-]", "")
	local id = ChangeHistoryService:TryBeginRecording("Save SkillKit skill")
	local target = (not self.readOnly) and self.source or nil
	if not target or not target.Parent then
		local folder = self:skillsFolder(true) :: Folder
		-- a new module; never overwrite another skill that happens to have the same name
		local unique, n = name, 1
		while folder:FindFirstChild(unique) do
			n += 1
			unique = name .. " " .. n
		end
		local m = Instance.new("ModuleScript")
		m.Name = unique
		m.Parent = folder
		target = m
	end
	(target :: any).Source = self:sourceText()
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
	self.source = target
	self.readOnly = false
	self.dirty = false
	self:log("info", "saved to " .. (target :: Instance):GetFullName())
	local ctx = self.slotCtx
	if ctx and ctx.entry.def.skills[ctx.slot] ~= (target :: Instance).Name then
		self:assignSlot(ctx.entry, ctx.slot, (target :: Instance).Name)
		self.slotCtx = ctx
	end
	if self.sourceKey then
		self:log("warn", "this was a game move: the copy is saved, paste it into the move file with Code to replace it there")
	end
	self:render()
end

function App:codeWindow()
	local body = Ui.modal("Code", 640, 520)
	local tabs = Ui.frame(body, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28) })
	Ui.list(tabs, 6, true)
	local area = Ui.frame(body, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36) })
	local function showText(text: string, note: string)
		area:ClearAllChildren()
		Ui.text(area, note, { TextColor3 = C.dim, TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), ZIndex = 63 })
		local box = Instance.new("TextBox")
		box.MultiLine = true
		box.ClearTextOnFocus = false
		box.TextEditable = true
		box.TextWrapped = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = Enum.TextYAlignment.Top
		box.Font = Ui.FontMono
		box.TextSize = 12
		box.TextColor3 = C.text
		box.BackgroundColor3 = C.field
		box.Position = UDim2.fromOffset(0, 38)
		box.Size = UDim2.new(1, 0, 1, -38)
		box.Text = text
		box.ZIndex = 63
		Ui.corner(box, 6)
		Ui.pad(box, 8)
		box.Parent = area
		return box
	end
	Ui.button(tabs, "Luau", function()
		showText(self:sourceText(), "The skill as Luau. Click in the box, Ctrl+A, Ctrl+C, and paste it into a .luau file (or a move's `skill = ...`).")
	end, { ZIndex = 63 })
	Ui.button(tabs, "SK1 code", function()
		local copy = self.SK.Schema.copy(self.skill)
		showText(self.SK.Codec.encode(copy), "A short shareable code. SkillKit.cast accepts it directly.")
	end, { ZIndex = 63 })
	Ui.button(tabs, "Import", function()
		local box = showText("", "Paste an SK1: code or Luau that starts with `return {`, then press Load.")
		Ui.button(area, "Load", function()
			local text = box.Text
			local skill
			if string.sub(text, 1, 4) == "SK1:" then
				skill = self.SK.Codec.decode(text)
			else
				local m = Instance.new("ModuleScript")
				m.Source = string.find(text, "^%s*return") and text or ("return " .. text)
				m.Parent = Workspace
				local ok, v = pcall(require, m)
				m:Destroy()
				skill = ok and v or nil
			end
			if type(skill) == "table" and (skill.branches or skill.nodes) then
				Ui.closePopup()
				self:load(skill, nil, nil, false)
				self.dirty = true
			else
				self:log("error", "that isn't a skill")
			end
		end, { Position = UDim2.new(1, -80, 0, 0), ZIndex = 64 })
	end, { ZIndex = 63 })
	showText(self:sourceText(), "The skill as Luau. Click in the box, Ctrl+A, Ctrl+C, and paste it into a .luau file (or a move's `skill = ...`).")
end

-- PREVIEW -----------------------------------------------------------------------------------------------------------------------
function App:play()
	if not self.skill then
		return
	end
	self.preview.speed = self.speed
	local copy = self.SK.Schema.copy(self.skill)
	self.SK.Schema.normalize(copy)
	-- keep the ids so log lines and the playhead find their cards
	self.logLines = {}
	self.preview:play(copy, self.branch)
	self:renderLog()
end

function App:onPreviewEvent(e: any)
	if e.kind ~= "node" then
		self:log(e.kind, e.msg, e.t)
	end
	if e.nodeId then
		self.activeNode = e.nodeId
		self:flashNode(e.nodeId)
	end
end

function App:flashNode(id: string)
	for node, frame in pairs(self.nodeFrames) do
		if node.id == id and frame.Parent then
			local s = frame:FindFirstChild("Hi") :: Frame?
			if s then
				s.BackgroundTransparency = 0.55
				task.delay(0.25, function()
					if s.Parent then
						s.BackgroundTransparency = 1
					end
				end)
			end
		end
	end
end

function App:log(kind: string, msg: string, t: number?)
	table.insert(self.logLines, { kind = kind, msg = msg, t = t })
	if #self.logLines > 200 then
		table.remove(self.logLines, 1)
	end
	self:renderLog()
	local st = self.statusLabel
	if st and st.Parent then
		st.Text = msg
		st.TextColor3 = (kind == "error" and C.bad) or (kind == "warn" and C.warn) or (kind == "hit" and C.good) or C.dim
	end
end

-- RENDER ----------------------------------------------------------------------------------------------------------------------
function App:open()
	if self.gui then
		self.gui.Enabled = true
		pcall(self.preview.ensureRigs, self.preview)
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillKitEditor"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Archivable = false
	gui.Parent = CoreGui
	self.gui = gui
	local root = Ui.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	self.root = root
	Ui.setHost(root)
	-- screen effects of the preview play inside the overlay
	local fxLayer = Ui.frame(root, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 })
	self.SK.Fx.config.screenParent = fxLayer
	self.top = Ui.frame(root, { Size = UDim2.new(1, 0, 0, TOP_H), BackgroundColor3 = C.bg })
	self.left = Ui.frame(root, { Position = UDim2.fromOffset(0, TOP_H), BackgroundColor3 = C.panel })
	self.timeline = Ui.frame(root, { BackgroundColor3 = C.bg })
	self.logPanel = Ui.frame(root, { AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = C.panel, BackgroundTransparency = 0.08 })
	Ui.corner(self.logPanel, 8)
	self:layout()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if self.gui and self.gui.Enabled then
			self:layout()
			self:render()
		end
	end)
	-- keep preview / fx instances out of the saved place
	Workspace.ChildAdded:Connect(function(c)
		if c.Name == "SkillKitFx" or c.Name == "SkillKitPreview" then
			c.Archivable = false
		end
	end)
	if not self.skill then
		self:load(self.SK.TestSkills.Combo or newSkill("New skill"), nil, nil, false)
		self.openExample = "Combo"
		self.nav = { level = "home" }
	end
	-- Space plays / stops while the editor is open (not while typing in a box)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not (self.gui and self.gui.Enabled) then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
			self:togglePlay()
		end
	end)
	self:render()
	-- the two preview dummies appear on the floor in front of the camera as soon as the editor opens
	pcall(self.preview.ensureRigs, self.preview)
end

-- sizes the panels to the viewport so the middle stays free for moving the camera
function App:layout()
	if not self.gui then
		return
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	if self.show.log == nil then
		self.show.log = vp.X >= 1500
	end
	local leftW = math.floor(math.clamp(vp.X * 0.3, 300, 420))
	local logW = math.floor(math.clamp(vp.X * 0.2, 220, 320))
	local timeH = math.floor(math.clamp(vp.Y * 0.24, 120, 200))
	local showLeft = self.show.left and not self.hidden
	local showTime = self.show.timeline and not self.hidden
	local showLog = self.show.log and not self.hidden
	local bottom = showTime and timeH or 0
	self.left.Visible = showLeft
	self.left.Position = UDim2.fromOffset(0, TOP_H)
	self.left.Size = UDim2.new(0, leftW, 1, -TOP_H - bottom)
	self.timeline.Visible = showTime
	self.timeline.Position = UDim2.new(0, 0, 1, -timeH)
	self.timeline.Size = UDim2.new(1, 0, 0, timeH)
	self.logPanel.Visible = showLog
	self.logPanel.Position = UDim2.new(1, -8, 0, TOP_H + 8)
	self.logPanel.Size = UDim2.new(0, logW, 1, -TOP_H - bottom - 16)
end

-- points the editor camera at the preview dummies (spawns them if needed)
function App:viewDummies()
	self.preview:ensureRigs()
	local a, b = self.preview.caster, self.preview.dummy
	local pa = a and a:FindFirstChild("HumanoidRootPart")
	local pb = b and b:FindFirstChild("HumanoidRootPart")
	if not (pa and pb) then
		return
	end
	local mid = (pa.Position + pb.Position) / 2
	local side = (pb.Position - pa.Position)
	side = Vector3.new(side.X, 0, side.Z)
	side = side.Magnitude > 0 and side.Unit or Vector3.new(1, 0, 0)
	local out = side:Cross(Vector3.yAxis) -- perpendicular: see both side-on
	local cam = Workspace.CurrentCamera
	local from = mid + out * 22 + Vector3.new(0, 7, 0)
	-- stay on the side the camera is already on
	if (cam.CFrame.Position - (mid - out * 22)).Magnitude < (cam.CFrame.Position - from).Magnitude then
		from = mid - out * 22 + Vector3.new(0, 7, 0)
	end
	cam.CFrame = CFrame.lookAt(from, mid)
	cam.Focus = CFrame.new(mid)
end

-- TREE / CHARACTERS / FLOW ------------------------------------------------------------------------------------------------------
function App:flowWindow()
	Flow.open(self)
end

-- open a node from the tree: its branch, the Loop / Group chain it sits in, selected and expanded
function App:jumpTo(branch: string, chain: { any }, node: any)
	self.branch = branch
	self.path = table.clone(chain)
	if not self.show.left then
		self.show.left = true
		self:layout()
	end
	local parent = (self.nav and self.nav.level == "node") and self.nav.parent or self.nav
	if not parent or parent.level ~= "skill" then
		parent = { level = "skill", parent = { level = "home" } }
	end
	self:go({ level = "node", node = node, parent = parent })
	self.selected = { [node] = true }
	task.delay(0.05, function()
		local f = self.nodeFrames[node]
		local sc = self.listFrame
		if f and sc and f.Parent then
			local y = f.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y - 6
			sc.CanvasPosition = Vector2.new(0, math.max(0, y))
		end
	end)
end

local function mouseAt(): Vector2
	local ok, p = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	return ok and p or Vector2.new(260, 120)
end

function App:assignSlot(entry: any, slot: string, skillName: string?)
	entry.def.skills[slot] = skillName
	entry.module = Tree.saveCharacter(entry.def, entry.module)
	self:log("info", ("%s · %s = %s"):format(tostring(entry.def.name), slot, skillName or "(empty)"))
	self:render()
end

function App:openSlot(entry: any, slot: string)
	local name = entry.def.skills[slot]
	local folder = self:skillsFolder(false)
	local m = folder and folder:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		self:log("warn", ("%s · %s points at %q, which isn't in SkillKitSkills"):format(tostring(entry.def.name), slot, tostring(name)))
		self:slotMenu(entry, slot)
		return
	end
	local s, err = Tree.freshRequire(m)
	if type(s) ~= "table" then
		self:log("error", "couldn't load " .. m.Name .. ": " .. tostring(err))
		return
	end
	self:load(s, m, nil, false)
	self.slotCtx = { entry = entry, slot = slot }
	self:render()
end

function App:slotMenu(entry: any, slot: string)
	local def = entry.def
	local items: { any } = { { header = true, text = string.upper(tostring(def.name) .. " · " .. slot) } }
	table.insert(items, { text = "New skill in this slot", color = C.good, onClick = function()
		self:load({ name = tostring(def.name) .. " " .. slot, cooldown = 2, branches = { Default = {} } }, nil, nil, false)
		self.slotCtx = { entry = entry, slot = slot }
		self:log("info", "new skill for " .. slot .. ": press Save to put it in the slot")
		self:render()
	end })
	if self.skill then
		table.insert(items, { text = "Put the open skill here (" .. tostring(self.skill.name) .. ")", color = C.accent, onClick = function()
			self.slotCtx = { entry = entry, slot = slot }
			self:save()
		end })
	end
	local saved = Tree.savedSkills()
	if #saved > 0 then
		table.insert(items, { header = true, text = "SAVED SKILLS" })
		for _, m in ipairs(saved) do
			table.insert(items, { text = m.Name, onClick = function()
				self:assignSlot(entry, slot, m.Name)
			end })
		end
	end
	if def.skills[slot] then
		table.insert(items, { header = true, text = "" })
		table.insert(items, { text = "Clear slot", color = C.bad, onClick = function()
			self:assignSlot(entry, slot, nil)
		end })
	end
	Ui.menu(mouseAt(), items, 280)
end

function App:newCharacter()
	local existing = {}
	for _, e in ipairs(Tree.characters()) do
		existing[tostring(e.def.id)] = true
	end
	local n = 1
	while existing["Character" .. n] do
		n += 1
	end
	local def = {
		id = "Character" .. n,
		name = "Character " .. n,
		stats = table.clone(Tree.DEFAULT_STATS),
		keys = {},
		skills = {},
	}
	for slot, k in pairs(Tree.DEFAULT_KEYS) do
		def.keys[slot] = table.clone(k)
	end
	local entry = { def = def, module = nil }
	entry.module = Tree.saveCharacter(def, nil)
	self.treeOpen["c:" .. def.id] = true
	self.treeOpen.chars = true
	self:log("info", "made " .. (entry.module :: Instance):GetFullName())
	self:go({ level = "character", entry = entry })
	self:characterWindow(entry)
end

-- name, stats and keybinds of a character
function App:characterWindow(entry: any)
	local def = self.SK.Schema.copy(entry.def)
	def.stats = def.stats or {}
	def.keys = def.keys or {}
	def.skills = def.skills or {}
	local vp = Workspace.CurrentCamera.ViewportSize
	local body = Ui.modal("Character: " .. tostring(def.name), math.min(560, vp.X - 40), math.min(560, vp.Y - 40))
	local sc = Instance.new("ScrollingFrame")
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Size = UDim2.new(1, 0, 1, -40)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	sc.ScrollBarThickness = 4
	sc.ZIndex = 62
	sc.Parent = body
	Ui.list(sc, 6)
	local order = 0
	local function o(): number
		order += 1
		return order
	end
	local function rowOf(label: string): Frame
		local r = Ui.frame(sc, { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 26), LayoutOrder = o(), ZIndex = 62 })
		Ui.text(r, label, { Size = UDim2.new(0, 120, 1, 0), TextColor3 = C.dim, TextSize = 13, ZIndex = 63 })
		return r
	end
	local function head(text: string)
		Ui.text(sc, text, { Font = Ui.FontBold, TextSize = 13, TextColor3 = C.accent, LayoutOrder = o(), ZIndex = 63, Size = UDim2.new(1, 0, 0, 22) })
	end
	head("IDENTITY")
	local r = rowOf("name")
	Ui.input(r, tostring(def.name or ""), function(t)
		if t ~= "" then
			def.name = t
		end
	end, { Position = UDim2.fromOffset(124, 0), Size = UDim2.new(1, -124, 1, 0), ZIndex = 63 })
	r = rowOf("id")
	Ui.text(r, tostring(def.id) .. "   (module name)", { Position = UDim2.fromOffset(124, 0), Size = UDim2.new(1, -124, 1, 0), ZIndex = 63, TextColor3 = C.dim })
	head("STATS")
	local statNames = {}
	for _, k in ipairs({ "health", "walkSpeed", "sprintSpeed", "jumpPower", "damageMult", "defenseMult" }) do
		table.insert(statNames, k)
	end
	for k in pairs(def.stats) do
		if not table.find(statNames, k) then
			table.insert(statNames, k)
		end
	end
	for _, k in ipairs(statNames) do
		r = rowOf(k)
		Ui.input(r, def.stats[k] ~= nil and Ui.fmt(def.stats[k]) or "", function(t)
			def.stats[k] = tonumber(t)
		end, { Position = UDim2.fromOffset(124, 0), Size = UDim2.new(0, 100, 1, 0), ZIndex = 63, PlaceholderText = tostring(Tree.DEFAULT_STATS[k] or "") })
	end
	head("KEYBINDS  (KeyCode / UserInputType names: One, Q, MouseButton1, ButtonX …)")
	r = rowOf("")
	Ui.text(r, "PC", { Position = UDim2.fromOffset(124, 0), Size = UDim2.fromOffset(150, 26), TextColor3 = C.dim, TextSize = 12, ZIndex = 63 })
	Ui.text(r, "Gamepad", { Position = UDim2.fromOffset(282, 0), Size = UDim2.fromOffset(150, 26), TextColor3 = C.dim, TextSize = 12, ZIndex = 63 })
	for _, slot in ipairs(Tree.SLOTS) do
		def.keys[slot] = def.keys[slot] or table.clone(Tree.DEFAULT_KEYS[slot] or { pc = "", gamepad = "" })
		local k = def.keys[slot]
		r = rowOf(slot .. (def.skills[slot] and ("  · " .. def.skills[slot]) or ""))
		Ui.input(r, k.pc or "", function(t)
			k.pc = t
		end, { Position = UDim2.fromOffset(124, 0), Size = UDim2.fromOffset(150, 26), ZIndex = 63 })
		Ui.input(r, k.gamepad or "", function(t)
			k.gamepad = t
		end, { Position = UDim2.fromOffset(282, 0), Size = UDim2.fromOffset(150, 26), ZIndex = 63 })
	end
	Ui.button(body, "Save character", function()
		-- inputs commit on focus lost; give a pending one a frame
		task.defer(function()
			entry.def = def
			entry.module = Tree.saveCharacter(def, entry.module)
			Ui.closePopup()
			self:log("info", "saved character " .. tostring(def.name))
			self:render()
		end)
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(150, 30), BackgroundColor3 = C.good, ZIndex = 63 })
	Ui.text(body, "Saved to ReplicatedStorage.SkillKitCharacters. In the game: SkillKit.defineCharacter(require(module)).", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -160, 0, 30), TextColor3 = C.dim, TextSize = 11, TextWrapped = true, ZIndex = 63 })
end

-- JJS IMPORT ---------------------------------------------------------------------------------------------------------------------
-- writes a skill table to ReplicatedStorage.SkillKitSkills/<name> (no editor state involved)
function App:writeSkill(skill: any): ModuleScript
	local name = (tostring(skill.name or "Skill")):gsub("[^%w_ %-]", "")
	local folder = self:skillsFolder(true) :: Folder
	local m = folder:FindFirstChild(name) :: ModuleScript?
	if not m then
		local nm = Instance.new("ModuleScript")
		nm.Name = name
		nm.Parent = folder
		m = nm
	end
	local copy = self.SK.Schema.copy(skill)
	self.SK.Schema.normalize(copy)
	copy.__normalized = nil
	local compact = Serialize.compact(copy, self.SK.Schema.Defaults);
	(m :: any).Source = Serialize.toSource(compact, ("-- SkillKit skill \"%s\" (imported from a JJS code)\n"):format(tostring(skill.name)))
	return m :: ModuleScript
end

-- import notes, grouped: the same message from several places shows once with a count
function App:showNotes(title: string, notes: { string })
	local order, counts = {}, {}
	for _, nt in ipairs(notes) do
		-- drop the "move: branch #n NODE: " location so identical swaps group together
		local msg = nt:match("#%d+ [%u_]+: (.+)$") or nt:match("^[^:]+: (.+)$") or nt
		if not counts[msg] then
			counts[msg] = 0
			table.insert(order, msg)
		end
		counts[msg] += 1
	end
	self:log("info", ("%s: %d note(s), %d different"):format(title, #notes, #order))
	for _, msg in ipairs(order) do
		self:log("warn", counts[msg] > 1 and ("%s  (x%d)"):format(msg, counts[msg]) or msg)
	end
	if #notes > 0 and not self.show.log then
		self.show.log = true
		self.hidden = false
		self:layout()
		self:render()
	end
end

function App:jjsWindow(prefill: string?)
	local vp = Workspace.CurrentCamera.ViewportSize
	local body = Ui.modal("Import JJS code", math.min(620, vp.X - 40), math.min(440, vp.Y - 40))
	Ui.text(body, "Paste a Jujutsu Shenanigans character code. Its moves become SkillKit skills: timings, hitboxes, branches and tags carry over; JJS's own animations and effects are swapped for the closest built-in ones (listed in the log).", { Size = UDim2.new(1, 0, 0, 48), TextWrapped = true, TextColor3 = C.dim, TextSize = 13, ZIndex = 63, TextYAlignment = Enum.TextYAlignment.Top })
	local box = Ui.input(body, prefill or "", function() end, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -100), MultiLine = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ClearTextOnFocus = false, Font = Ui.FontMono, TextSize = 12, ZIndex = 63, PlaceholderText = "paste the code here" })
	local status = Ui.text(body, "", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -330, 0, 34), TextColor3 = C.bad, TextSize = 12, TextWrapped = true, ZIndex = 63 })
	local function decoded(): any
		local moves, err = Jjs.decode(box.Text)
		if not moves then
			status.Text = err or "couldn't read that code"
			return nil
		end
		if #moves == 0 then
			status.Text = "the code has no moves"
			return nil
		end
		return moves
	end
	Ui.button(body, "Open a move...", function()
		local moves = decoded()
		if not moves then
			return
		end
		local items = { { header = true, text = ("%d MOVE(S) IN THE CODE"):format(#moves) } }
		for _, mv in ipairs(moves) do
			table.insert(items, { text = ("%s   (%s)"):format(tostring(mv.NAME), Jjs.slotOf(mv)), onClick = function()
				local skill, notes = Jjs.convert(mv)
				self:load(skill, nil, nil, false)
				self.dirty = true
				self:showNotes("imported " .. tostring(mv.NAME), notes)
			end })
		end
		Ui.menu(Vector2.new(body.AbsolutePosition.X + 120, body.AbsolutePosition.Y + 60), items, 320)
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -170, 1, 0), Size = UDim2.fromOffset(150, 32), ZIndex = 63, BackgroundColor3 = C.accent })
	Ui.button(body, "Import as character", function()
		local moves = decoded()
		if not moves then
			return
		end
		Ui.closePopup()
		self:importJjsCharacter(moves)
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(160, 32), ZIndex = 63, BackgroundColor3 = C.good })
	box:CaptureFocus()
end

-- every move becomes a saved skill, and a character gets them in its slots
function App:importJjsCharacter(moves: { any }, charName: string?)
	local recording = ChangeHistoryService:TryBeginRecording("Import JJS character")
	local def = {
		id = "",
		name = charName or "JJS import",
		stats = table.clone(Tree.DEFAULT_STATS),
		keys = {},
		skills = {},
	}
	local existing = {}
	for _, e in ipairs(Tree.characters()) do
		existing[tostring(e.def.id)] = true
	end
	local n = 1
	while existing["JJS" .. n] do
		n += 1
	end
	def.id = "JJS" .. n
	if not charName then
		def.name = "JJS import " .. n
	end
	for slot, k in pairs(Tree.DEFAULT_KEYS) do
		def.keys[slot] = table.clone(k)
	end
	local allNotes = {}
	local extras = 0
	local first
	-- several MELEE moves are JJS's M1 combo: merge them into one M1 skill
	local melees, rest = {}, {}
	for _, mv in ipairs(moves) do
		table.insert(mv.K_NAME == "MELEE" and melees or rest, mv)
	end
	local items: { any } = {}
	if #melees > 1 then
		local skill, notes = Jjs.convertCombo(melees, "M1 combo")
		table.insert(items, { move = { NAME = "M1 combo", K_NAME = "MELEE" }, skill = skill, notes = notes })
	elseif #melees == 1 then
		table.insert(rest, 1, melees[1])
	end
	for _, mv in ipairs(rest) do
		local skill, notes = Jjs.convert(mv)
		table.insert(items, { move = mv, skill = skill, notes = notes })
	end
	for _, it in ipairs(items) do
		local mv, skill, notes = it.move, it.skill, it.notes
		local slot = Jjs.slotOf(mv)
		if def.skills[slot] then
			-- a second move for the same slot: Skill1..4 then Custom, else keep it saved without a slot
			for _, alt in ipairs({ "Skill1", "Skill2", "Skill3", "Skill4", "Custom", "Passive" }) do
				if not def.skills[alt] then
					slot = alt
					break
				end
			end
		end
		-- a readable name: "<character> <slot>", plus the JJS move name when it says something ("1", "2" don't)
		local jname = tostring(mv.NAME or "")
		local named = jname ~= "" and not tonumber(jname) and jname ~= slot
		local extra = 0
		if def.skills[slot] then
			extras += 1
			extra = extras
		end
		skill.name = def.id .. " " .. (extra > 0 and ("Extra" .. extra) or slot) .. (named and (" " .. jname) or "")
		local m = self:writeSkill(skill)
		if not def.skills[slot] then
			def.skills[slot] = m.Name
		else
			table.insert(allNotes, m.Name .. ": no free slot, saved without one")
		end
		for _, nt in ipairs(notes) do
			table.insert(allNotes, tostring(mv.NAME) .. ": " .. nt)
		end
		first = first or { skill = skill, module = m, slot = slot }
	end
	local cm = Tree.saveCharacter(def, nil)
	-- keep the decoded JJS data next to the character, for checking the import later
	pcall(function()
		local raw = Instance.new("StringValue")
		raw.Name = "JJSSource"
		raw.Value = HttpService:JSONEncode(moves)
		raw.Parent = cm
	end)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if first then
		self:load(first.skill, first.module, nil, false)
		for _, e in ipairs(Tree.characters()) do
			if e.module == cm then
				self.slotCtx = { entry = e, slot = first.slot }
				self.nav = { level = "character", entry = e }
			end
		end
	end
	self:showNotes(("imported %d move(s) into %s"):format(#moves, cm:GetFullName()), allNotes)
	self:render()
	return def, cm
end

function App:close()
	self.preview:clear()
	if self.gui then
		self.gui.Enabled = false
	end
	Ui.closePopup()
end

function App:render()
	if not self.gui or not self.skill then
		return
	end
	self:renderTop()
	self:renderLeft()
	self:renderTimeline()
	self:renderLog()
end

function App:renderTop()
	local top = self.top :: Frame
	top:ClearAllChildren()
	Ui.pad(top, 10, 10, 8, 8)
	local row = Instance.new("ScrollingFrame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -36, 1, 0)
	row.CanvasSize = UDim2.new()
	row.AutomaticCanvasSize = Enum.AutomaticSize.X
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.ScrollBarThickness = 3
	row.Parent = top
	Ui.list(row, 6, true)
	local order = 0
	local function o(): number
		order += 1
		return order
	end
	local function gap()
		Ui.frame(row, { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = o() })
	end
	local function b(text: string, tip: string?, fn: () -> (), color: Color3?): TextButton
		local bt = Ui.button(row, text, fn, { LayoutOrder = o(), Size = UDim2.fromOffset(#text * 7 + 14, 30), BackgroundColor3 = color or C.card })
		if tip then
			Ui.tip(bt, tip)
		end
		return bt
	end
	local function menuButton(text: string, tip: string, items: () -> { any }): TextButton
		local bt: TextButton
		bt = b(text .. " ▼", tip, function()
			Ui.menu(bt.AbsolutePosition + Vector2.new(0, 34), items(), 230)
		end)
		return bt
	end

	-- skill name and cooldown
	local nameBox = Ui.input(row, self.skill.name or "", function(t)
		if t ~= "" and t ~= self.skill.name then
			self.skill.name = t
			self:changed()
		end
	end, { Size = UDim2.fromOffset(150, 30), LayoutOrder = o(), Font = Ui.FontBold, PlaceholderText = "skill name" })
	Ui.tip(nameBox, "Skill name (also the saved module's name)")
	local cd = Ui.input(row, Ui.fmt(self.skill.cooldown or 1), function(t)
		local n = tonumber(t)
		if n then
			self.skill.cooldown = n
			self:changed()
		end
	end, { Size = UDim2.fromOffset(56, 30), LayoutOrder = o(), PlaceholderText = "cd" })
	Ui.text(cd, "cd", { Position = UDim2.new(1, -18, 0, 0), Size = UDim2.fromOffset(16, 30), TextColor3 = C.dim, TextSize = 11 })
	Ui.tip(cd, "Cooldown in seconds")
	gap()

	-- file
	menuButton("File", "New, open, import / export", function()
		return {
			{ text = "New skill", onClick = function()
				self:load(newSkill("New skill"), nil, nil, false)
			end },
			{ text = "New skill in a character slot...", onClick = function()
				self:pickSlot("New skill: which slot?", function(entry, slot)
					self:load(newSkill(tostring(entry.def.name) .. " " .. slot), nil, nil, false)
					self.slotCtx = { entry = entry, slot = slot }
					self:render()
				end)
			end },
			{ text = "Open...", onClick = function()
				self:openMenu(Vector2.new(self.top.AbsolutePosition.X + 160, self.top.AbsolutePosition.Y + 44))
			end },
			{ text = "Open selected (Explorer)", onClick = function()
				self:openSelected()
			end },
			{ text = "Code: copy / share / import", onClick = function()
				self:codeWindow()
			end },
			{ text = "Import JJS code...", color = C.warn, onClick = function()
				self:jjsWindow()
			end },
			{ text = "Save", color = C.accent, onClick = function()
				self:save()
			end },
		}
	end)
	b(self.dirty and "Save •" or "Save", self.source and ("Save to " .. self.source:GetFullName()) or "Save to ReplicatedStorage.SkillKitSkills", function()
		self:save()
	end, self.dirty and C.accent or nil)
	local undoB = b("Undo", ("Undo the last edit (%d)"):format(#self.undoStack), function()
		self:undo()
	end)
	undoB.TextTransparency = #self.undoStack == 0 and 0.6 or 0
	local redoB = b("Redo", ("Redo (%d)"):format(#self.redoStack), function()
		self:redo()
	end)
	redoB.TextTransparency = #self.redoStack == 0 and 0.6 or 0
	gap()

	-- preview
	local playing = self.preview.running ~= nil
	b(playing and "■ Stop" or "▶ Play", "Play the skill on the dummies (Space)", function()
		self:togglePlay()
	end, playing and C.bad or C.good)
	b(("×%s"):format(Ui.fmt(self.speed)), "Preview speed: 1, 0.5, 0.25, 2", function()
		local steps = { 1, 0.5, 0.25, 2 }
		local i = table.find(steps, self.speed) or 1
		self.speed = steps[i % #steps + 1]
		self:savePrefs()
		self:renderTop()
	end)
	menuButton("Preview", "The preview dummies, and what Check nodes see", function()
		local function cond(text: string, key: string)
			local on = self.preview:conditions()[key] == true
			return { text = text .. (on and "   (yes)" or "   (no)"), color = on and C.good or C.line, onClick = function()
				local c = self.preview:conditions()
				c[key] = not c[key]
			end }
		end
		return {
			{ text = "Bring dummies in front of me", onClick = function()
				self.preview:stop()
				local existed = self.preview.caster ~= nil and self.preview.caster.Parent ~= nil
				self.preview:ensureRigs()
				if existed then
					self.preview:placeHere()
				end
			end },
			{ text = "Look at dummies", onClick = function()
				self:viewDummies()
			end },
			{ text = "Reset poses and tags (combo counters)", onClick = function()
				self.preview:stop()
				self.preview:resetPositions()
			end },
			{ text = "Clear effects", onClick = function()
				self.preview:clear()
			end },
			{ header = true, text = "PRETEND (FOR CHECK NODES)" },
			cond("Caster is in the air", "inAir"),
			cond("Caster is jumping", "jumping"),
			cond("Skill key is held", "holding"),
			cond("Aiming at the dummy", "aiming"),
			cond("Dummy attacks during counters", "counterHit"),
			{ text = ("Caster health: %d%%  (click to change)"):format(math.floor(self.preview:conditions().health * 100 + 0.5)), onClick = function()
				local c = self.preview:conditions()
				local steps = { 1, 0.5, 0.2 }
				local i = table.find(steps, c.health) or 1
				c.health = steps[i % #steps + 1]
			end },
		}
	end)
	gap()

	-- views
	menuButton("View", "Panels and the branch flow view", function()
		local function item(text: string, on: boolean, fn: () -> ())
			return { text = text .. (on and "   (on)" or "   (off)"), color = on and C.good or C.line, onClick = fn }
		end
		local function flip(key: string)
			return function()
				self.hidden = false
				self.show[key] = not self.show[key]
				self:layout()
				self:savePrefs()
				self:render()
			end
		end
		return {
			item("Node panel", self.show.left and not self.hidden, flip("left")),
			{ text = "Branch flow (how branches connect)", onClick = function()
				self:flowWindow()
			end },
			item("Timeline", self.show.timeline and not self.hidden, flip("timeline")),
			item("Log", self.show.log and not self.hidden, flip("log")),
			{ text = self.hidden and "Show all panels" or "Hide all panels (free the 3D view)", onClick = function()
				self.hidden = not self.hidden
				self:layout()
				self:render()
			end },
		}
	end)

	-- status: the last message (click to open the log)
	local last = self.logLines[#self.logLines]
	local statusText, statusColor
	if last then
		statusText = last.msg
		statusColor = (last.kind == "error" and C.bad) or (last.kind == "warn" and C.warn) or (last.kind == "hit" and C.good) or C.dim
	else
		statusText = self.readOnly and "read-only: Save makes a copy" or (self.source and self.source.Name or "not saved yet")
		statusColor = C.dim
	end
	local st = Ui.button(row, statusText, function()
		self.hidden = false
		self.show.log = not self.show.log
		self:layout()
		self:render()
	end, { LayoutOrder = 99, Size = UDim2.fromOffset(170, 30), BackgroundTransparency = 1, Font = Ui.Font, TextSize = 12, TextColor3 = statusColor, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.tip(st, "Last message. Click to show / hide the log")
	self.statusLabel = st
	local x = Ui.button(top, "X", function()
		self:close()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.bad })
	Ui.tip(x, "Close the editor")
end

-- UNDO / PREFS / KEYS -----------------------------------------------------------------------------------------------------------
function App:snapshot()
	self.lastSnap = self.SK.Schema.copy(self.skill)
end

function App:restore(skill: any)
	self.skill = skill
	if not skill.branches[self.branch] then
		self.branch = "Default"
	end
	self.path = {}
	self.selected = {}
	self.dirty = true
	self:snapshot()
	self:render()
end

function App:undo()
	local prev = table.remove(self.undoStack)
	if not prev then
		return
	end
	table.insert(self.redoStack, self.SK.Schema.copy(self.skill))
	self:restore(prev)
	self:log("info", "undo")
end

function App:redo()
	local nxt = table.remove(self.redoStack)
	if not nxt then
		return
	end
	table.insert(self.undoStack, self.SK.Schema.copy(self.skill))
	self:restore(nxt)
	self:log("info", "redo")
end

function App:togglePlay()
	if self.preview.running then
		self.preview:stop()
	else
		self:play()
	end
	task.delay(0.05, function()
		self:renderTop()
	end)
end

function App:savePrefs()
	if not self.plugin then
		return
	end
	pcall(function()
		self.plugin:SetSetting("SkillKitEditorPrefs", { left = self.show.left, timeline = self.show.timeline, log = self.show.log, leftMode = self.leftMode, speed = self.speed })
	end)
end

function App:loadPrefs()
	if not self.plugin then
		return
	end
	local ok, p = pcall(function()
		return self.plugin:GetSetting("SkillKitEditorPrefs")
	end)
	if ok and type(p) == "table" then
		if p.left ~= nil then
			self.show.left = p.left
		end
		if p.timeline ~= nil then
			self.show.timeline = p.timeline
		end
		if p.log ~= nil then
			self.show.log = p.log
		end
		if p.leftMode == "tree" or p.leftMode == "nodes" then
			self.leftMode = p.leftMode
		end
		if type(p.speed) == "number" then
			self.speed = p.speed
		end
	end
end

-- NAVIGATION ---------------------------------------------------------------------------------------------------------------
-- The left panel is one page at a time, like folders: Home (characters, skills, examples) > a character (its slots) >
-- a skill (the nodes of a branch) > a node (its settings). "< Back" goes up a level; ◀ ▶ step through the other items
-- at the same level. self.nav = { level = "home" | "character" | "group" | "skill" | "node", ... }
function App:go(nav: any)
	self.nav = nav
	self.selected = {}
	Ui.closePopup()
	self:render()
end

-- open a skill page from a list; parent is the page to come back to
function App:openSkillPage(load: () -> (), parent: any)
	load()
	self.branch = "Default"
	self.path = {}
	self:go({ level = "skill", parent = parent })
end

-- the skills a page lists, as { text, open = fn, ... } (used for lists and for ◀ ▶ on a skill page)
function App:skillItems(parent: any): { any }
	local out = {}
	if parent.level == "character" then
		local entry = parent.entry
		for _, slot in ipairs(Tree.SLOTS) do
			local name = entry.def.skills[slot]
			if name then
				table.insert(out, { key = slot, text = slot, open = function()
					self:openSlot(entry, slot)
				end })
			end
		end
	elseif parent.level == "group" then
		if parent.group == "loose" then
			local used = {}
			for _, e in ipairs(Tree.characters()) do
				for _, nm in pairs(e.def.skills) do
					used[nm] = true
				end
			end
			for _, m in ipairs(Tree.savedSkills()) do
				if not used[m.Name] then
					table.insert(out, { key = m, text = m.Name, module = m, open = function()
						local s, err = Tree.freshRequire(m)
						if type(s) == "table" then
							self:load(s, m, nil, false)
						else
							self:log("error", "couldn't load " .. m.Name .. ": " .. tostring(err))
						end
					end })
				end
			end
		elseif parent.group == "examples" then
			local names = {}
			for name in pairs(self.SK.TestSkills) do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in ipairs(names) do
				table.insert(out, { key = name, text = name, open = function()
					self:load(self.SK.TestSkills[name], nil, nil, false)
					self.openExample = name
				end })
			end
		elseif parent.group == "moves" then
			for _, sk in ipairs(parent.set.skills) do
				table.insert(out, { key = sk.slot, text = sk.slot, open = function()
					self:load(sk.skill, parent.set.module, sk.slot, true)
				end })
			end
		end
	end
	return out
end

-- which item of a parent's list is the open skill
function App:currentSkillKey(parent: any): any
	if parent.level == "character" then
		return self.slotCtx and self.slotCtx.slot
	elseif parent.group == "loose" then
		return self.source
	elseif parent.group == "examples" then
		return self.openExample
	elseif parent.group == "moves" then
		return self.sourceKey
	end
	return nil
end

function App:renderLeft()
	local left = self.left :: Frame
	local scrollY = self.listFrame and self.listFrame.CanvasPosition.Y or 0
	left:ClearAllChildren()
	self.nodeFrames = {}
	Ui.pad(left, 10, 10, 10, 10)
	Ui.list(left, 6)
	local nav = self.nav or { level = "skill", parent = { level = "home" } }
	self.nav = nav
	if nav.level == "node" and not table.find(self:list(), nav.node) then
		nav = nav.parent or { level = "skill", parent = { level = "home" } }
		self.nav = nav
	end

	-- header: < Back, title, ◀ ▶ -------------------------------------------------------------------------------------------
	local head = Ui.frame(left, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
	local title, back, siblings, here = "", nil, nil, nil
	if nav.level == "home" then
		title = "Characters & skills"
	elseif nav.level == "character" then
		title = tostring(nav.entry.def.name or nav.entry.def.id)
		back = { level = "home" }
		siblings = Tree.characters()
		for i, e in ipairs(siblings) do
			if e.module == nav.entry.module then
				here = i
			end
		end
		siblings = siblings and table.clone(siblings)
		if siblings then
			for i, e in ipairs(siblings) do
				siblings[i] = { go = { level = "character", entry = e } }
			end
		end
	elseif nav.level == "group" then
		title = nav.title or "Skills"
		back = { level = "home" }
	elseif nav.level == "skill" then
		title = tostring(self.skill and self.skill.name or "?") .. (self.readOnly and "  (read-only)" or "")
		back = nav.parent
		local items = self:skillItems(nav.parent or { level = "home" })
		if #items > 1 then
			local cur = self:currentSkillKey(nav.parent)
			siblings = {}
			for i, it in ipairs(items) do
				if it.key == cur then
					here = i
				end
				siblings[i] = { open = it.open }
			end
		end
		if #self.path > 0 then
			-- inside a Loop / Group: back goes out of it
			back = "inner"
			title = (self.path[#self.path].name or self.path[#self.path].type) .. "  (inside " .. tostring(self.skill.name) .. ")"
			siblings = nil
		end
	elseif nav.level == "node" then
		local list = self:list()
		title = Tree.summary(nav.node)
		back = nav.parent
		siblings = {}
		for i, n in ipairs(list) do
			if n == nav.node then
				here = i
			end
			siblings[i] = { go = { level = "node", node = n, parent = nav.parent } }
		end
	end
	local x = 0
	if back then
		local bb = Ui.button(head, "< Back", function()
			if back == "inner" then
				self:back()
			else
				self:go(back)
			end
		end, { Size = UDim2.fromOffset(62, 30), BackgroundColor3 = C.cardHi })
		Ui.tip(bb, "Up one level")
		x = 68
	end
	local navW = (siblings and #siblings > 1) and 64 or 0
	Ui.text(head, title, { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x - navW, 1, 0), Font = Ui.FontBold, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd })
	if siblings and #siblings > 1 and here then
		local function step(d: number)
			local i = (here - 1 + d) % #siblings + 1
			local s = siblings[i]
			if s.go then
				self:go(s.go)
			else
				self:openSkillPage(s.open, nav.parent)
			end
		end
		local p = Ui.button(head, "◀", function()
			step(-1)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -32, 0, 0), Size = UDim2.fromOffset(30, 30), TextSize = 12 })
		local n = Ui.button(head, "▶", function()
			step(1)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(30, 30), TextSize = 12 })
		Ui.tip(p, ("Previous (%d of %d)"):format(here, #siblings))
		Ui.tip(n, ("Next (%d of %d)"):format(here, #siblings))
	end

	-- the page's scrolling body
	local function body(extra: number): ScrollingFrame
		local sc = Instance.new("ScrollingFrame")
		sc.BackgroundTransparency = 1
		sc.BorderSizePixel = 0
		sc.Size = UDim2.new(1, 0, 1, -(36 + extra))
		sc.LayoutOrder = 10
		sc.ScrollBarThickness = 5
		sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sc.CanvasSize = UDim2.new()
		sc.Parent = left
		Ui.list(sc, 4)
		self.listFrame = sc
		task.defer(function()
			if sc.Parent then
				sc.CanvasPosition = Vector2.new(0, scrollY)
			end
		end)
		return sc
	end
	-- one clickable line in a list page
	local order = 0
	local function line(sc: Instance, text: string, opts: any)
		order += 1
		local r = Instance.new("TextButton")
		r.AutoButtonColor = true
		r.BorderSizePixel = 0
		r.BackgroundColor3 = opts.selected and C.cardHi or C.card
		r.Text = ""
		r.Size = UDim2.new(1, -6, 0, 34)
		r.LayoutOrder = order
		r.Parent = sc
		Ui.corner(r, 6)
		local stripe = Ui.frame(r, { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = opts.color or C.line })
		Ui.corner(stripe, 2)
		local rightW = 6
		for _, bt in ipairs(opts.buttons or {}) do
			local w = math.max(24, #bt.text * 7 + 10)
			local b = Ui.button(r, bt.text, bt.onClick, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightW, 0.5, 0), Size = UDim2.fromOffset(w, 22), TextSize = 12, BackgroundColor3 = C.field, TextColor3 = bt.color or C.text })
			if bt.tip then
				Ui.tip(b, bt.tip)
			end
			rightW += w + 4
		end
		Ui.text(r, text, { Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -14 - rightW, 0, opts.sub and 18 or 30), Font = Ui.FontBold, TextSize = 14, TextColor3 = opts.dim and C.dim or C.text, TextTruncate = Enum.TextTruncate.AtEnd })
		if opts.sub then
			Ui.text(r, opts.sub, { Position = UDim2.fromOffset(14, 17), Size = UDim2.new(1, -14 - rightW, 0, 15), TextSize = 12, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd })
		end
		if opts.onClick then
			r.Activated:Connect(opts.onClick)
		end
		if opts.tip then
			Ui.tip(r, opts.tip)
		end
		return r
	end
	local function del(title: string, message: string, run: () -> (), yes: string?)
		return { text = "X", color = C.bad, tip = yes or "Delete", onClick = function()
			self:confirm(title, message, yes or "Delete", run)
		end }
	end

	-- HOME: sections you can fold: Characters, Skills, Examples -------------------------------------------------------
	if nav.level == "home" then
		local sc = body(0)
		self.homeOpen = self.homeOpen or { characters = true, skills = true, examples = false }
		local function section(key: string, label: string, count: number?, color: Color3)
			order += 1
			local open = self.homeOpen[key] ~= false
			local h = Instance.new("TextButton")
			h.AutoButtonColor = true
			h.BorderSizePixel = 0
			h.BackgroundColor3 = C.bg
			h.Text = ""
			h.Size = UDim2.new(1, -6, 0, 28)
			h.LayoutOrder = order
			h.Parent = sc
			Ui.corner(h, 6)
			Ui.text(h, open and "▼" or "▶", { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(14, 28), TextColor3 = color, TextSize = 11 })
			Ui.text(h, string.upper(label) .. (count and ("   " .. count) or ""), { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), Font = Ui.FontBold, TextSize = 12, TextColor3 = color })
			local underline = Ui.frame(h, { Position = UDim2.new(0, 8, 1, -2), Size = UDim2.new(1, -16, 0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.6 })
			local _ = underline
			h.Activated:Connect(function()
				self.homeOpen[key] = not open
				self:renderLeft()
			end)
			return open
		end
		local function gap()
			order += 1
			Ui.frame(sc, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = order })
		end

		local chars = Tree.characters()
		if section("characters", "Characters", #chars, C.good) then
			for _, entry in ipairs(chars) do
				local n = 0
				for _ in pairs(entry.def.skills) do
					n += 1
				end
				line(sc, tostring(entry.def.name or entry.def.id), {
					sub = ("%d skill(s)"):format(n) .. (entry.err and ("  ·  error: " .. entry.err) or ""),
					color = C.good,
					tip = "Open this character",
					onClick = function()
						self:go({ level = "character", entry = entry })
					end,
					buttons = { del("Delete character " .. tostring(entry.def.name) .. "?", "The character goes; its skills are kept (under Skills). Ctrl+Z in Studio brings it back.", function()
						self:deleteCharacter(entry)
					end) },
				})
			end
			line(sc, "+ New character", { color = C.good, dim = true, onClick = function()
				self:newCharacter()
			end })
		end
		gap()
		local loose = self:skillItems({ level = "group", group = "loose" })
		local sets = Tree.gameMoves()
		if section("skills", "Skills", #loose, C.accent) then
			line(sc, "Skills (no character)", { sub = ("%d skill(s)"):format(#loose), color = C.accent, onClick = function()
				self:go({ level = "group", group = "loose", title = "Skills (no character)" })
			end })
			for _, set in ipairs(sets) do
				line(sc, set.name, { sub = ("game moves, read-only  ·  %d"):format(#set.skills), color = C.warn, onClick = function()
					self:go({ level = "group", group = "moves", set = set, title = set.name .. " (game, read-only)" })
				end })
			end
			line(sc, "+ New skill", { color = C.accent, dim = true, onClick = function()
				self:load({ name = "New skill", cooldown = 2, branches = { Default = {} } }, nil, nil, false)
				self:go({ level = "skill", parent = { level = "group", group = "loose", title = "Skills (no character)" } })
			end })
		end
		gap()
		local exCount = 0
		for _ in pairs(self.SK.TestSkills) do
			exCount += 1
		end
		if section("examples", "Examples", exCount, C.dim) then
			for _, it in ipairs(self:skillItems({ level = "group", group = "examples" })) do
				line(sc, it.text, { color = C.dim, tip = "Open this example (read-only)", onClick = function()
					self:openSkillPage(it.open, { level = "group", group = "examples", title = "Examples (read-only)" })
				end })
			end
		end
		return
	end

	-- CHARACTER: its slots ------------------------------------------------------------------------------------------------
	if nav.level == "character" then
		local entry = nav.entry
		-- the character's stats as small chips; the whole strip opens the settings (name, stats, keybinds)
		local info = Instance.new("TextButton")
		info.AutoButtonColor = true
		info.BorderSizePixel = 0
		info.BackgroundColor3 = C.bg
		info.Text = ""
		info.Size = UDim2.new(1, 0, 0, 30)
		info.LayoutOrder = 2
		info.Parent = left
		Ui.corner(info, 6)
		Ui.stroke(info, C.line)
		local chips = Ui.frame(info, { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -40, 1, 0) })
		Ui.list(chips, 4, true)
		local st = entry.def.stats or {}
		for i, pair in ipairs({ { "HP", st.health or 100 }, { "Walk", st.walkSpeed or 16 }, { "Sprint", st.sprintSpeed or 24 }, { "Jump", st.jumpPower or 50 } }) do
			local chip = Ui.frame(chips, { LayoutOrder = i, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.card })
			Ui.corner(chip, 10)
			Ui.pad(chip, 7, 7, 0, 0)
			local label = Ui.text(chip, ("%s %s"):format(pair[1], Ui.fmt(pair[2])), { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, TextSize = 11, TextColor3 = C.dim })
			label.Active = false
		end
		Ui.text(info, "Edit", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(30, 30), TextSize = 12, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Right })
		Ui.tip(info, "Name, stats and keybinds")
		info.Activated:Connect(function()
			self:characterWindow(entry)
		end)
		local sc = body(36)
		for _, slot in ipairs(Tree.SLOTS) do
			local name = entry.def.skills[slot]
			local k = entry.def.keys and entry.def.keys[slot]
			local keyText = k and k.pc and k.pc ~= "" and ("  [" .. k.pc .. "]") or ""
			local buttons = { { text = "...", tip = "New skill here, put the open skill here, pick a saved one", onClick = function()
				self:slotMenu(entry, slot)
			end } }
			if name then
				table.insert(buttons, 1, del("Empty slot " .. slot .. "?", name .. " is taken out of the slot; the skill itself is kept.", function()
					self:assignSlot(entry, slot, nil)
				end, "Empty the slot"))
			end
			line(sc, slot .. keyText, {
				sub = name or "(empty)",
				color = name and C.good or C.line,
				dim = name == nil,
				selected = self.slotCtx and self.slotCtx.entry.module == entry.module and self.slotCtx.slot == slot,
				tip = name and "Open this skill" or "Empty: click to fill it",
				buttons = buttons,
				onClick = function()
					if name then
						self:openSkillPage(function()
							self:openSlot(entry, slot)
						end, { level = "character", entry = entry })
					else
						self:slotMenu(entry, slot)
					end
				end,
			})
		end
		return
	end

	-- GROUP: a list of skills --------------------------------------------------------------------------------------------
	if nav.level == "group" then
		local sc = body(0)
		local items = self:skillItems(nav)
		if #items == 0 then
			Ui.text(sc, "Nothing here yet.", { TextColor3 = C.dim, Size = UDim2.new(1, 0, 0, 30) })
		end
		for _, it in ipairs(items) do
			local buttons = {}
			if it.module then
				table.insert(buttons, del("Delete skill " .. it.text .. "?", "Removes ReplicatedStorage.SkillKitSkills." .. it.text .. ". Ctrl+Z in Studio brings it back.", function()
					self:deleteSkillModule(it.module)
				end))
			end
			line(sc, it.text, { color = nav.group == "examples" and C.dim or (nav.group == "moves" and C.warn or C.accent), tip = "Open this skill", buttons = buttons, onClick = function()
				self:openSkillPage(it.open, nav)
			end })
		end
		return
	end

	-- NODE: one node's settings -----------------------------------------------------------------------------------------
	if nav.level == "node" then
		local sc = body(0)
		local list = self:list()
		local t, idx = 0, 1
		for i, n in ipairs(list) do
			if n == nav.node then
				idx = i
				break
			end
			if n.type == "Wait" then
				t += n.time or 0
			end
		end
		self.expanded[nav.node] = true
		self:renderNode(sc, nav.node, idx, t, true)
		return
	end

	-- SKILL: the nodes of a branch ----------------------------------------------------------------------------------------
	local bar = Ui.frame(left, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
	Ui.list(bar, 6, true)
	local function prompt(ptitle: string, initial: string, onOk: (string) -> ())
		local pb = Ui.modal(ptitle, 360, 130)
		local box = Ui.input(pb, initial, function() end, { ZIndex = 63, Size = UDim2.new(1, 0, 0, 30) })
		Ui.button(pb, "OK", function()
			local txt = box.Text
			Ui.closePopup()
			onOk(txt)
		end, { Position = UDim2.new(1, -60, 0, 40), ZIndex = 63, BackgroundColor3 = C.accent })
		box:CaptureFocus()
	end
	local branchB
	branchB = Ui.button(bar, "Branch: " .. self.branch .. " ▼", function()
		local items = { { header = true, text = "BRANCHES" } }
		for _, nm in ipairs(self:branchNames()) do
			table.insert(items, { text = nm .. "  (" .. #self.skill.branches[nm] .. ")", color = nm == self.branch and C.accent or nil, onClick = function()
				self.branch = nm
				self.path = {}
				self.selected = {}
				self:render()
			end })
		end
		if not self.readOnly then
			table.insert(items, { header = true, text = "" })
			table.insert(items, { text = "+ New branch", color = C.good, onClick = function()
				prompt("New branch", "", function(txt)
					self:newBranch(txt)
				end)
			end })
			if self.branch ~= "Default" then
				table.insert(items, { text = "Rename " .. self.branch, onClick = function()
					prompt("Rename branch", self.branch, function(txt)
						self:renameBranch(self.branch, txt)
					end)
				end })
				table.insert(items, { text = "Delete " .. self.branch, color = C.bad, onClick = function()
					self:confirm("Delete branch " .. self.branch .. "?", ("Its %d node(s) go too. Undo brings it back."):format(#(self.skill.branches[self.branch] or {})), "Delete", function()
						self:deleteBranch(self.branch)
					end)
				end })
			end
			table.insert(items, { text = "See how branches connect (Flow)", onClick = function()
				self:flowWindow()
			end })
		end
		Ui.menu(branchB.AbsolutePosition + Vector2.new(0, 32), items, 260)
	end, { Size = UDim2.new(1, -150, 0, 30), LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.tip(branchB, "Switch branch, add, rename or delete one")
	local addB
	addB = Ui.button(bar, "+ Add ▼", function()
		local items = {}
		table.insert(items, { header = true, text = "QUICK" })
		for _, t in ipairs({ "Wait", "Branch", "Loop" }) do
			table.insert(items, { text = t .. "   ·  " .. (Meta.Describe[t] or ""), color = Meta.FlowColor, onClick = function()
				self:insert(self:newNode(t))
			end })
		end
		for _, cat in ipairs(Meta.Categories) do
			table.insert(items, { header = true, text = string.upper(cat.name), color = cat.color })
			for _, t in ipairs(cat.types) do
				table.insert(items, { text = t .. "   ·  " .. (Meta.Describe[t] or ""), color = cat.color, onClick = function()
					self:insert(self:newNode(t))
				end })
			end
		end
		Ui.menu(addB.AbsolutePosition + Vector2.new(0, 32), items, 380)
	end, { Size = UDim2.fromOffset(74, 30), LayoutOrder = 2, BackgroundColor3 = C.accent })
	Ui.tip(addB, "Add a node after the selected one")
	local editB
	editB = Ui.button(bar, "Edit ▼", function()
		local n = #self:selection()
		local items = {
			{ header = true, text = n > 0 and ("%d SELECTED"):format(n) or "SELECT NODES FIRST (TICK SEVERAL)" },
			{ text = self.multi and "Select several: on" or "Select several: off", color = self.multi and C.good or nil, onClick = function()
				self.multi = not self.multi
				self:renderLeft()
			end },
			{ text = "Copy", onClick = function()
				self:copy()
			end },
			{ text = "Paste", onClick = function()
				self:paste()
			end },
			{ text = "Move up", onClick = function()
				self:move(-1)
			end },
			{ text = "Move down", onClick = function()
				self:move(1)
			end },
			{ text = "Group / ungroup", onClick = function()
				self:group()
			end },
			{ text = "Delete", color = C.bad, onClick = function()
				self:delete()
			end },
		}
		Ui.menu(editB.AbsolutePosition + Vector2.new(0, 32), items, 240)
	end, { Size = UDim2.fromOffset(64, 30), LayoutOrder = 3 })
	Ui.tip(editB, "Copy, paste, move, group, delete; select several")

	local sc = body(36)
	local list = self:list()
	if #list == 0 then
		Ui.text(sc, "Empty. Press + Add to add a node.", { TextColor3 = C.dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 40) })
	end
	local t = 0
	for i, node in ipairs(list) do
		self:renderNode(sc, node, i, t)
		if node.type == "Wait" then
			t += node.time or 0
		end
	end
end

function App:renderNode(parent: Instance, node: any, index: number, startT: number, fullPage: boolean?)
	local _, color = Meta.category(node.type)
	local sel = self.selected[node] == true
	local card = Ui.frame(parent, { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = sel and C.cardHi or C.card, LayoutOrder = index })
	Ui.corner(card, 7)
	if sel then
		Ui.stroke(card, color, 1.5)
	end
	self.nodeFrames[node] = card
	local hi = Ui.frame(card, { Name = "Hi", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 1, ZIndex = 0 })
	Ui.corner(hi, 7)
	local stripe = Ui.frame(card, { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color })
	Ui.corner(stripe, 2)
	local inner = Ui.frame(card, { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -14, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Ui.list(inner, 4)
	Ui.pad(inner, 0, 0, 6, 6)

	-- header: expand arrow, badge, name, type, start time, select
	local head = Instance.new("TextButton")
	head.AutoButtonColor = false
	head.BackgroundTransparency = 1
	head.Text = ""
	head.Size = UDim2.new(1, 0, 0, 26)
	head.LayoutOrder = 0
	head.Parent = inner
	-- in a list a card is one line (click it to open the node's own page); on that page it shows every setting
	local expanded = fullPage == true
	if self.multi and not fullPage then
		local tick = Ui.button(head, sel and "X" or "", function()
			self.selected[node] = not self.selected[node] or nil
			self:renderLeft()
		end, { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = sel and C.accent or C.field, TextSize = 12 })
		Ui.tip(tick, "Tick to select")
	else
		Ui.text(head, tostring(index), { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(0, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.dim, TextSize = 12 })
	end
	local badge = Ui.text(head, Meta.Badge[node.type] or "?", { Position = UDim2.fromOffset(30, 1), Size = UDim2.fromOffset(28, 24), BackgroundTransparency = 0, BackgroundColor3 = color, TextColor3 = Color3.new(0.05, 0.05, 0.08), Font = Ui.FontBold, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.corner(badge, 5)
	local summary = node.type
	if node.type == "Wait" then
		summary = "Wait " .. Ui.fmt(node.time or 0) .. "s"
	elseif node.type == "Branch" then
		summary = "Branch → " .. (node.target ~= "" and node.target or "?") .. " (" .. (node.mode or "Switch") .. ")"
	elseif node.type == "Keyframes" or node.type == "Animation" then
		summary = node.type .. " · " .. tostring(node.anim)
	elseif node.type == "Sound" then
		summary = "Sound · " .. tostring(node.sound)
	elseif node.type == "PresetVFX" then
		summary = "VFX · " .. tostring(node.preset)
	elseif node.type == "Hitbox" then
		summary = ("Hitbox · %s dmg"):format(Ui.fmt(node.damage or 0))
	elseif node.type == "Loop" or node.type == "Group" then
		summary = ("%s · %d inside"):format(node.type, #(node.nodes or {}))
	elseif node.type == "Tags" then
		summary = ("Tags · %s %s"):format(node.op or "", node.tag or "")
	elseif node.type == "Check" then
		summary = "If " .. Meta.condsText(node.conds)
	elseif node.type == "Heal" then
		summary = ("Heal · %s%s"):format(Ui.fmt(node.amount or 0), node.percent and "%" or "")
	elseif node.type == "Meter" then
		summary = ("Meter · %s %s %s"):format(node.op or "Add", tostring(node.meter), Ui.fmt(node.value or 0))
	elseif node.type == "Counter" then
		summary = ("Counter · %ss"):format(Ui.fmt(node.time or 1))
	end
	if fullPage then
		-- on its own page the name can be typed (it shows instead of the summary)
		local nb = Ui.input(head, node.name or "", function(t)
			local v = t ~= "" and t or nil
			if v ~= node.name then
				node.name = v
				self:changed()
			end
		end, { Position = UDim2.fromOffset(64, 1), Size = UDim2.new(1, -64 - 44 - 80, 0, 24), PlaceholderText = summary .. "  (click to name it)", BackgroundTransparency = 1, Font = Ui.FontBold })
		local _ = nb
	else
		Ui.text(head, node.name and (node.name .. "  ·  " .. summary) or summary, { Position = UDim2.fromOffset(64, 1), Size = UDim2.new(1, -64 - 44, 0, 24), Font = Ui.FontBold, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	Ui.text(head, Ui.fmt(math.floor(startT * 100 + 0.5) / 100) .. "s", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 1), Size = UDim2.fromOffset(40, 24), TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right })
	-- quick actions: shown when the card is hovered or selected
	local quick = Ui.frame(head, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -48, 0, 1), Size = UDim2.fromOffset(78, 24), BackgroundColor3 = sel and C.cardHi or C.card, Visible = sel, ZIndex = 3 })
	Ui.list(quick, 4, true)
	local dupB = Ui.button(quick, "Dup", function()
		self:duplicateNode(node)
	end, { Size = UDim2.fromOffset(36, 22), TextSize = 12, LayoutOrder = 1, BackgroundColor3 = C.field })
	Ui.tip(dupB, "Duplicate this node")
	local delB = Ui.button(quick, "Del", function()
		self:deleteNode(node)
	end, { Size = UDim2.fromOffset(36, 22), TextSize = 12, LayoutOrder = 2, BackgroundColor3 = C.field, TextColor3 = C.bad })
	Ui.tip(delB, "Delete this node (Undo brings it back)")
	card.MouseEnter:Connect(function()
		quick.Visible = true
	end)
	card.MouseLeave:Connect(function()
		quick.Visible = self.selected[node] == true
	end)
	head.Activated:Connect(function()
		if fullPage then
			return
		end
		if self.multi then
			self.selected[node] = not self.selected[node] or nil
			self:renderLeft()
			return
		end
		-- open the node's own page (◀ ▶ there step through this list)
		self.selected = { [node] = true }
		self:go({ level = "node", node = node, parent = self.nav })
		self.selected = { [node] = true }
	end)
	if not expanded then
		return
	end
	if Meta.Describe[node.type] then
		Ui.text(inner, Meta.Describe[node.type], { TextColor3 = C.dim, TextSize = 12, LayoutOrder = 1, TextWrapped = true })
	end
	for i, field in ipairs(Meta.Fields[node.type] or {}) do
		self:renderField(inner, node, field, 10 + i)
	end
end

function App:renderField(parent: Instance, node: any, field: any, order: number)
	local key, kind = field.key, field.kind
	local row = Ui.frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order })
	local labelT = Ui.text(row, field.label or key, { Size = UDim2.new(0, 132, 1, 0), TextColor3 = C.dim, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
	local slot = Ui.frame(row, { BackgroundTransparency = 1, Position = UDim2.fromOffset(136, 0), Size = UDim2.new(1, -136, 1, 0) })
	local v = node[key]
	local function set(x: any)
		node[key] = x
		self:changed()
	end
	local SK = self.SK
	if kind == "number" then
		local box = Ui.input(slot, v ~= nil and Ui.fmt(v) or "", function(t)
			local n = tonumber(t)
			if n ~= nil and n ~= v then
				set(n)
			elseif t == "" and v ~= nil then
				set(nil)
			end
		end)
		-- drag the label left / right to change the number
		labelT.Text = (field.label or key) .. "  <>"
		local grab = Instance.new("TextButton")
		grab.BackgroundTransparency = 1
		grab.Text = ""
		grab.Size = UDim2.fromScale(1, 1)
		grab.Parent = labelT
		Ui.tip(grab, "Drag left / right to change")
		local start = 0
		local acc = 0
		local moved = false
		grab.MouseButton1Down:Connect(function()
			start = tonumber(box.Text) or 0
			acc = 0
			moved = false
		end)
		Ui.drag(grab, function(d)
			acc += d.X
			moved = true
			local step = math.abs(start) >= 20 and 0.5 or (math.abs(start) >= 2 and 0.05 or 0.01)
			local nv = math.floor((start + acc * step) * 100 + 0.5) / 100
			node[key] = nv
			box.Text = Ui.fmt(nv)
		end, function()
			if moved then
				self:changed()
			end
		end)
	elseif kind == "text" then
		Ui.input(slot, v ~= nil and tostring(v) or "", function(t)
			local x = t ~= "" and t or nil
			if x ~= v then
				set(x)
			end
		end)
	elseif kind == "bool" then
		Ui.toggle(slot, v == true, function(on)
			set(on)
		end)
	elseif kind == "enum" or kind == "branch" or kind == "preset" then
		local opts = field.opts or {}
		if kind == "branch" then
			opts = { "(none)" }
			for _, nm in ipairs(self:branchNames()) do
				table.insert(opts, nm)
			end
			table.insert(opts, "+ new branch…")
		elseif kind == "preset" then
			opts = {}
			for nm in pairs(SK.Fx.Presets) do
				table.insert(opts, nm)
			end
			table.sort(opts)
		end
		local shown = (v == nil or v == "") and (kind == "branch" and "(none)" or "—") or tostring(v)
		local b
		b = Ui.button(slot, shown .. "  ▼", function()
			local items = {}
			for _, o in ipairs(opts) do
				table.insert(items, { text = o, onClick = function()
					if o == "(none)" then
						set(nil)
					elseif o == "+ new branch…" then
						local body = Ui.modal("New branch", 360, 130)
						local box = Ui.input(body, "", function() end, { ZIndex = 63, Size = UDim2.new(1, 0, 0, 30) })
						Ui.button(body, "OK", function()
							local name = box.Text
							Ui.closePopup()
							if name ~= "" then
								self.skill.branches[name] = self.skill.branches[name] or {}
								set(name)
							end
						end, { Position = UDim2.new(1, -60, 0, 40), ZIndex = 63, BackgroundColor3 = C.accent })
						box:CaptureFocus()
					else
						set(o)
					end
				end })
			end
			Ui.menu(b.AbsolutePosition + Vector2.new(0, 28), items, math.max(180, b.AbsoluteSize.X))
		end, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Font, BackgroundColor3 = C.field })
	elseif kind == "vector" then
		Ui.vector(slot, v, function(x)
			set(x)
		end)
	elseif kind == "color" then
		Ui.color(slot, v, function(x)
			set(x)
		end)
	elseif kind == "curve" then
		local graph = Ui.curveGraph(slot, SK.Curves, v, Vector2.new(46, 24), key == "fade" or key == "speedCurve")
		graph.Position = UDim2.new(1, -46, 0, 1)
		local b
		b = Ui.button(slot, (v == nil and "none" or (type(v) == "string" and v or (v == true and "fade" or "custom"))) .. "  ▼", function()
			local items = { { text = "none", onClick = function()
				set(nil)
			end } }
			for _, nm in ipairs(SK.Curves.names()) do
				table.insert(items, { text = nm, onClick = function()
					set(nm)
				end })
			end
			Ui.menu(b.AbsolutePosition + Vector2.new(0, 28), items, 200)
		end, { Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Font, BackgroundColor3 = C.field })
	elseif kind == "asset" then
		local reg = field.opts
		local box = Ui.input(slot, v ~= nil and tostring(v) or "", function(t)
			local x: any = tonumber(t) or (t ~= "" and t or nil)
			if x ~= v then
				set(x)
			end
		end, { Size = UDim2.new(1, -30, 1, 0), PlaceholderText = "name or asset id" })
		local b
		b = Ui.button(slot, "▼", function()
			local items = {}
			local names = SK.Registry.list(reg)
			if reg == "mesh" then
				for _, s in ipairs({ "Sphere", "Block", "Cylinder" }) do
					table.insert(names, 1, s)
				end
			end
			for _, nm in ipairs(names) do
				table.insert(items, { text = nm, onClick = function()
					set(nm)
				end })
			end
			if #items == 0 then
				table.insert(items, { header = true, text = "no " .. reg .. " in the registry: type an id" })
			end
			Ui.menu(b.AbsolutePosition + Vector2.new(-200, 28), items, 230)
		end, { Position = UDim2.new(1, -26, 0, 0), Size = UDim2.fromOffset(26, 26) })
		local _ = box
	elseif kind == "range" then
		local cur = type(v) == "table" and v or { 0, 0 }
		for i = 1, 2 do
			Ui.input(slot, Ui.fmt(cur[i] or 0), function(t)
				local n = tonumber(t)
				if n then
					local copy = { cur[1] or 0, cur[2] or 0 }
					copy[i] = n
					set(copy)
				end
			end, { Position = UDim2.new((i - 1) / 2, i == 2 and 3 or 0, 0, 0), Size = UDim2.new(0.5, -3, 1, 0) })
		end
	elseif kind == "multi" then
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		slot.Size = UDim2.new(1, -136, 0, 0)
		slot.AutomaticSize = Enum.AutomaticSize.Y
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(92, 22)
		grid.CellPadding = UDim2.fromOffset(4, 4)
		grid.Parent = slot
		local cur = type(v) == "table" and v or {}
		for _, o in ipairs(field.opts) do
			local on = table.find(cur, o) ~= nil
			Ui.button(slot, o, function()
				local copy = table.clone(cur)
				local i = table.find(copy, o)
				if i then
					table.remove(copy, i)
				else
					table.insert(copy, o)
				end
				set(copy)
			end, { BackgroundColor3 = on and C.accent or C.field, TextColor3 = on and Color3.new(0.05, 0.05, 0.1) or C.dim, Font = Ui.Font, TextSize = 12 })
		end
	elseif kind == "homing" then
		local on = type(v) == "table"
		Ui.toggle(slot, on, function(x)
			set(x and { chance = 1, turnSpeed = 6, range = 60, delay = 0 } or nil)
		end)
		if on then
			row.Size = UDim2.new(1, 0, 0, 26 + 4 * 28)
			for i, k in ipairs({ "chance", "turnSpeed", "range", "delay" }) do
				Ui.text(row, "   " .. k, { Position = UDim2.fromOffset(0, i * 28), Size = UDim2.fromOffset(132, 26), TextColor3 = C.dim, TextSize = 12 })
				Ui.input(row, Ui.fmt(v[k] or 0), function(t)
					local n = tonumber(t)
					if n then
						v[k] = n
						self:changed()
					end
				end, { Position = UDim2.fromOffset(136, i * 28), Size = UDim2.new(1, -136, 0, 26) })
			end
		end
	elseif kind == "conds" then
		-- a list of conditions: what, not, value / meter, remove
		local conds = type(v) == "table" and v or {}
		Ui.button(slot, "+ condition", function()
			table.insert(conds, { what = "InAir" })
			set(conds)
		end, { Size = UDim2.fromOffset(110, 24), BackgroundColor3 = C.cardHi })
		row.Size = UDim2.new(1, 0, 0, 26 + #conds * 28)
		local WHATS = { "InAir", "Jumping", "Holding", "Aiming", "Health", "Meter" }
		for i, c in ipairs(conds) do
			local y = i * 28
			local line = Ui.frame(row, { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -12, 0, 26) })
			local whatB
			whatB = Ui.button(line, (c.what or "InAir") .. " ▼", function()
				local items = {}
				for _, w in ipairs(WHATS) do
					table.insert(items, { text = w, onClick = function()
						c.what = w
						if w == "Health" then
							c.value = c.value or 0.5
						elseif w == "Meter" then
							c.meter = c.meter or "awakening"
							c.value = c.value or 1
						end
						set(conds)
					end })
				end
				Ui.menu(whatB.AbsolutePosition + Vector2.new(0, 28), items, 160)
			end, { Size = UDim2.fromOffset(96, 24), Font = Ui.Font, TextSize = 13, BackgroundColor3 = C.field })
			Ui.tip(whatB, "InAir, Jumping, Holding the key, Aiming at someone, Health (fraction of max), Meter")
			local notB = Ui.toggle(line, c["not"] == true, function(on)
				c["not"] = on or nil
				set(conds)
			end, { Position = UDim2.fromOffset(100, 0), Size = UDim2.fromOffset(44, 24) })
			notB.Text = c["not"] and "NOT" or "is"
			Ui.tip(notB, "Invert this condition")
			local x = 148
			if c.what == "Meter" then
				Ui.input(line, tostring(c.meter or ""), function(t)
					c.meter = t ~= "" and t or "awakening"
					set(conds)
				end, { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(84, 24), PlaceholderText = "meter" })
				x += 88
			end
			if c.what == "Health" or c.what == "Meter" then
				Ui.text(line, ">=", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(18, 24), TextColor3 = C.dim, TextSize = 12 })
				Ui.input(line, Ui.fmt(c.value or 0), function(t)
					local n = tonumber(t)
					if n then
						c.value = n
						set(conds)
					end
				end, { Position = UDim2.fromOffset(x + 20, 0), Size = UDim2.fromOffset(46, 24) })
			end
			Ui.button(line, "X", function()
				table.remove(conds, i)
				set(conds)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(24, 24), TextSize = 12, BackgroundColor3 = C.field, TextColor3 = C.bad })
		end
	elseif kind == "nodes" then
		Ui.button(slot, ("Open inner nodes (%d) >"):format(#(node.nodes or {})), function()
			self:openInner(node)
		end, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.cardHi })
	end
end

function App:renderTimeline()
	local tl = self.timeline :: Frame
	tl:ClearAllChildren()
	Ui.pad(tl, 10, 10, 6, 6)
	local list = self:list()
	-- schedule: start of each node, its length
	local rows = {}
	local t = 0
	local keyframes = {}
	for _, nm in ipairs(self.SK.Registry.list("keyframes")) do
		keyframes[nm] = self.SK.Registry.get("keyframes", nm)
	end
	for _, n in ipairs(list) do
		local d = Meta.duration(n, keyframes)
		table.insert(rows, { node = n, start = t, dur = d })
		if n.type == "Wait" then
			t += n.time or 0
		end
	end
	local total = 0.5
	for _, r in ipairs(rows) do
		total = math.max(total, r.start + r.dur)
	end
	total = math.ceil(total * 4) / 4
	self.timelineTotal = total
	local labelW = 150
	Ui.text(tl, ("TIMELINE  ·  %s  ·  %.2fs"):format(self.branch .. (#self.path > 0 and " >" or ""), total), { Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.dim, Font = Ui.FontBold, TextSize = 12 })
	local area = Ui.frame(tl, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), BackgroundTransparency = 1 })
	local ruler = Ui.frame(area, { Position = UDim2.fromOffset(labelW, 0), Size = UDim2.new(1, -labelW, 0, 16), BackgroundTransparency = 1 })
	local step = total <= 1.5 and 0.1 or (total <= 4 and 0.25 or 0.5)
	local k = 0
	while k <= total + 1e-6 do
		local x = k / total
		Ui.frame(ruler, { Position = UDim2.new(x, 0, 0, 10), Size = UDim2.fromOffset(1, 6), BackgroundColor3 = C.line })
		if math.abs((k / (step * 2)) - math.floor(k / (step * 2) + 0.5)) < 1e-6 then
			Ui.text(ruler, Ui.fmt(math.floor(k * 100 + 0.5) / 100), { Position = UDim2.new(x, 2, 0, -2), Size = UDim2.fromOffset(40, 12), TextSize = 10, TextColor3 = C.dim })
		end
		k += step
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 20)
	scroll.Size = UDim2.new(1, 0, 1, -20)
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = area
	Ui.list(scroll, 2)
	for i, r in ipairs(rows) do
		local n = r.node
		local _, color = Meta.category(n.type)
		local row = Ui.frame(scroll, { Size = UDim2.new(1, -6, 0, 20), BackgroundColor3 = self.selected[n] and C.cardHi or C.panel, LayoutOrder = i })
		Ui.corner(row, 4)
		Ui.text(row, (n.name or n.type), { Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(labelW - 10, 20), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = C.dim })
		local track = Ui.frame(row, { Position = UDim2.fromOffset(labelW, 0), Size = UDim2.new(1, -labelW, 1, 0), BackgroundTransparency = 1 })
		if n.type == "Wait" then
			local w = Ui.frame(track, { Position = UDim2.new(r.start / total, 0, 0.5, -1), Size = UDim2.new(r.dur / total, 0, 0, 2), BackgroundColor3 = C.dim })
			local _ = w
		else
			local bar = Ui.frame(track, { Position = UDim2.new(r.start / total, 0, 0, 3), Size = UDim2.new(math.max(r.dur / total, 0.006), 0, 1, -6), BackgroundColor3 = color })
			Ui.corner(bar, 3)
		end
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = row
		hit.Activated:Connect(function()
			-- open that node's page
			self:jumpTo(self.branch, self.path, n)
		end)
	end
	-- playhead
	local head = Ui.frame(area, { Position = UDim2.fromOffset(labelW, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C.bad, Visible = false, ZIndex = 5 })
	self.playhead = head
	self.playheadLabelW = labelW
end

function App:tick()
	local head = self.playhead :: Frame?
	if not head or not head.Parent then
		return
	end
	local t = self.preview:time()
	if t and self.timelineTotal then
		head.Visible = true
		local area = head.Parent :: Frame
		local w = area.AbsoluteSize.X - self.playheadLabelW
		head.Position = UDim2.fromOffset(self.playheadLabelW + math.clamp(t / self.timelineTotal, 0, 1) * w, 0)
	else
		head.Visible = false
	end
end

function App:renderLog()
	local p = self.logPanel :: Frame?
	if not p then
		return
	end
	p:ClearAllChildren()
	Ui.corner(p, 8)
	Ui.pad(p, 10)
	Ui.text(p, "PREVIEW LOG", { Size = UDim2.new(1, -60, 0, 18), Font = Ui.FontBold, TextSize = 12, TextColor3 = C.dim })
	Ui.button(p, "clear", function()
		self.logLines = {}
		self:renderLog()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -2), Size = UDim2.fromOffset(50, 20), TextSize = 12 })
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 24)
	scroll.Size = UDim2.new(1, 0, 1, -24)
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = p
	Ui.list(scroll, 2)
	local colors = { hit = C.good, miss = C.warn, warn = C.warn, error = C.bad, tag = Color3.fromRGB(150, 200, 255), branch = Color3.fromRGB(200, 170, 255), done = C.accent }
	for i, l in ipairs(self.logLines) do
		local prefix = l.t and ("%.2fs  "):format(l.t) or ""
		Ui.text(scroll, prefix .. l.msg, { LayoutOrder = i, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -6, 0, 16), TextSize = 12, TextColor3 = colors[l.kind] or C.text, Font = Ui.FontMono })
	end
	task.defer(function()
		if scroll.Parent then
			scroll.CanvasPosition = Vector2.new(0, 1e6)
		end
	end)
end

return App
