--!strict
-- The tree panel of the skill editor:
--   CHARACTERS   character -> slots (M1, Skill1-4, Block, Dash, Awakening, Passive, Custom) -> the skill in each slot
--   GAME MOVES   the game's Moves modules (read-only) -> their skills
--   SKILLS       saved skills and the examples
--   (the open skill's branches -> nodes show under its slot, or under SKILLS when it has no slot)
-- Characters are ModuleScripts in ReplicatedStorage.SkillKitCharacters. Each returns a CharacterDef whose `skills` maps a
-- slot to a skill module name in ReplicatedStorage.SkillKitSkills, and whose `slots` holds the required skill tables, so
-- the game can pass it straight to SkillKit.defineCharacter.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Meta = require(script.Parent.Meta)
local Serialize = require(script.Parent.Serialize)
local Ui = require(script.Parent.Ui)

local C = Ui.C
local Tree = {}

Tree.SLOTS = { "M1", "Skill1", "Skill2", "Skill3", "Skill4", "Block", "Dash", "Awakening", "Passive", "Custom" }
Tree.DEFAULT_KEYS = {
	M1 = { pc = "MouseButton1", gamepad = "ButtonR2" },
	Skill1 = { pc = "One", gamepad = "ButtonX" },
	Skill2 = { pc = "Two", gamepad = "ButtonY" },
	Skill3 = { pc = "Three", gamepad = "ButtonB" },
	Skill4 = { pc = "Four", gamepad = "DPadUp" },
	Block = { pc = "F", gamepad = "ButtonL1" },
	Dash = { pc = "Q", gamepad = "ButtonL2" },
	Awakening = { pc = "G", gamepad = "DPadDown" },
	Passive = { pc = "", gamepad = "" },
	Custom = { pc = "", gamepad = "" },
}
Tree.DEFAULT_STATS = { health = 100, walkSpeed = 16, sprintSpeed = 24, jumpPower = 50, damageMult = 1, defenseMult = 1 }

-- the fields that point at a branch, and what to call the link in the flow view
Tree.LINKS = {
	Branch = { { "target", "branch" } },
	Hitbox = { { "victimBranch", "hit" }, { "finisherBranch", "finisher" }, { "missBranch", "miss" } },
	Projectile = { { "hitBranch", "hit" }, { "expireBranch", "expire" } },
	Tags = { { "passBranch", "pass" }, { "failBranch", "fail" } },
	Travel = { { "arriveBranch", "arrive" } },
	Grab = { { "grabBranch", "grab" }, { "missBranch", "miss" } },
}

-- DATA ----------------------------------------------------------------------------------------------------------------------
-- requires a fresh copy (so edits show up) and gives up after 2 s, so a module that yields can't freeze the editor
local function freshRequire(m: ModuleScript): (any, string?)
	local clone = m:Clone()
	clone.Archivable = false
	clone.Parent = m.Parent
	local done, ok, result = false, false, nil
	task.spawn(function()
		ok, result = pcall(require, clone)
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 2 do
		task.wait()
	end
	clone:Destroy()
	if not done then
		return nil, "it yields (waits) for more than 2 s when required"
	end
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end
Tree.freshRequire = freshRequire

local function folder(name: string, create: boolean?): Folder?
	local f = ReplicatedStorage:FindFirstChild(name)
	if not f and create then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = ReplicatedStorage
	end
	return f :: Folder?
end

-- reads the character modules (without running their skill requires: the `skills` names are enough)
local cache: { [string]: { t: number, v: any } } = {}
local function cached(key: string, fn: () -> any): any
	local c = cache[key]
	if c and os.clock() - c.t < 3 then
		return c.v
	end
	local v = fn()
	cache[key] = { t = os.clock(), v = v }
	return v
end
function Tree.invalidate()
	table.clear(cache)
end

function Tree.characters(): { any }
	return cached("chars", Tree.readCharacters)
end

function Tree.readCharacters(): { any }
	local out = {}
	local f = folder("SkillKitCharacters")
	if not f then
		return out
	end
	for _, m in ipairs(f:GetChildren()) do
		if m:IsA("ModuleScript") then
			local def, err = freshRequire(m)
			if type(def) == "table" then
				def.skills = def.skills or {}
				def.stats = def.stats or {}
				def.keys = def.keys or {}
				table.insert(out, { def = def, module = m })
			else
				table.insert(out, { def = { id = m.Name, name = m.Name .. " (error)", skills = {}, stats = {}, keys = {} }, module = m, err = err })
			end
		end
	end
	table.sort(out, function(a, b)
		return tostring(a.def.name) < tostring(b.def.name)
	end)
	return out
end

local function characterSource(def: any): string
	local data = {
		id = def.id,
		name = def.name,
		stats = def.stats,
		keys = def.keys,
		skills = def.skills,
	}
	local header = ("-- SkillKit character \"%s\" (made with the SkillKit editor)\n"):format(tostring(def.name))
		.. "-- `skills` maps a slot to a module in ReplicatedStorage.SkillKitSkills; `slots` (the skill tables) is filled\n"
		.. "-- from it below, so this can go straight to SkillKit.defineCharacter(require(thisModule)).\n"
		.. "local ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\n"
		.. "local Skills = ReplicatedStorage:FindFirstChild(\"SkillKitSkills\")\n"
		.. "if not Skills and game:GetService(\"RunService\"):IsRunning() then\n"
		.. "\tSkills = ReplicatedStorage:WaitForChild(\"SkillKitSkills\", 10)\n"
		.. "end\n"
		.. "local def = "
	local body = Serialize.toSource(data, ""):gsub("^return ", "")
	return header
		.. body
		.. "def.slots = {}\n"
		.. "for slot, name in pairs(def.skills) do\n"
		.. "\tlocal m = Skills and Skills:FindFirstChild(name)\n"
		.. "\tif m then\n"
		.. "\t\tdef.slots[slot] = require(m)\n"
		.. "\telse\n"
		.. "\t\twarn((\"[SkillKit] %s.%s: no skill module named %s\"):format(def.id, slot, name))\n"
		.. "\tend\n"
		.. "end\n"
		.. "return def\n"
end
Tree.characterSource = characterSource

function Tree.saveCharacter(def: any, module: ModuleScript?): ModuleScript
	local id = ChangeHistoryService:TryBeginRecording("Save SkillKit character")
	local f = folder("SkillKitCharacters", true) :: Folder
	local m = module
	if not m or not m.Parent then
		local name = tostring(def.id):gsub("[^%w_%-]", "")
		m = f:FindFirstChild(name) :: ModuleScript?
		if not m then
			local nm = Instance.new("ModuleScript")
			nm.Name = name
			nm.Parent = f
			m = nm
		end
	end
	(m :: any).Source = characterSource(def)
	Tree.invalidate()
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
	return m :: ModuleScript
end

function Tree.savedSkills(): { ModuleScript }
	local out = {}
	local f = folder("SkillKitSkills")
	if f then
		for _, m in ipairs(f:GetChildren()) do
			if m:IsA("ModuleScript") then
				table.insert(out, m)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

-- A game's own move sets, if it keeps them as ModuleScripts in a folder named "Moves" anywhere in ReplicatedStorage
-- (each returns { [slot] = { ..., skill = <SkillKit skill> } }). Read-only in the editor: Save makes a copy.
function Tree.movesFolder(): Instance?
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d.Name == "Moves" and (d:IsA("Folder") or d:IsA("ModuleScript")) and not d:IsDescendantOf(ReplicatedStorage:FindFirstChild("SkillKit") or d) then
			return d
		end
	end
	return nil
end

-- the game's move sets: { name, module, skills = { {slot, skill} } }
function Tree.gameMoves(): { any }
	-- a move set that already has a SkillKit character with the same id is shown as that character
	local ids = {}
	for _, e in ipairs(Tree.characters()) do
		ids[string.lower(tostring(e.def.id))] = true
	end
	local out = {}
	for _, set in ipairs(cached("moves", Tree.readGameMoves)) do
		if not ids[string.lower(set.name)] then
			table.insert(out, set)
		end
	end
	return out
end

function Tree.readGameMoves(): { any }
	local out = {}
	local moves = Tree.movesFolder()
	if not moves then
		return out
	end
	for _, m in ipairs(moves:GetChildren()) do
		if m:IsA("ModuleScript") then
			local set = freshRequire(m)
			if type(set) == "table" then
				local skills = {}
				for slot, move in pairs(set) do
					if type(move) == "table" and type(move.skill) == "table" then
						table.insert(skills, { slot = tostring(slot), skill = move.skill })
					end
				end
				if #skills > 0 then
					table.sort(skills, function(a, b)
						return a.slot < b.slot
					end)
					table.insert(out, { name = m.Name, module = m, skills = skills })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- a short one-line summary of a node for the tree
function Tree.summary(n: any): string
	local t = n.type
	if t == "Wait" then
		return ("Wait %ss"):format(Ui.fmt(n.time or 0))
	elseif t == "Branch" then
		return ("Branch → %s (%s)"):format(tostring(n.target ~= "" and n.target or "?"), n.mode or "Switch")
	elseif t == "Hitbox" then
		return ("Hitbox %s dmg"):format(Ui.fmt(n.damage or 0))
	elseif t == "Projectile" then
		return ("Projectile %s dmg"):format(Ui.fmt(n.damage or 0))
	elseif t == "Keyframes" or t == "Animation" then
		return t .. " " .. tostring(n.anim or "")
	elseif t == "Sound" then
		return "Sound " .. tostring(n.sound or "")
	elseif t == "PresetVFX" then
		return "VFX " .. tostring(n.preset or "")
	elseif t == "Tags" then
		return ("Tags %s %s"):format(n.op or "Add", tostring(n.tag or ""))
	elseif t == "State" then
		return "State " .. tostring(n.category or "")
	elseif t == "Loop" then
		return ("Loop ×%s"):format(n.count == 0 and "∞" or tostring(n.count or 1))
	elseif t == "Group" then
		return "Group " .. tostring(n.name or n.groupId or "")
	end
	return t
end

-- UI ------------------------------------------------------------------------------------------------------------------------
-- open/closed state survives re-renders: keyed by a string path
local function isOpen(app: any, key: string, default: boolean): boolean
	app.treeOpen = app.treeOpen or {}
	local v = app.treeOpen[key]
	if v == nil then
		return default
	end
	return v
end
local function toggle(app: any, key: string, default: boolean)
	app.treeOpen[key] = not isOpen(app, key, default)
	app:render()
end

function Tree.render(app: any, panel: Frame)
	local scrollY = app.treeScroll and app.treeScroll.CanvasPosition.Y or 0
	panel:ClearAllChildren()
	local sc = Instance.new("ScrollingFrame")
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Size = UDim2.fromScale(1, 1)
	sc.CanvasSize = UDim2.new()
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 4
	sc.Parent = panel
	app.treeScroll = sc
	Ui.pad(sc, 6, 8, 8, 8)
	Ui.list(sc, 1)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- One row. Clicking the row selects / opens what it stands for (opts.onClick). Rows that have children get a small
	-- ▶ / ▼ button on the left (opts.expand = { key, default }) that only shows or hides them.
	local function row(depth: number, text: string, opts: any): (TextButton, boolean)
		local indent = 4 + depth * 16
		local r = Instance.new("TextButton")
		r.AutoButtonColor = false
		r.BorderSizePixel = 0
		r.BackgroundTransparency = 1
		r.Text = ""
		r.Size = UDim2.new(1, 0, 0, opts.height or 24)
		r.LayoutOrder = nextOrder()
		r.Parent = sc
		-- indent guides: one faint line per level, so it's clear what sits inside what
		for k = 0, depth - 1 do
			Ui.frame(r, { Position = UDim2.fromOffset(4 + k * 16 + 8, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.line, BackgroundTransparency = 0.3 })
		end
		-- the highlight starts at the row's own indent (never at the panel edge)
		local hl = Ui.frame(r, { Position = UDim2.fromOffset(indent, 1), Size = UDim2.new(1, -indent, 1, -2), BackgroundColor3 = C.cardHi, BackgroundTransparency = opts.selected and 0 or 1 })
		Ui.corner(hl, 4)
		if opts.selected then
			local bar = Ui.frame(hl, { Size = UDim2.new(0, 3, 1, -6), Position = UDim2.fromOffset(0, 3), BackgroundColor3 = C.accent })
			Ui.corner(bar, 2)
		end
		if opts.onClick then
			r.MouseEnter:Connect(function()
				if not opts.selected then
					hl.BackgroundTransparency = 0.6
				end
			end)
			r.MouseLeave:Connect(function()
				hl.BackgroundTransparency = opts.selected and 0 or 1
			end)
		end
		-- column 1 (fixed width): the ▶ / ▼ button, or a dot when there's nothing inside
		local open = false
		if opts.expand then
			open = isOpen(app, opts.expand[1], opts.expand[2])
			local key, default = opts.expand[1], opts.expand[2]
			local tb = Ui.button(r, open and "▼" or "▶", function()
				toggle(app, key, default)
			end, { Position = UDim2.new(0, indent + 3, 0.5, -9), Size = UDim2.fromOffset(18, 18), TextSize = 10, BackgroundColor3 = C.field, TextColor3 = C.dim })
			Ui.tip(tb, open and "Hide what's inside" or "Show what's inside")
		elseif opts.dot then
			local d = Ui.frame(r, { Position = UDim2.new(0, indent + 9, 0.5, -3), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = opts.dot })
			Ui.corner(d, 3)
		end
		-- column 2: badge + text, always at the same place for rows of the same level
		local x = indent + 26
		if opts.badge then
			local b = Ui.frame(r, { Position = UDim2.new(0, x, 0.5, -8), Size = UDim2.fromOffset(20, 16), BackgroundColor3 = opts.color or C.card })
			Ui.corner(b, 4)
			Ui.text(b, opts.badge, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Ui.FontBold, TextSize = 10, TextColor3 = Color3.new(1, 1, 1) })
			x += 24
		end
		local rightW = opts.rightW or 0
		Ui.text(r, text, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x - rightW - 2, 1, 0),
			TextColor3 = opts.textColor or C.text,
			Font = opts.bold and Ui.FontBold or Ui.Font,
			TextSize = opts.size or 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		if opts.onClick then
			r.Activated:Connect(opts.onClick)
		end
		if opts.tip then
			Ui.tip(r, opts.tip)
		end
		return r, open
	end
	local function smallButtons(r: Instance, list: { any })
		for i, bt in ipairs(list) do
			local w = math.max(22, #bt.text * 7 + 8)
			local b = Ui.button(r, bt.text, bt.onClick, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(i - 1) * (w + 4), 0.5, 0), Size = UDim2.fromOffset(w, 18), TextSize = 12, BackgroundColor3 = C.card })
			if bt.tip then
				Ui.tip(b, bt.tip)
			end
		end
	end
	-- the open skill's branches > nodes > nested Loop / Group nodes, starting at indent `base`
	local function skillBranches(base: number)
		for _, bname in ipairs(app:branchNames()) do
			local list = app.skill.branches[bname] or {}
			local current = bname == app.branch and #app.path == 0
			local _, open = row(base, ("%s  ·  %d node(s)"):format(bname, #list), {
				expand = #list > 0 and { "b:" .. bname, false } or nil,
				bold = true,
				selected = current,
				dot = #list == 0 and Meta.FlowColor or nil,
				tip = "Open this branch in the node view",
				onClick = function()
					app.branch = bname
					app.path = {}
					app.selected = {}
					app.leftMode = "nodes"
					app:render()
				end,
			})
			if open then
				local function walk(nodes: { any }, depth: number, chain: { any })
					for _, n in ipairs(nodes) do
						local _, color = Meta.category(n.type)
						local hasKids = type(n.nodes) == "table" and #n.nodes > 0
						local _, kidsOpen = row(depth, Tree.summary(n), {
							expand = hasKids and { "n:" .. tostring(n.id or tostring(n)), false } or nil,
							badge = Meta.Badge[n.type] or "?",
							color = color,
							selected = app.selected[n] and app.branch == bname,
							tip = "Edit this node",
							onClick = function()
								app:jumpTo(bname, chain, n)
							end,
						})
						if hasKids and kidsOpen then
							local nextChain = table.clone(chain)
							table.insert(nextChain, n)
							walk(n.nodes, depth + 1, nextChain)
						end
					end
				end
				walk(list, base + 1, {})
			end
		end
	end

	-- Everything is a character: your characters and the game's move sets (read-only); the examples sit below them. Under each: its slots / skills; under the open one: branches > nodes.
	local function skillRow(depth: number, label: string, here: boolean, opts: any)
		local r, open = row(depth, label, {
			expand = (here and app.skill) and { "open:" .. label, true } or nil,
			dot = not here and (opts.dot or C.good) or nil,
			textColor = opts.textColor,
			bold = here,
			selected = here,
			rightW = opts.buttons and 26 or 0,
			tip = opts.tip or "Open this skill",
			onClick = function()
				if here then
					app.leftMode = "nodes"
					app:render()
				else
					opts.open()
				end
			end,
		})
		smallButtons(r, opts.buttons or {})
		if here and open then
			skillBranches(depth + 1)
		end
	end

	row(0, "+ New character", { textColor = C.accent, tip = "Make a new character", onClick = function()
		app:newCharacter()
	end })

	for _, entry in ipairs(Tree.characters()) do
		local def = entry.def
		local holdsOpen = app.slotCtx ~= nil and app.slotCtx.entry.module == entry.module
		local _, open = row(0, tostring(def.name or def.id), {
			expand = { "c:" .. tostring(def.id), holdsOpen },
			bold = true,
			tip = "Name, stats and keybinds",
			onClick = function()
				app:characterWindow(entry)
			end,
		})
		if entry.err then
			row(1, "error: " .. entry.err, { textColor = C.bad })
		end
		if open then
			for _, slot in ipairs(Tree.SLOTS) do
				local skillName = def.skills[slot]
				local k = def.keys and def.keys[slot]
				local keyText = k and k.pc and k.pc ~= "" and (" [" .. k.pc .. "]") or ""
				local menu = { { text = "...", tip = "New skill here, put the open skill here, pick a saved one, clear", onClick = function()
					app:slotMenu(entry, slot)
				end } }
				if skillName then
					skillRow(1, slot .. keyText .. "  ·  " .. skillName, holdsOpen and app.slotCtx.slot == slot, {
						buttons = menu,
						open = function()
							app:openSlot(entry, slot)
						end,
					})
				else
					local r = row(1, slot .. keyText .. "  ·  (empty)", { dot = C.line, textColor = C.dim, rightW = 26, tip = "Empty: click to fill it", onClick = function()
						app:slotMenu(entry, slot)
					end })
					smallButtons(r, menu)
				end
			end
		end
	end

	-- the game's move sets, shown like characters (read-only: Save makes an editable copy)
	for _, set in ipairs(Tree.gameMoves()) do
		local holds = app.source == set.module and app.sourceKey ~= nil
		local _, open = row(0, set.name .. "  (game, read-only)", { expand = { "m:" .. set.name, holds }, bold = true, textColor = C.dim })
		if open then
			for _, sk in ipairs(set.skills) do
				skillRow(1, sk.slot, holds and app.sourceKey == sk.slot, { dot = C.warn, tip = "Open (Save makes an editable copy)", open = function()
					app:load(sk.skill, set.module, sk.slot, true)
				end })
			end
		end
	end

	-- skills that aren't in any character: saved ones no slot uses, and the open skill if it was never saved
	local inCharacter: { [string]: boolean } = {}
	for _, entry in ipairs(Tree.characters()) do
		for _, nm in pairs(entry.def.skills) do
			inCharacter[nm] = true
		end
	end
	local loose = {}
	for _, m in ipairs(Tree.savedSkills()) do
		if not inCharacter[m.Name] then
			table.insert(loose, m)
		end
	end
	local unsavedOpen = app.skill and not app.source and not app.openExample and not app.slotCtx
	if #loose > 0 or unsavedOpen then
		local holds = unsavedOpen or (app.source ~= nil and table.find(loose, app.source) ~= nil)
		local _, open = row(0, "Skills (no character)", { expand = { "loose", holds }, bold = true, textColor = C.dim, tip = "Skills that aren't in a character. Use ... on a slot to put one in" })
		if open then
			if unsavedOpen then
				skillRow(1, tostring(app.skill.name) .. "  (not saved)", true, { open = function() end })
			end
			for _, m in ipairs(loose) do
				skillRow(1, m.Name, app.source == m, { dot = C.accent, open = function()
					local sk, err = freshRequire(m)
					if type(sk) == "table" then
						app:load(sk, m, nil, false)
					else
						app:log("error", "couldn't load " .. m.Name .. ": " .. tostring(err))
					end
				end })
			end
		end
	end

	-- the examples
	local names = {}
	for name in pairs(app.SK.TestSkills) do
		table.insert(names, name)
	end
	table.sort(names)
	local _, exOpen = row(0, "Examples  (read-only)", { expand = { "examples", app.openExample ~= nil }, bold = true, textColor = C.dim })
	if exOpen then
		for _, name in ipairs(names) do
			skillRow(1, name, app.openExample == name, { dot = C.dim, tip = "Open this example", open = function()
				app:load(app.SK.TestSkills[name], nil, nil, false)
				app.openExample = name
				app:render()
			end })
		end
	end
	task.defer(function()
		if sc.Parent then
			sc.CanvasPosition = Vector2.new(0, scrollY)
		end
	end)
end

-- BRANCH FLOW ---------------------------------------------------------------------------------------------------------------
-- every link between branches: { from, to, label, node, kind }
function Tree.links(skill: any): { any }
	local out = {}
	for bname, list in pairs(skill.branches) do
		local function walk(nodes: { any })
			for _, n in ipairs(nodes) do
				for _, l in ipairs(Tree.LINKS[n.type] or {}) do
					local field, label = l[1], l[2]
					local to = n[field]
					if type(to) == "string" and to ~= "" then
						local text = label
						if n.type == "Branch" then
							text = n.mode or "Switch"
						elseif n.type ~= "Branch" then
							text = n.type .. " " .. label
						end
						table.insert(out, { from = bname, to = to, label = text, node = n, kind = label })
					end
				end
				if type(n.nodes) == "table" then
					walk(n.nodes)
				end
			end
		end
		walk(list)
	end
	return out
end

return Tree
