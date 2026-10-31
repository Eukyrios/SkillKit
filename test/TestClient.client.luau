-- Starts SkillKit's client side in the stand-alone test place (animations, VFX, sounds, your own motion).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage:WaitForChild("SkillKit")).initClient()
