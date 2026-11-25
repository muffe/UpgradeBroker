-- Model.lua: what an item does to your character, as a percentage.
--
-- Instead of fixed stat weights, the model takes your current totals (Character.lua), adds the item and takes
-- away what it replaces, and works out three things before and after:
--   dmg   damage per second (healing per second for healers) from WoW Forever's combat rules
--   surv  effective health: health / (share of a hit that gets through armor, avoidance and blocks)
--   sus   mana you can spend in a fight (pool + regeneration; health for warlocks, who Life Tap)
-- The item's value is the change of dmg^a * surv^b * sus^c, with a, b, c per role and mode (Specs.lua).
-- So caps, diminishing returns and what you already have all count by themselves: hit past the cap gives
-- nothing, crit is worth more with more attack power, and so on.
--
-- Combat rules from wowsims/forever (MIT License, Copyright (c) 2022 wowsims team), sim/core/target.go:
-- miss 5% + 0.1% per point of weapon skill short (0.2% past 10), +19% for white swings while dual wielding;
-- dodge 5% + 0.1% per point; parry from the front; glancing 10% + 2% per point; spell miss 4% + 1% per level,
-- 17% at +3; crit suppression 0.2% per point plus 1.8% at +3; weapon skill from items lowers miss and dodge and
-- raises glancing damage. Special attacks hit for one swing plus attack power at the normalized weapon speed.
-- Ranged attacks and wands roll the ranged table; spell penetration adds damage; pets take stats from you.
local _, GL = ...

local Model = {}
GL.Model = Model

