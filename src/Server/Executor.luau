--!strict
-- A Cast is one use of a skill: its clock, its branch cursors, the threads its nodes started, what it hit.
-- Nodes in a branch start in order; only Wait advances a cursor. A node that lasts (a hitbox, a projectile) spawns
-- its own thread with cast:spawn, so the cast knows it's still busy. The cast ends when nothing is left running, or
-- early on cancel (stun, death, a new cast that cancels it).
local Players = game:GetService("Players")

local DebugLog = require(script.Parent.Parent.DebugLog)
local Rig = require(script.Parent.Parent.Rig)

local Executor = {}

export type Cursor = { branch: string, stopped: boolean }

local Cast = {}
Cast.__index = Cast
Executor.Cast = Cast

local nextCastId = 0
local MAX_TIME = 30

-- handlers are filled in by Server/Nodes (type -> function(cast, node, cursor))
Executor.Handlers = {} :: { [string]: (any, any, Cursor) -> () }

function Executor.new(args: any)
	nextCastId += 1
	local self = setmetatable({
		id = nextCastId,
		user = args.user :: Model,
		player = args.player or Players:GetPlayerFromCharacter(args.user),
		skill = args.skill,
		adapter = args.adapter,
		target = args.target, -- a preferred target (AI / preview)
		alive = true,
		startTime = os.clock(),
		seed = math.random(1, 2 ^ 30),
		lastHit = nil :: Model?,
		hits = {} :: { Model },
		busy = 0,
		threads = {} :: { thread },
		cleanups = {} :: { () -> () },
		visualTags = {} :: { [string]: Instance },
		projectiles = {} :: { [string]: any },
		finished = Instance.new("BindableEvent"),
		endReason = nil :: string?,
	}, Cast)
	return self
end

function Cast:log(node: any?, kind: string, msg: string, data: any?)
	DebugLog.write(self.player or self.user, self.id, node, kind, msg, data)
end

function Cast:time(): number
	return os.clock() - self.startTime
end

function Cast:userRoot(): BasePart?
	return Rig.root(self.user)
end

function Cast:onCleanup(fn: () -> ())
	table.insert(self.cleanups, fn)
end

-- run fn on its own thread; the cast stays busy until it returns
function Cast:spawn(fn: (...any) -> (), ...: any)
	self.busy += 1
	local args = table.pack(...)
	local th = task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then
			self:log(nil, "error", "node thread failed: " .. tostring(err))
		end
		self.busy -= 1
		self:checkDone()
	end)
	table.insert(self.threads, th)
end

-- a wait that ends early when the cast or cursor stops
function Cast:wait(seconds: number, cursor: Cursor?): boolean
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		if not self.alive or (cursor and cursor.stopped) then
			return false
		end
		task.wait()
	end
	return self.alive and not (cursor and cursor.stopped)
end

function Cast:runNodes(list: { any }, cursor: Cursor)
	for _, node in ipairs(list) do
		if not self.alive or cursor.stopped then
			return
		end
		if node.type == "Wait" then
			if not self:wait(node.time or 0, cursor) then
				return
			end
		else
			local handler = Executor.Handlers[node.type]
			if handler then
				local ok, err = pcall(handler, self, node, cursor)
				if not ok then
					self:log(node, "error", tostring(err))
				end
			else
				self:log(node, "warn", "no handler for node type " .. tostring(node.type))
			end
		end
	end
end

-- start a branch on a new cursor (its own thread)
function Cast:runBranch(name: string, from: any?): Cursor?
	local list = self.skill.branches[name]
	if not list then
		self:log(from, "warn", ("branch %q not found"):format(name), { code = "branch_missing" })
		return nil
	end
	local cursor: Cursor = { branch = name, stopped = false }
	if name ~= "Default" then
		self:log(from, "info", "branch " .. name .. " ran")
	end
	self:spawn(function()
		self:runNodes(list, cursor)
	end)
	return cursor
end

-- a branch field on a node fired: Switch leaves the current branch, Continue runs both
function Cast:branch(name: string?, mode: string?, cursor: Cursor?, from: any?)
	if not name or name == "" or not self.alive then
		return
	end
	if mode == "Switch" and cursor then
		cursor.stopped = true
	end
	self:runBranch(name, from)
