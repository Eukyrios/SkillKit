--!strict
-- Curves replace easing styles everywhere a value changes over time.
-- A curve is a preset name ("cubicOut", "fadeLate", ...) or { points = { {t, v}, ... }, smooth = bool?, reverse = bool? }
-- with t and v in 0..1 (v may overshoot). Two readings:
--   Curves.ease(c, t)  progress 0 -> 1 (tweens: mesh visuals, travel, keyframes). Unknown/nil = linear.
--   Curves.mult(c, t)  a multiplier over time (velocity fade, projectile speed, particle size). nil = constant 1.
-- Custom presets: Curves.register(name, curve).
local TweenService = game:GetService("TweenService")

local Curves = {}

type Point = { number }
export type Curve = string | { points: { Point }, smooth: boolean?, reverse: boolean? }

local STYLES = {
	sine = Enum.EasingStyle.Sine,
	quad = Enum.EasingStyle.Quad,
	cubic = Enum.EasingStyle.Cubic,
	quart = Enum.EasingStyle.Quart,
	quint = Enum.EasingStyle.Quint,
	expo = Enum.EasingStyle.Exponential,
	circ = Enum.EasingStyle.Circular,
	back = Enum.EasingStyle.Back,
	elastic = Enum.EasingStyle.Elastic,
	bounce = Enum.EasingStyle.Bounce,
}
local DIRS = { In = Enum.EasingDirection.In, Out = Enum.EasingDirection.Out, InOut = Enum.EasingDirection.InOut }

local custom: { [string]: Curve } = {}

-- shaped presets (progress-style, 0 -> 1)
local SHAPES: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	hold = function(t)
		return t >= 1 and 1 or 0
	end,
	pop = function(t) -- overshoots to 1.15 then settles
		local s = 1.70158 * 1.6
		t -= 1
		return t * t * ((s + 1) * t + s) + 1
	end,
	fadeLate = function(t) -- stays put, then goes at the end
		return t < 0.65 and 0 or (t - 0.65) / 0.35
	end,
	fadeEarly = function(t)
		return t > 0.35 and 1 or t / 0.35
	end,
	pulse = function(t) -- there and back
		return math.sin(t * math.pi)
	end,
}

local function sampleShape(name: string, t: number): number?
	local f = SHAPES[name]
	if f then
		return f(t)
	end
	-- "<style><Dir>", e.g. cubicOut, sineInOut, backIn
	local style, dir = string.match(name, "^(%l+)(In%a*)$")
	if not style then
		style, dir = string.match(name, "^(%l+)(Out)$")
	end
	if style and dir and STYLES[style] and DIRS[dir] then
		return TweenService:GetValue(t, STYLES[style], DIRS[dir])
	end
	return nil
end

local function samplePoints(c: { points: { Point }, smooth: boolean?, reverse: boolean? }, t: number): number
	local pts = c.points
	if c.reverse then
		t = 1 - t
	end
	if #pts == 0 then
		return t
	end
	if t <= pts[1][1] then
		return pts[1][2]
	end
	if t >= pts[#pts][1] then
		return pts[#pts][2]
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		if t >= a[1] and t <= b[1] then
			local span = b[1] - a[1]
			local u = span > 0 and (t - a[1]) / span or 0
			if c.smooth ~= false then
				-- monotone-ish Hermite (Catmull-Rom tangents) between the points
				local p0 = pts[i - 1] or a
				local p3 = pts[i + 2] or b
				local m1 = (b[2] - p0[2]) / math.max(b[1] - p0[1], 1e-4) * span
				local m2 = (p3[2] - a[2]) / math.max(p3[1] - a[1], 1e-4) * span
				local u2, u3 = u * u, u * u * u
				return (2 * u3 - 3 * u2 + 1) * a[2] + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * b[2] + (u3 - u2) * m2
			end
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return t
end

function Curves.register(name: string, curve: Curve)
	custom[name] = curve
end

function Curves.names(): { string }
	local list = {}
	for k in pairs(SHAPES) do
		table.insert(list, k)
	end
	for s in pairs(STYLES) do
		for d in pairs(DIRS) do
			table.insert(list, s .. d)
		end
	end
	for k in pairs(custom) do
		table.insert(list, k)
	end
	table.sort(list)
	return list
end

-- progress 0 -> 1
function Curves.ease(c: Curve?, t: number): number
	t = math.clamp(t, 0, 1)
	if c == nil then
		return t
	end
	if type(c) == "string" then
		local reg = custom[c]
		if reg then
			return Curves.ease(reg, t)
		end
		return sampleShape(c, t) or t
	end
	return samplePoints(c :: any, t)
end

-- a multiplier over time. Presets read as "how much is left": fadeOut / fade = 1 -> 0, fadeIn = 0 -> 1,
-- any easing name = 1 - ease (so "cubicOut" fades fast then slow), "constant" = 1. Custom points are taken as-is.
function Curves.mult(c: Curve?, t: number): number
	t = math.clamp(t, 0, 1)
	if c == nil or c == "constant" or c == false then
		return 1
	end
	if c == true or c == "fade" or c == "fadeOut" then
		return 1 - t
	end
	if c == "fadeIn" then
		return t
	end
	if type(c) == "string" then
		local reg = custom[c]
		if reg and type(reg) == "table" then
			return samplePoints(reg :: any, t)
		end
		return 1 - Curves.ease(c, t)
	end
	return samplePoints(c :: any, t)
end

-- a NumberSequence from a curve between two values (max 20 keypoints, Roblox's limit)
function Curves.sequence(c: Curve?, from: number, to: number, mode: string?): NumberSequence
	local keys = {}
	local n = 12
	for i = 0, n do
		local t = i / n
		local k = mode == "mult" and Curves.mult(c, t) or Curves.ease(c, t)
		table.insert(keys, NumberSequenceKeypoint.new(t, from + (to - from) * k))
	end
	return NumberSequence.new(keys)
end

return Curves