local max, min = math.max, math.min
local SCHOOLS = { "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }

---------------------------------------------------------------------------
-- Context: who you fight
---------------------------------------------------------------------------
-- level: mobs of your own level, face to face (they can parry). endgame: a boss three levels above, from
-- behind (tanks from the front).
function Model.Context(s)
	if s.mode == "endgame" then
		return { d = 3, front = s.spec.role == "tank", attacker = s.level + 3 }
	end
	return { d = 0, front = true, attacker = s.level }
end

---------------------------------------------------------------------------
-- Level curves (only their ratio to what items add matters)
---------------------------------------------------------------------------
-- Spell damage per second of a level-appropriate rotation before spell damage, and what one point of spell
-- damage adds per second. Spells learned below level 20 get less from spell damage.
-- (for specs without a filler in the data; a level 1 spell still does a few points per second)
function Model.SpellBase(level) return 3 + 1.2 * level + 0.04 * level * level end

-- A spell's highest rank at a level (Data/Leveling.lua): avg, mana, cast, coef. nil if the class has none yet.
function Model.SpellRank(name, level)
	local ranks = name and GL.LevelingData and GL.LevelingData.spells[name]
	if not ranks then return nil end
	for l = math.min(60, math.floor(level)), 1, -1 do
		local r = ranks[l]
		if r then return r[1], r[2], r[3], r[4] end
	end
end

-- ExpectedStat for a normal mob of a level: health, DPS before armor, armor, armor constant.
function Model.Creature(level)
	local t = GL.LevelingData and GL.LevelingData.creature[math.max(1, math.min(60, math.floor(level)))]
	if t then return t[1], t[2], t[3], t[4] end
	return 4365 * level / 60, 60 * level / 60, 3566 * level / 60, 400 + 85 * level
end

-- What food or water of your level restores per second.
local function Band(list, level)
	local v = list[1][2]
	for _, e in ipairs(list) do if level >= e[1] then v = e[2] end end
	return v
end
function Model.SpellCoef(level)
	if level < 20 then return 0.30 * max(0.4, 1 - (20 - level) * 0.0375) end
	return 0.30
end
-- A typical wand or ranged weapon of your level (for the first one you equip).
function Model.RefRangedDPS(level) return max(3, 0.7 * level) end
-- The size of a hit you take: a mob of your level (ExpectedStat: 60.45 DPS at 60, 2 s swings) or a boss.
function Model.HitSize(ctx)
	if ctx.attacker > 60 then return 1800 end
	return max(10, 2 * 60.45 * (ctx.attacker / 60) ^ 1.4)
end

---------------------------------------------------------------------------
-- State: your totals plus the weapons. Apply adds and takes away items.
---------------------------------------------------------------------------
-- The damage shares of a spec for this character: hunters get their pet at level 10.
function Model.Comps(s)
	if s.comps then return s.comps end
	local comps = s.spec.comps[s.mode] or s.spec.comps.level
	if s.class == "HUNTER" and s.level < 10 and comps.pet then
		local c, total = {}, 0
		for k, v in pairs(comps) do if k ~= "pet" then c[k] = v; total = total + v end end
		for k, v in pairs(c) do c[k] = v / total end
		comps = c
	end
	s.comps = comps
	return comps
end

-- The filler a character can cast: the spec's, else the class's first damage spell (a level 1 frost mage
-- has Fireball, not Frostbolt yet).
-- A spec's schools while it still lacks its main spells (Data/Specs.lua schoolsBelow: bands by level).
function Model.SchoolsBelow(spec, level)
	for _, band in ipairs(spec.schoolsBelow or {}) do
		if level < band.level then return band.schools end
	end
end

Model.SPELL_SCHOOL = { Fireball = "FIRE", Frostbolt = "FROST", ["Shadow Bolt"] = "SHADOW", Smite = "HOLY",
	["Lightning Bolt"] = "NATURE", Wrath = "NATURE" }
local FALLBACK = { MAGE = "Fireball", WARLOCK = "Shadow Bolt", PRIEST = "Smite", SHAMAN = "Lightning Bolt", DRUID = "Wrath" }
function Model.Filler(s)
	if not s.spec.filler then return nil end -- melee hybrids: their spells are not a filler (seals, shocks)
	if Model.SpellRank(s.spec.filler, s.level) then return s.spec.filler end
	local alt = FALLBACK[s.class]
	if alt and Model.SpellRank(alt, s.level) then return alt end
end

function Model.FromSnapshot(s)
	local x = {}
	for k, v in pairs(s.stats) do x[k] = v end
	x.MHASTE = 0
	x.mh, x.oh, x.ranged = s.mh, s.oh, s.ranged
	x.shield = s.equipped[17] ~= nil and s.equipped[17].kind == "shield"
	return x
end

local function AddStats(d, stats, sign)
	for k, v in pairs(stats) do
		if k ~= "SPEED" and k ~= "DPS" then d[k] = (d[k] or 0) + sign * v end
	end
end

-- add / remove: lists of items. weapons: { mh =, oh =, ranged = } (false = empty hand), or nil to keep yours.
function Model.Apply(s, x0, add, remove, weapons)
	local addList, removeList = add or {}, remove or {}
	local d = {}
	for _, item in ipairs(add or {}) do AddStats(d, item.stats, 1) end
	for _, item in ipairs(remove or {}) do AddStats(d, item.stats, -1) end
	local c = s.conv
	local x = {}
	for k, v in pairs(x0) do x[k] = v end
	local function add(k, v) if v and v ~= 0 then x[k] = (x[k] or 0) + v end end

	local str, agi, sta, int, spi = d.STR or 0, d.AGI or 0, d.STA or 0, d.INT or 0, d.SPI or 0
	add("STR", str); add("AGI", agi); add("STA", sta); add("INT", int); add("SPI", spi)
	-- talents and forms that turn one stat into another (Character.TalentConv); Cat Form gives 100% of
	-- Agility as attack power (3025 effect 5)
	local catAgi = (s.inForm and s.spec.key == "CAT") and 1 or 0
	local spFromStats = (c.intSP or 0) * int + (c.spiSP or 0) * spi
		+ (c.arcaneBlast and (Model.ARCANE_CHARGES[s.mode] or 2) * 0.12 * int or 0)
	add("AP", c.apStr * str + c.apAgi * agi + catAgi * agi + (c.intAP or 0) * int + (d.AP or 0) + (s.inForm and (d.FAP or 0) or 0))
	add("RAP", c.rapAgi * agi + (c.intRAP or 0) * int + (d.AP or 0) + (d.RAP or 0))
	add("CRIT", c.critAgi * agi + (d.CRIT or 0))
	add("RCRIT", c.critAgi * agi + (d.CRIT or 0))
	add("SCRIT", c.critInt * int + (d.CRIT or 0) + (d.SCRIT or 0))
	add("DODGE", c.dodgeAgi * agi + (d.DODGE or 0))
	add("ARMOR", 2 * agi + (d.ARMOR or 0))
	add("HP", GL.Classes.HEALTH_PER_STA * sta + (d.HP or 0))
	if GL.Classes.stats[s.class].mana then
		add("MANA", GL.Classes.MANA_PER_INT * int + (d.MANA or 0))
		add("REGEN_OOC", c.regenSpi * spi + (d.MP5 or 0) / 5)
		add("REGEN_IC", c.regenSpi * c.icShare * spi + (d.MP5 or 0) / 5)
	end
	for _, school in ipairs(SCHOOLS) do add("SP_" .. school, (d.SP or 0) + (d["SP_" .. school] or 0) + spFromStats) end
	add("HEAL", (d.HEAL or 0) + (c.intHeal or 0) * int + (c.spiHeal or 0) * spi)
	add("HIT", d.HIT); add("SHIT", (d.HIT or 0) + (d.SHIT or 0))
	add("HASTE", d.HASTE); add("MHASTE", d.MHASTE)
	-- 0.05 block value a point of Strength (wowsims/forever core/character.go)
	add("EXP", d.EXP); add("DEF", d.DEF); add("PARRY", d.PARRY); add("BLOCK", d.BLOCK); add("BLOCKVAL", (d.BLOCKVAL or 0) + 0.05 * str)
	for k, v in pairs(d) do
		if k == "SPEN" or k == "WDMG" or k:find("^WSKILL_") then add(k, v) end
	end

	-- a shield in the off hand after the swap (a first shield counts its block, a two-hander drops it)
	for _, item in ipairs(removeList) do if item.kind == "shield" then x.shield = false end end
	for _, item in ipairs(addList) do
		if item.kind == "shield" then
			-- a first shield also brings the 5 % base block chance the game only shows with a shield on
			if not x0.shield and (x0.BLOCK or 0) <= 0 then x.BLOCK = (x.BLOCK or 0) + 5 end
			x.shield = true
		end
	end
	if weapons then
		if weapons.mh ~= nil then x.mh = weapons.mh or nil end
		if weapons.oh ~= nil then x.oh = weapons.oh or nil end
		if weapons.ranged ~= nil then x.ranged = weapons.ranged or nil end
		-- in cat or bear form the paw hits with the new weapon's damage per second at the form's speed
		if s.inForm then
			if weapons.mh ~= nil then
				x.mh = GL.Character.Weapon(weapons.mh and { stats = { DPS = weapons.mh.dps } } or nil,
					GL.Character.FORM_SPEED[s.spec.key], s.level)
			end
			x.oh = nil
		end
	end
	return x
end

-- Arcane Charges (Arcane Blast talent): 12% of Intellect as spell damage per charge, up to 4. The charges
-- fall off 18 s after the first, so they average fewer than 4 (estimate: 2 in short leveling fights, 3.5 on a boss).
Model.ARCANE_CHARGES = { level = 2, endgame = 3.5 }

---------------------------------------------------------------------------
-- Damage parts
---------------------------------------------------------------------------
-- The melee table of one hand. skill: weapon skill above the level-based maximum (items). It lowers miss and
-- dodge and raises the glancing damage, but not parry, the glancing chance or crit suppression
-- (wowsims/forever core/target.go newAttackTableHand).
local function MeleeTables(x, ctx, critY, dualWield, skill)
	local base = 5 * ctx.d
	local sd = base - (skill or 0)
	local miss = sd > 10 and (5 + 0.2 * sd) or (5 + 0.1 * sd)
	local dodge = max(0, 5 + 0.1 * sd - (x.EXP or 0))
	local parry = 0
	if ctx.front then parry = max(0, (base > 10 and (5 + 0.6 * base) or (5 + 0.1 * base)) - (x.EXP or 0)) end
	local glance = min(100, 10 + 2 * base)
	local gMin = min(0.91, max(0.01, 1.3 - 0.05 * sd))
	local gMax = min(0.99, max(0.2, 1.2 - 0.03 * sd))
	local glanceMult = (gMin + gMax) / 2
	local supp = (base > 0 and 0.2 * base or 0) + (ctx.d >= 3 and 1.8 or 0)
	local crit = max(0, (x.CRIT or 0) - supp)
	local hit = x.HIT or 0
	-- white swings: one roll over miss, dodge, parry, glancing, crit, hit
	local missW = max(0, miss + (dualWield and 19 or 0) - hit)
	local left = max(0, 100 - missW - dodge - parry - glance)
	local critW = min(crit, left)
	local W = ((left - critW) + glance * glanceMult + critW * 2) / 100
	-- special attacks: hit or not, then crit
	local missY = max(0, miss - hit)
	local land = max(0, 100 - missY - dodge - parry) / 100
	local Y = land * (1 + crit / 100 * ((critY or 2) - 1))
	return { W = W, Y = Y, miss = miss, land = land, crit = crit, supp = supp }
end

local function SpellHit(x, ctx)
	local miss = ctx.d >= 3 and 17 or max(0, 4 + ctx.d)
	return 1 - max(0, miss - (x.SHIT or 0)) / 100
end

-- Special attacks hit for one swing of the weapon plus attack power at the weapon's normalized speed
-- (wowsims/forever core/attack.go): daggers 1.7, other one-handers 2.4, two-handers 3.3, ranged 2.8; a paw
-- its form's speed.
function Model.NormSpeed(w)
	if w.form then return w.speed end
	local sub = w.sub
	if sub == 2 or sub == 3 or sub == 16 or sub == 18 or sub == 19 or w.kind == "ranged" then return 2.8 end
	if sub == 15 then return 1.7 end
	if w.kind == "2h" or sub == 1 or sub == 5 or sub == 6 or sub == 8 or sub == 10 or sub == 20 then return 3.3 end
	return 2.4
end

local function Skill(x, w) return (w and not w.form and w.sub and x["WSKILL_" .. w.sub]) or 0 end

-- Spell penetration past the target's resistance (none on normal mobs) pays out as bonus damage on hits:
-- P / (P + 8L + 19), nothing under 1% (wowsims/forever core/spell_resistances.go, EV-0142).
function Model.PenBonus(pen, level)
	if not pen or pen <= 0 then return 0 end
	local b = pen / (pen + 8 * level + 19)
	return b >= 0.01 and b or 0
end

-- A pet's or demon's damage per second, with what it takes from you (wowsims/forever):
--   demons: 17% of your spell damage (the better of Shadow and Fire) as attack power (warlock/pets.go), and with
--     Demonic Brand each branded hit adds (level - 26) x 1.5 + 15.5 + 0.078 x your spell damage of the brand's
--     school (Fire for the Imp, Shadow for the others)
--   hunter pets: 10% of your higher attack power, your higher crit, your hit and expertise (hunter/pets.go); with
--     Summon Hawk about 3 hawks, each 80% of (ranged attack power + 14 x main-hand dps) at 60 per dps
-- The pet's own damage is a share of a mob of your level's (ExpectedStat; estimates: 0.6 for a demon, 1.25 for
-- a happy hunter pet). Only the ratio to what it inherits matters: Calibrate scales the part to its share.
function Model.PetDPS(s, x, ctx)
	local L = min(60, s.level)
	local _, mobDPS = Model.Creature(L)
	local c = s.conv or {}
	if s.class == "WARLOCK" then
		local spEff = max(x.SP_SHADOW or 0, x.SP_FIRE or 0)
		local dps = 0.6 * mobDPS + 0.8 * 0.17 * spEff / 14
		local brand = c.brand or 0
		if brand > 0 and L >= 26 then
			local school = c.petFamily == "Imp" and "SP_FIRE" or "SP_SHADOW"
			-- a Searing Pain about every 12 s brands 2 hits a rank; a demon hits every 2 s (estimate)
			local rate = min(0.5, brand * 2 / 12)
			dps = dps + rate * ((L - 26) * 1.5 + 15.5 + 0.078 * (x[school] or 0))
		end
		return dps
	end
	if s.class == "HUNTER" then
		local land = 1 - (max(0, (ctx.d >= 3 and 8 or 5) - (x.HIT or 0)) + max(0, 5 - (x.EXP or 0))) / 100
		local crit = max(x.CRIT or 0, x.RCRIT or 0)
		local dps = (1.25 * mobDPS + 0.1 * max(x.AP or 0, x.RAP or 0) / 14) * land * (1 + crit / 100)
		if c.hawk and L >= 25 then
			local mh = x.mh and x.mh.dps or 0.5
			dps = dps + 3 * (0.153 * mobDPS + 0.8 * ((x.RAP or 0) + 14 * mh) / 60) * land * (1 + crit / 200)
		end
		return dps
	end
	return 1
end

-- Raw size of each damage part (any unit; Calibrate turns them into shares).
function Model.Parts(s, x, ctx)
	local spec, level = s.spec, s.level
	local comps = Model.Comps(s)
	local out = {}
	local meleeHaste = 1 + ((x.HASTE or 0) + (x.MHASTE or 0)) / 100
	local spellHaste = 1 + (x.HASTE or 0) / 100
	local mh, wdmg = x.mh, x.WDMG or 0
	local dw = x.oh ~= nil
	local T = MeleeTables(x, ctx, spec.critY, dw, Skill(x, mh))

	if comps.white or comps.yellow then
		local mhDPS = mh and (mh.dps + wdmg / mh.speed) or 0
		local white = (mhDPS + (x.AP or 0) / 14) * T.W * meleeHaste
		if dw then
			local To = MeleeTables(x, ctx, spec.critY, true, Skill(x, x.oh))
			white = white + (x.oh.dps + wdmg / x.oh.speed + (x.AP or 0) / 14) * 0.5 * To.W * meleeHaste
		end
		out.white = white
		-- one special attack: a swing of the weapon plus attack power at its normalized speed (cooldowns
		-- set how often, so a slower weapon with the same dps hits harder)
		out.yellow = (mh and (mhDPS * mh.speed + (x.AP or 0) * Model.NormSpeed(mh) / 14) or (x.AP or 0) * 2.4 / 14) * T.Y
	end
	if comps.ranged or comps.shots or comps.wand then
		local r = x.ranged
		local isWand = r and r.sub == 19
		local TR = MeleeTables(x, ctx, spec.critY, false, Skill(x, r))
		-- ranged attacks and wands roll the ranged table: physical hit lowers their miss, spell hit does nothing
		local hitR = 1 - max(0, TR.miss - (x.HIT or 0)) / 100
		if comps.ranged or comps.shots then
			-- no bow, gun or crossbow: no shots at all (the first one is rated against a typical one of your level)
			local hasBow = r and not isWand
			local rcrit = max(0, (x.RCRIT or 0) - TR.supp)
			local dps = hasBow and r.dps or 0
			out.ranged = (hasBow and (dps + (x.RAP or 0) / 14) or 0) * hitR * (1 + rcrit / 100 * ((spec.critR or 2) - 1)) * meleeHaste
			out.shots = (hasBow and (dps * r.speed + (x.RAP or 0) * 2.8 / 14) or 0) * hitR * (1 + rcrit / 100 * ((spec.critY or 2) - 1))
			out.rangedRef = (Model.RefRangedDPS(level) + (x.RAP or 0) / 14) * hitR
			out.shotsRef = out.rangedRef * 2.8
		end
		if comps.wand then
			out.wand = ((r and isWand) and r.dps or 0) * hitR * (1 + (x.SCRIT or 0) / 100 * 0.5) * spellHaste
			out.wandRef = Model.RefRangedDPS(level) * hitR
		end
	end
	if comps.spell then
		-- per second of casting the spec's filler at its rank for your level (WoW Forever game data);
		-- specs without one (paladin seals, shaman weapons and shocks) use a level curve, scaled per spec
		-- (hybridSP) so spell damage weighs against attack power as in wowsims/forever's stat weights
		local base, coef
		local avg, _, cast, c = Model.SpellRank(Model.Filler(s), level)
		if avg then base, coef = avg / cast, c / cast
		else base, coef = Model.SpellBase(level), Model.SpellCoef(level) * (spec.hybridSP or 1) end
		-- the schools: the spec's, or the fallback spell's own (a level 1 frost mage's Fireball is Fire)
		local filler = Model.Filler(s)
		local schools = (filler and filler ~= spec.filler and { [Model.SPELL_SCHOOL[filler] or "SHADOW"] = 1 })
			or Model.SchoolsBelow(spec, level) or spec.schools or { SHADOW = 1 }
		local sum = 0
		for school, share in pairs(schools) do
			sum = sum + share * (base + (x["SP_" .. school] or 0) * coef)
		end
		sum = sum * (1 + Model.PenBonus(x.SPEN, level))
		if spec.meleeSpells then
			-- seals and Holy Strike roll the main hand's melee table, and their crits double (wowsims/forever
			-- paladin/seal_of_righteousness.go, holy_strike.go; EV-0059, EV-0060)
			out.spell = sum * T.land * (1 + T.crit / 100) * meleeHaste
		else
			out.spell = sum * SpellHit(x, ctx) * (1 + (x.SCRIT or 0) / 100 * ((spec.critMult or 1.5) - 1)) * spellHaste
		end
	end
	if comps.heal then
		local base, coef
		-- the heal: the best rank of the spec's heal, or of the first in its list that you have (Lesser Heal, Heal, Greater Heal)
		local heals = type(spec.heal) == "table" and spec.heal or { spec.heal }
		local avg, _, cast, c
		for _, name in ipairs(heals) do
			avg, _, cast, c = Model.SpellRank(name, level)
			if avg then break end
		end
		if avg then base, coef = avg / cast, c / cast else base, coef = 1.4 * Model.SpellBase(level), Model.SpellCoef(level) * 1.1 end
		out.heal = (base + (x.HEAL or 0) * coef) * (1 + (x.SCRIT or 0) / 100 * ((spec.critMult or 1.5) - 1)) * spellHaste
	end
	if comps.pet then out.pet = Model.PetDPS(s, x, ctx) end
	return out
end

-- Armor: armor / (armor + 400 + 85 x attacker level), at every level (wowsims/forever core/spell_resistances.go).
-- A boss three levels above crits 5.6% of its swings, 0.04% less a point of defense, and crushes 15% for 150%
-- (wowsims/forever core/target.go).
function Model.Survival(s, x, ctx)
	local la = ctx.attacker
	local k = 400 + 85 * la
	local armor = max(0, x.ARMOR or 0)
	local dr = min(0.75, armor / (armor + k))
	-- the game's dodge and parry already hold the defense you wear; count only the change
	local def = ((x.DEF or 0) - (s.stats.DEF or 0)) * 0.04
	local avoid = (5 + def) + (x.DODGE or 0) + def + ((x.PARRY or 0) > 0 and (x.PARRY + def) or 0)
	avoid = min(0.95, avoid / 100)
	local blockRed = 0
	if x.shield and (x.BLOCK or 0) > 0 then
		blockRed = min(0.9, (x.BLOCK + def) / 100 * min(1, (x.BLOCKVAL or 0) / Model.HitSize(ctx)))
	end
	local extra = 0
	if la >= s.level + 3 then extra = max(0, 5.6 - 0.04 * (x.DEF or 0)) / 100 + 0.15 * 0.5 end
	local taken = (1 - dr) * (1 - avoid) * (1 - blockRed) * (1 + extra)
	return max(1, x.HP or 1) / max(0.01, taken)
end

-- Mana per fight. Levelling: you drink every few pulls, so a quarter of the pool goes to each fight, plus
-- what you regenerate while fighting and while walking to the next mob. Endgame: one long fight on the
-- whole pool. Warlocks Life Tap, so part of their health counts as mana.
function Model.Sustain(s, x)
	if not GL.Classes.stats[s.class].mana then return 1 end
	local pool = (x.MANA or 0) + (s.spec.lifeTap and (x.HP or 0) * GL.Specs.LIFE_TAP_SHARE or 0)
	local mana
	if s.mode == "endgame" then
		mana = pool + (x.REGEN_IC or 0) * 180
	else
		mana = pool / 4 + (x.REGEN_IC or 0) * 25 + (x.REGEN_OOC or 0) * 20
	end
	return max(1, mana)
end

---------------------------------------------------------------------------
-- Calibration: at your current gear each part has the share Specs.lua gives it.
---------------------------------------------------------------------------
function Model.Calibrate(s)
	if s.calib then return s.calib end
	local ctx = Model.Context(s)
	local x0 = Model.FromSnapshot(s)
	local parts = Model.Parts(s, x0, ctx)
	local comps = Model.Comps(s)
	local f = {}
	for name, share in pairs(comps) do
		local raw = parts[name] or 0
		-- a part you have nothing for yet (no wand, no bow): scaled to a typical one of your level
		if raw <= 0 then raw = parts[name .. "Ref"] or 1 end
		f[name] = share / raw
	end
	s.calib = { f = f, ctx = ctx, x0 = x0, parts0 = parts, weights = GL.Specs.Weights(s.spec, s.mode, s.class) }
	s.base = Model.Evaluate(s, x0)
	return s.calib
end

function Model.Evaluate(s, x)
	local cal = Model.Calibrate(s)
	local parts = Model.Parts(s, x, cal.ctx)
	local dmg, heal = 0, 0
	for name, factor in pairs(cal.f) do
		dmg = dmg + factor * (parts[name] or 0)
		if name == "heal" then heal = factor * (parts[name] or 0) end
	end
	-- healers: healing apart from the damage they do alone (wand, Smite) for the window's rows
	return { dmg = max(1e-6, dmg), heal = heal, solo = dmg - heal, surv = Model.Survival(s, x, cal.ctx), sus = Model.Sustain(s, x) }
end

---------------------------------------------------------------------------
-- Levelling: kills per hour
---------------------------------------------------------------------------
-- One kill cycle against a normal mob of your level (ExpectedStat, WoW Forever game data):
--   fight   mob health / your damage per second (physical damage after the mob's armor)
--   travel  walking to and pulling the next mob (estimate: 8 s)
--   rest    eating back the health you lost and drinking back the mana you spent, at the rate food and water
--           of your level restore (game data), less what you regenerate while walking; both at once.
--           Warlocks turn health into mana (Life Tap), so they eat and drink one shared deficit.
--   stops   sitting down and getting up (estimate: 3 s per stop); a bigger pool means fewer stops
-- Kills per hour = 3600 / (fight + travel + rest + stops). On top, a small share for staying alive on bad
-- pulls (deaths cost minutes; estimate 5 %, on effective health).
Model.TRAVEL, Model.STOP, Model.SAFETY = 8, 3, 0.05
-- tank specs level by pulling several mobs at once, so staying alive counts more (estimate)
Model.TANK_SAFETY = 0.2

-- Your damage per second in absolute numbers, worked out the same way for any gear: the share-weighted rate of
-- what you can do (melee swings and shooting through the mob's armor, casting your filler, wanding, each at its
-- real size), times the parts that ride on top of those (special attacks, the pet). Also returns which parts
-- you have, so a first bow or wand can be told apart.
local ABS = { white = true, ranged = true, spell = true, wand = true }
function Model.AbsDPS(s, parts)
	local comps = Model.Comps(s)
	local _, _, mobArmor, armorK = Model.Creature(s.level)
	local phys = 1 - mobArmor / (mobArmor + armorK)
	local filler = Model.Filler(s)
	-- a hunter without a bow fights in melee the whole time (the time it would shoot goes to melee). A caster
	-- without a wand gets nothing for the wand's share of the time (it waits for mana or hits with the staff),
	-- so a first wand counts in full.
	local function has(name) return name == "pet" or (parts[name] or 0) > 0 end
	local stand = {}
	if not has("ranged") and has("white") then stand.ranged, stand.shots = "white", "white" end
	local function Total(stand)
		local share, usedStand = {}, false
		for name, v in pairs(comps) do
			local target = (has(name) and not stand[name]) and name or stand[name] or (name == "wand" and "wand") or nil
			if target and target ~= name then usedStand = true end
			if target then share[target] = (share[target] or 0) + v end
		end
		local rate, wsum, present, key = 0, 0, 0, {}
		for name, v in pairs(share) do
			local p = parts[name] or 0
			present = present + v
			key[#key + 1] = name .. (p > 0 and "" or "0")
			if ABS[name] and (name ~= "spell" or filler) then
				rate = rate + v * p * ((name == "white" or name == "ranged") and phys or 1)
				wsum = wsum + v
			end
		end
		if wsum <= 0 then return nil end
		table.sort(key)
		-- a stand-in (melee for a missing bow) makes the detailed model's shares wrong for this character: mark it
		return rate / wsum * present / wsum, table.concat(key, ",") .. (usedStand and "+stand" or "")
	end
	local dps, key = Total(stand)
	-- with a bow and a melee weapon, a hunter fights the faster way: the whole rotation with the bow, or melee
	if has("ranged") and has("white") then
		local melee, meleeKey = Total({ ranged = "white", shots = "white" })
		if melee and (not dps or melee > dps) then dps, key = melee, meleeKey end
	end
	return dps, key
end

function Model.LevelCycle(s, x, n)
	local L = s.level
	local hp, mobDPS, mobArmor, armorK = Model.Creature(L)
	local cal = s.calib
	local spec = s.spec
	local comps = Model.Comps(s)
	local filler = Model.Filler(s)
	-- your damage per second in absolute numbers (Model.AbsDPS). With the same kinds of damage before and after
	-- (no first bow, no first wand), the detailed model's change is applied to it, which also counts crit on
	-- special attacks; when a new kind of damage appears, both sides are worked out the same absolute way
	local parts0 = cal.parts0
	local abs0, key0 = Model.AbsDPS(s, parts0)
	if not abs0 then return nil end
	local dps
	if x == cal.x0 then
		dps = abs0
	else
		local parts = Model.Parts(s, x, cal.ctx)
		local abs1, key1 = Model.AbsDPS(s, parts)
		if not abs1 then return nil end
		local same = key1 == key0 and not key0:find("+stand", 1, true)
		dps = same and abs0 * n.dmg / s.base.dmg or abs1
	end
	local fight = hp / math.max(0.1, dps)

	-- damage you take: the mob's DPS through your armor, avoidance and whatever holds it (a pet)
	local armor = math.max(0, x.ARMOR or 0)
	local dr = math.min(0.75, armor / (armor + armorK))
	-- defense you add lowers the mob's hit chance and raises dodge and parry (0.04 % each per point)
	local def = ((x.DEF or 0) - (s.stats.DEF or 0)) * 0.04
	local avoid = math.min(0.9, (5 + def + (x.DODGE or 0) + def + ((x.PARRY or 0) > 0 and (x.PARRY + def) or 0)) / 100)
	-- a pet holds the mob from level 10 (voidwalker, hunter pet)
	local petTank = (spec.petTank and L >= 10) and spec.petTank or 1
	local block = 0
	if x.shield and (x.BLOCK or 0) > 0 then
		block = math.min(0.9, (x.BLOCK + def) / 100 * math.min(1, (x.BLOCKVAL or 0) / (mobDPS * 2)))
	end
	local hpLost = mobDPS * (1 - dr) * (1 - avoid) * (1 - block) * petTank * fight

	-- mana you spend: casting your filler for your spell share of the fight, or a share of that for hybrids
	local manaSpent = 0
	if GL.Classes.stats[s.class].mana then
		local name = filler or spec.manaSpell or spec.heal
		local _, cost, cast = Model.SpellRank(name, L)
		if cost then
			local share = filler and ((comps.spell or 0) + (comps.heal or 0)) or (spec.manaUse or 0.3)
			manaSpent = cost / cast * share * fight
		end
		manaSpent = math.max(0, manaSpent - (x.REGEN_IC or 0) * fight - (x.REGEN_OOC or 0) * Model.TRAVEL)
	end

	local food, drink = Band(GL.LevelingData.food, L), Band(GL.LevelingData.drink, L)
	local rest
	if spec.lifeTap then
		-- Life Tap turns health into mana, not back: health needs food, the total needs both
		rest = math.max(hpLost / food, (hpLost + manaSpent) / (food + drink))
	else
		-- you sit until the slower of the two is full. Pulls differ, so sometimes health and sometimes mana
		-- decides: a soft maximum (power 4) instead of a hard one, so the other one still counts a little
		local a, b = hpLost / food, manaSpent / drink
		rest = (a ^ 4 + b ^ 4) ^ 0.25
	end
	local stops = Model.STOP * (hpLost / math.max(1, x.HP or 1) + (manaSpent > 0 and manaSpent / math.max(1, x.MANA or 1) or 0))
	return { fight = fight, travel = Model.TRAVEL, rest = rest, stops = stops,
		total = fight + Model.TRAVEL + rest + stops, dps = dps, hpLost = hpLost, manaSpent = manaSpent }
end

-- The change from your current gear to state x: total and per part, in percent.
function Model.Gain(s, x)
	local cal = Model.Calibrate(s)
	local b, n, w = s.base, Model.Evaluate(s, x), cal.weights
	local rd, rs, rm = n.dmg / b.dmg, n.surv / b.surv, n.sus / b.sus
	local total = (rd ^ w.dmg) * (rs ^ w.surv) * (rm ^ w.sus)
	local out = {
		total = (total - 1) * 100,
		dmg = (rd - 1) * 100, surv = (rs - 1) * 100, sus = (rm - 1) * 100,
		weights = w,
	}
	if (b.heal or 0) > 0 then
		out.heal = (n.heal / b.heal - 1) * 100
		out.solo = (b.solo or 0) > 1e-9 and (n.solo / b.solo - 1) * 100 or nil
	end
	-- levelling (not as a healer, whose healing doesn't kill anything): kills per hour from the kill cycle
	if s.mode == "level" and s.spec.role ~= "healer" and GL.LevelingData then
		local c0 = cal.cycle0 or Model.LevelCycle(s, cal.x0, s.base)
		cal.cycle0 = c0
		local c1 = c0 and Model.LevelCycle(s, x, n)
		if c1 then
			local safety = s.spec.role == "tank" and Model.TANK_SAFETY or Model.SAFETY
			out.total = ((c0.total / c1.total) * rs ^ safety - 1) * 100
			out.cycle, out.cycle0 = c1, c0
		end
	end
	return out
end
