--!strict
-- Developer helpers (server). From the command bar during a playtest:
--   local SK = require(game.ReplicatedStorage.SkillKit)
--   SK.dev.runAll(game.Players:GetPlayers()[1])     every node type against a fresh dummy, then a report
--   SK.dev.run(player, "Hitbox")                     one test skill
--   SK.dev.selfTest()                                 pure checks (schema, curves, codec) that need no player
local Players = game:GetService("Players")

local Dev = {}
Dev.Skills = require(script.TestSkills)

local function server()
	return require(script.Parent.Server) :: any
end

function Dev.selfTest(): { string }
	local Schema = require(script.Parent.Schema) :: any
	local Curves = require(script.Parent.Curves) :: any
	local Codec = require(script.Parent.Codec) :: any
	local out = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(out, (ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. detail .. ")") or ""))
	end
	for name, skill in pairs(Dev.Skills) do
		local copy = Schema.copy(skill)
		local _, errors = Schema.normalize(copy)
		check("schema " .. name, #errors == 0, errors[1])
	end
	check("curve linear", math.abs(Curves.ease("linear", 0.5) - 0.5) < 1e-6)
	check("curve cubicOut", Curves.ease("cubicOut", 0.5) > 0.8)
	check("curve points", math.abs(Curves.ease({ points = { { 0, 0 }, { 1, 1 } }, smooth = false }, 0.25) - 0.25) < 1e-6)
	check("curve mult fade", math.abs(Curves.mult(true, 0.25) - 0.75) < 1e-6)
	local skill = Schema.copy(Dev.Skills.Combo)
	local code = Codec.encode(skill)
	local back, err = Codec.decode(code)
	check("codec round trip", back ~= nil and back.name == skill.name and typeof(back.branches.Default[2].size) == "Vector3", err)
	local json = game:GetService("HttpService"):JSONEncode({ n = #skill.branches.Default })
	check("codec prefix", string.sub(code, 1, 4) == "SK1:", tostring(#code) .. " chars")
	local _ = json
	return out
end

-- run one test skill against a dummy in front of the player; returns the cast and the dummy
function Dev.run(player: Player, name: string, opts: any?)
	local Server = server()
	local skill = Dev.Skills[name]
	assert(skill, "no test skill " .. name)
	local Schema = require(script.Parent.Schema) :: any
	local o = table.clone(opts or {})
	o.player = player
	if name == "Block" then
		o.dummyBlocking = true
	end
	return Server.preview(Schema.copy(skill), o)
end

-- every test skill in turn; returns { name = { ok, log lines } }
function Dev.runAll(player: Player?, gap: number?): { [string]: any }
	player = player or Players:GetPlayers()[1]
	assert(player and player.Character, "needs a player with a character")
	local Server = server()
	local DebugLog = require(script.Parent.DebugLog) :: any
	local results = {}
	local names = {}
	for n in pairs(Dev.Skills) do
		table.insert(names, n)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		DebugLog.clear(player)
		local cast, dummy = Dev.run(player :: Player, name)
		if cast then
			local t0 = os.clock()
			while cast.alive and os.clock() - t0 < 8 do
				task.wait(0.1)
			end
		end
		local lines = {}
		local errors = 0
		for _, e in ipairs(DebugLog.get(player)) do
			table.insert(lines, DebugLog.format(e))
			if e.kind == "error" then
				errors += 1
			end
		end
		results[name] = { ok = cast ~= nil and errors == 0, ended = cast and cast.endReason, lines = lines }
		if dummy then
			dummy:Destroy()
		end
		task.wait(gap or 0.4)
		-- back to where we were (motion tests move us)
		local Rig = require(script.Parent.Rig) :: any
		local root = Rig.root(player.Character)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	return results
end

-- a one-line-per-skill report from runAll
function Dev.report(results: { [string]: any }): string
	local out = {}
	local names = {}
	for n in pairs(results) do
		table.insert(names, n)
	end
	table.sort(names)
	for _, n in ipairs(names) do
		local r = results[n]
		local last = r.lines[#r.lines] or ""
		table.insert(out, ("%s %s [%s] %d events; last: %s"):format(r.ok and "OK  " or "FAIL", n, tostring(r.ended), #r.lines, last))
	end
	return table.concat(out, "\n")
end

return Dev
