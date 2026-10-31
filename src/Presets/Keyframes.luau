--!strict
-- Built-in keyframe animations (no uploads needed). Format:
--   { fps = 24 | 30 | 60, duration = seconds, looped = bool?,
--     joints = { [logicalJoint] = { { t = seconds, r = Vector3(deg x, y, z), p = Vector3?, ease = "auto" | curve }, ... } } }
-- Rotations are degrees in torso space: +X pitches the limb forward/up for arms (raise), +Y turns left, +Z rolls.
-- Joint names: Root Waist Neck RightArm RightForearm LeftArm LeftForearm RightLeg RightShin LeftLeg LeftShin.
-- "auto" ease = a Catmull-Rom spline through the neighbouring keys: animators only place keys.
local V = Vector3.new

local function k(t: number, x: number, y: number?, z: number?)
	return { t = t, r = V(x, y or 0, z or 0) }
end

return {
	-- a right-hand horizontal slash: wind up, cut across, recover
	slash_right = {
		fps = 60,
		duration = 0.45,
		joints = {
			Waist = { k(0, 0, 0), k(0.12, 0, 35), k(0.24, 0, -40), k(0.45, 0, 0) },
			RightArm = { k(0, 0, 0, 0), k(0.12, 80, 40, 20), k(0.24, 90, -70, 0), k(0.45, 0, 0, 0) },
			RightForearm = { k(0, 0), k(0.12, 40), k(0.24, 5), k(0.45, 0) },
			LeftArm = { k(0, 0), k(0.24, 20, 0, -15), k(0.45, 0) },
			Neck = { k(0, 0), k(0.12, 0, -15), k(0.24, 0, 20), k(0.45, 0) },
		},
	},
	slash_left = {
		fps = 60,
		duration = 0.45,
		joints = {
			Waist = { k(0, 0, 0), k(0.12, 0, -35), k(0.24, 0, 40), k(0.45, 0, 0) },
			LeftArm = { k(0, 0, 0, 0), k(0.12, 80, -40, -20), k(0.24, 90, 70, 0), k(0.45, 0, 0, 0) },
			LeftForearm = { k(0, 0), k(0.12, 40), k(0.24, 5), k(0.45, 0) },
			RightArm = { k(0, 0), k(0.24, 20, 0, 15), k(0.45, 0) },
			Neck = { k(0, 0), k(0.12, 0, 15), k(0.24, 0, -20), k(0.45, 0) },
		},
	},
	-- a straight punch with the right arm
	punch = {
		fps = 60,
		duration = 0.35,
		joints = {
			Waist = { k(0, 0, 0), k(0.08, 0, 25), k(0.16, 0, -25), k(0.35, 0, 0) },
			RightArm = { k(0, 0), k(0.08, 40, 0, 10), k(0.16, 90, 0, 0), k(0.35, 0) },
			RightForearm = { k(0, 0), k(0.08, 80), k(0.16, 0), k(0.35, 0) },
			LeftArm = { k(0, 0), k(0.16, 50, 0, -10), k(0.35, 0) },
			LeftForearm = { k(0, 0), k(0.16, 90), k(0.35, 0) },
		},
	},
	-- a forward dash: lean in, arms back
	dash = {
		fps = 30,
		duration = 0.4,
		joints = {
			Waist = { k(0, 0), k(0.08, -25), k(0.32, -25), k(0.4, 0) },
			RightArm = { k(0, 0), k(0.08, -50, 0, 15), k(0.32, -50, 0, 15), k(0.4, 0) },
			LeftArm = { k(0, 0), k(0.08, -50, 0, -15), k(0.32, -50, 0, -15), k(0.4, 0) },
			RightLeg = { k(0, 0), k(0.08, 30), k(0.32, 30), k(0.4, 0) },
			LeftLeg = { k(0, 0), k(0.08, -30), k(0.32, -30), k(0.4, 0) },
			Neck = { k(0, 0), k(0.08, 15), k(0.32, 15), k(0.4, 0) },
		},
	},
	-- a back dash: lean back, arms forward
	back_dash = {
		fps = 30,
		duration = 0.4,
		joints = {
			Waist = { k(0, 0), k(0.08, 18), k(0.32, 18), k(0.4, 0) },
			RightArm = { k(0, 0), k(0.08, 40, 0, 10), k(0.32, 40, 0, 10), k(0.4, 0) },
			LeftArm = { k(0, 0), k(0.08, 40, 0, -10), k(0.32, 40, 0, -10), k(0.4, 0) },
			RightLeg = { k(0, 0), k(0.08, 25), k(0.4, 0) },
			LeftLeg = { k(0, 0), k(0.08, -10), k(0.4, 0) },
		},
	},
	-- guard: forearms crossed in front of the face (held)
	block = {
		fps = 30,
		duration = 0.2,
		hold = true,
		joints = {
			RightArm = { k(0, 0), k(0.2, 80, 30, 10) },
			RightForearm = { k(0, 0), k(0.2, 90) },
			LeftArm = { k(0, 0), k(0.2, 80, -30, -10) },
			LeftForearm = { k(0, 0), k(0.2, 90) },
			Waist = { k(0, 0), k(0.2, -8) },
		},
	},
	-- hit reaction: snap back and recover
	stagger = {
		fps = 30,
		duration = 0.5,
		joints = {
			Waist = { k(0, 0), k(0.08, 25, 0, 8), k(0.5, 0) },
			Neck = { k(0, 0), k(0.08, 30), k(0.5, 0) },
			RightArm = { k(0, 0), k(0.08, 30, 0, 25), k(0.5, 0) },
			LeftArm = { k(0, 0), k(0.08, 30, 0, -25), k(0.5, 0) },
		},
	},
	-- both hands thrust forward (a beam / blast pose)
	blast = {
		fps = 60,
		duration = 0.9,
		joints = {
			Waist = { k(0, 0), k(0.15, 0, 30), k(0.3, -10, -10), k(0.75, -10, -10), k(0.9, 0) },
			RightArm = { k(0, 0), k(0.15, -30, 0, 20), k(0.3, 90, 15, 0), k(0.75, 90, 15, 0), k(0.9, 0) },
			LeftArm = { k(0, 0), k(0.15, -30, 0, -20), k(0.3, 90, -15, 0), k(0.75, 90, -15, 0), k(0.9, 0) },
			RightLeg = { k(0, 0), k(0.3, 15), k(0.9, 0) },
			LeftLeg = { k(0, 0), k(0.3, -20), k(0.9, 0) },
		},
	},
}
