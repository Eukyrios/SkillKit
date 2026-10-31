--!strict
-- One RemoteEvent for everything SkillKit sends (server -> client only; casting is the game's business).
-- Messages: (kind: string, payload: table). Kinds are listed in Client/init.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Net = {}
local NAME = "SkillKitNet"

local remote: RemoteEvent
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = NAME
		remote.Parent = ReplicatedStorage
	end
end

function Net.remote(): RemoteEvent
	if not remote then
		remote = ReplicatedStorage:WaitForChild(NAME) :: RemoteEvent
	end
	return remote
end

-- to every client
function Net.all(kind: string, payload: any)
	Net.remote():FireAllClients(kind, payload)
end

-- to one player
function Net.to(player: Player, kind: string, payload: any)
	Net.remote():FireClient(player, kind, payload)
end

-- to every client within `radius` of a point (cheap culling for heavy effects)
function Net.near(position: Vector3, radius: number, kind: string, payload: any)
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - position).Magnitude <= radius then
			Net.remote():FireClient(p, kind, payload)
		end
	end
end

return Net
