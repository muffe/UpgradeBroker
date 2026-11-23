-- tests/run.lua: lua5.1 tests/run.lua (from the addon folder). Checks the rating on characters like yours.
package.path = "tests/?.lua;" .. package.path
local T = require("stubs")
local GL = T.Load(".")

local fails, n = 0, 0
local function check(name, cond, info)
	n = n + 1
	if not cond then fails = fails + 1 print("FAIL " .. name .. (info and ("  " .. info) or "")) else print("ok   " .. name .. (info and ("  " .. info) or "")) end
end
local function rate(link)
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	return GL.Compare:Rate(link)
end
local function pct(r) return r and r.gain and ("%.2f%%"):format(r.gain.total) or tostring(r and r.reason) end

---------------------------------------------------------------------------
-- Warlock 35, Demonology, levelling
---------------------------------------------------------------------------
T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800,
	spAll = 20, scrit = 6, armor = 420, regen = 14, regenIC = 0 })
GL.cdb.spec = "DEMO"
T.equipped[5] = T.Item("robe-old", { name = "Old Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1,
	stats = { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 6, RESISTANCE0_NAME = 50 } })
T.equipped[18] = T.Item("wand-old", { name = "Old Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19,
	stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 22 }, lines = { { leftText = "", rightText = "Speed 1.50" } } })

local shadowRobe = T.Item("robe-shadow", { name = "Shadow Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1,
	stats = { RESISTANCE0_NAME = 52 }, lines = { "Equip: Increases damage done by Shadow spells and effects by up to 12." } })
local staRobe = T.Item("robe-sta", { name = "Robe of Stamina", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1,
	stats = { ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_INTELLECT_SHORT = 6, RESISTANCE0_NAME = 52 } })
local same = T.Item("robe-old", T.items["robe-old"])
local wand = T.Item("wand-new", { name = "New Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19,
	stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 28 } })
local leather = T.Item("leather", { name = "Leather Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 2,
	stats = { ITEM_MOD_STAMINA_SHORT = 30 } })
local future = T.Item("future", { name = "Future Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1, reqLevel = 37,
	stats = { ITEM_MOD_STAMINA_SHORT = 15, ITEM_MOD_INTELLECT_SHORT = 10 } })

local r1, r2, r3, r4 = rate(shadowRobe), rate(staRobe), rate(wand), rate(same)
check("warlock: shadow damage robe is an upgrade", r1.gain.total > 0.5, pct(r1))
check("warlock: stamina robe helps a little", r2.gain.total > 0, pct(r2))
check("warlock: +12 shadow damage beats +12 stamina while levelling (Forever cut base spell damage)", r1.gain.total > r2.gain.total)
check("warlock: wand 22 -> 28 dps is an upgrade", r3.gain.total > 0.5, pct(r3))
check("warlock: the robe you wear is +0%", math.abs(r4.gain.total) < 1e-9, pct(r4))
check("warlock: leather is not usable", not rate(leather).ok)
local rf = rate(future)
check("warlock: level 37 robe is usable later", rf.ok and rf.reason == "later", pct(rf))
-- gear a warlock can never wear is turned away before its tooltip is read
local plate = T.Item("plate", { name = "Plate Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, stats = {} })
local sword2h = T.Item("2h-sword", { name = "Greatsword", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8, stats = {} })
local far = T.Item("far", { name = "Far Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1, reqLevel = 45, stats = {} })
local s35 = GL.Character:Get()
check("quick reject: plate for a warlock", GL.Compare.QuickReject(s35, plate) == "armor")
check("quick reject: a two-handed sword for a warlock", GL.Compare.QuickReject(s35, sword2h) == "weapon")
check("quick reject: level 45 at 35", GL.Compare.QuickReject(s35, far) == "level")
check("quick reject: a cloth robe takes the full look", GL.Compare.QuickReject(s35, staRobe) == nil)
check("quick reject: the level 37 robe takes the full look", GL.Compare.QuickReject(s35, future) == nil)
print(("     shadow robe: dmg %+.2f surv %+.2f mana %+.2f"):format(r1.gain.dmg, r1.gain.surv, r1.gain.sus))
print(("     stamina robe: dmg %+.2f surv %+.2f mana %+.2f"):format(r2.gain.dmg, r2.gain.surv, r2.gain.sus))

---------------------------------------------------------------------------
-- Paladin 25, Retribution, levelling: two-handers and rings
---------------------------------------------------------------------------
T.Reset({ level = 25, class = "PALADIN", className = "Paladin", stats = { 70, 40, 65, 45, 50 }, hp = 900, mana = 900,
	ap = 190, spAll = 0, crit = 6, scrit = 5, armor = 900, regen = 8, regenIC = 0 })
GL.cdb.spec = "RET"
T.equipped[16] = T.Item("2h-old", { name = "Old Greatsword", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8,
	stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 16, ITEM_MOD_STRENGTH_SHORT = 5 } })
T.equipped[11] = T.Item("ring-a", { name = "Ring A", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_STRENGTH_SHORT = 6 } })
T.equipped[12] = T.Item("ring-b", { name = "Ring B", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_STAMINA_SHORT = 2 } })
local bigSword = T.Item("2h-new", { name = "New Greatsword", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8,
	stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 21, ITEM_MOD_STRENGTH_SHORT = 5 } })
