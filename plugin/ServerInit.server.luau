-- Starts SkillKit's server side with the default adapter (added by the SkillKit plugin because this place had no
-- SkillKit.init call). Replace the adapter with your game's rules: see the SkillKit README.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillKit = require(ReplicatedStorage:WaitForChild("SkillKit"))
if not SkillKit.isReady() then
	SkillKit.init()
end
