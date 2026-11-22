-- Character.lua: your character as it is right now (the totals the character sheet shows) and the gear
-- you wear. Every rating starts from here: an item's value is what your totals become with it.
local _, GL = ...

local Character = {}
GL.Character = Character

local P = function(v) return GL.Plain(v) end
local function Call(f, ...)
	if type(f) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(f, ...)
	if ok then return P(a), P(b), P(c), P(d) end
end

-- GetSpellBonusDamage / GetSpellCritChance school indexes
local SCHOOL_INDEX = { HOLY = 2, FIRE = 3, NATURE = 4, FROST = 5, SHADOW = 6, ARCANE = 7 }
Character.SCHOOL_INDEX = SCHOOL_INDEX

local snap

function Character:Invalidate() snap = nil end

-- Your professions and their ranks: { ["engineering"] = 150 }. nil when the client can't say.
function Character.Skills()
	local out, found = {}, false
	if GetProfessions and GetProfessionInfo then
		for _, idx in ipairs({ Call(GetProfessions) }) do
			local name, _, rank = Call(GetProfessionInfo, idx)
			if name and rank then out[name:lower()] = rank; found = true end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, Call(GetNumSkillLines) or 0 do
			local name, header, _, rank = Call(GetSkillLineInfo, i)
			if name and not header and rank then out[name:lower()] = rank; found = true end
		end
	end
	return found and out or nil
end

