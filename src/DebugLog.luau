--!strict
-- Structured log of what each node did, per owner (a Player or a model), with likely-cause hints.
--   DebugLog.write(owner, castId, node?, kind, msg, data?)   kind: info | warn | error | tag
--   DebugLog.get(owner) -> { entries, newest last }
--   DebugLog.print(owner, count?)                          prints to the Output
--   DebugLog.onEntry(fn)                                  hook (e.g. forward to a debug panel)
local DebugLog = {}

local MAX = 500
local logs: { [any]: { any } } = setmetatable({}, { __mode = "k" }) :: any
local hooks: { (any, any) -> () } = {}

-- why a node probably didn't do what the author expected, keyed by the event code
DebugLog.Hints = {
	hitbox_miss = "the box doesn't reach anyone: check size/position, the attach part and hitUser/hitOnlyUser",
	projectile_timeout = "it ran out of time before reaching anyone: raise lifetime or speed, or aim with direction = toTarget",
	projectile_wall = "it hit the map before a target: raise position.Y or the start offset",
	travel_inside = "already inside stopDistance of the target, so there was nowhere to go",
	travel_no_target = "no target: nothing was hit yet (lastHit) and nobody was in front within range",
	asset_failed = "the asset didn't load: wrong id, wrong asset type, or the asset isn't public/owned",
	tag_nil = "the tag was never set on this character (nil counts as 0 for Add/Subtract)",
	branch_missing = "no branch with that name in this skill",
	blocked = "the target was blocking and the hitbox is blockable",
	no_breakables = "no breakable parts in the box: tag parts with SkillKitBreakable (or the node's tags)",
}

function DebugLog.write(owner: any, castId: number?, node: any?, kind: string, msg: string, data: any?)
	local list = logs[owner]
	if not list then
		list = {}
		logs[owner] = list
	end
	local code = data and data.code
	local entry = {
		t = os.clock(),
		castId = castId,
		nodeId = node and node.id,
		nodeType = node and node.type,
		nodeName = node and (node.name or node.type),
		kind = kind,
		msg = msg,
		hint = code and DebugLog.Hints[code] or nil,
		data = data,
	}
	table.insert(list, entry)
	if #list > MAX then
		table.remove(list, 1)
	end
	for _, fn in ipairs(hooks) do
		task.spawn(fn, owner, entry)
	end
	return entry
end

function DebugLog.get(owner: any): { any }
	return logs[owner] or {}
end

function DebugLog.clear(owner: any)
	logs[owner] = nil
end

function DebugLog.onEntry(fn: (any, any) -> ())
	table.insert(hooks, fn)
end

function DebugLog.format(e: any): string
	local s = ("[%s] #%s %s: %s"):format(e.kind, tostring(e.castId or "-"), e.nodeName or "cast", e.msg)
	if e.hint then
		s ..= "  (likely: " .. e.hint .. ")"
	end
	return s
end

function DebugLog.print(owner: any, count: number?)
	local list = DebugLog.get(owner)
	local from = math.max(1, #list - (count or 40) + 1)
	for i = from, #list do
		print("[SkillKit] " .. DebugLog.format(list[i]))
	end
end

return DebugLog
