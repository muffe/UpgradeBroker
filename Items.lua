-- Items.lua: reads an item's stats into one table with our own stat names.
--
-- Stat names (percent stats are in percent, WoW Forever's own unit on tooltips):
--   STR AGI STA INT SPI            primary stats
--   ARMOR HP MANA                  armor (base and bonus), extra health and mana
--   AP RAP FAP                     attack power (melee and ranged), ranged only, in cat/bear form only
--   SP SP_<SCHOOL> HEAL            spell damage (all schools / one school), healing
--   CRIT SCRIT HIT SHIT HASTE MHASTE EXP    crit, spell-only crit, hit, spell-only hit, haste, attack-only haste, expertise
--   DEF DODGE PARRY BLOCK BLOCKVAL tank stats (defense in skill points)
--   MP5 HP5                        regeneration
--   DPS SPEED                      weapon damage per second and speed
-- WoW Forever's GetItemStats reports percent stats as ratings (1% crit = 14), so they are read from the
-- tooltip where it says "... by 1%" and only converted from the rating when the tooltip can't be read.
local _, GL = ...

local Items = {}
GL.Items = Items

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
Items.GetItemInfo, Items.GetItemInfoInstant = GetItemInfo, GetItemInfoInstant

-- Rating for 1% on WoW Forever (wowsims/forever ui/sim/constants/mechanics.ts).
local RATING = { CRIT = 14, SCRIT = 14, HIT = 10, SHIT = 10, HASTE = 10, EXP = 10, DODGE = 12, PARRY = 15, BLOCK = 5 }

local STAT_KEYS = {
	STRENGTH = "STR", AGILITY = "AGI", STAMINA = "STA", INTELLECT = "INT", SPIRIT = "SPI",
	RESISTANCE0 = "ARMOR", EXTRA_ARMOR = "ARMOR", DAMAGE_PER_SECOND = "DPS",
	ATTACK_POWER = "AP", RANGED_ATTACK_POWER = "RAP", FERAL_ATTACK_POWER = "FAP",
	SPELL_POWER = "SP", SPELL_DAMAGE_DONE = "SP", SPELL_HEALING_DONE = "HEAL",
	MANA_REGENERATION = "MP5", POWER_REGEN0 = "MP5", HEALTH_REGEN = "HP5", HEALTH = "HP", MANA = "MANA",
	CRIT = "CRIT", CRIT_MELEE = "CRIT", CRIT_RANGED = "CRIT", CRIT_SPELL = "SCRIT",
	HIT = "HIT", HIT_MELEE = "HIT", HIT_RANGED = "HIT", HIT_SPELL = "SHIT",
	HASTE = "HASTE", SPELL_HASTE = "HASTE", EXPERTISE = "EXP",
	DEFENSE_SKILL = "DEF", DODGE = "DODGE", PARRY = "PARRY", BLOCK = "BLOCK", BLOCK_VALUE = "BLOCKVAL",
}

local function KeyOf(blizzKey)
	local s = blizzKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_NAME$", ""):gsub("_RATING$", "")
	return STAT_KEYS[s], RATING[STAT_KEYS[s] or ""] ~= nil
end
Items.KeyOf = KeyOf

local SCHOOLS = { "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }

---------------------------------------------------------------------------
-- Tooltip text (English client; other languages fall back to GetItemStats)
---------------------------------------------------------------------------
-- Each rule: a pattern on the lower-cased line and the stat it gives. First match wins.
local PCT_RULES = {
	{ "critical strike with spells by (%d+%.?%d*)%%", "SCRIT" },
	{ "critical strike[^%d]* by (%d+%.?%d*)%%", "CRIT" },
	{ "hit with spells by (%d+%.?%d*)%%", "SHIT" },
	{ "chance to hit[^%d]* by (%d+%.?%d*)%%", "HIT" },
	{ "dodged or parried by (%d+%.?%d*)%%", "EXP" },
	{ "attack and casting speed by (%d+%.?%d*)%%", "HASTE" },
	{ "casting speed[^%d]* by (%d+%.?%d*)%%", "HASTE" },
	{ "haste[^%d]* by (%d+%.?%d*)%%", "HASTE" },
	{ "attack speed by (%d+%.?%d*)%%", "MHASTE" },
	{ "dodge an attack by (%d+%.?%d*)%%", "DODGE" },
	{ "parry an attack by (%d+%.?%d*)%%", "PARRY" },
	{ "block attacks with a shield by (%d+%.?%d*)%%", "BLOCK" },
}
local FLAT_RULES = {
	{ "damage and healing done by magical spells and effects by up to (%d+)", "SP", "HEAL" },
	{ "healing done by spells and effects by up to (%d+)", "HEAL" },
	{ "healing spells and effects by up to (%d+)", "HEAL" },
	{ "block value of your shield by (%d+)", "BLOCKVAL" },
	{ "increased defense %+(%d+)", "DEF" },
	{ "defense skill by (%d+)", "DEF" },
	{ "restores (%d+) mana per 5 sec", "MP5" },
	{ "(%d+) mana per 5 sec", "MP5" },
	{ "restores (%d+) health per 5 sec", "HP5" },
	{ "%+(%d+) attack power in cat, bear", "FAP" },
	{ "attack power by (%d+) in cat, bear", "FAP" },
	{ "%+(%d+) ranged attack power", "RAP" },
	{ "ranged attack power by (%d+)", "RAP" },
	{ "%+(%d+) attack power", "AP" },
	{ "attack power by (%d+)", "AP" },
}

local function Lower(t) return t and t:lower() or nil end

-- Reads the item's tooltip: percent stats, Equip: lines GetItemStats may miss, the weapon speed and flags.
local function ReadTooltip(link, out, meta)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return false end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
	local pct, flat = {}, {}
	local classesPrefix = Lower((_G.ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s.*$", ""))
	for i, line in ipairs(data.lines) do
		local raw = GL.Plain(line.leftText)
		local t = Lower(raw)
		if t and i > 1 then
			local c = line.leftColor
			-- a red line (a profession, class, race or weapon skill you lack) makes the item unusable;
			-- the level line is handled from GetItemInfo, so items you will wear soon stay in the list
			if c and (c.r or 0) > 0.9 and (c.g or 1) < 0.25 and (c.b or 1) < 0.25 and not t:find("level") then
				meta.blocked = raw
			end
			-- the weapon type on the right ("Bow") is red when you can't use it. Armor types are left to
			-- Compare.CanUse, which knows that plate and mail come at level 40.
			local rc, rt = line.rightColor, GL.Plain(line.rightText)
			if meta.classID ~= 4 and rc and rt and (rc.r or 0) > 0.9 and (rc.g or 1) < 0.25 and (rc.b or 1) < 0.25 then
				meta.blocked = rt
			end
			if t:find("^use:") or t:find("^chance on hit") then
				meta.effect = true
			elseif t:find("^set:") or t:find("^%(%d+%) set") then
				meta.set = true
			elseif t:find("^unique") then
				meta.unique = true
			elseif classesPrefix and t:sub(1, #classesPrefix) == classesPrefix then
				meta.classes = t:sub(#classesPrefix + 1)
			elseif t:find("^equip:") and not t:find("when fighting") and not t:find("for %d+ sec") then
				local matched = false
				for _, r in ipairs(PCT_RULES) do
					local v = tonumber(t:match(r[1]))
					if v then pct[r[2]] = (pct[r[2]] or 0) + v; matched = true break end
				end
				if not matched then
					for _, school in ipairs(SCHOOLS) do
						local v = tonumber(t:match("damage done by " .. school:lower() .. " spells and effects by up to (%d+)"))
						if v then flat["SP_" .. school] = (flat["SP_" .. school] or 0) + v; matched = true break end
					end
				end
				if not matched then
					for _, r in ipairs(FLAT_RULES) do
						local v = tonumber(t:match(r[1]))
						if v then
							flat[r[2]] = (flat[r[2]] or 0) + v
							if r[3] then flat[r[3]] = (flat[r[3]] or 0) + v end
							matched = true break
						end
					end
				end
				if not matched then meta.effect = true end
			end
			-- a profession the item needs ("Requires Engineering (150)"); checked against the character's skills
			local skill, rank = raw:match("^Requires (.-) %((%d+)%)$")
			if skill and not skill:lower():find("level") then meta.skillReq = { name = skill:lower(), rank = tonumber(rank) } end
			-- a shield's own block value ("40 Block"), when GetItemStats leaves it out
			local blockValue = tonumber(t:match("^(%d+) block$"))
			if blockValue then flat.BLOCKVAL = (flat.BLOCKVAL or 0) + blockValue end
			local right = GL.Plain(line.rightText)
			local speed = right and tonumber(right:match("(%d+%.%d+)"))
			if speed and right:lower():find("speed") then out.SPEED = speed end
		end
	end
	-- percent stats: the tooltip is exact, so it replaces every value converted from a rating
	if next(pct) then
		for k in pairs(RATING) do out[k] = nil end
		for k, v in pairs(pct) do out[k] = v end
	end
	-- "+10 Shadow Spell Damage" may come from GetItemStats as spell damage for every school
	local schoolSum = 0
	for _, school in ipairs(SCHOOLS) do schoolSum = schoolSum + (flat["SP_" .. school] or 0) end
	if schoolSum > 0 and not flat.SP and out.SP and math.abs(out.SP - schoolSum) < 0.5 then out.SP = nil end
	-- flat stats: only where GetItemStats had nothing (it usually has them; the text is a fallback)
	for k, v in pairs(flat) do
		-- (a shield's base block value comes only from the text, on top of any Equip: bonus GetItemStats knows)
		if out[k] == nil or (k == "BLOCKVAL" and v > out[k]) then out[k] = v end
	end
	return true
end

---------------------------------------------------------------------------
-- Item info
---------------------------------------------------------------------------
-- What kind of thing goes where. slots: inventory slots it can go into.
local EQUIP = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Items.EQUIP = EQUIP
local KIND = {
	INVTYPE_2HWEAPON = "2h", INVTYPE_WEAPON = "1h", INVTYPE_WEAPONMAINHAND = "mh", INVTYPE_WEAPONOFFHAND = "ohw",
	INVTYPE_SHIELD = "shield", INVTYPE_HOLDABLE = "held", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged",
	INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "relic",
}

local cache = {}       -- [link] = item
local waiting = {}     -- [itemID] = GetTime() of the request while the client loads it
function Items.ClearCache() cache = {} end

-- An item: { link, id, name, icon, quality, ilvl, reqLevel, equipLoc, slots, kind, classID, subclassID,
-- stats = {...}, unique, effect, set, blocked, classes, sell }. nil while the client is still loading it
-- (GL_ITEM_LOADED fires when it arrives) or when it isn't gear.
function Items.Get(link)
	if type(link) ~= "string" then return nil end
	local hit = cache[link]
	if hit ~= nil then return hit or nil end
	local id, _, _, equipLoc = GetItemInfoInstant(link)
	if not id or not EQUIP[equipLoc or ""] then cache[link] = false return nil end
	local name, _, quality, ilvl, reqLevel, _, _, _, _, icon, sell, classID, subclassID = GetItemInfo(link)
	if not name then
		-- asked again when no answer came (the game drops items it has loaded to make room for others)
		local now = GetTime and GetTime() or 0
		if not waiting[id] or now - waiting[id] > 5 then
			waiting[id] = now
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		end
		return nil
	end
	local stats, raw = {}, GetItemStats and GetItemStats(link) or {}
	for k, v in pairs(raw) do
		local key = KeyOf(k)
		v = GL.Plain(v)
		if key and type(v) == "number" then
			stats[key] = (stats[key] or 0) + (RATING[key] and v / RATING[key] or v)
		end
	end
	local item = {
		link = link, id = id, name = name, icon = icon, quality = quality or 1, ilvl = ilvl or 0,
		reqLevel = reqLevel or 0, equipLoc = equipLoc, slots = EQUIP[equipLoc], kind = KIND[equipLoc],
		classID = classID, subclassID = subclassID, sell = sell or 0, stats = stats,
	}
	if not ReadTooltip(link, stats, item) then return nil end
	if stats.DPS and not stats.SPEED then stats.SPEED = 2.5 end
	if (C_Item and C_Item.GetItemUniquenessByID) then
		local ok, isUnique, _, limit = pcall(C_Item.GetItemUniquenessByID, id)
		if ok and (isUnique or limit == 1) then item.unique = true end
	end
	cache[link] = item
	return item
end

GL:On("GET_ITEM_INFO_RECEIVED", function(id, ok)
	if id and waiting[id] then
		waiting[id] = nil
		GL:Fire("GL_ITEM_LOADED", id)
	end
end)

-- Human names for the stats, for the stat lines under an upgrade.
Items.LABELS = {
	STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit", ARMOR = "Armor",
	HP = "Health", MANA = "Mana", AP = "Attack Power", RAP = "Ranged Attack Power", FAP = "Feral Attack Power",
	SP = "Spell Damage", HEAL = "Healing", CRIT = "Crit", SCRIT = "Spell Crit", HIT = "Hit", SHIT = "Spell Hit",
	HASTE = "Haste", MHASTE = "Attack Speed", EXP = "Expertise", DEF = "Defense", DODGE = "Dodge", PARRY = "Parry",
	BLOCK = "Block", BLOCKVAL = "Block Value", MP5 = "Mana/5s", HP5 = "Health/5s", DPS = "Weapon DPS",
	SP_HOLY = "Holy Damage", SP_FIRE = "Fire Damage", SP_NATURE = "Nature Damage", SP_FROST = "Frost Damage",
	SP_SHADOW = "Shadow Damage", SP_ARCANE = "Arcane Damage",
}
Items.PERCENT = { CRIT = true, SCRIT = true, HIT = true, SHIT = true, HASTE = true, MHASTE = true, EXP = true,
	DODGE = true, PARRY = true, BLOCK = true }
Items.SCHOOLS = SCHOOLS

-- red tooltip lines (a weapon skill or level you lacked) can change when you level or learn a skill
GL:On("PLAYER_LEVEL_UP", function() Items.ClearCache() end)
GL:On("SKILL_LINES_CHANGED", function() Items.ClearCache() end)