local ring = T.Item("ring-new", { name = "Ring of Strength", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
local plate = T.Item("plate", { name = "Plate Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
local dagger = T.Item("dagger", { name = "Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } })

local p1, p2 = rate(bigSword), rate(ring)
check("paladin: 16 -> 21 dps two-hander is a big upgrade", p1.gain.total > 5, pct(p1))
check("paladin: ring replaces the weaker ring (Ring 2)", p2.label == "Ring 2", p2.label)
check("paladin: ring has a per-slot list", p2.perSlot and #p2.perSlot == 2)
check("paladin: plate below 40 is not usable", not rate(plate).ok)
check("paladin: daggers are not usable", not rate(dagger).ok)

---------------------------------------------------------------------------
-- Warrior 60, Arms, endgame: hit stops at the cap (8% for special attacks)
---------------------------------------------------------------------------
T.Reset({ level = 60, class = "WARRIOR", className = "Warrior", stats = { 300, 120, 250, 30, 60 }, hp = 5000,
	ap = 900, crit = 20, hit = 7, armor = 5000 })
GL.cdb.spec = "ARMS"; GL.cdb.mode = "endgame"
T.equipped[16] = T.Item("2h-60", { name = "Big Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 1,
	stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 60 } })
T.equipped[6] = T.Item("belt-old", { name = "Belt", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 4, stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
local hit1 = T.Item("belt-hit1", { name = "Belt of Hit", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 4,
	stats = { ITEM_MOD_STRENGTH_SHORT = 10 }, lines = { "Equip: Improves your chance to hit by 1%." } })
local hit3 = T.Item("belt-hit3", { name = "Belt of More Hit", equipLoc = "INVTYPE_WAIST", classID = 4, subclassID = 4,
	stats = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_HIT_RATING_SHORT = 30 }, lines = { "Equip: Improves your chance to hit by 3%." } })
local w1, w3 = rate(hit1), rate(hit3)
check("warrior: 1% hit below the cap is worth something", w1.gain.total > 0.3, pct(w1))
check("warrior: 3% hit is worth less than 3x 1% (cap at 8%)", w3.gain.total < 3 * w1.gain.total, pct(w3))
check("warrior: tooltip percent replaces the rating (3%, not 3% + 3%)", GL.Items.Get(hit3).stats.HIT == 3)

---------------------------------------------------------------------------
-- Every spec at levels 12, 35 and 60 in both modes: a finite rating, stamina never hurts, the main stat helps
---------------------------------------------------------------------------
local CLASSNAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local sta = T.Item("neck-sta", { name = "Neck", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_STAMINA_SHORT = 8 } })
local main = {
	T.Item("neck-str", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_STRENGTH_SHORT = 8 } }),
	T.Item("neck-agi", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_AGILITY_SHORT = 8 } }),
	T.Item("neck-sp", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 8 } }),
	T.Item("neck-heal", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 8 } }),
}
local bad = 0
for class, specs in pairs(GL.Specs.list) do
	for _, spec in ipairs(specs) do
		for _, level in ipairs({ 12, 35, 60 }) do
			for _, mode in ipairs({ "level", "endgame" }) do
				local f = level / 60
				T.Reset({ level = level, class = class, className = CLASSNAMES[class], stats = { 100 * f, 80 * f, 120 * f, 90 * f, 80 * f },
					hp = 3500 * f, mana = 2500 * f, ap = 600 * f, rap = 400 * f, spAll = 100 * f, heal = 150 * f, crit = 10, scrit = 8,
					armor = 2000 * f, regen = 10, regenIC = 2, dw = GL.Classes.dualWield[class] })
				T.equipped[16] = T.Item("w-" .. class, { name = "W", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10,
					stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 * f } })
				GL.cdb.spec, GL.cdb.mode = spec.key, mode
				local rs = rate(sta)
				local best = -1
				for _, l in ipairs(main) do local r = rate(l); if r.gain.total > best then best = r.gain.total end end
				local okNum = rs.gain.total == rs.gain.total and rs.gain.total >= 0 and best == best and best > 0
				if not okNum then bad = bad + 1; print(("     %s %s %d %s: sta %s main %.2f"):format(class, spec.key, level, mode, pct(rs), best)) end
			end
		end
	end
