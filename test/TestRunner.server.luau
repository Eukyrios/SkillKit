-- Stand-alone test for the SkillKit add-on, with no game code. Open an empty Baseplate, run
--   rojo serve test.project.json        (from the SkillKit repo folder)
-- connect the Rojo plugin, then press Play. When you spawn this script:
--   1 runs the pure checks (schema, curves, codec)
--   2 puts a breakable wall in front of you (for the Debris node)
--   3 plays every test skill against a fresh dummy, one by one
--   4 prints a report to the Output; every line should start with OK / PASS
-- Chat commands while playing:  /sk <TestName>   one test skill (Hitbox, Combo, Projectile, ...)
--                               /sk all          the whole suite again
--                               /sk log          your debug log
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SkillKit = require(ReplicatedStorage:WaitForChild("SkillKit"))
-- a game that already started SkillKit keeps its own adapter; an empty place gets the default one
task.wait(1)
if not SkillKit.isReady() then
	SkillKit.init() -- default adapter: anything with a Humanoid can be hit
end

local function wall(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = workspace:FindFirstChild("SkillKitTestWall")
	if old then
		old:Destroy()
	end
	local w = Instance.new("Part")
	w.Name = "SkillKitTestWall"
	w.Size = Vector3.new(8, 8, 1.5)
	w.Anchored = true
	w.Material = Enum.Material.Brick
	w.Color = Color3.fromRGB(150, 140, 130)
	w.CFrame = root.CFrame * CFrame.new(0, 1, -5)
	w.Parent = workspace
	CollectionService:AddTag(w, "SkillKitBreakable")
end

local function suite(player: Player)
	print("[SkillKitTest] pure checks:\n" .. table.concat(SkillKit.dev.selfTest(), "\n"))
	local results = {}
	local names = {}
	for name in pairs(SkillKit.dev.Skills) do
		table.insert(names, name)
	end
	table.sort(names)
	print("[SkillKitTest] running " .. #names .. " test skills on a dummy...")
	for _, name in ipairs(names) do
		if name == "Debris" then
			wall(player)
		end
		SkillKit.debug.clear(player)
		local cast, dummy = SkillKit.dev.run(player, name)
		local t0 = os.clock()
		while cast and cast.alive and os.clock() - t0 < 8 do
			task.wait(0.1)
		end
		local lines, errors = {}, 0
		for _, e in ipairs(SkillKit.debug.get(player)) do
			table.insert(lines, SkillKit.DebugLog.format(e))
			if e.kind == "error" then
				errors += 1
			end
		end
		results[name] = { ok = cast ~= nil and errors == 0, ended = cast and cast.endReason, lines = lines }
		if dummy then
			dummy:Destroy()
		end
		task.wait(0.5)
	end
	print("[SkillKitTest] report:\n" .. SkillKit.dev.report(results))
end

local function onPlayer(player: Player)
	player.Chatted:Connect(function(msg)
		local arg = string.match(msg, "^/sk%s+(%S+)")
		if not arg then
			return
		end
		if arg == "all" then
			suite(player)
		elseif arg == "log" then
			SkillKit.debug.dump(player)
		elseif SkillKit.dev.Skills[arg] then
			if arg == "Debris" then
				wall(player)
			end
			SkillKit.debug.clear(player)
			SkillKit.dev.run(player, arg)
			task.wait(1.5)
			SkillKit.debug.dump(player)
		else
			warn("[SkillKitTest] no test skill named " .. arg)
		end
	end)
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart")
	task.wait(2)
	suite(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end
