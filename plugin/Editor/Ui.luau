--!strict
-- Small UI kit for the skill editor overlay: dark panels, rounded buttons, inputs, a dropdown popup, a colour field
-- with a live swatch, a curve picker with a mini graph.
local UserInputService = game:GetService("UserInputService")

local Ui = {}

Ui.C = {
	bg = Color3.fromRGB(17, 19, 26),
	panel = Color3.fromRGB(24, 27, 36),
	card = Color3.fromRGB(32, 36, 48),
	cardHi = Color3.fromRGB(40, 45, 60),
	field = Color3.fromRGB(18, 20, 28),
	line = Color3.fromRGB(52, 58, 76),
	text = Color3.fromRGB(232, 234, 240),
	dim = Color3.fromRGB(150, 156, 172),
	accent = Color3.fromRGB(110, 160, 255),
	good = Color3.fromRGB(90, 200, 140),
	bad = Color3.fromRGB(230, 90, 90),
	warn = Color3.fromRGB(240, 190, 80),
}
local C = Ui.C
Ui.Font = Enum.Font.BuilderSans
Ui.FontBold = Enum.Font.BuilderSansBold
Ui.FontMono = Enum.Font.RobotoMono

function Ui.corner(p: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = p
	return c
end
function Ui.stroke(p: Instance, color: Color3?, t: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or C.line
	s.Thickness = t or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
function Ui.pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	local x = Instance.new("UIPadding")
	x.PaddingLeft = UDim.new(0, l)
	x.PaddingRight = UDim.new(0, r or l)
	x.PaddingTop = UDim.new(0, t or l)
	x.PaddingBottom = UDim.new(0, b or t or l)
	x.Parent = p
	return x
end
function Ui.list(p: Instance, gap: number?, horizontal: boolean?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	if horizontal then
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = p
	return l
end

function Ui.frame(parent: Instance?, props: any?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.panel
	for k, v in pairs(props or {}) do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

function Ui.text(parent: Instance?, text: string, props: any?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Ui.Font
	t.TextSize = 14
	t.TextColor3 = C.text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = text
	t.Size = UDim2.new(1, 0, 0, 18)
	for k, v in pairs(props or {}) do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

function Ui.button(parent: Instance?, text: string, onClick: (() -> ())?, props: any?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = C.card
	b.Font = Ui.FontBold
	b.TextSize = 14
	b.TextColor3 = C.text
	b.Text = text
	b.Size = UDim2.fromOffset(math.max(28, #text * 8 + 18), 28)
	Ui.corner(b, 6)
	for k, v in pairs(props or {}) do
		(b :: any)[k] = v
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	b.Parent = parent
	return b
end

function Ui.input(parent: Instance?, value: string, onCommit: (string) -> (), props: any?): TextBox
	local t = Instance.new("TextBox")
	t.BorderSizePixel = 0
	t.BackgroundColor3 = C.field
	t.ClearTextOnFocus = false
	t.Font = Ui.Font
	t.TextSize = 14
	t.TextColor3 = C.text
	t.PlaceholderColor3 = C.dim
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = value
	t.Size = UDim2.new(1, 0, 0, 26)
	Ui.corner(t, 5)
	Ui.pad(t, 6, 6, 0, 0)
	for k, v in pairs(props or {}) do
		(t :: any)[k] = v
	end
	t.FocusLost:Connect(function()
		onCommit(t.Text)
	end)
	t.Parent = parent
	return t
end

-- POPUPS ------------------------------------------------------------------------------------------------------------------
local popupHost: Frame? = nil
local tipLabel: TextLabel? = nil
local currentPopup: Instance? = nil
function Ui.setHost(host: Frame)
	popupHost = host
end
function Ui.closePopup()
	if tipLabel then
		tipLabel:Destroy()
		tipLabel = nil
	end
	if currentPopup then
		currentPopup:Destroy()
		currentPopup = nil
	end
end

-- a menu of items at a screen position. items: { { text, onClick, color?, header? } }
function Ui.menu(at: Vector2, items: { any }, width: number?)
	Ui.closePopup()
	local host = popupHost :: Frame
	local shield = Instance.new("TextButton")
	shield.Name = "Popup"
	shield.BackgroundTransparency = 1
	shield.Text = ""
	shield.Size = UDim2.fromScale(1, 1)
	shield.ZIndex = 50
	shield.Parent = host
	shield.Activated:Connect(Ui.closePopup)
	currentPopup = shield
	local w = width or 200
	local h = math.min(#items * 26 + 10, 420)
	local x = math.clamp(at.X - host.AbsolutePosition.X, 4, host.AbsoluteSize.X - w - 4)
	local y = math.clamp(at.Y - host.AbsolutePosition.Y, 4, math.max(4, host.AbsoluteSize.Y - h - 4))
	local box = Instance.new("ScrollingFrame")
	box.Position = UDim2.fromOffset(x, y)
	box.Size = UDim2.fromOffset(w, h)
	box.BackgroundColor3 = C.panel
	box.BorderSizePixel = 0
	box.ScrollBarThickness = 4
	box.AutomaticCanvasSize = Enum.AutomaticSize.Y
	box.CanvasSize = UDim2.new()
	box.ZIndex = 51
	box.Parent = shield
	Ui.corner(box, 8)
	Ui.stroke(box)
	Ui.pad(box, 5)
	Ui.list(box, 2)
	for i, it in ipairs(items) do
		if it.header then
			Ui.text(box, it.text, { LayoutOrder = i, ZIndex = 52, TextColor3 = it.color or C.dim, Font = Ui.FontBold, TextSize = 12, Size = UDim2.new(1, 0, 0, 20) })
		else
			local b = Ui.button(box, "  " .. it.text, function()
				Ui.closePopup()
				it.onClick()
			end, { LayoutOrder = i, ZIndex = 52, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Font, BackgroundColor3 = C.panel })
			if it.color then
				local dot = Ui.frame(b, { Size = UDim2.fromOffset(4, 14), Position = UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = it.color, ZIndex = 53 })
				Ui.corner(dot, 2)
			end
		end
	end
	return box
end

-- a modal box with a title and a body frame (returned)
function Ui.modal(title: string, width: number, height: number): Frame
	Ui.closePopup()
	local host = popupHost :: Frame
	local shield = Instance.new("TextButton")
	shield.Name = "Modal"
	shield.BackgroundColor3 = Color3.new(0, 0, 0)
	shield.BackgroundTransparency = 0.45
	shield.Text = ""
	shield.AutoButtonColor = false
	shield.Size = UDim2.fromScale(1, 1)
	shield.ZIndex = 60
	shield.Parent = host
	currentPopup = shield
	local box = Ui.frame(shield, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width, height), BackgroundColor3 = C.panel, ZIndex = 61 })
	Ui.corner(box, 10)
	Ui.stroke(box)
	Ui.text(box, title, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -60, 0, 22), Font = Ui.FontBold, TextSize = 17, ZIndex = 62 })
	Ui.button(box, "X", Ui.closePopup, { Position = UDim2.new(1, -38, 0, 8), Size = UDim2.fromOffset(28, 26), ZIndex = 62 })
	local body = Ui.frame(box, { Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 1, -54), BackgroundTransparency = 1, ZIndex = 62 })
	return body
end

-- FIELDS --------------------------------------------------------------------------------------------------------------------
local function fmt(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.3g", n)
end
Ui.fmt = fmt

-- a hex colour (or Color3) -> Color3
function Ui.toColor(v: any): Color3?
	if typeof(v) == "Color3" then
		return v
	elseif type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, v)
		return ok and c or nil
	elseif type(v) == "table" and type(v[1]) == "table" then
		return Ui.toColor(v[1][2])
	end
	return nil
end

-- three number boxes for a Vector3
function Ui.vector(parent: Instance, v: Vector3?, onChange: (Vector3) -> ())
	local row = Ui.frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	Ui.list(row, 4, true)
	local cur = v or Vector3.zero
	local labels = { "X", "Y", "Z" }
	for i = 1, 3 do
		local val = i == 1 and cur.X or (i == 2 and cur.Y or cur.Z)
		local box = Ui.input(row, fmt(val), function(text)
			local n = tonumber(text)
			if not n then
				return
			end
			local x, y, z = cur.X, cur.Y, cur.Z
			if i == 1 then
				x = n
			elseif i == 2 then
				y = n
			else
				z = n
			end
			cur = Vector3.new(x, y, z)
			onChange(cur)
		end, { Size = UDim2.new(1 / 3, -3, 1, 0), LayoutOrder = i, PlaceholderText = labels[i] })
		local tag = Ui.text(box, labels[i], { Size = UDim2.fromOffset(10, 26), Position = UDim2.new(1, -12, 0, 0), TextColor3 = C.dim, TextSize = 11 })
		tag.TextXAlignment = Enum.TextXAlignment.Right
	end
	return row
end

-- a colour field: a swatch that follows what you type (live), committed on focus lost
function Ui.color(parent: Instance, v: any, onChange: (string?) -> ())
	local row = Ui.frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
	local c = Ui.toColor(v)
	local swatch = Ui.frame(row, { Size = UDim2.fromOffset(26, 26), BackgroundColor3 = c or C.field })
	Ui.corner(swatch, 5)
	Ui.stroke(swatch)
	local initial = (typeof(v) == "Color3" and "#" .. v:ToHex()) or (type(v) == "string" and v) or ""
	local box = Ui.input(row, initial, function(text)
		text = string.gsub(text, "%s", "")
		if text == "" then
			onChange(nil)
			return
		end
		if string.sub(text, 1, 1) ~= "#" then
			text = "#" .. text
		end
		if Ui.toColor(text) then
			onChange(string.lower(text))
		end
	end, { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -32, 1, 0), PlaceholderText = "#ffcc66" })
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local t = box.Text
		if string.sub(t, 1, 1) ~= "#" then
			t = "#" .. t
		end
		local live = Ui.toColor(t)
		if live then
			swatch.BackgroundColor3 = live
		end
	end)
	return row
end

-- a tiny graph of a curve (progress over time)
function Ui.curveGraph(parent: Instance, Curves: any, curve: any, size: Vector2, mult: boolean?)
	local g = Ui.frame(parent, { Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = C.field, ClipsDescendants = true })
	Ui.corner(g, 4)
	local n = 18
	for i = 0, n do
		local t = i / n
		local v = mult and Curves.mult(curve, t) or Curves.ease(curve, t)
		local dot = Ui.frame(g, {
			Size = UDim2.fromOffset(2, 2),
			Position = UDim2.new(t, -1, 1 - math.clamp(v, -0.1, 1.15) * 0.8 - 0.1, -1),
			BackgroundColor3 = C.accent,
		})
		dot.ZIndex = g.ZIndex + 1
	end
	return g
end

-- a toggle chip
function Ui.toggle(parent: Instance, on: boolean, onChange: (boolean) -> (), props: any?): TextButton
	local b = Ui.button(parent, on and "ON" or "OFF", nil, props)
	b.Size = (props and props.Size) or UDim2.fromOffset(52, 24)
	b.BackgroundColor3 = on and C.good or C.field
	b.TextColor3 = on and Color3.new(0.05, 0.1, 0.05) or C.dim
	b.Activated:Connect(function()
		onChange(not on)
	end)
	return b
end

-- a hover hint under a control (shown after a short pause)
function Ui.tip(gui: GuiObject, text: string)
	local token = 0
	gui.MouseEnter:Connect(function()
		token += 1
		local my = token
		task.delay(0.35, function()
			if my ~= token or not gui.Parent or not popupHost then
				return
			end
			if tipLabel then
				tipLabel:Destroy()
			end
			local host = popupHost :: Frame
			local t = Instance.new("TextLabel")
			t.Name = "Tip"
			t.BackgroundColor3 = Color3.fromRGB(8, 9, 13)
			t.BackgroundTransparency = 0.05
			t.BorderSizePixel = 0
			t.Font = Ui.Font
			t.TextSize = 13
			t.TextColor3 = C.text
			t.Text = text
			t.AutomaticSize = Enum.AutomaticSize.XY
			t.Size = UDim2.new()
			t.ZIndex = 95
			local x = gui.AbsolutePosition.X - host.AbsolutePosition.X
			local y = gui.AbsolutePosition.Y - host.AbsolutePosition.Y + gui.AbsoluteSize.Y + 4
			t.Position = UDim2.fromOffset(math.clamp(x, 4, math.max(4, host.AbsoluteSize.X - 260)), y)
			Ui.corner(t, 4)
			Ui.pad(t, 6, 6, 3, 3)
			t.Parent = host
			tipLabel = t
		end)
	end)
	gui.MouseLeave:Connect(function()
		token += 1
		if tipLabel then
			tipLabel:Destroy()
			tipLabel = nil
		end
	end)
end

-- drag helper: calls onMove(delta) while the mouse is held on `handle`
function Ui.drag(handle: GuiObject, onMove: (Vector2) -> (), onEnd: (() -> ())?)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local last = Vector2.new(input.Position.X, input.Position.Y)
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement then
				local p = Vector2.new(i.Position.X, i.Position.Y)
				onMove(p - last)
				last = p
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 then
				moveConn:Disconnect()
				endConn:Disconnect()
				if onEnd then
					onEnd()
				end
			end
		end)
	end)
end

return Ui
