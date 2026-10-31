--!strict
-- The branch flow view: every branch of the skill as a box, laid out left to right by how far it is from Default, with an
-- arrow for every link (Branch nodes, Hitbox hit / finisher / miss, Projectile hit / expire, Tags pass / fail, Travel
-- arrive, Grab grab / miss). Click a box to open that branch.
local Ui = require(script.Parent.Ui)
local Tree = require(script.Parent.Tree)

local C = Ui.C
local Flow = {}

local BOX_W, BOX_H = 170, 52
local GAP_X, GAP_Y = 120, 34

local KIND_COLOR = {
	hit = Color3.fromRGB(90, 200, 140),
	pass = Color3.fromRGB(90, 200, 140),
	grab = Color3.fromRGB(90, 200, 140),
	arrive = Color3.fromRGB(90, 200, 140),
	finisher = Color3.fromRGB(240, 190, 80),
	miss = Color3.fromRGB(230, 90, 90),
	fail = Color3.fromRGB(230, 90, 90),
	expire = Color3.fromRGB(230, 130, 90),
	branch = Color3.fromRGB(150, 156, 172),
}

local function line(parent: Instance, a: Vector2, b: Vector2, color: Color3, z: number): Frame
	local d = b - a
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, 2)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.ZIndex = z
	f.Parent = parent
	return f
end

