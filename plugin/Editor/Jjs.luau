--!strict
-- Imports Jujutsu Shenanigans (JJS) character codes into SkillKit skills.
-- A JJS code is base64( zstd( JSON ) ). The JSON is a list of moves: { NAME, K_NAME (SKILL | SPECIAL | MELEE | CHASE |
-- AWAKENING), COOLDOWN?, KEY?, DATA } where DATA is itself a JSON string { Line = nodes, Prop, Req, Branch? = { name =
-- { Line, Req } } }. Node fields left at their JJS default are omitted from codes, so the defaults below fill them back in
-- (format as documented by the open-source libjjs encoder).
-- JJS's own animations, effects and built-in moves can't be used in another game, so they are swapped for the closest
-- SkillKit equivalent and every swap is listed in the notes.
local HttpService = game:GetService("HttpService")

local Jjs = {}

-- JJS animation ids ([character][animation]) -> names, to pick a similar built-in keyframe animation
local ANIMS: { [number]: any } = {
	[1] = { name = "HonoredOne", [1] = "HollowPurple", [2] = "InfiniteVoid", [3] = "LapseBlue", [4] = "LapseBlueMaximum", [5] = "RapidPunches", [6] = "ReversalRed", [7] = "ReversalRedMaximum", [8] = "Teleport", [9] = "TwofoldHit", [10] = "TwofoldKick", [11] = "Ultimate", [12] = "ShortVoid", [13] = "Melee1", [14] = "Melee2", [15] = "Melee3", [16] = "Melee4", [17] = "Up", [18] = "Down", [19] = "Chase" },
	[2] = { name = "Vessel", [1] = "CursedStrike", [2] = "CursedStrikeHit", [3] = "CrushingBlow", [4] = "DivergentFist1", [5] = "DivergentFist2", [6] = "DivergentFist3", [7] = "DivergentFist4", [8] = "ManjiKick", [9] = "ManjiKickHit", [10] = "Cleave", [11] = "Dismantle", [12] = "FlameArrow", [13] = "Rush", [14] = "RushHit", [15] = "MalevolentShrine", [16] = "SlaughterDemon", [17] = "Ultimate", [18] = "UltimateEnchain", [19] = "Instincts", [20] = "Melee1", [21] = "Melee2", [22] = "Melee3", [23] = "Melee4" },
	[3] = { name = "RestlessGambler", [1] = "Counter", [2] = "EnergySurge", [3] = "FeverBuilder", [4] = "IdleDeath", [5] = "LuckyRushdown", [6] = "LuckyVolley", [7] = "OverLuck", [8] = "ReserveBalls", [9] = "Rhythm", [10] = "RoughEnergy", [11] = "ShutterDoors", [12] = "Melee1", [13] = "Melee2", [14] = "Melee3", [15] = "Melee4", [16] = "Up", [17] = "Chase" },
	[4] = { name = "TenShadows", [1] = "DivineDog", [2] = "GreatSerpent", [3] = "MahoragaSummon", [4] = "MahoragaUse", [5] = "MaxElephant", [6] = "Nue", [7] = "RabbitEscape", [8] = "Shadow", [9] = "ShadowSwarm", [10] = "ShadowSwarm1", [11] = "ShadowSwarm2", [12] = "ShadowSwarm3", [13] = "ShadowSwarmHit", [14] = "ShadowSwarmRun", [15] = "Ultimate", [16] = "Melee1", [17] = "Melee2", [18] = "Melee3", [19] = "Melee4" },
	[5] = { name = "Mahoraga", [1] = "Adaptation", [2] = "DivinePummel", [3] = "Earthquake", [4] = "GroundPitch", [5] = "Parry", [6] = "Takedown", [7] = "WorldSlash", [8] = "Melee1", [9] = "Melee2", [10] = "Melee3", [11] = "Melee4", [12] = "Up", [13] = "Down" },
	[6] = { name = "Perfection", [1] = "BodyRepel", [2] = "CrushingRushdown", [3] = "CrushingRushdownHit", [4] = "DrillSplit", [5] = "FaceBlitz", [6] = "FocusStrike", [7] = "ForceGrab", [8] = "HeadSplitter", [9] = "HeadSplitterHit", [10] = "HeartPiercer", [11] = "IdleTransfig", [12] = "SelfPerfection", [13] = "Soulfire", [14] = "SpikeWrath", [15] = "Stockpile", [16] = "Ultimate", [17] = "Ultimate2", [18] = "WideStrike", [19] = "WideStrikeHit", [20] = "ChaseClub", [21] = "ChaseSword", [22] = "ChaseArmor", [23] = "Melee1", [24] = "Melee2", [25] = "Melee3", [26] = "Melee4", [27] = "Up", [28] = "Club_Melee1", [29] = "Club_Melee2", [30] = "Club_Melee3", [31] = "Club_Melee4", [32] = "Down", [33] = "Sword_Melee1", [34] = "Sword_Melee2", [35] = "Sword_Melee3", [36] = "Sword_Melee4" },
	[7] = { name = "BloodManipulation", [1] = "BloodEdge", [2] = "BloodEdgeVictim", [3] = "BloodRain", [4] = "Convergence", [5] = "PiercingBlood", [6] = "PlasmaWave", [7] = "RedScale", [8] = "RedScaleAir", [9] = "RedScaleVictim", [10] = "SlicingExorcism", [11] = "Supernova", [12] = "SupernovaCounter", [13] = "Ultimate", [14] = "WingKing", [15] = "WingKingVictim", [16] = "Melee1", [17] = "Melee2", [18] = "Melee3", [19] = "Melee4" },
	[8] = { name = "Switcher", [1] = "Brothers", [2] = "BruteForce", [3] = "ClimaxJump", [4] = "ClimaxJumpHit", [5] = "Dreams", [6] = "ElbowDrop", [7] = "IdolDebut", [8] = "PebbleThrow", [9] = "PebbleThrowHit", [10] = "SwiftKick", [11] = "SwiftKickHit", [12] = "Ultimate", [13] = "UltimateSummon", [14] = "JumpStart", [15] = "JumpEnd", [16] = "TakadaIdle", [17] = "Emote", [18] = "Clap1", [19] = "Clap2", [20] = "Clap3", [21] = "Melee1", [22] = "Melee2", [23] = "Melee3", [24] = "Melee4" },
	[9] = { name = "Locust", [1] = "BlackMucus", [2] = "BugFlight", [3] = "Flight", [4] = "FourArmed", [5] = "SnapChomp", [6] = "SnapChompHit", [7] = "Ultimate", [8] = "Melee1", [9] = "Melee2", [10] = "Melee3", [11] = "Melee4" },
	[10] = { name = "DefenseAttorney", [1] = "DeadlySentence", [2] = "Execution", [3] = "ExecutionHit1", [4] = "ExecutionHit2", [5] = "ExecutionHit3", [6] = "ExtendSwing", [7] = "FinalJudgement", [8] = "FinalJudgementHit", [9] = "Grapple", [10] = "JusticeServed", [11] = "JusticeServedHit", [12] = "TwirlingStrikes", [13] = "Ultimate", [14] = "Dodge1", [15] = "Dodge2", [16] = "Dodge3", [17] = "Dodge4", [18] = "Dodge5", [19] = "Verdict", [20] = "TripleSentence", [21] = "TripleSentenceHit", [22] = "JudgeReach", [23] = "JudgeReachHit", [24] = "JudgeReachHit2", [25] = "GavelThrow", [26] = "Melee1", [27] = "Melee2", [28] = "Melee3", [29] = "Melee4", [30] = "AltMelee1", [31] = "AltMelee2", [32] = "AltMelee3", [33] = "AltMelee4", [34] = "Chase", [35] = "JudgeReach2", [36] = "PressingCharges" },
	[11] = { name = "StarRage", [1] = "GarudaRebound", [2] = "GarudaStab", [3] = "GarudaStabHit", [4] = "MassBreaker", [5] = "RisingStar", [6] = "Ultimate", [7] = "Melee1", [8] = "Melee2", [9] = "Melee3", [10] = "Melee4", [30] = "AltMelee1", [31] = "AltMelee2", [32] = "AltMelee3", [33] = "AltMelee4" },
	[12] = { name = "Heian", [1] = "Chant", [2] = "Dismantle", [3] = "FlameArrow", [4] = "Kamutoke", [5] = "MalevolentShrine", [6] = "WCS" },
	[13] = { name = "CursedPartners", [1] = "ResoluteSlash", [2] = "Revolve", [3] = "SeveringPath", [4] = "Sheath", [5] = "Veilstep", [6] = "VeilstepDive", [7] = "SeveringPathAir", [8] = "RevolveReaction", [9] = "YutaBeam", [10] = "Launch", [11] = "Ultimate", [12] = "JacobLadder", [13] = "JacobLadderTarget", [14] = "ElbowBeatdown", [15] = "ElbowBeatdownTarget", [16] = "RunSlash", [17] = "CursedSpeech", [18] = "Melee1", [19] = "Melee2", [20] = "Melee3", [21] = "Melee4", [22] = "Chase", [23] = "Up", [24] = "Down", [25] = "SeveringSwing", [26] = "Outburst", [27] = "QuickdrawAerial", [28] = "SecondWind", [29] = "EnergyRipple", [30] = "Ult_Melee1", [31] = "Ult_Melee2", [32] = "Ult_Melee3", [33] = "Ult_Melee4", [34] = "Ultimate2" },
	[14] = { name = "AspiringMangaka", [1] = "Despair", [2] = "EyeCatch", [3] = "ShutUp", [4] = "ShutUpVictim", [5] = "Sacrilegious", [6] = "SacrilegiousHit", [7] = "Ultimate", [8] = "UltimateHit", [9] = "UltimateAfter", [10] = "Mark", [11] = "Melee1", [12] = "Melee2", [13] = "Melee3", [14] = "Melee4", [15] = "Up" },
	[15] = { name = "PuppetMaster", [1] = "BoostOnStart", [2] = "BoostOnEnd", [3] = "BoostOnTarget", [4] = "UltraSpin", [5] = "UltraSpinHit", [6] = "UltraCannon", [7] = "User", [8] = "Grab", [9] = "Kick", [10] = "FunnyFall", [11] = "SmoothLanding1", [12] = "SmoothLanding2", [13] = "BackSlide", [14] = "SupermanLanding", [15] = "ArmsFlyIn", [16] = "BoostOn", [17] = "BoostOnHit", [18] = "HeatEmission", [19] = "MiracleCannon", [20] = "PigeonViola", [21] = "AbsoluteDestructionOLD", [22] = "GunShot", [23] = "Kick", [24] = "JumpCrouch", [25] = "Stagger", [26] = "Spawn", [27] = "UltEnd", [28] = "Melee1", [29] = "Melee2", [30] = "Melee3", [31] = "Melee4", [32] = "Ult_Melee1", [33] = "Ult_Melee2", [34] = "Ult_Melee3", [35] = "Ult_Melee4", [36] = "Up", [37] = "AbsoluteDestruction", [38] = "AbsoluteDestructionAir" },
	[16] = { name = "HeadOfTheHei", [1] = "Bleedout", [2] = "BleedoutHit", [3] = "CursoryImpact", [4] = "DecisiveStrike", [5] = "DecisiveStrikeHit", [6] = "Flicker", [7] = "ProjectionBreaker", [8] = "Ultimate", [9] = "UltimateHit", [10] = "TopSpeed", [11] = "FlashFreezing", [12] = "TendrilGrab", [13] = "MoonPalace", [14] = "Acceleration", [15] = "Melee1", [16] = "Melee2", [17] = "Melee3", [18] = "Melee4", [19] = "Ult_Melee1", [20] = "Ult_Melee2", [21] = "Ult_Melee3", [22] = "Ult_Melee4" },
	[17] = { name = "Salaryman", [1] = "CleavingWhirlwind", [2] = "SeveranceKick", [3] = "BluntCut", [4] = "Stabilize", [5] = "StabilizeTarget", [6] = "StabilizeTargetShort", [7] = "RatioBreak1", [8] = "RatioBreak2", [9] = "RatioBreak3", [10] = "RatioBreak4", [11] = "RatioBreakStun", [12] = "Ultimate", [13] = "Melee1", [14] = "Melee2", [15] = "Melee3", [16] = "Melee4", [17] = "Up", [18] = "Down", [19] = "Ult_Melee1", [20] = "Ult_Melee2", [21] = "Ult_Melee3", [22] = "Ult_Melee4", [23] = "Sharpen", [24] = "Interrogate", [25] = "InterrogateHit", [26] = "InterrogateFinalHit", [27] = "Collapse" },
	[18] = { name = "MonkeyKid", [1] = "Kamehameha", [2] = "KiSpam", [3] = "StaffExtend", [4] = "StaffUppercut", [5] = "Ultimate", [6] = "Melee1", [7] = "Melee2", [8] = "Melee3", [9] = "Melee4" },
	[19] = { name = "LuckyCoward", [1] = "Ambush", [2] = "Stinger", [3] = "Backstab", [4] = "BackstabTargetBack", [5] = "BackstabTargetFront", [6] = "Trip", [7] = "CheapShot", [8] = "DirtyPlay", [9] = "JawbreakerHit", [10] = "JarbreakerVictim", [11] = "Melee1", [12] = "Melee2", [13] = "Melee3", [14] = "Melee4", [15] = "Melee4Victim", [16] = "MeleeChase", [17] = "SwordChase", [18] = "Up", [19] = "Down", [20] = "Taunt1", [21] = "Taunt2", [22] = "Taunt3", [23] = "Taunt4" },
	[20] = { name = "CrowCharmer", [1] = "BirdCall", [2] = "BirdHold", [3] = "Bounding", [4] = "BoundingVictim", [5] = "Circling", [6] = "CirclingVictim", [7] = "CirclingVictimFinisher", [8] = "Flock", [9] = "GlidingFlight", [10] = "GlidingFlightVictim", [11] = "ImpetusUpdraft", [12] = "Melee1", [13] = "Melee2", [14] = "Melee3", [15] = "Melee4", [16] = "Up", [17] = "Down", [18] = "Chase" },
	[21] = { name = "DisasterPlants", [1] = "BudShot", [2] = "DefenseResponse", [3] = "FlowerField", [4] = "RootSwarm", [5] = "SurgingThorns", [6] = "Melee1", [7] = "Melee2", [8] = "Melee3", [9] = "Melee4", [10] = "Chase" },
	[22] = { name = "TrueCannon", [1] = "Appetizer", [2] = "GraniteBlast", [3] = "HadNoIdea", [4] = "HadNoIdeaHit", [5] = "Recovery", [6] = "Recovery2", [7] = "SecondHelping", [8] = "ThisDessert", [9] = "ThisDessertHit", [10] = "Ultimate", [11] = "Unsatisfied", [12] = "WhatAreYouAfter", [13] = "WhatAreYouAfterHit", [14] = "Chase", [15] = "Melee3_2", [16] = "WerentInvited", [17] = "Recovery3" },
	[23] = { name = "BlackDeath", [1] = "FesteringStrikes", [2] = "Detach", [3] = "Reattach", [4] = "ChokeholdHit", [5] = "ChokeholdVictim", [6] = "EarthenTrance", [7] = "RoachSwarm", [8] = "Melee1", [9] = "Melee2", [10] = "Melee3", [11] = "Melee4", [12] = "Ult_Melee1", [13] = "Ult_Melee2", [14] = "Ult_Melee3", [15] = "Ult_Melee4", [16] = "Parthenogenesis", [17] = "Eat", [18] = "EatVictim" },
	[24] = { name = "Emotes", [1] = "Sasage", [2] = "Objection", [3] = "Guy", [4] = "Baldi", [5] = "Legend", [6] = "FingerWag", [7] = "Briefcase", [8] = "IrisOut2", [9] = "Pipebomb", [10] = "ChaosEmerald", [11] = "UFO", [12] = "Potential3", [13] = "Greedler", [14] = "Flop", [15] = "Sunglasses", [16] = "Doomer", [17] = "Stance", [18] = "WelcomeBack", [19] = "Popipo", [20] = "Aizo", [21] = "Moneylender", [22] = "Role", [23] = "RatDance", [24] = "Looping", [25] = "Emote_1A", [26] = "Unlicensed", [27] = "Sturdy", [28] = "LagTrain", [29] = "OKTOBERFEST", [30] = "Mystery", [31] = "Gangdance", [32] = "Birdbrain", [33] = "Spin", [34] = "PopStep", [35] = "PonyStory", [36] = "ElectroShuffle", [37] = "Potential", [38] = "SeatDepression", [39] = "PeaceSign", [40] = "Hopping", [41] = "Role2", [42] = "SecretTechnique", [43] = "Train", [44] = "Delightful", [45] = "NuhUh", [46] = "Confess", [47] = "Sprint", [48] = "Specialist", [49] = "HighFive", [50] = "SimplyWalkAroundIt", [51] = "Breakdance", [52] = "Fumo", [53] = "Gubby", [54] = "SH3NANIGANS", [55] = "Ship", [56] = "Crazy", [57] = "FusionDance", [58] = "Tomadachi", [59] = "NevadaMadness", [60] = "When", [61] = "ChestBump", [62] = "Cardboard", [63] = "Haircut", [64] = "MochiMaker", [65] = "Sit2", [66] = "ShubaDuck", [67] = "Unlicensed2", [68] = "Piano", [69] = "Kawaii", [70] = "Homelander", [71] = "Yeah", [72] = "Broom", [73] = "Wonderland", [74] = "Kikifuku", [75] = "MESMERIZED", [76] = "Cookie", [77] = "Facepalm", [78] = "DeadOrAlive", [79] = "Mannrobics", [80] = "Neurotoxin", [81] = "Strech2", [82] = "Challenger", [83] = "Unlucky", [84] = "Sneeze", [85] = "Brain", [86] = "Mockery", [87] = "Throne", [88] = "DieOfDeath", [89] = "Modulo", [90] = "Oddloop", [91] = "Mechanism", [92] = "ShowMeYaMoves", [93] = "Paradise2", [94] = "Reader", [95] = "Watashi", [96] = "Split", [97] = "CookingGranny", [98] = "IrisOut", [99] = "Trumpet", [100] = "Bow", [101] = "Power", [102] = "Drums", [103] = "Chill", [104] = "Helicopter", [105] = "Chill2", [106] = "HowTzeWasMoving", [107] = "Miko", [108] = "MirrorWorld", [109] = "Lethal", [110] = "Drag", [111] = "Killbind", [112] = "SpareChange", [113] = "Coinflip", [114] = "More", [115] = "Clap", [116] = "Stylish", [117] = "Unlicensed3", [118] = "Message", [119] = "Thunder", [120] = "Heart", [121] = "Winner", [122] = "Grillify", [123] = "Mozzarella", [124] = "Rainwalk", [125] = "Jiggy", [126] = "SwordSurfing", [127] = "BubbleBlower", [128] = "VirtualInsanity", [129] = "MissMe", [130] = "Broke", [131] = "KazotskyKick", [132] = "Menacing", [133] = "Selfie", [134] = "Caramelldansen", [135] = "ImOld", [136] = "AuraMonster", [137] = "Heart111", [138] = "EggheadsEndeavour", [139] = "Provocation", [140] = "DevilHunter", [141] = "Superstar1", [142] = "LowCortisol", [143] = "Flow", [144] = "Score", [145] = "ItsGoingDown", [146] = "GroundDrone", [147] = "Update", [148] = "Roach", [149] = "Warfstache", [150] = "Meditation", [151] = "Static", [152] = "TVTime", [153] = "Dogsync", [154] = "HeartbeatHeartbreak", [155] = "EntryFlow", [156] = "Snap", [157] = "Taunt", [158] = "Basketball", [159] = "BrightestHeart", [160] = "Clash", [161] = "IMissTheQuiet", [162] = "Insanity", [163] = "Stomp", [164] = "TrickyDJ", [165] = "Conga", [166] = "Camera", [167] = "StreamerAdventures", [168] = "Unyeah", [169] = "HoofShuffle", [170] = "StrongestOfHistory", [171] = "StarPower", [172] = "CursedInstincts", [173] = "BigShoe", [174] = "Popcorn", [175] = "Clash2", [176] = "Perfect", [177] = "OPP", [178] = "ExcuseMeSir", [179] = "BillyBounce", [180] = "DreamFriends", [181] = "Mourning", [182] = "Insane2", [183] = "Boombox", [184] = "LostMedia", [185] = "Sidepot", [186] = "Camcorder", [187] = "Bird", [188] = "Speedster", [189] = "Paradise", [190] = "Potential2", [191] = "Paradise3", [192] = "Pickaxe", [193] = "Coin", [194] = "SmoothCriminal", [195] = "Bling", [196] = "TrueSelf", [197] = "Pokedance", [198] = "Science", [199] = "ItsNoUse", [200] = "Stretch", [201] = "Tiger", [202] = "Hugo", [203] = "Tired", [204] = "NanaBooBoo", [205] = "Comedian", [206] = "Burnice", [207] = "Dare", [208] = "Paced", [209] = "Jeep", [210] = "Rocks", [211] = "MoneyFan", [212] = "Honored", [213] = "Bow3", [214] = "ChalkToss", [215] = "LuckStar", [216] = "Turron", [217] = "Nervous", [218] = "TakeMyHat", [219] = "SpokenFor", [220] = "Emote_61", [221] = "DidYouSeeThat", [222] = "TrueCurse", [223] = "Democracy", [224] = "SaiyanWalk", [225] = "DemonDance", [226] = "BrazilianCalisthenics", [227] = "Equestria", [228] = "Bang", [229] = "LiarDancer", [230] = "GangFlex", [231] = "Love", [232] = "HardJump", [233] = "DoTheBartman", [234] = "Envelope", [235] = "Legend2", [236] = "Lonely", [237] = "RAHHH", [238] = "JaxToy", [239] = "Guidance", [240] = "AbsoluteCinema", [241] = "Jevil", [242] = "Demon", [243] = "Murder", [244] = "Turbo", [245] = "Vessel", [246] = "Teto", [247] = "HippocampalReload", [248] = "Jackpot", [249] = "Garbage", [250] = "Yamcha", [251] = "Megaphone", [252] = "GlassHeart", [253] = "Ghouls", [254] = "Vance", [255] = "Extinguish", [256] = "LightSticks", [257] = "Sit", [258] = "Ganon", [259] = "BizarreDuo", [260] = "Ragdoll", [261] = "Swap", [262] = "StrongestOfToday", [263] = "Carry", [264] = "Jolly", [265] = "Sugawara", [266] = "Chirumiru", [267] = "Garry", [268] = "Smug", [269] = "LyingRage", [270] = "Bathtub", [271] = "MUSTARD", [272] = "Slipbeat", [273] = "BoomMic", [274] = "BlueSky", [275] = "OnTop", [276] = "Jackpot2", [277] = "AMimir", [278] = "PitchforkProtest", [279] = "Superstar3", [280] = "FingerStand", [281] = "Spin2", [282] = "Retrial", [283] = "Fumokill", [284] = "Potion", [285] = "Brainrot", [286] = "AreYou", [287] = "PsychicRun", [288] = "Places", [289] = "KickBack", [290] = "Piggyback", [291] = "WarGirl", [292] = "Salesman", [293] = "DeadWrong", [294] = "ExProvocation", [295] = "Superstar2", [296] = "Photos", [297] = "Vesselll", [298] = "Cooking", [299] = "Eggrolled", [300] = "Sanitizer", [301] = "Windy", [302] = "Reclassed", [303] = "Competent", [304] = "Bizarre", [305] = "LemonCookie", [306] = "SpeedFeat", [307] = "SodaPop", [308] = "Onion", [309] = "ABA", [310] = "Headphones", [311] = "Cake", [312] = "Hug", [313] = "Wait", [314] = "Awkward", [315] = "Insane", [316] = "TestEmote", [317] = "Silly", [318] = "NecoArc", [319] = "Bow2", [320] = "Dragon", [321] = "Lob" },
}