end
check("all specs: finite ratings, stamina >= 0, main stat > 0", bad == 0, bad .. " bad")

---------------------------------------------------------------------------
-- Edge cases from council review 08
---------------------------------------------------------------------------
GL.cdb.mode = nil
-- a level 1 frost mage has Fireball, not Frostbolt yet
T.Reset({ level = 1, class = "MAGE", className = "Mage", stats = { 20, 20, 20, 25, 25 }, hp = 50, mana = 100, regen = 1 })
GL.cdb.spec = "FROST"
local mageNeck = T.Item("mage-neck", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_INTELLECT_SHORT = 1 } })
local rm = rate(mageNeck)
check("frost mage level 1 uses Fireball (short fights)", rm.gain.cycle0 and rm.gain.cycle0.fight < 30, rm.gain.cycle0 and ("%.1f s"):format(rm.gain.cycle0.fight))

-- a level 5 hunter: no pet yet, no bow: the first bow is a big upgrade
T.Reset({ level = 5, class = "HUNTER", className = "Hunter", stats = { 20, 25, 22, 20, 20 }, hp = 120, mana = 100, ap = 30, rap = 40, regen = 2 })
GL.cdb.spec = "BM"
local bow = T.Item("bow", { name = "Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } })
local rb = rate(bow)
check("hunter 5: first bow is a big upgrade", rb.gain.total > 10, pct(rb))
check("hunter 5: no pet share before level 10", not GL.Model.Comps(GL.Character:Get()).pet)

-- a first shield counts its block
T.Reset({ level = 30, class = "WARRIOR", className = "Warrior", stats = { 80, 50, 70, 20, 30 }, hp = 1000, ap = 250, crit = 6, armor = 1800, block = 5, blockval = 30 })
GL.cdb.spec = "PROT"
T.equipped[16] = T.Item("1h-war", { name = "Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } })
local shield = T.Item("shield", { name = "Shield", equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, stats = { RESISTANCE0_NAME = 400 }, lines = { "Equip: Increases the block value of your shield by 10." } })
local rs = rate(shield)
check("prot warrior: a first shield is an upgrade", rs.gain.total > 1, pct(rs))
local shieldRows = {}
for _, e in ipairs(GL.Compare.Contributions(rs)) do shieldRows[e.text or e.key] = e.pct end
check("prot warrior: the shield's block gets its own line", (shieldRows["Shield block"] or 0) > 0.1,
	("shield %.2f armor %.2f block value %.2f"):format(shieldRows["Shield block"] or 0, shieldRows.ARMOR or 0, shieldRows.BLOCKVAL or 0))

-- a two-hander replacing main and off hand: the swap gets its own line in the explanation
T.Reset({ level = 30, class = "WARRIOR", className = "Warrior", stats = { 80, 50, 70, 20, 30 }, hp = 1000, ap = 250, crit = 6, armor = 1800, dw = true })
GL.cdb.spec = "FURY"
T.equipped[16] = T.Item("mh18", { name = "MH", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 18 } })
T.equipped[17] = T.Item("oh15", { name = "OH", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 } })
local big = T.Item("2h33", { name = "2H", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 33 } })
local r2h = rate(big)
local rows = GL.Compare.Contributions(r2h)
local sum = 0
for _, e in ipairs(rows) do sum = sum + (e.pct or 0) end
check("2H vs MH+OH: the explanation has a line and adds up", #rows >= 1 and math.abs(sum - r2h.gain.total) < 0.15, ("%d rows, %.2f vs %.2f"):format(#rows, sum, r2h.gain.total))

-- an alt whose gear isn't loaded yet gets no rating instead of a wrong one
T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800, spAll = 20, scrit = 6, armor = 420, regen = 14 })
GL.cdb.spec = "DEMO"
local fake = { class = "WARLOCK", classLocal = "Warlock", level = 35, name = "Alt", stats = { STR = 30, AGI = 35, STA = 80, INT = 110, SPI = 105, HP = 1300, MANA = 1800 },
	conv = { critAgi = 0.05, critInt = 0.03, dodgeAgi = 0.05, regenSpi = 0.125, icShare = 0, apStr = 1, apAgi = 0, rapAgi = 0 }, equipped = { [5] = "not-loaded-yet" } }