function Flow.open(app: any)
	local skill = app.skill
	if not skill then
		return
	end
	local names = app:branchNames()
	local links = Tree.links(skill)

	-- columns: breadth-first distance from Default; unreachable branches go in a last column
	local level: { [string]: number } = { Default = 0 }
	local queue = { "Default" }
	while #queue > 0 do
		local b = table.remove(queue, 1) :: string
		for _, l in ipairs(links) do
			if l.from == b and skill.branches[l.to] and level[l.to] == nil then
				level[l.to] = level[b] + 1
				table.insert(queue, l.to)
			end
		end
	end
	local maxLevel = 0
	for _, v in pairs(level) do
		maxLevel = math.max(maxLevel, v)
	end
	local orphans = false
	for _, n in ipairs(names) do
		if level[n] == nil then
			level[n] = maxLevel + 1
			orphans = true
		end
	end
	local cols: { [number]: { string } } = {}
	for _, n in ipairs(names) do
		local l = level[n]
		cols[l] = cols[l] or {}
		table.insert(cols[l], n)
	end
	local pos: { [string]: Vector2 } = {}
	local maxRows, colCount = 1, 0
	for l, list in pairs(cols) do
		colCount = math.max(colCount, l + 1)
		maxRows = math.max(maxRows, #list)
		for i, n in ipairs(list) do
			pos[n] = Vector2.new(20 + l * (BOX_W + GAP_X), 30 + (i - 1) * (BOX_H + GAP_Y))
		end
	end

	local vp = workspace.CurrentCamera.ViewportSize
	local body = Ui.modal("Branch flow: " .. tostring(skill.name), math.min(980, vp.X - 40), math.min(600, vp.Y - 40))
	local legend = Ui.text(body, "Arrows show which node starts which branch. Click a box to open that branch." .. (orphans and "  Last column: branches nothing points to." or ""), { Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.dim, TextSize = 12, ZIndex = 62 })
	local _ = legend
	local canvas = Instance.new("ScrollingFrame")
	canvas.BackgroundColor3 = C.bg
	canvas.BorderSizePixel = 0
	canvas.Position = UDim2.fromOffset(0, 24)
	canvas.Size = UDim2.new(1, 0, 1, -24)
	canvas.ScrollBarThickness = 5
	canvas.ScrollingDirection = Enum.ScrollingDirection.XY
	canvas.CanvasSize = UDim2.fromOffset(40 + colCount * (BOX_W + GAP_X), 60 + maxRows * (BOX_H + GAP_Y))
	canvas.ZIndex = 62
	canvas.Parent = body
	Ui.corner(canvas, 6)

	-- links (drawn first so boxes sit on top); several links between the same pair fan out vertically
	local pairCount: { [string]: number } = {}
	for _, l in ipairs(links) do
		local a, b = pos[l.from], pos[l.to]
		local color = KIND_COLOR[l.kind] or KIND_COLOR.branch
		if not b then
			-- a link to a branch that doesn't exist
			b = nil
		end
		if a and b then
			local key = l.from .. ">" .. l.to
			pairCount[key] = (pairCount[key] or 0) + 1
			local k = pairCount[key] - 1
			local fan = (k % 2 == 0 and 1 or -1) * math.ceil(k / 2) * 9
			local p1, p2
			if l.from == l.to then
				-- a loop back to itself: a small hook above the box
				local top = a + Vector2.new(BOX_W * 0.7, 0)
				local up = top + Vector2.new(0, -18 - k * 6)
				local left = up + Vector2.new(-BOX_W * 0.4, 0)
				line(canvas, top, up, color, 63)
				line(canvas, up, left, color, 63)
				line(canvas, left, left + Vector2.new(0, 18 + k * 6), color, 63)
				p1, p2 = up, left
			elseif b.X > a.X then
				p1 = a + Vector2.new(BOX_W, BOX_H / 2 + fan)
				p2 = b + Vector2.new(0, BOX_H / 2 + fan)
				line(canvas, p1, p2, color, 63)
				-- arrow head
				local d = (p2 - p1).Unit
				local n = Vector2.new(-d.Y, d.X)
				line(canvas, p2, p2 - d * 9 + n * 5, color, 63)
				line(canvas, p2, p2 - d * 9 - n * 5, color, 63)
			else
				-- going back (or within a column): route under the boxes
				local yLow = math.max(a.Y, b.Y) + BOX_H + 12 + k * 6
				local s = a + Vector2.new(BOX_W / 2 + fan, BOX_H)
				local e = b + Vector2.new(BOX_W / 2 - fan, BOX_H)
				line(canvas, s, Vector2.new(s.X, yLow), color, 63)
				line(canvas, Vector2.new(s.X, yLow), Vector2.new(e.X, yLow), color, 63)
				line(canvas, Vector2.new(e.X, yLow), e, color, 63)
				line(canvas, e, e + Vector2.new(-5, 8), color, 63)
				line(canvas, e, e + Vector2.new(5, 8), color, 63)
				p1, p2 = Vector2.new(s.X, yLow), Vector2.new(e.X, yLow)
			end
			local mid = (p1 + p2) / 2
			local tag = Ui.text(canvas, l.label, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromOffset(mid.X, mid.Y - 1),
				Size = UDim2.fromOffset(110, 14),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 11,
				Font = Ui.FontBold,
				TextColor3 = color,
				BackgroundColor3 = C.bg,
				BackgroundTransparency = 0.15,
				ZIndex = 64,
			})
			tag.AutomaticSize = Enum.AutomaticSize.X
			tag.Size = UDim2.fromOffset(0, 14)
		end
	end

	-- boxes
	for _, n in ipairs(names) do
		local p = pos[n]
		local list = skill.branches[n] or {}
		local b = Ui.button(canvas, "", function()
			Ui.closePopup()
			app.branch = n
			app.path = {}
			app.selected = {}
			app.treeOpen = app.treeOpen or {}
			app.treeOpen["b:" .. n] = true
			app:render()
		end, {
			Position = UDim2.fromOffset(p.X, p.Y),
			Size = UDim2.fromOffset(BOX_W, BOX_H),
			BackgroundColor3 = n == app.branch and C.cardHi or C.card,
			ZIndex = 65,
		})
		Ui.stroke(b, n == "Default" and C.accent or C.line, n == app.branch and 2 or 1)
		Ui.text(b, n, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 20), Font = Ui.FontBold, TextSize = 15, ZIndex = 66, TextTruncate = Enum.TextTruncate.AtEnd })
		local kinds = {}
		for i, node in ipairs(list) do
			if i > 4 then
				table.insert(kinds, "…")
				break
			end
			table.insert(kinds, node.type)
		end
		Ui.text(b, #list == 0 and "(empty)" or table.concat(kinds, " · "), { Position = UDim2.fromOffset(10, 27), Size = UDim2.new(1, -20, 0, 16), TextSize = 11, TextColor3 = C.dim, ZIndex = 66, TextTruncate = Enum.TextTruncate.AtEnd })
	end

	-- links to missing branches
	local missing = {}
	for _, l in ipairs(links) do
		if not skill.branches[l.to] then
			table.insert(missing, ("%s → %s (%s)"):format(l.from, l.to, l.label))
		end
	end
	if #missing > 0 then
		Ui.text(canvas, "Missing branches: " .. table.concat(missing, ",  "), {
			Position = UDim2.new(0, 20, 1, -26),
			Size = UDim2.new(1, -40, 0, 18),
			TextColor3 = C.bad,
			TextSize = 12,
			ZIndex = 66,
		})
	end
end

return Flow
