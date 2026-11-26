-- Data/Specs.lua: how each spec deals damage (or heals), as shares of its output. The model (Model.lua)
-- scales each share with the stats that drive it, starting from your character as it is now, so the shares
-- only say how the output splits up, not how big it is.
--
-- Components:
--   white   melee auto attacks (both hands)      yellow  melee special attacks (normalized weapon damage)
--   ranged  auto shot                            shots   ranged special attacks
--   spell   spell damage (schools below)          heal    healing spells
--   wand    wand shots between spells             pet     a pet or demon (Model.PetDPS: what it takes from you)
-- Hunters keep a little melee while leveling (before the first bow and when mobs reach them).
-- Shares per mode: "level" (fighting mobs of your level alone) and "endgame" (a raid boss 3 levels above).
-- critMult: spell crit damage (1.5 base; talents like Ruin, Ice Shards, Elemental Fury make it 2).
-- critY: special attack crit damage (2.0 base; Impale and Lethality add 0.2, Mortal Shots 0.3); critR: auto shot
-- crit damage (Mortal Shots). meleeSpells: the spell part rolls the melee table and crits double (paladin seals).
-- filler / heal: the spell whose rank at your level (Data/Leveling.lua, WoW Forever game data) sets the base
-- damage or healing and the spell power coefficient of the spell part. dots: damage over time put on each mob
-- before the filler, in this order, where it beats the filler (Model.Rotation); talent = only with the talent.
-- schools: the filler's (a dot has its own).
-- Levelling time model (Model.LevelCycle): manaUse = mana spent while fighting as a share of casting manaSpell
-- nonstop (melee and hunter specs; casters spend their spell share); petTank = share of a mob's damage that
-- reaches you because a pet holds it (voidwalker, hunter pet). Both are estimates.
local _, GL = ...

local S = {}
GL.Specs = S

-- How much each part of a character counts toward the one percentage shown for an item.
--   dmg  damage (or healing for healers)   surv  effective health   sus  mana you can spend per fight
S.ROLE_WEIGHTS = {
	level = {
		dps    = { dmg = 0.78, surv = 0.10, sus = 0.12 },
		tank   = { dmg = 0.50, surv = 0.42, sus = 0.08 },
		healer = { dmg = 0.50, surv = 0.20, sus = 0.30 },
	},
	endgame = {
		dps    = { dmg = 0.92, surv = 0.03, sus = 0.05 },
		tank   = { dmg = 0.30, surv = 0.70, sus = 0.00 },
		healer = { dmg = 0.62, surv = 0.03, sus = 0.35 },
	},
}

local function spec(t) return t end

-- Melee hybrids have no filler spell: their spell part follows a level curve (Model.SpellBase / SpellCoef).
-- hybridSP scales the curve's spell damage coefficient so a point of spell damage weighs against a point of
-- attack power as in wowsims/forever's level 60 stat weights (Retribution about 2, Enhancement about 1.3).
local HYBRID_SP = { PALADIN = 1.8, SHAMAN = 1.9 }

