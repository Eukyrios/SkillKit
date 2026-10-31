--!strict
-- One test skill per node type (plus a combo that uses branches and tags). Each is cast by a player at a dummy
-- 8 studs in front (Dev.runAll). Original content; nothing here comes from another game.
local V = Vector3.new
local C = Color3.fromRGB

return {
	Hitbox = {
		name = "Test Hitbox",
		branches = {
			Default = {
				{ type = "Keyframes", anim = "punch" },
				{ type = "Wait", time = 0.12 },
				{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 10, stun = 0.4, knockback = V(0, 4, 20), visible = true, victimBranch = "Hit", mode = "Continue" },
				{ type = "Wait", time = 0.3 },
			},
			Hit = { { type = "PresetVFX", preset = "impact", subject = "lastHit" }, { type = "Sound", sound = "swing" } },
		},
	},
	Combo = {
		name = "Test Combo",
		branches = {
			Default = {
				{ type = "Tags", tag = "combo", op = "Check", compare = ">=", value = 2, passBranch = "Finisher", mode = "Switch" },
				{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 6, stun = 0.5, visible = true, victimBranch = "Count", mode = "Continue" },
				{ type = "Keyframes", anim = "slash_right" },
				{ type = "Wait", time = 0.4 },
			},
			Count = {
				{ type = "Tags", tag = "combo", op = "Add", value = 1, time = 3 },
				{ type = "PresetVFX", preset = "impact", subject = "lastHit", color = "#ffd27a" },
			},
			Finisher = {
				{ type = "Tags", tag = "combo", op = "Set", value = 0 },
				{ type = "Keyframes", anim = "blast" },
				{ type = "Wait", time = 0.3 },
				{ type = "Hitbox", shape = "Cylinder", size = V(30, 6, 6), rotation = V(0, 90, 0), position = V(0, 0, 15), damage = 20, knockback = V(0, 15, 50), visible = true },
				{ type = "PresetVFX", preset = "beam", color = "#9ad0ff", size = 0.8 },
				{ type = "Wait", time = 0.6 },
			},
		},
	},
	Branch = {
		name = "Test Branch",
		branches = {
			Default = {
				{ type = "Branch", target = "Side", mode = "Continue" },
				{ type = "Wait", time = 0.2 },
				{ type = "Branch", target = "Next", mode = "Switch" },
				{ type = "Sound", sound = "boom" }, -- never runs: the branch switched
			},
			Side = { { type = "PresetVFX", preset = "ring" } },
			Next = { { type = "PresetVFX", preset = "burst" }, { type = "Wait", time = 0.2 } },
		},
	},
	Loop = {
		name = "Test Loop",
		nodes = {
			{ type = "Loop", count = 3, interval = 0.15, blocking = true, nodes = {
				{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 2, visible = true },
				{ type = "PresetVFX", preset = "ring", position = V(0, 0, 6) },
			} },
		},
	},
	Group = {
		name = "Test Group",
		nodes = {
			{ type = "Group", name = "spark set", nodes = {
				{ type = "PresetVFX", preset = "wind" },
				{ type = "Wait", time = 0.1 },
				{ type = "PresetVFX", preset = "burst", color = "#ff9a5c" },
			} },
			{ type = "Wait", time = 0.3 },
		},
	},
	State = {
		name = "Test State",
		nodes = {
			{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), visible = true },
			{ type = "State", subject = "lastHit", category = "Disable", sub = { "Movement", "Jump", "Skill" }, duration = 1 },
			{ type = "State", subject = "user", category = "Multiplier", sub = { "Speed" }, value = 1.5, duration = 1 },
			{ type = "State", subject = "lastHit", category = "Body", duration = 0.6 },
			{ type = "Wait", time = 0.2 },
		},
	},
	Ragdoll = {
		name = "Test Ragdoll",
		nodes = {
			{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 5, canRagdoll = true, ragdollTime = 1, knockback = V(0, 10, 25), visible = true },
			{ type = "Wait", time = 0.4 },
		},
	},
	Block = {
		name = "Test Block",
		nodes = {
			{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 10, visible = true, missBranch = nil },
			{ type = "Wait", time = 0.3 },
		},
	},
	Projectile = {
		name = "Test Projectile",
		branches = {
			Default = {
				{ type = "Keyframes", anim = "blast" },
				{ type = "Wait", time = 0.3 },
				{ type = "Projectile", direction = "toTarget", speed = 60, damage = 12, knockback = V(0, 6, 20), color = C(140, 200, 255), position = V(0, 1, 3), projectileTag = "orb", hitBranch = "Boom", mode = "Continue" },
				{ type = "Wait", time = 0.8 },
			},
			Boom = { { type = "PresetVFX", preset = "burst", subject = "lastHit", color = "#8cc8ff" } },
		},
	},
	Homing = {
		name = "Test Homing",
		nodes = {
			{ type = "Projectile", direction = V(0.8, 0.3, 1), speed = 45, lifetime = 3, homing = { chance = 1, turnSpeed = 5, range = 80, delay = 0.1 }, damage = 6, color = C(255, 140, 90) },
			{ type = "Wait", time = 1 },
		},
	},
	Grab = {
		name = "Test Grab",
		nodes = {
			{ type = "Travel", time = 0.25, stopDistance = 3 },
			{ type = "Wait", time = 0.3 },
			{ type = "Grab", size = V(6, 6, 8), position = V(0, 0, 4), duration = 0.8, damage = 4, releaseKnockback = V(0, 15, 40) },
			{ type = "Wait", time = 0.9 },
		},
	},
	Debris = {
		name = "Test Debris",
		nodes = {
			{ type = "Debris", position = V(0, 0, 5), size = V(10, 10, 10), count = 6, force = 50, lifetime = 3, settleAfter = 1.5, rebuildAfter = 5, visible = true },
			{ type = "PresetVFX", preset = "impact", position = V(0, 0, 5) },
			{ type = "Wait", time = 0.2 },
		},
	},
	Velocity = {
		name = "Test Velocity",
		nodes = {
			{ type = "Keyframes", anim = "dash" },
			{ type = "Velocity", direction = V(0, 0, 1), speed = 60, time = 0.25, fade = "cubicIn" },
			{ type = "Wait", time = 0.3 },
			{ type = "Velocity", direction = V(0, 0, -1), speed = 40, time = 0.2, holdHeight = true },
			{ type = "Keyframes", anim = "back_dash" },
			{ type = "Wait", time = 0.25 },
		},
	},
	Travel = {
		name = "Test Travel",
		branches = {
			Default = {
				{ type = "Travel", time = 0.35, stopDistance = 4, arc = 3, curve = "cubicOut", arriveBranch = "Arrive", mode = "Continue" },
				{ type = "Wait", time = 0.45 },
			},
			Arrive = { { type = "Hitbox", size = V(6, 6, 8), position = V(0, 0, 4), damage = 5, visible = true } },
		},
	},
	Teleport = {
		name = "Test Teleport",
		nodes = {
			{ type = "PresetVFX", preset = "afterimage" },
			{ type = "Teleport", who = "user", to = "lastHit", offset = V(0, 0, 4), facing = "target" },
			{ type = "PresetVFX", preset = "burst", color = "#b48cff" },
			{ type = "Wait", time = 0.2 },
		},
	},
	Animation = {
		name = "Test Animation",
		nodes = {
			{ type = "Animation", anim = 507770239, speed = 1.2 }, -- Roblox's default wave
			{ type = "Keyframes", anim = "slash_left", mirror = true },
			{ type = "Wait", time = 0.6 },
		},
	},
	Sound = {
		name = "Test Sound",
		nodes = {
			{ type = "Sound", sound = "swing", pitch = 1.2 },
			{ type = "Wait", time = 0.2 },
			{ type = "Sound", sound = "lunge", subject = "user" },
			{ type = "Wait", time = 0.3 },
		},
	},
	PresetVFX = {
		name = "Test Preset VFX",
		nodes = {
			{ type = "PresetVFX", preset = "shake", size = 1.5 },
			{ type = "PresetVFX", preset = "flash", color = "#ffffff" },
			{ type = "PresetVFX", preset = "vignette", color = "#200010" },
			{ type = "PresetVFX", preset = "blur" },
			{ type = "PresetVFX", preset = "tint", color = "#ffd0d0" },
			{ type = "PresetVFX", preset = "fov" },
			{ type = "PresetVFX", preset = "glow", color = "#ffcc66" },
			{ type = "PresetVFX", preset = "wind" },
			{ type = "Wait", time = 0.6 },
		},
	},
	Particle = {
		name = "Test Particle",
		nodes = {
			{ type = "Particle", texture = "sparkle", color = { { 0, "#ffe08a" }, { 1, "#ff6a3d" } }, emitCount = 40, speed = { 15, 30 }, size = 1.2, sizeCurve = "fadeLate", duration = 0.5 },
			{ type = "Particle", texture = "smoke", enabled = true, rate = 20, duration = 0.6, size = 2, transparencyCurve = "sineIn", position = V(0, -2, 0) },
			{ type = "Wait", time = 0.7 },
		},
	},
	MeshVisual = {
		name = "Test Mesh Visual",
		nodes = {
			{ type = "MeshVisual", mesh = "Sphere", size = V(2, 2, 2), altSize = V(14, 14, 14), color = C(255, 220, 140), altColor = C(255, 120, 60), material = "ForceField", time = 0.6, sizeCurve = "cubicOut", fadeCurve = "fadeLate", visualTag = "orb" },
			{ type = "MeshVisual", mesh = "Block", size = V(8, 0.4, 0.4), position = V(-6, 1, 4), altPosition = V(6, 1, 4), rotation = V(0, 0, 0), altRotation = V(0, 0, 90), time = 0.4, moveCurve = "pop" },
			{ type = "Highlight", applyTo = "orb", fill = "#ffcc66", outline = "#ffffff", duration = 0.5 },
			{ type = "Wait", time = 0.7 },
		},
	},
	Highlight = {
		name = "Test Highlight",
		nodes = {
			{ type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6) },
			{ type = "Highlight", subject = "lastHit", fill = "#ff4040", outline = "#ffffff", duration = 0.6, fadeCurve = "sineIn" },
			{ type = "Highlight", subject = "user", fill = "#40a0ff", duration = 0.4 },
			{ type = "Wait", time = 0.6 },
		},
	},
	Check = {
		name = "Test Check",
		branches = {
			Default = {
				-- on the ground at full health: Grounded runs; in the air it would be Aerial
				{ type = "Check", conds = { { what = "InAir" } }, passBranch = "Aerial", mode = "Switch" },
				{ type = "Check", conds = { { what = "Health", value = 0.5 }, { what = "InAir", ["not"] = true } }, passBranch = "Grounded", failBranch = "Hurt", mode = "Switch" },
			},
			Aerial = { { type = "Keyframes", anim = "blast" }, { type = "Wait", time = 0.3 } },
			Grounded = { { type = "Keyframes", anim = "punch" }, { type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 2 }, { type = "Wait", time = 0.3 } },
			Hurt = { { type = "Keyframes", anim = "back_dash" }, { type = "Wait", time = 0.3 } },
		},
	},
	Counter = {
		name = "Test Counter",
		branches = {
			Default = {
				{ type = "Keyframes", anim = "block" },
				{ type = "Counter", time = 0.8, stun = 1, counterBranch = "Punish" },
				{ type = "Wait", time = 0.8 },
			},
			Punish = { { type = "Keyframes", anim = "slash_right" }, { type = "Hitbox", size = V(6, 6, 10), position = V(0, 0, 6), damage = 12, knockback = V(0, 10, 30) }, { type = "Wait", time = 0.3 } },
		},
	},
	Heal = {
		name = "Test Heal and Meter",
		branches = {
			Default = {
				{ type = "Heal", amount = 20 },
				{ type = "Meter", meter = "awakening", op = "Add", value = 25 },
				{ type = "Check", conds = { { what = "Meter", meter = "awakening", value = 25 } }, passBranch = "Ready", mode = "Continue" },
				{ type = "Wait", time = 0.2 },
			},
			Ready = { { type = "PresetVFX", preset = "glow", color = "#ffd27a" } },
		},
	},
}