local DEFAULTS: { [string]: { [string]: any } } = {
	WAIT = { TIME = 1 },
	SKILL = { MOVE = "Divergent Fist", SPEED = 1, START = 0, ["HOLD FOR"] = 0, ["ENABLE VARIANTS"] = true, ["CANCEL LAST"] = false },
	SPECIAL = { SPEC = "Limitless", SPEED = 1, ["ENABLE VARIANTS"] = true, ["CANCEL LAST"] = false },
	ANIM = { ANIM_USE = { 1, 1 }, PREVIEW = { 0, 10 }, SPEED = 1, ["FADE IN"] = 0.1, ["FADE OUT"] = 0, ["LAST HIT"] = -1, LOOPED = false },
	SFX = { ID = 12222253, START = 0, END = 500, SPEED = 1, VOLUME = 1, ["FADE IN"] = 0, ["FADE OUT"] = 0, GLOBAL = false, ["PROJECTILE TAG"] = "nil", CANCEL = false },
	VELO = { FORCE = "0, 0, 0", TIME = 0, FADE = false, TRACK = false, ["LAST HIT"] = -1, RAGDOLL = 0, ["TRUE RAGDOLL"] = false, ["RELATIVE FROM BRANCH"] = false },
	CONNECT = { SIGNAL = "Nothing", TIME = 0.1, RANGE = "inf" },
	HITBOX = {
		POSITION = "0, 0, 4", ROTATION = "0, 0, 0", SIZE = "6, 6, 6", STUN = 1, ["STUN ANIM"] = false, DAMAGE = 1, DEBREE = 0,
		["ATTACK TYPE"] = "Melee", BLOCKABLE = true, ["360 BLOCK"] = false, ["CANCEL ENEMY"] = true, ["CLEAR KNOCKBACK"] = false,
		["CAN KILL"] = true, ["HIT RAGDOLL"] = false, ["HIT USER"] = false, ["SINGLE TARGET"] = true, BRANCH = "nil",
		["BRANCH TARGET"] = "nil", ["BRANCH FINISHER"] = "nil", ["PROJECTILE TAG"] = "nil", ["IGNORE WAKEUP"] = false,
	},
	BRANCH = { BRANCH = "nil", RANDOM = "", ["LAST HIT"] = -1 },
	VISUAL = {
		EFFECT = "Slash", TIME = 1, POSITION = "0, 0, 0", ROTATION = "0, 0, 0", SIZE = 1, COLOR = "255, 255, 255", OPACITY = 0,
		["ALT POSITION"] = "0, 0, 0", ["ALT ROTATION"] = "0, 0, 0", ["ALT SIZE"] = 1, ["ALT COLOR"] = "255, 255, 255", ["ALT OPACITY"] = 0,
		TEXTURE = 0, ["BODY PART"] = "HumanoidRootPart", ["EASING STYLE"] = "Linear", ["EASING DIRECTION"] = "In", ["PROJECTILE TAG"] = "nil",
		["VISUAL TAG"] = "nil", AMOUNT = 1, ["RUN ON SERVER"] = false, ["RELATIVE FROM BRANCH"] = false, ["CANCEL ON INTERRUPT"] = false,
		["CAN COLLIDE"] = false, ["LAST HIT"] = -1,
	},
	GRAB = { ["BODY PART"] = "HumanoidRootPart", ["BODY PART2"] = "HumanoidRootPart", TIME = 1, POSITION = "0, 0, 0", ROTATION = "0, 0, 0", ["LAST HIT"] = 1 },
	PROJECTILE = {
		DAMAGE = 1, STUN = 1, SPEED = 1, SIZE = "6, 6, 6", POSITION = "0, 0, 0", ROTATION = "0, 0, 0", ["ATTACK TYPE"] = "Melee",
		["PROJECTILE TAG"] = "nil", ["REFLECT COUNT"] = 0, ["FILTER INTERVAL"] = 1, BRANCH = "nil", ["BRANCH TARGET"] = "nil",
		["BRANCH COLLIDED"] = "nil", CONTINUE = false, ["HIT RAGDOLL"] = false, ["STUN ANIM"] = false, ["HIT USER"] = false,
		BLOCKABLE = true, ["360 BLOCK"] = false, ["CAN KILL"] = true, ["AIM LAST HIT"] = -1, TIME = 1, ["IGNORE WAKEUP"] = true,
		DEBREE = 0, ["CANCEL ENEMY"] = true, CACHE = true, ["CLEAR KNOCKBACK"] = false,
	},
	COUNTER = { TIME = 1, STUN = 1, ["ATTACK TYPE2"] = "Melee", BRANCH = "nil", ["BRANCH TARGET"] = "nil", ["CANCEL ENEMY"] = true, ["REMOVE ON HIT"] = true },
	TAG = { TAG = "nil", VALUE = "nil", TIME = 1, ["ADD/REMOVE"] = true, CHECK = false, SET = true, BRANCH = "nil", ["LAST HIT"] = -1 },
	STATE = { STATE = "Stun", VALUE = 1, TIME = 1, ["DISABLE BURST"] = false, ["CANCEL ON END"] = false, ["LAST HIT"] = -1, BRANCH = "nil", CHECK = false },
	TELEPORT = { POSITION = "0, 0, 0", ROTATION = "0, 0, 0", ["PROJECTILE TAG"] = "nil", ["LAST HIT"] = -1, ["RELATIVE FROM BRANCH"] = false },
	ULTGIB = { AMOUNT = 5 },
	HPGIB = { AMOUNT = 5 },
	EVGIB = { AMOUNT = 5 },
	HITCNCL = { TIME = 1, ENDLAG = 1, BRANCH = "nil", FLIP = false },
	SETCD = { KEY = -1, COOLDOWN = -1 },
	LOOP = { ["LOOP BACK"] = 1, HOLD = false, ["LOOP AMOUNT"] = 3 },
}
Jjs.DEFAULTS = DEFAULTS

