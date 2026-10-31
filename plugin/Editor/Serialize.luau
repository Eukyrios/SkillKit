--!strict
-- Writes a skill table as readable Luau source ("return { ... }"), for ModuleScripts and the Code window.
local Serialize = {}

local function num(n: number): string
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return tostring(math.floor(n))
	end
	local s = string.format("%.3f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local IDENT = "^[%a_][%w_]*$"
local KEYWORDS = { ["and"] = 1, ["break"] = 1, ["do"] = 1, ["else"] = 1, ["elseif"] = 1, ["end"] = 1, ["false"] = 1, ["for"] = 1, ["function"] = 1, ["if"] = 1, ["in"] = 1, ["local"] = 1, ["nil"] = 1, ["not"] = 1, ["or"] = 1, ["repeat"] = 1, ["return"] = 1, ["then"] = 1, ["true"] = 1, ["until"] = 1, ["while"] = 1, ["continue"] = 1 }

-- the order keys are written in: type and name first, then the rest alphabetically
local function keyOrder(t: { [any]: any }): { any }
	local keys = {}
	for k in pairs(t) do
		if k ~= "__normalized" then
			table.insert(keys, k)
		end
	end
	table.sort(keys, function(a, b)
		local pa = (a == "type" and 0) or (a == "name" and 1) or (a == "id" and 99) or 10
		local pb = (b == "type" and 0) or (b == "name" and 1) or (b == "id" and 99) or 10
		if pa ~= pb then
			return pa < pb
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function isArray(t: { [any]: any }): boolean
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then
			return false
		end
		n += 1
	end
	return n == #t
end

local function value(v: any, indent: string, inline: boolean?): string
	local t = typeof(v)
	if t == "number" then
		return num(v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "Vector3" then
		return ("Vector3.new(%s, %s, %s)"):format(num(v.X), num(v.Y), num(v.Z))
	elseif t == "Vector2" then
		return ("Vector2.new(%s, %s)"):format(num(v.X), num(v.Y))
	elseif t == "Color3" then
		return ("Color3.fromRGB(%d, %d, %d)"):format(math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
	elseif t == "CFrame" then
		local c = { v:GetComponents() }
		for i, x in ipairs(c) do
			c[i] = num(x)
		end
		return "CFrame.new(" .. table.concat(c, ", ") .. ")"
	elseif t == "table" then
		if next(v) == nil then
			return "{}"
		end
		local inner = indent .. "\t"
		local parts = {}
		if isArray(v) then
			-- short arrays of plain values stay on one line
			local simple = true
			for _, x in ipairs(v) do
				if type(x) == "table" then
					simple = false
					break
				end
			end
			if simple or inline then
				for _, x in ipairs(v) do
					table.insert(parts, value(x, inner, true))
				end
				return "{ " .. table.concat(parts, ", ") .. " }"
			end
			for _, x in ipairs(v) do
				-- a node: one line when it has no nested node lists
				local oneLine = type(x) == "table" and x.type ~= nil and x.nodes == nil
				table.insert(parts, inner .. value(x, inner, oneLine))
			end
			return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
		end
		for _, k in ipairs(keyOrder(v)) do
			local key = (type(k) == "string" and string.match(k, IDENT) and not KEYWORDS[k]) and k or ("[" .. value(k, inner) .. "]")
			table.insert(parts, key .. " = " .. value(v[k], inner, inline))
		end
		if inline then
			return "{ " .. table.concat(parts, ", ") .. " }"
		end
		return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. ",\n" .. indent .. "}"
	end
	return "nil --[[ " .. t .. " ]]"
end

-- strip fields equal to the node defaults so saved files stay short
function Serialize.compact(skill: any, defaults: { [string]: any }): any
	local function same(a: any, b: any): boolean
		if typeof(a) ~= typeof(b) then
			return false
		end
		if type(a) == "table" then
			for k, x in pairs(a) do
				if not same(x, b[k]) then
					return false
				end
			end
			for k in pairs(b) do
				if a[k] == nil then
					return false
				end
			end
			return true
		end
		return a == b
	end
	local function walk(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local d = type(v.type) == "string" and defaults[v.type]
		local out = {}
		for k, x in pairs(v) do
			if k == "__normalized" or k == "version" then
				continue
			end
			if d and k ~= "type" and d[k] ~= nil and same(x, d[k]) then
				continue
			end
			out[k] = walk(x)
		end
		return out
	end
	return walk(skill)
end

function Serialize.toSource(skill: any, header: string?): string
	return (header or "") .. "return " .. value(skill, "") .. "\n"
end

return Serialize