-- The spec: your choice, else the one the game says you are, else the class's first.
-- The talent tree with the most points (1 to 3, in the game's order), or nil when the client can't say.
-- WoW Forever keeps talents as trait groups (the same way RatingBuster reads them); older clients have
-- GetTalentTabInfo.
local TREE_SPECS = {
	WARRIOR = { "ARMS", "FURY", "PROT" }, PALADIN = { "HOLY", "PROT", "RET" }, HUNTER = { "BM", "MM", "SV" },
	ROGUE = { "ASSA", "COMBAT", "SUB" }, PRIEST = { "DISC", "HOLY", "SHADOW" }, SHAMAN = { "ELE", "ENH", "RESTO" },
	MAGE = { "ARCANE", "FIRE", "FROST" }, WARLOCK = { "AFFLI", "DEMO", "DESTRO" }, DRUID = { "BALANCE", "CAT", "RESTO" },
}
local function TraitTree()
	local SI, TR = C_SpecializationInfo, C_Traits
	if not (SI and TR and SI.GetCombatConfigIDForSpecGroup and TR.GetConfigInfo and TR.GetGroupDisplayInfoByTreeID
		and TR.GetGroupCurrencyInfo) then return nil end
	local ok, tree = pcall(function()
		local group = SI.GetActiveSpecGroup and SI.GetActiveSpecGroup() or 1
		local configID = SI.GetCombatConfigIDForSpecGroup(group)
		local info = configID and TR.GetConfigInfo(configID)
		local treeID = info and info.treeIDs and info.treeIDs[1]
		if not treeID then return nil end
		local ids, index = {}, {}
		for _, d in ipairs(TR.GetGroupDisplayInfoByTreeID(treeID) or {}) do
			ids[#ids + 1] = d.groupID
			index[d.groupID] = (d.orderIndex or 0) + 1
		end
		local best, most = nil, 0
		for _, g in ipairs(TR.GetGroupCurrencyInfo(configID, ids) or {}) do
			local spent = g.currencyInfos and g.currencyInfos[1] and g.currencyInfos[1].spent or 0
			if spent > most then most, best = spent, index[g.traitNodeGroupID] end
		end
		return best
	end)
	if ok then return tree end
end
local function TalentTab()
	if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
	local best, most = nil, 0
	for tab = 1, Call(GetNumTalentTabs) or 0 do
		local ok, a, b, c, d = pcall(GetTalentTabInfo, tab)
		-- (name, icon, pointsSpent) on old clients; (id, name, description, icon, pointsSpent) on newer ones
		local spent = ok and (type(c) == "number" and c or (select(5, GetTalentTabInfo(tab)))) or 0
		if type(spent) == "number" and spent > most then most, best = spent, tab end
	end
	return best
end

-- The spec your talents say you play, or nil.
function Character.DetectSpec(class)
	local tree = TraitTree() or TalentTab()
	return tree and TREE_SPECS[class] and TREE_SPECS[class][tree] or nil
end

-- The spec: the one your talents say, unless you picked another for these talents in the window or options.
-- A pick made before a respec no longer counts.
function Character.SpecKey(class)
	local list = GL.Specs.ForClass(class)
	local detected = Character.DetectSpec(class)
	local chosen = GL.cdb and GL.cdb.spec
	local valid = false
	for _, s in ipairs(list) do if s.key == chosen then valid = true end end
	if valid and (not detected or GL.cdb.specFor == detected) then return chosen end
	if detected then return detected end
	return list[1] and list[1].key
end

local function SumItems(equipped, key)
	local t = 0
	for _, item in pairs(equipped) do t = t + (item.stats[key] or 0) end
	return t
end

local function Weapon(item, formLevel)
	if formLevel then return { dps = 0.9 * formLevel, speed = 1, form = true } end
	if not item or not item.stats.DPS then return nil end
	return { dps = item.stats.DPS, speed = item.stats.SPEED or 2.5, kind = item.kind, sub = item.subclassID }
end
Character.Weapon = Weapon

-- Builds the snapshot. Returns nil while gear is still loading (try again on GL_ITEM_LOADED).
function Character:Build()
	local class = GL.PlayerClass()
	local level = GL.PlayerLevel()
	local specKey = Character.SpecKey(class)
	local spec = GL.Specs.Get(class, specKey)
	local cdata = GL.Classes.stats[class]
	local s = { class = class, level = level, spec = spec, mode = GL:Mode(), equipped = {}, incomplete = false }

	for slot = 1, 18 do
		local link = GetInventoryItemLink("player", slot)
		if link and slot ~= 4 then
			local item = GL.Items.Get(link)
			if item then s.equipped[slot] = item else s.incomplete = true end
		end
	end

	local st = {}
	s.stats = st
	for i, key in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
		local _, value = Call(UnitStat, "player", i)
		st[key] = value or 0
	end
	local base, pos, neg = Call(UnitAttackPower, "player")
	st.AP = (base or 0) + (pos or 0) + (neg or 0)
	base, pos, neg = Call(UnitRangedAttackPower, "player")
	st.RAP = (base or 0) + (pos or 0) + (neg or 0)
	for school, idx in pairs(SCHOOL_INDEX) do st["SP_" .. school] = Call(GetSpellBonusDamage, idx) or 0 end
	st.HEAL = Call(GetSpellBonusHealing) or 0
	st.CRIT = Call(GetCritChance) or 0
	st.RCRIT = Call(GetRangedCritChance) or st.CRIT
	local scrit = 0
	for _, idx in pairs(SCHOOL_INDEX) do scrit = math.max(scrit, Call(GetSpellCritChance, idx) or 0) end
	st.SCRIT = scrit
	-- hit: the game's number if it gives one (talents included), at least what your gear says
	st.HIT = math.max(Call(GetHitModifier) or 0, SumItems(s.equipped, "HIT"))
	st.SHIT = math.max(Call(GetSpellHitModifier) or 0, SumItems(s.equipped, "HIT") + SumItems(s.equipped, "SHIT"))
	st.HASTE = math.max(0, SumItems(s.equipped, "HASTE"))
	st.EXP = SumItems(s.equipped, "EXP")
	st.DEF = SumItems(s.equipped, "DEF")
	local _, armor = Call(UnitArmor, "player")
	st.ARMOR = armor or 0
	st.HP = Call(UnitHealthMax, "player") or 0
	st.MANA = cdata.mana and (Call(UnitPowerMax, "player", 0) or 0) or 0
	st.DODGE = Call(GetDodgeChance) or 0
	st.PARRY = cdata.parry and (Call(GetParryChance) or 0) or 0
	st.BLOCK = Call(GetBlockChance) or 0
	st.BLOCKVAL = Call(GetShieldBlock) or 0
	local ooc, ic = Call(GetManaRegen)
	-- no number from the client: Spirit's part of WoW Forever's regeneration (wowsims mana.go), nothing while casting
	if not ooc and cdata.mana then ooc = (st.SPI or 0) * GL.Classes.MANA_PER_SPI end
	st.REGEN_OOC, st.REGEN_IC = ooc or 0, ic or 0

	s.skills = Character.Skills()

	-- what one more point of a primary stat gives you now
	local conv = {}
	s.conv = conv
	local agiCrit = Call(GetCritChanceFromAgility, "player")
	local intCrit = Call(GetSpellCritChanceFromIntellect, "player")
	local scale = GL.Classes.CritScale(level)
	conv.critAgi = (agiCrit and st.AGI > 0 and agiCrit > 0) and agiCrit / st.AGI or cdata.critAgi * scale
	conv.critInt = (intCrit and st.INT > 0 and intCrit > 0) and intCrit / st.INT or cdata.critInt * scale
	conv.dodgeAgi = conv.critAgi * (cdata.dodgeAgi or 1)
	local spiRegen = Call(GetUnitManaRegenRateFromSpirit, "player")
	conv.regenSpi = (spiRegen and st.SPI > 0 and spiRegen > 0) and spiRegen / st.SPI or GL.Classes.MANA_PER_SPI
	-- share of the not-casting regeneration you keep while casting (talents like Meditation)
	conv.icShare = (st.REGEN_OOC > 0) and math.min(1, st.REGEN_IC / st.REGEN_OOC) or 0
	conv.apStr, conv.apAgi, conv.rapAgi = cdata.apStr, cdata.apAgi, cdata.rapAgi

	-- cat and bear form come at their level; before that a feral druid fights with the weapon
	s.inForm = spec.form and level >= (spec.formLevel or 1) or false
	local formLevel = s.inForm and level or nil
	s.mh = Weapon(s.equipped[16], formLevel)
	s.oh = (not s.inForm) and s.equipped[17] and s.equipped[17].stats.DPS and Weapon(s.equipped[17]) or nil
	s.ranged = Weapon(s.equipped[18])
	-- the game knows; without an answer: rogues from level 10, warriors and hunters from 20
	local dw = Call(CanDualWield)
	if dw == nil then dw = GL.Classes.dualWield[class] and level >= (class == "ROGUE" and 10 or 20) or false end
	s.canDualWield = dw and true or false
	return s
end

-- The snapshot, cached until gear, spec or level change. In combat the last one is kept.
function Character:Get()
	if snap and (not snap.incomplete or InCombatLockdown()) then return snap end
	if InCombatLockdown() and snap then return snap end
	local ok, res = pcall(Character.Build, Character)
	if ok then snap = res else GL:Error(res) end
	return snap
end

function Character:Dump()
	local s = self:Get()
	if not s then return GL:Print("no snapshot") end
	GL:Print(("%s %s level %d, %s"):format(s.class, s.spec.name, s.level, s.mode))
	local keys = {}
	for k in pairs(s.stats) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = ("%s=%.4g"):format(k, s.stats[k]) end
	GL:Print(table.concat(parts, " "))
	GL:Print(("crit/agi %.4f crit/int %.4f regen/spi %.4f mh %s oh %s ranged %s"):format(s.conv.critAgi, s.conv.critInt,
		s.conv.regenSpi, s.mh and ("%.1f"):format(s.mh.dps) or "-", s.oh and ("%.1f"):format(s.oh.dps) or "-",
		s.ranged and ("%.1f"):format(s.ranged.dps) or "-"))
	local m = GL.Model.Evaluate(s, GL.Model.FromSnapshot(s))
	GL:Print(("model: dmg %.1f surv %.0f sus %.0f"):format(m.dmg, m.surv, m.sus))
end

GL:On("GL_ITEM_LOADED", function()
	if snap and snap.incomplete then snap = nil; GL:Invalidate() end
end)

---------------------------------------------------------------------------
-- Alts: every character you log in on is remembered (totals, gear, weapons in bags), so you can shop for it
-- from another character on the same realm and faction, e.g. a bank character at the auction house.
---------------------------------------------------------------------------
local function Copy(t)
	local c = {}
	for k, v in pairs(t or {}) do c[k] = type(v) == "table" and Copy(v) or v end
	return c
end

local function RealmKey() return GL.RealmKey() end
Character.RealmKey = RealmKey

local function Realm()
	GL.db.chars = GL.db.chars or {}
	local key = RealmKey()
	if not key then return nil end
	GL.db.chars[key] = GL.db.chars[key] or {}
	return GL.db.chars[key]
end

function Character:Save()
	local s = snap
	if not (s and GL.db) or s.incomplete then return end
	local name = UnitName("player")
	if not name then return end
	local realm = Realm()
	if not realm then return end
	local old = realm[name] or {}
	local d = { name = name, class = s.class, classLocal = UnitClass("player"), level = s.level, time = time(),
		-- this character's own choices win; one made from another character is kept until it sets its own
		-- the spec this character plays now; a pick made for it from another character ends with this login
		specKey = s.spec.key, spec = nil, mode = GL.cdb.mode or old.mode, stats = Copy(s.stats), conv = Copy(s.conv),
		canDualWield = s.canDualWield, skills = s.skills, equipped = {}, bagWeapons = {} }
	for slot, item in pairs(s.equipped) do d.equipped[slot] = item.link end
	local numSlots = C_Container and C_Container.GetContainerNumSlots
	local getLink = C_Container and C_Container.GetContainerItemLink
	if numSlots and getLink then
		for bag = 0, (NUM_BAG_SLOTS or 4) do
			for slot = 1, numSlots(bag) or 0 do
				local link = getLink(bag, slot)
				-- decided from instant item data, so a weapon the client hasn't loaded yet is kept as well
				local equipLoc
				if link then equipLoc = select(4, GL.Items.GetItemInfoInstant(link)) end
				local slots = equipLoc and GL.Items.EQUIP[equipLoc]
				if slots and (slots[1] == 16 or slots[1] == 17) then d.bagWeapons[#d.bagWeapons + 1] = link end
			end
		end
	end
	realm[name] = d
end

-- Your other characters on this realm and faction, newest first: { name, class, level, time }.
function Character:Alts()
	local list, me = {}, UnitName("player")
	for name, d in pairs(GL.db and GL.db.chars and RealmKey() and GL.db.chars[RealmKey()] or {}) do
		if name ~= me then list[#list + 1] = d end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

function Character:AltData(name)
	local realm = GL.db and GL.db.chars and RealmKey() and GL.db.chars[RealmKey()]
	return realm and name and realm[name]
end

-- name in any case ("übergroßer" finds "Übergroßer"); returns the saved name
function Character:Forget(name)
	local realm = GL.db and GL.db.chars and RealmKey() and GL.db.chars[RealmKey()]
	if not (realm and name) then return nil end
	for saved in pairs(realm) do
		if saved == name or saved:lower() == name:lower() or saved:sub(3):lower() == name:sub(3):lower() and #saved == #name then
			realm[saved] = nil
			return saved
		end
	end
end

-- A snapshot of an alt from what was saved, the same shape as Build's.
function Character.FromSaved(d)
	local spec = GL.Specs.Get(d.class, d.spec or d.specKey)
	local s = { class = d.class, classLocal = d.classLocal, level = d.level, spec = spec,
		mode = d.mode or (d.level >= 60 and "endgame" or "level"), equipped = {}, incomplete = false,
		isAlt = true, altName = d.name, stats = Copy(d.stats), conv = Copy(d.conv), canDualWield = d.canDualWield,
		bagWeaponLinks = d.bagWeapons or {}, skills = d.skills }
	for slot, link in pairs(d.equipped or {}) do
		local item = GL.Items.Get(link)
		if item then s.equipped[tonumber(slot) or slot] = item else s.incomplete = true end
	end
	s.inForm = spec.form and d.level >= (spec.formLevel or 1) or false
	-- weapons in the alt's bags pair with one-handers; wait for them like for the gear worn
	for _, link in ipairs(s.bagWeaponLinks) do if not GL.Items.Get(link) then s.incomplete = true end end
	local formLevel = s.inForm and d.level or nil
	s.mh = Weapon(s.equipped[16], formLevel)
	s.oh = (not s.inForm) and s.equipped[17] and s.equipped[17].stats.DPS and Weapon(s.equipped[17]) or nil
	s.ranged = Weapon(s.equipped[18])
	return s
end

-- Who the window shows: you, or the alt chosen in its header (GL.viewing = name).
local altSnaps = {}
function Character:Viewed()
	local d = GL.viewing and self:AltData(GL.viewing)
	if not d then GL.viewing = nil return self:Get() end
	local s = altSnaps[d.name]
	if not s or s.incomplete then s = Character.FromSaved(d); altSnaps[d.name] = s end
	return s
end

local baseInvalidate = Character.Invalidate
function Character:Invalidate()
	baseInvalidate(self)
	altSnaps = {}
end

-- remember this character whenever its gear settles, and on the way out
GL:On("GL_CHANGED", function() if not InCombatLockdown() then Character:Get(); Character:Save() end end)
GL:On("PLAYER_LOGOUT", function() Character:Save() end)