-- JJS effect -> SkillKit preset (nil = no equivalent: noted)
local EFFECTS: { [string]: string } = {
	Slash = "beam", Cleave = "beam", ["Whirl Slash"] = "ring", Dismantle = "beam", ["Melee Trail"] = "afterimage",
	["Black Flash"] = "burst", Sparks = "burst", ["Energy Sparks"] = "burst", ["Weak Lightning"] = "burst", ["Mass Hit"] = "impact",
	Burst = "burst", Clash = "impact", Blood = "impact", Block = "highlight",
	["Shake Light"] = "shake", ["Shake Medium"] = "shake", ["Shake Heavy"] = "shake", Camera = "shake",
	Afterimage = "afterimage", Afterimage2 = "afterimage",
	Ring = "ring", ["Wind Ring"] = "ring", ["Wind Expand"] = "wind", ["360 Wind"] = "wind", ["Wind Streak"] = "wind",
	Beam = "beam", Beams = "beam", ["Screen Color"] = "tint", Overlay = "flash", ["Field of View"] = "fov",
	Glow = "glow", ["Circle Glow"] = "glow", Shine = "glow", Light = "glow", Star = "glow", ["Star Outline"] = "glow",
	["Cursed Energy"] = "glow", ["Rough Energy"] = "glow", Flames = "glow", Distortion = "blur",
	Sphere = "mesh:Sphere", Cylinder = "mesh:Cylinder", Wedge = "mesh:Block", Mesh = "mesh:Sphere", Billboard = "glow",
}

