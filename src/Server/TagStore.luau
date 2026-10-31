--!strict
-- Number tags on characters (combo counters, charge, marks). Tags with `keep` live on the Player and survive death;
-- others live on the character model and expire after their time (0 = until death).
local Players = game:GetService("Players")

local TagStore = {}

type Tag = { value: number, untilT: number, keep: boolean }
local byOwner: { [Instance]: { [string]: Tag } } = setmetatable({}, { __mode = "k" }) :: any

local function owners(model: Instance): (Instance, Player?)
	local player = Players:GetPlayerFromCharacter(model :: Model)
	return model, player
end

local function read(owner: Instance?, name: string): Tag?
	local t = owner and byOwner[owner]
	local tag = t and t[name]
	if tag and tag.untilT > 0 and os.clock() > tag.untilT then
		(t :: any)[name] = nil
		return nil
	end
	return tag
end

function TagStore.get(model: Instance, name: string): number?
	local m, p = owners(model)
	local tag = read(m, name) or read(p, name)
	return tag and tag.value or nil
end

function TagStore.set(model: Instance, name: string, value: number, time: number?, keep: boolean?)
	local m, p = owners(model)
	local owner = (keep and p) or m
	byOwner[owner] = byOwner[owner] or {}
	byOwner[owner][name] = { value = value, untilT = (time and time > 0) and os.clock() + time or 0, keep = keep == true }
	if keep and p then
		-- one copy only
		local mt = byOwner[m]
		if mt then
			mt[name] = nil
		end
	end
	model:SetAttribute("SK_" .. name, value)
end

function TagStore.remove(model: Instance, name: string)
	local m, p = owners(model)
	for _, o in ipairs({ m, p :: any }) do
		if o and byOwner[o] then
			byOwner[o][name] = nil
		end
	end
	model:SetAttribute("SK_" .. name, nil)
end

function TagStore.all(model: Instance): { [string]: number }
	local out = {}
	local m, p = owners(model)
	for _, o in ipairs({ p :: any, m }) do
		if o and byOwner[o] then
			for k in pairs(byOwner[o]) do
				local v = TagStore.get(model, k)
				if v then
					out[k] = v
				end
			end
		end
	end
	return out
end

-- a new character starts with only the kept tags
function TagStore.onCharacter(player: Player, character: Model)
	local kept = byOwner[player]
	if kept then
		for name, tag in pairs(kept) do
			character:SetAttribute("SK_" .. name, tag.value)
		end
	end
end

return TagStore
