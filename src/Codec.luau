--!strict
-- Skill codes: short shareable strings for skills and characters.
--   Codec.encode(value) -> "SK1:..."     Codec.decode(code) -> value | nil, err
-- Format: JSON (Vector3 / Color3 / CFrame / Vector2 / NumberRange tagged) -> drop default values -> LZW -> base64.
local HttpService = game:GetService("HttpService")

local Codec = {}
local PREFIX = "SK1:"

-- value <-> JSON-safe ---------------------------------------------------------------------------------------------
local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function pack(v: any): any
	local t = typeof(v)
	if t == "Vector3" then
		return { ["$v3"] = { round(v.X), round(v.Y), round(v.Z) } }
	elseif t == "Vector2" then
		return { ["$v2"] = { round(v.X), round(v.Y) } }
	elseif t == "Color3" then
		return { ["$c3"] = v:ToHex() }
	elseif t == "CFrame" then
		local c = { v:GetComponents() }
		for i, x in ipairs(c) do
			c[i] = round(x)
		end
		return { ["$cf"] = c }
	elseif t == "NumberRange" then
		return { ["$nr"] = { v.Min, v.Max } }
	elseif t == "table" then
		local out = {}
		for k, x in pairs(v) do
			if k ~= "__normalized" then
				out[k] = pack(x)
			end
		end
		return out
	end
	return v
end
local function unpackValue(v: any): any
	if type(v) ~= "table" then
		return v
	end
	if v["$v3"] then
		local a = v["$v3"]
		return Vector3.new(a[1], a[2], a[3])
	elseif v["$v2"] then
		return Vector2.new(v["$v2"][1], v["$v2"][2])
	elseif v["$c3"] then
		return Color3.fromHex(v["$c3"])
	elseif v["$cf"] then
		return CFrame.new(table.unpack(v["$cf"]))
	elseif v["$nr"] then
		return NumberRange.new(v["$nr"][1], v["$nr"][2])
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = unpackValue(x)
	end
	return out
end

-- drop node fields equal to their defaults (smaller codes; Schema.normalize puts them back)
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
local function strip(v: any, defaults: { [string]: any }): any
	if type(v) ~= "table" then
		return v
	end
	local d = type(v.type) == "string" and defaults[v.type]
	local out = {}
	for k, x in pairs(v) do
		if k == "__normalized" or (d and k ~= "type" and d[k] ~= nil and same(x, d[k])) then
			continue
		end
		out[k] = strip(x, defaults)
	end
	return out
end

-- LZW over bytes ----------------------------------------------------------------------------------------------------
local function lzw(s: string): { number }
	local dict: { [string]: number } = {}
	for i = 0, 255 do
		dict[string.char(i)] = i
	end
	local nextCode = 256
	local w = ""
	local out = {}
	for i = 1, #s do
		local c = string.sub(s, i, i)
		local wc = w .. c
		if dict[wc] then
			w = wc
		else
			table.insert(out, dict[w])
			if nextCode < 65535 then
				dict[wc] = nextCode
				nextCode += 1
			end
			w = c
		end
	end
	if w ~= "" then
		table.insert(out, dict[w])
	end
	return out
end
local function unlzw(codes: { number }): string
	local dict: { [number]: string } = {}
	for i = 0, 255 do
		dict[i] = string.char(i)
	end
	local nextCode = 256
	if #codes == 0 then
		return ""
	end
	local w = dict[codes[1]]
	local out = { w }
	for i = 2, #codes do
		local k = codes[i]
		local entry
		if dict[k] then
			entry = dict[k]
		elseif k == nextCode then
			entry = w .. string.sub(w, 1, 1)
		else
			error("bad code")
		end
		table.insert(out, entry)
		if nextCode < 65535 then
			dict[nextCode] = w .. string.sub(entry, 1, 1)
			nextCode += 1
		end
		w = entry
	end
	return table.concat(out)
end

-- 16-bit codes -> bytes -> base64 ----------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function toBase64(bytes: { number }): string
	local out = {}
	for i = 1, #bytes, 3 do
		local a, b, c = bytes[i], bytes[i + 1] or 0, bytes[i + 2] or 0
		local n = a * 65536 + b * 256 + c
		local chunk = {}
		for j = 3, 0, -1 do
			local idx = math.floor(n / 64 ^ j) % 64
			table.insert(chunk, string.sub(B64, idx + 1, idx + 1))
		end
		if bytes[i + 1] == nil then
			chunk[3], chunk[4] = "=", "="
		elseif bytes[i + 2] == nil then
			chunk[4] = "="
		end
		table.insert(out, table.concat(chunk))
	end
	return table.concat(out)
end
local function fromBase64(s: string): { number }
	local map = {}
	for i = 1, 64 do
		map[string.sub(B64, i, i)] = i - 1
	end
	local bytes = {}
	for i = 1, #s, 4 do
		local q = { string.byte(s, i, i + 3) }
		local n, pad = 0, 0
		for j = 1, 4 do
			local ch = q[j] and string.char(q[j]) or "="
			if ch == "=" then
				pad += 1
				n = n * 64
			else
				n = n * 64 + (map[ch] or 0)
			end
		end
		table.insert(bytes, math.floor(n / 65536) % 256)
		if pad < 2 then
			table.insert(bytes, math.floor(n / 256) % 256)
		end
		if pad < 1 then
			table.insert(bytes, n % 256)
		end
	end
	return bytes
end

function Codec.encode(value: any): string
	local Schema = require(script.Parent.Schema) :: any
	local json = HttpService:JSONEncode(pack(strip(value, Schema.Defaults)))
	local codes = lzw(json)
	local bytes = table.create(#codes * 2)
	for _, c in ipairs(codes) do
		table.insert(bytes, math.floor(c / 256))
		table.insert(bytes, c % 256)
	end
	return PREFIX .. toBase64(bytes)
end

function Codec.decode(code: string): (any, string?)
	if type(code) ~= "string" or string.sub(code, 1, #PREFIX) ~= PREFIX then
		return nil, "not a SkillKit code (expected " .. PREFIX .. ")"
	end
	local ok, result = pcall(function()
		local bytes = fromBase64(string.sub(code, #PREFIX + 1))
		local codes = table.create(#bytes // 2)
		for i = 1, #bytes - 1, 2 do
			table.insert(codes, bytes[i] * 256 + bytes[i + 1])
		end
		return unpackValue(HttpService:JSONDecode(unlzw(codes)))
	end)
	if not ok then
		return nil, "corrupt code: " .. tostring(result)
	end
	return result, nil
end

return Codec