-- JJS easing (style + direction) -> a SkillKit curve name ("cubicOut", "linear", ...)
local EASE = { Linear = "linear", Sine = "sine", Quad = "quad", Cubic = "cubic", Exponential = "expo", Back = "back" }
local function easing(n: any): string
	local style = EASE[tostring(n["EASING STYLE"] or "Linear")] or "linear"
	if style == "linear" then
		return "linear"
	end
	local dir = tostring(n["EASING DIRECTION"] or "In")
	return style .. ((dir == "Out" or dir == "InOut") and dir or "In")
end

-- slot of a JJS move in a SkillKit character
local function slotOf(move: any): string
	local k = move.K_NAME
	if k == "MELEE" then
		return "M1"
	elseif k == "CHASE" then
		return "Dash"
	elseif k == "AWAKENING" then
		return "Awakening"
	elseif k == "SPECIAL" then
		return "Custom"
	end
	local key = tonumber(move.KEY) or 1
	return key >= 1 and key <= 4 and ("Skill" .. key) or "Custom"
end
Jjs.slotOf = slotOf

-- DECODE ---------------------------------------------------------------------------------------------------------------------
function Jjs.decode(code: string): (any, string?)
	code = (code:gsub("%s", ""))
	if code == "" then
		return nil, "empty code"
	end
	local ok, res = pcall(function()
		local ES = game:GetService("EncodingService") :: any
		local raw = ES:Base64Decode(buffer.fromstring(code))
		local json = ES:DecompressBuffer(raw, Enum.CompressionAlgorithm.Zstd)
		return buffer.tostring(json)
	end)
	if not ok then
		return nil, "not a JJS code (couldn't unpack it): " .. tostring(res)
	end
	local ok2, moves = pcall(HttpService.JSONDecode, HttpService, res)
	if not ok2 or type(moves) ~= "table" then
		return nil, "the code unpacked but isn't JSON"
	end
	if moves.NAME then
		moves = { moves }
	end
	for _, m in ipairs(moves) do
		if type(m.DATA) == "string" then
			local ok3, data = pcall(HttpService.JSONDecode, HttpService, m.DATA)
			m.DATA = ok3 and data or {}
		end
		m.DATA = m.DATA or {}
	end
	return moves, nil