local alt = GL.Character.FromSaved(fake)
check("alt with gear still loading is not rated", alt.incomplete and GL.Compare:Rate(shadowRobe, alt) == nil)

-- casters spend mana while leveling, so Spirit shortens their rest
T.Reset({ level = 30, class = "MAGE", className = "Mage", stats = { 25, 30, 60, 120, 110 }, hp = 900, mana = 2000, spAll = 20, scrit = 6, armor = 300, regen = 12 })
GL.cdb.spec = "FROST"
local spiNeck = T.Item("spi-neck", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_SPIRIT_SHORT = 10 } })
local rsp = rate(spiNeck)
check("frost mage 30 spends mana per kill", rsp.gain.cycle0 and rsp.gain.cycle0.manaSpent > 100, rsp.gain.cycle0 and ("%.0f mana"):format(rsp.gain.cycle0.manaSpent))
check("frost mage 30: +10 Spirit shortens resting", rsp.gain.cycle and rsp.gain.cycle.rest < rsp.gain.cycle0.rest, pct(rsp))

-- a bowless hunter's weapon swap predicts what rebuilding with that weapon gives
T.Reset({ level = 20, class = "HUNTER", className = "Hunter", stats = { 40, 60, 50, 30, 30 }, hp = 500, mana = 400, ap = 80, rap = 100, regen = 5 })
GL.cdb.spec = "BM"
T.equipped[16] = T.Item("sw12", { name = "S12", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } })
local sw14 = T.Item("sw14", { name = "S14", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14 } })
local rh = rate(sw14)
local predicted = rh.gain.cycle.fight
T.equipped[16] = sw14
local rh2 = rate(spiNeck)
check("bowless hunter: predicted fight = rebuilt fight", math.abs(predicted - rh2.gain.cycle0.fight) < 0.05, ("%.2f vs %.2f"):format(predicted, rh2.gain.cycle0.fight))

-- a first wand is an upgrade for a caster; spell damage still counts for a melee hybrid
T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800, spAll = 20, scrit = 6, armor = 420, regen = 14 })
GL.cdb.spec = "DEMO"
local firstWand = T.Item("first-wand", { name = "Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 } })
local rw = rate(firstWand)
check("warlock 35 without a wand: a first wand is an upgrade", rw.gain.total > 1, pct(rw))
T.Reset({ level = 35, class = "PALADIN", className = "Paladin", stats = { 90, 50, 80, 60, 60 }, hp = 1500, mana = 1200, ap = 260, crit = 6, scrit = 5, armor = 2000, regen = 9 })
GL.cdb.spec = "RET"
T.equipped[16] = T.Item("2h-ret", { name = "2H", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } })
local spRet = T.Item("sp-ret", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, stats = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 } })
local rr = rate(spRet)
check("ret paladin 35: +10 spell damage counts", rr.gain.total > 0.3, pct(rr))

-- a level 5 shadow priest still casts Smite: holy damage counts
T.Reset({ level = 5, class = "PRIEST", className = "Priest", stats = { 20, 20, 25, 30, 30 }, hp = 120, mana = 250, regen = 3 })
GL.cdb.spec = "SHADOW"
local holyN = T.Item("holy-n", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, lines = { "Equip: Increases damage done by Holy spells and effects by up to 5." } })
check("shadow priest 5: holy damage counts (Smite)", rate(holyN).gain.total > 0.3, pct(rate(holyN)))