end

function Cast:checkDone()
	if self.alive and self.busy <= 0 then
		self:finish("done")
	end
end

function Cast:finish(reason: string)
	if not self.alive then
		return
	end
	self.alive = false
	self.endReason = reason
	for i = #self.cleanups, 1, -1 do
		local ok, err = pcall(self.cleanups[i])
		if not ok then
			self:log(nil, "error", "cleanup failed: " .. tostring(err))
		end
	end
	table.clear(self.cleanups)
	if reason ~= "done" then
		self:log(nil, "info", ("cast ended early: %s"):format(reason))
	end
	self.finished:Fire(reason)
	task.defer(function()
		self.finished:Destroy()
	end)
end

function Cast:cancel(reason: string?)
	self:finish(reason or "cancelled")
end

function Cast:start()
	self:log(nil, "info", ("cast %s (%s) started"):format(tostring(self.skill.name), tostring(self.skill.id or "")))
	-- watchdog: death, a stun on the user, the hard time limit
	task.spawn(function()
		while self.alive do
			if not Rig.alive(self.user) then
				self:cancel("user died")
				break
			end
			if self.skill.cancelOnStun ~= false and self.adapter.isStunned(self.user) and self:time() > 0.05 then
				self:cancel("user stunned")
				break
			end
			if self:time() > (self.skill.maxTime or MAX_TIME) then
				self:cancel("max time")
				break
			end
			task.wait(0.05)
		end
	end)
	self:runBranch("Default")
end

-- subjects: "user" | "lastHit" | "target" | "projectile:<tag>" | "visual:<tag>" -> Model | BasePart | nil
function Cast:resolve(subject: any): Instance?
	if subject == nil or subject == "user" then
		return self.user
	elseif subject == "lastHit" then
		return self.lastHit
	elseif subject == "target" then
		return self.lastHit or self.target
	elseif type(subject) == "string" then
		local kind, tag = string.match(subject, "^(%a+):(.+)$")
		if kind == "projectile" then
			local p = self.projectiles[tag :: string]
			return p and p.part or nil
		elseif kind == "visual" then
			return self.visualTags[tag :: string]
		end
	end
	return nil
end

-- the CFrame of a subject (model root, a part), or nil
function Cast:frameOf(subject: any): CFrame?
	local inst = self:resolve(subject)
	if not inst then
		return nil
	end
	if inst:IsA("Model") then
		local r = Rig.root(inst)
		return r and r.CFrame or inst:GetPivot()
	elseif inst:IsA("BasePart") then
		return inst.CFrame
	end
	return nil
end

-- a local (right, up, forward) offset from a CFrame
function Executor.offset(cf: CFrame, v: Vector3?): CFrame
	v = v or Vector3.zero
	return cf + cf.RightVector * v.X + cf.UpVector * v.Y + cf.LookVector * v.Z
end
function Executor.dir(cf: CFrame, v: Vector3): Vector3
	return cf.RightVector * v.X + cf.UpVector * v.Y + cf.LookVector * v.Z
end

-- the nearest valid target in front of the user (within range and a cone)
function Cast:pickTarget(range: number?, cone: number?): Model?
	if self.lastHit and Rig.alive(self.lastHit) then
		return self.lastHit
	end
	if self.target and Rig.alive(self.target) then
		return self.target
	end
	local root = self:userRoot()
	if not root then
		return nil
	end
	local best, bestScore = nil, math.huge
	local cosMax = math.cos(math.rad(cone or 40))
	for _, model in ipairs(self.adapter.candidates(self.user)) do
		local r = Rig.root(model)
		if r and model ~= self.user and self.adapter.canHit(self.user, model) then
			local to = r.Position - root.Position
			local d = to.Magnitude
			if d <= (range or 60) and d > 0 then
				local facing = root.CFrame.LookVector:Dot(to.Unit)
				if facing >= cosMax then
					local score = d * (2 - facing)
					if score < bestScore then
						best, bestScore = model, score
					end
				end
			end
		end
	end
	return best
end

return Executor