end

-- encode (for making test / example codes in Studio)
function Jjs.encode(moves: { any }): string
	local ES = game:GetService("EncodingService") :: any
	local out = {}
	for i, m in ipairs(moves) do
		local c = table.clone(m)
		if type(c.DATA) == "table" then
			c.DATA = HttpService:JSONEncode(c.DATA)
		end
		out[i] = c
	end
	local json = HttpService:JSONEncode(out)
	local packed = ES:CompressBuffer(buffer.fromstring(json), Enum.CompressionAlgorithm.Zstd, 9)
	return buffer.tostring(ES:Base64Encode(packed))
end

-- CONVERT --------------------------------------------------------------------------------------------------------------------
local function vec(s: any): Vector3
	if type(s) == "table" then
		return Vector3.new(tonumber(s[1]) or 0, tonumber(s[2]) or 0, tonumber(s[3]) or 0)
	end
	local n = {}
	for x in tostring(s or ""):gmatch("[-%d%.e]+") do
		table.insert(n, tonumber(x) or 0)
	end
	return Vector3.new(n[1] or 0, n[2] or 0, n[3] or 0)
end
local function rgb(s: any): Color3
	local v = vec(s)
	return Color3.fromRGB(math.clamp(v.X, 0, 255), math.clamp(v.Y, 0, 255), math.clamp(v.Z, 0, 255))
end
local function num(v: any, fallback: number): number
	if v == "inf" then
		return 9999
	end
	return tonumber(v) or fallback
end
local function br(v: any): string?
	if type(v) ~= "string" or v == "nil" or v == "" then
		return nil
	end
	return v
end
local function lastHit(n: any): boolean
	return (tonumber(n["LAST HIT"]) or -1) >= 0
end

