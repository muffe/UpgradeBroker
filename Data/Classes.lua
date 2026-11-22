-- Data/Classes.lua: how the primary stats turn into combat stats per class, and what each class can wear.
-- Numbers are WoW Forever's as modelled by wowsims/forever (MIT License, Copyright (c) 2022 wowsims team):
-- sim/core/base_stats_auto_gen.go (crit per Agility / Intellect at level 60), the AddStatDependency calls in
-- sim/<class>/<class>.go, sim/core/mana.go (15 mana per Intellect, 6.25 + Spirit/8 mana per second).
local _, GL = ...

local C = {}
GL.Classes = C

-- critAgi / critInt: percent crit per point at level 60. apStr / apAgi: melee attack power per point;
-- rapAgi: ranged attack power per point. parry: the class can parry. dodgeAgi: dodge per Agility as a
-- multiple of critAgi (rogues and hunters dodge twice as much as they crit). mana: uses mana.
C.stats = {
	WARRIOR = { critAgi = 0.0500, critInt = 0,      apStr = 2, apAgi = 0, rapAgi = 1, parry = true },
	PALADIN = { critAgi = 0.0506, critInt = 0.0167, apStr = 2, apAgi = 0, rapAgi = 0, parry = true, mana = true },
	HUNTER  = { critAgi = 0.0189, critInt = 0.0165, apStr = 1, apAgi = 1, rapAgi = 2, parry = true, mana = true, dodgeAgi = 2 },
	ROGUE   = { critAgi = 0.0345, critInt = 0,      apStr = 1, apAgi = 1, rapAgi = 1, parry = true, dodgeAgi = 2 },
	PRIEST  = { critAgi = 0.0500, critInt = 0.0168, apStr = 1, apAgi = 0, rapAgi = 0, mana = true },
	SHAMAN  = { critAgi = 0.0508, critInt = 0.0169, apStr = 2, apAgi = 0, rapAgi = 0, mana = true },
	MAGE    = { critAgi = 0.0514, critInt = 0.0168, apStr = 1, apAgi = 0, rapAgi = 0, mana = true },
	WARLOCK = { critAgi = 0.0500, critInt = 0.0165, apStr = 1, apAgi = 0, rapAgi = 0, mana = true },
	DRUID   = { critAgi = 0.0500, critInt = 0.0167, apStr = 2, apAgi = 0, rapAgi = 0, mana = true },
}

-- Below level 60 a point of Agility or Intellect gives more crit (the game's per-level tables). A level 20
-- character gets about 3.5 times level 60's crit per point; in between it is close to linear in the level.
-- Used only when the client has no GetCritChanceFromAgility / GetSpellCritChanceFromIntellect.
function C.CritScale(level)
	level = math.max(1, math.min(60, level or 60))
	return 1 / math.max(0.12, (level - 4) / 56)
end

C.MANA_PER_INT = 15
C.HEALTH_PER_STA = 10
C.MANA_PER_SPI = 1 / 8 -- mana per second per Spirit while not casting

-- Item class 4 (armor) subclasses: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem.
-- Item class 2 (weapons): 0 axe, 1 2h axe, 2 bow, 3 gun, 4 mace, 5 2h mace, 6 polearm, 7 sword, 8 2h sword,
-- 10 staff, 13 fist, 14 misc, 15 dagger, 16 thrown, 18 crossbow, 19 wand, 20 fishing pole.
local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end
C.weapons = {
	WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
	PALADIN = set(0, 1, 4, 5, 6, 7, 8),
	HUNTER  = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18),
	ROGUE   = set(0, 2, 3, 4, 7, 13, 15, 16, 18),
	PRIEST  = set(4, 10, 15, 19),
	SHAMAN  = set(0, 1, 4, 5, 10, 13, 15),
	MAGE    = set(7, 10, 15, 19),
	WARLOCK = set(7, 10, 15, 19),
	DRUID   = set(4, 5, 6, 10, 13, 15),
}
C.armor = {
	WARRIOR = set(1, 2, 3, 4, 6), PALADIN = set(1, 2, 3, 4, 6, 7), HUNTER = set(1, 2, 3), ROGUE = set(1, 2),
	PRIEST = set(1), SHAMAN = set(1, 2, 3, 6, 9), MAGE = set(1), WARLOCK = set(1), DRUID = set(1, 2, 8),
}
-- The armor type a class should wear: mail and plate are learned at level 40.
function C.MainArmor(class, level)
	if class == "WARRIOR" or class == "PALADIN" then return (level or 1) >= 40 and 4 or 3 end
	if class == "HUNTER" or class == "SHAMAN" then return (level or 1) >= 40 and 3 or 2 end
	if class == "ROGUE" or class == "DRUID" then return 2 end
	return 1
end
function C.ArmorLearnLevel(class, subclass)
	if subclass == 4 then return 40 end
	if subclass == 3 and (class == "HUNTER" or class == "SHAMAN") then return 40 end
	return 1
end

C.dualWield = set("WARRIOR", "ROGUE", "HUNTER")