S.list = {
	WARRIOR = {
		spec { key = "ARMS", name = "Arms", role = "dps", critY = 2.2,
			comps = { level = { white = 0.55, yellow = 0.45 }, endgame = { white = 0.5, yellow = 0.5 } } },
		spec { key = "FURY", name = "Fury", role = "dps", critY = 2.0,
			comps = { level = { white = 0.6, yellow = 0.4 }, endgame = { white = 0.6, yellow = 0.4 } } },
		spec { key = "PROT", name = "Protection", role = "tank", critY = 2.0, shield = true,
			comps = { level = { white = 0.55, yellow = 0.45 }, endgame = { white = 0.45, yellow = 0.55 } } },
	},
	PALADIN = {
		spec { key = "HOLY", name = "Holy", role = "healer", critMult = 1.5, heal = "Holy Light",
			comps = { level = { heal = 1 }, endgame = { heal = 1 } } },
		spec { key = "PROT", name = "Protection", role = "tank", critY = 2.0, critMult = 1.5, shield = true, manaUse = 0.35, manaSpell = "Holy Light",
			meleeSpells = true, hybridSP = HYBRID_SP.PALADIN,
			schools = { HOLY = 1 },
			comps = { level = { white = 0.45, yellow = 0.15, spell = 0.4 }, endgame = { white = 0.35, yellow = 0.15, spell = 0.5 } } },
		spec { key = "RET", name = "Retribution", role = "dps", critY = 2.0, critMult = 1.5, schools = { HOLY = 1 }, manaUse = 0.3, manaSpell = "Holy Light",
			meleeSpells = true, hybridSP = HYBRID_SP.PALADIN,
			comps = { level = { white = 0.5, yellow = 0.2, spell = 0.3 }, endgame = { white = 0.45, yellow = 0.2, spell = 0.35 } } },
	},
	HUNTER = {
		spec { key = "BM", name = "Beast Mastery", role = "dps", petTank = 0.35, manaUse = 0.45, manaSpell = "Lightning Bolt", critY = 2.0, ranged = true,
			comps = { level = { ranged = 0.3, shots = 0.17, white = 0.08, pet = 0.45 }, endgame = { ranged = 0.45, shots = 0.25, pet = 0.3 } } },
		spec { key = "MM", name = "Marksmanship", role = "dps", petTank = 0.35, manaUse = 0.45, manaSpell = "Lightning Bolt", critY = 2.3, critR = 2.3, ranged = true,
			comps = { level = { ranged = 0.36, shots = 0.26, white = 0.08, pet = 0.3 }, endgame = { ranged = 0.45, shots = 0.4, pet = 0.15 } } },
		spec { key = "SV", name = "Survival", role = "dps", petTank = 0.35, manaUse = 0.45, manaSpell = "Lightning Bolt", critY = 2.0, ranged = true,
			comps = { level = { ranged = 0.35, shots = 0.25, white = 0.1, pet = 0.3 }, endgame = { ranged = 0.45, shots = 0.3, white = 0.1, pet = 0.15 } } },
	},
	ROGUE = {
		spec { key = "ASSA", name = "Assassination", role = "dps", critY = 2.2,
			comps = { level = { white = 0.45, yellow = 0.55 }, endgame = { white = 0.45, yellow = 0.55 } } },
		spec { key = "COMBAT", name = "Combat", role = "dps", critY = 2.0,
			comps = { level = { white = 0.55, yellow = 0.45 }, endgame = { white = 0.6, yellow = 0.4 } } },
		spec { key = "SUB", name = "Subtlety", role = "dps", critY = 2.2,
			comps = { level = { white = 0.45, yellow = 0.55 }, endgame = { white = 0.5, yellow = 0.5 } } },
	},
	PRIEST = {
		spec { key = "DISC", name = "Discipline", role = "healer", critMult = 1.5, filler = "Smite", heal = { "Greater Heal", "Heal", "Lesser Heal" },
			comps = { level = { heal = 0.6, spell = 0.25, wand = 0.15 }, endgame = { heal = 1 } }, schools = { HOLY = 0.6, SHADOW = 0.4 } },
		spec { key = "HOLY", name = "Holy", role = "healer", critMult = 1.5, filler = "Smite", heal = { "Greater Heal", "Heal", "Lesser Heal" },
			comps = { level = { heal = 0.6, spell = 0.25, wand = 0.15 }, endgame = { heal = 1 } }, schools = { HOLY = 1 } },
		-- Smite until Mind Flay (level 20)
		spec { key = "SHADOW", name = "Shadow", role = "dps", critMult = 1.5, filler = "Mind Flay", schools = { SHADOW = 1 },
			dots = { "Shadow Word: Pain" },
			comps = { level = { spell = 0.8, wand = 0.2 }, endgame = { spell = 1 } } },
	},
	SHAMAN = {
		spec { key = "ELE", name = "Elemental", role = "dps", critMult = 2.0, filler = "Lightning Bolt", schools = { NATURE = 1 }, dots = { "Flame Shock" },
			comps = { level = { spell = 0.85, white = 0.15 }, endgame = { spell = 1 } } },
		spec { key = "ENH", name = "Enhancement", role = "dps", critY = 2.0, critMult = 1.5, manaUse = 0.3, manaSpell = "Lightning Bolt", schools = { NATURE = 0.6, FIRE = 0.4 },
			hybridSP = HYBRID_SP.SHAMAN,
			comps = { level = { white = 0.55, yellow = 0.2, spell = 0.25 }, endgame = { white = 0.55, yellow = 0.2, spell = 0.25 } } },
		spec { key = "RESTO", name = "Restoration", role = "healer", critMult = 1.5, schools = { NATURE = 1 }, filler = "Lightning Bolt", heal = "Healing Wave",
			comps = { level = { heal = 0.6, spell = 0.25, white = 0.15 }, endgame = { heal = 1 } } },
	},
	MAGE = {
		spec { key = "ARCANE", name = "Arcane", role = "dps", critMult = 1.5, filler = "Arcane Wrath", schools = { ARCANE = 0.9, FIRE = 0.1 },
			comps = { level = { spell = 0.9, wand = 0.1 }, endgame = { spell = 1 } } },
		spec { key = "FIRE", name = "Fire", role = "dps", critMult = 2.1, filler = "Fireball", schools = { FIRE = 1 },
			comps = { level = { spell = 0.9, wand = 0.1 }, endgame = { spell = 1 } } },
		spec { key = "FROST", name = "Frost", role = "dps", critMult = 2.0, filler = "Frostbolt", schools = { FROST = 1 },
			comps = { level = { spell = 0.9, wand = 0.1 }, endgame = { spell = 1 } } },
	},
	WARLOCK = {
		spec { key = "AFFLI", name = "Affliction", role = "dps", filler = "Shadow Bolt", petTank = 0.35, critMult = 1.2, schools = { SHADOW = 1 }, lifeTap = true,
			dots = { "Corruption", "Bane of Agony", { "Siphon Life", talent = true }, "Immolate" },
			comps = { level = { spell = 0.65, pet = 0.2, wand = 0.15 }, endgame = { spell = 0.85, pet = 0.15 } } },
		-- Searing Pain about every 12 s for Demonic Brand, Shadow Bolt between
		spec { key = "DEMO", name = "Demonology", role = "dps", filler = "Shadow Bolt", petTank = 0.35, critMult = 1.5, schools = { SHADOW = 0.85, FIRE = 0.15 }, lifeTap = true,
			dots = { "Corruption", "Bane of Agony", "Immolate" },
			comps = { level = { spell = 0.5, pet = 0.38, wand = 0.12 }, endgame = { spell = 0.75, pet = 0.25 } } },
		spec { key = "DESTRO", name = "Destruction", role = "dps", filler = "Shadow Bolt", petTank = 0.35, critMult = 2.0, schools = { SHADOW = 0.85, FIRE = 0.15 }, lifeTap = true,
			dots = { "Immolate", "Corruption", "Bane of Agony" },
			comps = { level = { spell = 0.72, pet = 0.18, wand = 0.1 }, endgame = { spell = 0.9, pet = 0.1 } } },
	},
	DRUID = {
		spec { key = "BALANCE", name = "Balance", role = "dps", critMult = 2.0, filler = "Wrath", schools = { ARCANE = 0.6, NATURE = 0.4 }, dots = { "Moonfire" },
			comps = { level = { spell = 1 }, endgame = { spell = 1 } } },
		spec { key = "CAT", name = "Feral (Cat)", role = "dps", critY = 2.0, form = true, formLevel = 20,
			comps = { level = { white = 0.5, yellow = 0.5 }, endgame = { white = 0.45, yellow = 0.55 } } },
		spec { key = "BEAR", name = "Feral (Bear)", role = "tank", critY = 2.0, form = true, formLevel = 10,
			comps = { level = { white = 0.5, yellow = 0.5 }, endgame = { white = 0.4, yellow = 0.6 } } },
		spec { key = "RESTO", name = "Restoration", role = "healer", critMult = 1.5, schools = { NATURE = 1 }, filler = "Wrath", heal = "Healing Touch",
			comps = { level = { heal = 0.6, spell = 0.4 }, endgame = { heal = 1 } } },
	},
}

-- Warlocks turn health into mana (Life Tap): part of their health counts as mana.
S.LIFE_TAP_SHARE = 0.5

function S.ForClass(class) return S.list[class] or {} end

function S.Get(class, key)
	for _, s in ipairs(S.ForClass(class)) do
		if s.key == key then return s end
	end
	return S.ForClass(class)[1]
end

-- The weights that combine damage, survival and mana into one percentage.
function S.Weights(spec, mode, class)
	local w = S.ROLE_WEIGHTS[mode][spec.role]
	local out = { dmg = w.dmg, surv = w.surv, sus = w.sus }
	if not GL.Classes.stats[class].mana then
		-- no mana: its share goes to damage and survival
		out.dmg, out.surv, out.sus = out.dmg + out.sus * 0.6, out.surv + out.sus * 0.4, 0
	end
	if spec.lifeTap and mode == "level" then out.surv, out.dmg = out.surv + 0.04, out.dmg - 0.04 end
	return out
end