-- a built-in keyframe animation that looks like the JJS one
local function animFor(id: any): (string, string)
	local c, a = 0, 0
	if type(id) == "table" then
		c, a = tonumber(id[1]) or 0, tonumber(id[2]) or 0
	end
	local ch = ANIMS[c]
	local name = ch and ch[a] or "?"
	local full = (ch and ch.name or ("char" .. c)) .. "." .. name
	local l = string.lower(name)
	local pick = "punch"
	if l:find("kick") then
		pick = "slash_left"
	elseif l:find("slash") or l:find("cleave") or l:find("dismantle") or l:find("swing") or l:find("cut") or l:find("blade") then
		pick = "slash_right"
	elseif l:find("dash") or l:find("rush") or l:find("chase") or l:find("teleport") or l:find("lunge") or l:find("charge") then
		pick = "dash"
	elseif l:find("back") or l:find("retreat") or l:find("down") then
		pick = "back_dash"
	elseif l:find("block") or l:find("counter") or l:find("guard") then
		pick = "block"
	elseif l:find("purple") or l:find("red") or l:find("blue") or l:find("blast") or l:find("arrow") or l:find("beam") or l:find("shot")
		or l:find("volley") or l:find("void") or l:find("ultimate") or l:find("domain") or l:find("shrine") or l:find("cannon") then
		pick = "blast"
	elseif l:find("melee2") or l:find("melee4") or l:find("fist2") or l:find("fist4") then
		pick = "slash_left"
	end
	return pick, full
end