-- a bow slower than the melee weapon is no downgrade: the hunter keeps fighting in melee
T.Reset({ level = 20, class = "HUNTER", className = "Hunter", stats = { 40, 60, 50, 30, 30 }, hp = 500, mana = 400, ap = 80, rap = 100, regen = 5 })
GL.cdb.spec = "SV"
T.equipped[16] = T.Item("sw14", T.items["sw14"])
local weakBow = T.Item("weak-bow", { name = "Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2 } })
check("hunter 20: a weak first bow is not a downgrade", rate(weakBow).gain.total >= -0.05, pct(rate(weakBow)))

-- a healer's healing row is healing only
T.Reset({ level = 30, class = "PRIEST", className = "Priest", stats = { 25, 30, 60, 120, 110 }, hp = 900, mana = 2000, spAll = 20, heal = 40, scrit = 6, armor = 300, regen = 12 })
GL.cdb.spec = "HOLY"
local healerWand = T.Item("healer-wand", { name = "Wand", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } })
local rhw = rate(healerWand)
check("holy priest: a wand adds no healing", rhw.gain.heal and math.abs(rhw.gain.heal) < 0.05 and (rhw.gain.solo or 0) > 0, rhw.gain.heal and ("heal %.2f solo %.2f"):format(rhw.gain.heal, rhw.gain.solo or 0))

-- with a bow on, a better sword never makes a hunter slower
T.Reset({ level = 20, class = "HUNTER", className = "Hunter", stats = { 40, 60, 50, 30, 30 }, hp = 500, mana = 400, ap = 80, rap = 100, regen = 5 })
GL.cdb.spec = "SV"
T.equipped[16] = T.Item("sw14", T.items["sw14"])
T.equipped[18] = T.Item("bow11", { name = "Bow", equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 11.2 } })
local sw15 = T.Item("sw15", { name = "S15", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 } })
check("hunter 20 with a bow: a better sword is not worse", rate(sw15).gain.total >= 0, pct(rate(sw15)))

-- a level 1 shadow priest has no shadow spell yet
T.Reset({ level = 1, class = "PRIEST", className = "Priest", stats = { 20, 20, 20, 25, 25 }, hp = 60, mana = 120, regen = 1 })
GL.cdb.spec = "SHADOW"
local shadowN = T.Item("shadow-n", { name = "N", equipLoc = "INVTYPE_NECK", classID = 4, subclassID = 0, lines = { "Equip: Increases damage done by Shadow spells and effects by up to 10." } })
check("shadow priest 1: shadow damage does nothing yet", math.abs(rate(shadowN).gain.total) < 0.05, pct(rate(shadowN)))

-- profession gear only with the profession
local goggles = T.Item("goggles", { name = "Goggles", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 1,
	stats = { ITEM_MOD_STAMINA_SHORT = 20, ITEM_MOD_INTELLECT_SHORT = 20 }, lines = { "Requires Engineering (150)" } })
T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800, spAll = 20, armor = 420, regen = 14 })
GL.cdb.spec = "DEMO"
check("engineering goggles: not for a character without Engineering", not rate(goggles).ok, tostring(rate(goggles).reason))
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Engineering", nil, 175 end
check("engineering goggles: fine with Engineering 175", rate(goggles).ok)
GetProfessions, GetProfessionInfo = nil, nil

-- the spec comes from the talents: a paladin with most points in Retribution is Retribution
T.Reset({ level = 25, class = "PALADIN", className = "Paladin", stats = { 70, 40, 65, 45, 50 }, hp = 900, mana = 900, ap = 190, armor = 900, regen = 8 })
GL.cdb.spec, GL.cdb.specFor = "HOLY", nil -- an old pick from before
C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 7 end }
C_Traits = {
	GetConfigInfo = function() return { treeIDs = { 1 } } end,
	GetGroupDisplayInfoByTreeID = function() return { { groupID = 10, orderIndex = 0 }, { groupID = 11, orderIndex = 1 }, { groupID = 12, orderIndex = 2 } } end,
	GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 10, currencyInfos = { { spent = 2 } } }, { traitNodeGroupID = 12, currencyInfos = { { spent = 14 } } } } end,
}
check("spec from talents: Retribution", GL.Character.SpecKey("PALADIN") == "RET", GL.Character.SpecKey("PALADIN"))
GL:SetSpec("PROT")
check("a pick for the current talents is kept", GL.Character.SpecKey("PALADIN") == "PROT")
C_SpecializationInfo, C_Traits = nil, nil

print(("%d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