-- one JJS node list -> SkillKit nodes (notes collects everything that didn't map 1:1)
-- JJS conditions ({ K_NAME, FLIP, AMOUNT }) -> SkillKit Check conditions
function Jjs.conds(reqs: { any }, notes: { string }, at: string): { any }
	local out = {}
	for _, r in ipairs(reqs or {}) do
		local k = tostring(r.K_NAME)
		local c: any = nil
		if k == "AIR" then
			c = { what = "InAir" }
		elseif k == "JUMP" then
			c = { what = "Jumping" }
		elseif k == "AIM" then
			c = { what = "Aiming" }
		elseif k == "HOLD" then
			c = { what = "Holding" }
		elseif k == "HP" then
			local a = tonumber(r.AMOUNT) or 1
			c = { what = "Health", value = a > 1 and a / 100 or a }
		elseif k == "ULT" then
			c = { what = "Meter", meter = "awakened", value = 1 }
		elseif k == "BAR" then
			c = { what = "Meter", meter = "awakening", value = tonumber(r.AMOUNT) or 2 }
		elseif k == "DOMAIN" then
			c = { what = "Meter", meter = "domain", value = 1 }
		else
			table.insert(notes, ("%s: condition %s has no SkillKit equivalent; ignored"):format(at, k))
		end
		if c then
			if r.FLIP == true then
				c["not"] = true
			end
			table.insert(out, c)
		end
	end
	return out
end

type Ctx = { prefix: string, conds: { [string]: { any } }, chains: { any }? }
local function convertLine(line: { any }, mult: { dmg: number, kb: number }, notes: { string }, where: string, ctx: Ctx?): { any }
	local out: { any } = {}
	local cx: Ctx = ctx or { prefix = "", conds = {} }
	-- branch names get the combo prefix (when several moves are merged into one skill)
	local function brn(v: any): string?
		local b = br(v)
		return b and (cx.prefix .. b) or nil
	end
	local function lastOf(t: string): any
		for i = #out, 1, -1 do
			if out[i].type == t then
				return out[i]
			end
		end
		return nil
	end
	for i, raw in ipairs(line or {}) do
		local k = raw.K_NAME
		local d = DEFAULTS[k] or {}
		local n = setmetatable(raw, { __index = d })
		local at = ("%s #%d %s"):format(where, i, tostring(k))
		if k == "WAIT" then
			table.insert(out, { type = "Wait", time = num(n.TIME, 1) })
		elseif k == "ANIM" then
			local pick, full = animFor(n.ANIM_USE)
			table.insert(out, { type = "Keyframes", anim = pick, speed = num(n.SPEED, 1), looped = n.LOOPED == true, subject = lastHit(n) and "lastHit" or "user" })
			table.insert(notes, ("%s: JJS animation %s -> built-in %q"):format(at, full, pick))
		elseif k == "SFX" then
			table.insert(out, { type = "Sound", sound = "rbxassetid://" .. tostring(n.ID), volume = math.clamp(num(n.VOLUME, 1) * 0.6, 0, 3), speed = num(n.SPEED, 1) })
		elseif k == "VELO" then
			local f = vec(n.FORCE)
			if f.Magnitude > 0 then
				table.insert(out, {
					type = "Velocity",
					subject = lastHit(n) and "lastHit" or "user",
					direction = f.Unit,
					speed = f.Magnitude * mult.kb,
					space = "Local",
					time = math.min(num(n.TIME, 0), 5),
					fade = n.FADE == true and "linear" or nil,
					track = n.TRACK == true,
					ragdoll = num(n.RAGDOLL, 0) > 0 or n["TRUE RAGDOLL"] == true,
				})
			end
		elseif k == "HITBOX" then
			local h: any = {
				type = "Hitbox",
				position = vec(n.POSITION),
				rotation = vec(n.ROTATION),
				size = vec(n.SIZE),
				damage = num(n.DAMAGE, 1) * mult.dmg,
				stun = math.max(0, num(n.STUN, 1)),
				blockable = n.BLOCKABLE ~= false,
				block360 = n["360 BLOCK"] == true,
				canKill = n["CAN KILL"] ~= false,
				hitRagdoll = n["HIT RAGDOLL"] == true,
				hitUser = n["HIT USER"] == true,
				singleTarget = n["SINGLE TARGET"] ~= false,
				victimBranch = brn(n.BRANCH) or brn(n["BRANCH TARGET"]),
				finisherBranch = brn(n["BRANCH FINISHER"]),
				-- JJS: a hitbox's BRANCH takes over the move (the rest of this line stops); BRANCH TARGET runs alongside
				mode = br(n.BRANCH) and "Switch" or "Continue",
			}
			if br(n.BRANCH) and br(n["BRANCH TARGET"]) and n.BRANCH ~= n["BRANCH TARGET"] then
				-- JJS runs both on a hit; SkillKit runs BRANCH, which then also starts BRANCH TARGET
				cx.chains = cx.chains or {}
				table.insert(cx.chains, { from = brn(n.BRANCH), to = brn(n["BRANCH TARGET"]) })
			end
			table.insert(out, h)
			if num(n.DEBREE, 0) > 0 then
				table.insert(out, { type = "Debris", position = h.position, size = h.size, count = math.clamp(math.floor(num(n.DEBREE, 0)), 1, 12) })
			end
		elseif k == "BRANCH" then
			local target = br(n.BRANCH)
			local random = tostring(n.RANDOM or "")
			if not target and random ~= "" then
				target = random:match("^%s*([^,]+)")
				table.insert(notes, ("%s: random branch (%s): SkillKit picks the first, %s"):format(at, random, tostring(target)))
			end
			local reqs = target and cx.conds[target]
			if target and reqs and #reqs > 0 then
				-- JJS only takes this branch when its conditions pass: a Check that switches to it, else the line goes on
				local conds = Jjs.conds(reqs, notes, at)
				if #conds > 0 then
					table.insert(out, { type = "Check", conds = conds, passBranch = cx.prefix .. target, mode = "Switch" })
				end
			elseif target then
				table.insert(out, { type = "Branch", target = cx.prefix .. target, mode = "Switch" })
			end
		elseif k == "VISUAL" then
			local eff = tostring(n.EFFECT)
			local preset = EFFECTS[eff]
			local subject = lastHit(n) and "lastHit" or "user"
			if eff == "Cancel" then
				table.insert(notes, ("%s: 'Cancel' (stops the move's earlier effects) isn't needed in SkillKit; skipped"):format(at))
			elseif eff == "Visibility" then
				table.insert(notes, ("%s: Visibility (hide / show body parts) has no SkillKit node; skipped"):format(at))
			elseif preset and preset:sub(1, 5) == "mesh:" then
				local s = num(n.SIZE, 1)
				local s2 = num(n["ALT SIZE"], s)
				table.insert(out, {
					type = "MeshVisual",
					mesh = preset:sub(6),
					subject = subject,
					position = vec(n.POSITION),
					altPosition = vec(n["ALT POSITION"]),
					rotation = vec(n.ROTATION),
					altRotation = vec(n["ALT ROTATION"]),
					size = Vector3.one * s,
					altSize = Vector3.one * s2,
					color = rgb(n.COLOR),
					altColor = rgb(n["ALT COLOR"]),
					transparency = num(n.OPACITY, 0),
					altTransparency = num(n["ALT OPACITY"], 0),
					time = math.min(num(n.TIME, 1), 10),
					moveCurve = easing(n),
					sizeCurve = easing(n),
					fadeCurve = easing(n),
					colorCurve = easing(n),
				})
			elseif preset then
				table.insert(out, {
					type = "PresetVFX",
					preset = preset,
					subject = subject,
					position = vec(n.POSITION),
					duration = math.min(num(n.TIME, 1), 10),
					color = rgb(n.COLOR),
					size = num(n.SIZE, 1),
				})
				if preset ~= string.lower(eff) then
					table.insert(notes, ("%s: effect %q -> preset %q"):format(at, eff, preset))
				end
			else
				table.insert(notes, ("%s: effect %q has no equivalent; skipped"):format(at, eff))
			end
		elseif k == "GRAB" then
			local p = vec(n.POSITION)
			table.insert(out, { type = "Grab", holdOffset = Vector3.new(p.X, p.Y, p.Z ~= 0 and -p.Z or -3), duration = num(n.TIME, 1) })
		elseif k == "PROJECTILE" then
			local size = vec(n.SIZE)
			table.insert(out, {
				type = "Projectile",
				size = math.max(size.X, size.Y, size.Z) / 2,
				radius = math.max(size.X, size.Y, size.Z) / 2,
				position = vec(n.POSITION),
				speed = num(n.SPEED, 1) * 60,
				lifetime = math.min(num(n.TIME, 1), 10),
				damage = num(n.DAMAGE, 1) * mult.dmg,
				stun = math.max(0, num(n.STUN, 1)),
				blockable = n.BLOCKABLE ~= false,
				canKill = n["CAN KILL"] ~= false,
				pierce = n.CONTINUE == true,
				projectileTag = br(n["PROJECTILE TAG"]),
				direction = num(n["AIM LAST HIT"], -1) >= 0 and "toTarget" or "look",
				hitBranch = brn(n.BRANCH) or brn(n["BRANCH TARGET"]),
				expireBranch = brn(n["BRANCH COLLIDED"]),
			})
			table.insert(notes, ("%s: projectile speed %s x 60 studs/s (a guess at JJS's scale)"):format(at, tostring(n.SPEED)))
		elseif k == "TAG" then
			local value = tonumber(n.VALUE) or 1
			local t: any = { type = "Tags", subject = lastHit(n) and "lastHit" or "user", tag = tostring(n.TAG), value = value, time = num(n.TIME, 1) }
			if n.CHECK == true then
				t.op = "Check"
				t.compare = ">="
				t.passBranch = brn(n.BRANCH)
			elseif n.SET == true then
				t.op = "Set"
			else
				t.op = n["ADD/REMOVE"] == false and "Subtract" or "Add"
			end
			table.insert(out, t)
		elseif k == "STATE" then
			local st = tostring(n.STATE)
			local s: any = { type = "State", subject = lastHit(n) and "lastHit" or "user", duration = num(n.TIME, 1), value = num(n.VALUE, 1) }
			if st == "Stun" then
				s.category, s.sub = "Disable", { "Movement", "Jump", "Skill" }
			elseif st == "NoM1" then
				s.category, s.sub = "Disable", { "Skill" }
			elseif st == "NoSprint" then
				s.category, s.sub = "Disable", { "Sprint" }
			elseif st == "NoJump" then
				s.category, s.sub = "Disable", { "Jump" }
			elseif st == "NoDash" or st == "DisableChase" then
				s.category, s.sub = "Disable", { "Movement" }
				table.insert(notes, ("%s: %s -> Disable Movement (no dash lock in SkillKit)"):format(at, st))
			elseif st == "DirectionLock" then
				s.category, s.sub = "Lock", { "Direction" }
			elseif st == "SpeedMultiplier" then
				s.category, s.sub = "Multiplier", { "Speed" }
			elseif st == "IFrame" then
				s.category, s.sub, s.value = "Multiplier", { "DamageTaken" }, 0
			elseif st == "Ragdoll" then
				s.category, s.sub = "Ragdoll", {}
			elseif st == "JumpMultiplier" then
				s.category, s.sub = "Multiplier", { "Jump" }
			elseif st == "Cancel" and not lastHit(n) then
				-- cancel on yourself = stop your current motion (a zero velocity replaces it)
				s = { type = "Velocity", subject = "user", direction = Vector3.new(0, 0, 1), speed = 0, space = "Local", time = 0.05 }
			elseif st == "Wakeup" or st == "Cancel" then
				s = nil
				table.insert(notes, ("%s: state %q is JJS-specific (%s); skipped"):format(at, st, st == "Wakeup" and "get-up" or "cancels the target's move"))
			else
				s = nil
				table.insert(notes, ("%s: state %q has no equivalent; skipped"):format(at, st))
			end
			if s then
				table.insert(out, s)
			end
		elseif k == "TELEPORT" then
			local p = vec(n.POSITION)
			table.insert(out, { type = "Teleport", who = "user", to = lastHit(n) and "lastHit" or "user", offset = Vector3.new(p.X, p.Y, -p.Z), rotation = vec(n.ROTATION) })
		elseif k == "LOOP" then
			local back = math.max(1, math.floor(num(n["LOOP BACK"], 1)))
			local amount = math.max(1, math.floor(num(n["LOOP AMOUNT"], 3)))
			local inner = {}
			for _ = 1, math.min(back, #out) do
				table.insert(inner, 1, table.remove(out))
			end
			table.insert(out, { type = "Loop", count = amount, blocking = true, nodes = inner })
			if n.HOLD == true then
				table.insert(notes, ("%s: 'loop while held' becomes a fixed %d repeats"):format(at, amount))
			end
		elseif k == "HITCNCL" then
			-- "hit cancel": if the last hitbox missed (or hit, when FLIP), go to BRANCH
			local h = lastOf("Hitbox")
			local target = brn(n.BRANCH)
			if h and target then
				if n.FLIP == true then
					h.victimBranch = h.victimBranch or target
				else
					h.missBranch = target
				end
			elseif target then
				table.insert(notes, ("%s: hit cancel to %s with no hitbox before it; skipped"):format(at, tostring(n.BRANCH)))
			end
		elseif k == "PARTICLE" then
			local function range(v: any, a: number, b: number): { number }
				local r = {}
				for x in tostring(v or ""):gmatch("[-%d%.e]+") do
					table.insert(r, tonumber(x) or 0)
				end
				return { r[1] or a, r[2] or r[1] or b }
			end
			local size = range(n.SIZE, 1, 1)
			local tr = range(n.TRANSPARENCY, 0, 1)
			local fb = range(n["FLIPBOOK SIZE"], 0, 0)
			local p: any = {
				type = "Particle",
				subject = lastHit(n) and "lastHit" or "user",
				position = vec(n.POSITION or "0, 0, 0"),
				texture = tonumber(n.TEXTURE) and ("rbxassetid://" .. tostring(n.TEXTURE)) or "",
				color = rgb(n.COLOR or "255, 255, 255"),
				emitCount = math.floor(num(n["EMIT COUNT"], 20)),
				lifetime = range(n.LIFETIME, 0.4, 0.8),
				speed = range(n.SPEED, 10, 20),
				rotSpeed = range(n["ROT SPEED"], 0, 0),
				size = (size[1] + size[2]) / 2,
				acceleration = vec(n.ACCELERATION or "0, 0, 0"),
				drag = num(n.DRAG, 0),
				transparencyCurve = { points = { { 0, tr[1] }, { 1, tr[2] } } },
			}
			if fb[1] > 1 then
				p.flipbook = { rows = fb[1], cols = fb[2], fps = num(n["FLIPBOOK FRAMERATE"], 30) }
			end
			table.insert(out, p)
		elseif k == "HPGIB" then
			table.insert(out, { type = "Heal", subject = lastHit(n) and "lastHit" or "user", amount = num(n.AMOUNT, 5) })
		elseif k == "ULTGIB" or k == "EVGIB" then
			table.insert(out, { type = "Meter", meter = k == "ULTGIB" and "awakening" or "evasion", op = "Add", value = num(n.AMOUNT, 5) })
		elseif k == "COUNTER" then
			table.insert(out, {
				type = "Counter",
				time = math.min(num(n.TIME, 1), 10),
				stun = math.max(0, num(n.STUN, 1)),
				counterBranch = brn(n.BRANCH) or brn(n["BRANCH TARGET"]),
				removeOnHit = n["REMOVE ON HIT"] ~= false,
				mode = "Switch",
			})
			if tostring(n["ATTACK TYPE2"] or "Melee") ~= "Melee" then
				table.insert(notes, ("%s: counter only for %s attacks in JJS; SkillKit counters every hit"):format(at, tostring(n["ATTACK TYPE2"])))
			end
		elseif k == "SKILL" or k == "SPECIAL" then
			table.insert(notes, ("%s: plays JJS's built-in %q: not available outside JJS; skipped"):format(at, tostring(n.MOVE or n.SPEC)))
		else
			table.insert(notes, ("%s: no SkillKit equivalent; skipped"):format(at))
		end
	end
	return out
end

-- one JJS move -> a SkillKit skill table + notes
-- one JJS move -> a SkillKit skill table + notes. `prefix` renames its branches (used when moves are merged).
function Jjs.convert(move: any, prefix: string?): (any, { string })
	local notes: { string } = {}
	local data = move.DATA or {}
	local prop = data.Prop or {}
	if type(prop) ~= "table" or prop[1] ~= nil then
		prop = {}
	end
	local mult = { dmg = tonumber(prop.DMG) or 1, kb = tonumber(prop.KNOCK) or 1 }
	local pre = prefix or ""
	local conds = {}
	for bname, b in pairs(data.Branch or {}) do
		if type(b.Req) == "table" and #b.Req > 0 then
			conds[bname] = b.Req
		end
	end
	local ctx = { prefix = pre, conds = conds }
	local name = tostring(move.NAME or "JJS skill")
	local skill: any = { name = name, cooldown = tonumber(move.COOLDOWN) or 1, branches = {} }
	skill.branches.Default = convertLine(data.Line or {}, mult, notes, pre .. "Default", ctx)
	for bname, b in pairs(data.Branch or {}) do
		skill.branches[pre .. bname] = convertLine(b.Line or {}, mult, notes, pre .. bname, ctx)
	end
	for _, c in ipairs(ctx.chains or {}) do
		local list = skill.branches[c.from]
		if list and skill.branches[c.to] then
			local already = false
			for _, nd in ipairs(list) do
				if nd.type == "Branch" and nd.target == c.to then
					already = true
				end
			end
			if not already then
				table.insert(list, 1, { type = "Branch", target = c.to, mode = "Continue" })
			end
		end
	end
	if type(data.Req) == "table" and #data.Req > 0 then
		local conds = Jjs.conds(data.Req, notes, pre .. "Default")
		if #conds > 0 then
			-- the whole move only runs when its conditions pass
			table.insert(skill.branches.Default, 1, { type = "Check", conds = conds, stopOnFail = true, mode = "Switch" })
		end
	end
	if prop.NOCANCEL then
		skill.cancelOnStun = false
	end
	if prop.INV then
		table.insert(skill.branches.Default, 1, { type = "State", category = "Multiplier", sub = { "DamageTaken" }, value = 0, duration = 1 })
		table.insert(notes, "Invincible -> DamageTaken x0 for 1 s at the start")
	end
	return skill, notes
end

-- JJS's M1 is up to four MELEE moves played in turn. They become one skill: a "m1" tag counts the presses (it
-- resets 1.5 s after the last one) and picks the hit; each hit's own branches keep their names, prefixed "HitN ".
function Jjs.convertCombo(melees: { any }, name: string): (any, { string })
	local notes: { string } = {}
	local skill: any = { name = name, cooldown = 0.35, branches = {} }
	local count = #melees
	local default: { any } = {
		{ type = "Tags", tag = "m1", op = "Add", value = 1, time = 1.5 },
	}
	for i = count, 1, -1 do
		local bname = "Hit" .. i
		table.insert(default, { type = "Tags", tag = "m1", op = "Check", compare = i == 1 and ">=" or ">=", value = i, passBranch = bname, mode = "Switch" })
		local sub, subNotes = Jjs.convert(melees[i], bname .. " ")
		local line = sub.branches.Default
		if i == count then
			table.insert(line, 1, { type = "Tags", tag = "m1", op = "Set", value = 0 })
		end
		skill.branches[bname] = line
		for b, l in pairs(sub.branches) do
			if b ~= "Default" then
				skill.branches[b] = l
			end
		end
		for _, nt in ipairs(subNotes) do
			table.insert(notes, ("hit %d: %s"):format(i, nt))
		end
		local cd = tonumber(melees[i].COOLDOWN)
		if cd and cd > skill.cooldown then
			skill.cooldown = cd
		end
	end
	skill.branches.Default = default
	table.insert(notes, ("%d M1 moves merged into one combo skill (a 'm1' tag picks the hit)"):format(count))
	return skill, notes
end

return Jjs
