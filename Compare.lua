-- Compare.lua: what an item would replace, whether you can use it, and how much stronger it makes you.
local _, GL = ...

local Compare = {}
GL.Compare = Compare

local Items, Model = GL.Items, GL.Model

local SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
	[15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}
Compare.SLOT_NAMES = SLOT_NAMES

local caches = setmetatable({}, { __mode = "k" }) -- [snapshot] = { [link] = result }
local worth = setmetatable({}, { __mode = "k" })  -- [snapshot] = { [links of worn items] = percent they add }
function Compare:ClearCache()
	caches = setmetatable({}, { __mode = "k" })
	worth = setmetatable({}, { __mode = "k" })
end

---------------------------------------------------------------------------
-- Can you use it?
---------------------------------------------------------------------------
-- Armor and weapon type: can this class wear it at wearLevel? Returns ok, reason.
local function TypeOK(s, classID, sub, equipLoc, wearLevel)
	local C = GL.Classes
	if classID == 4 then
		sub = sub or 0
		if sub > 0 then
			if not C.armor[s.class][sub] then return false, "armor" end
			if sub <= 4 then
				if C.ArmorLearnLevel(s.class, sub) > wearLevel then return false, "armor" end
				if GL.db and GL.db.ownArmorOnly and equipLoc ~= "INVTYPE_CLOAK" and sub ~= C.MainArmor(s.class, wearLevel) then
					return false, "armor"
				end
			end
		end
	elseif classID == 2 then
		if not C.weapons[s.class][sub or -1] then return false, "weapon" end
		if equipLoc == "INVTYPE_WEAPONOFFHAND" and not s.canDualWield then return false, "weapon" end
	end
	return true
end

-- Returns ok, reason. reason "later" = you can wear it within the levels you look ahead (ok is true then).
function Compare.CanUse(s, item)
	-- red tooltip lines describe the character you play, not an alt
	if item.blocked and not s.isAlt then return false, "blocked" end
	-- a profession item (goggles, fishing poles): only with that profession at that rank
	if item.skillReq then
		local have = s.skills and s.skills[item.skillReq.name]
		if not have or have < item.skillReq.rank then return false, "skill" end
	end
	if item.classes then
		local name = s.classLocal or UnitClass("player")
		if name and not item.classes:find(name:lower(), 1, true) then return false, "class" end
	end
	local need = item.reqLevel or 0
	local later = need > s.level
	if later and need - s.level > (GL.db and GL.db.levelsAhead or 3) then return false, "level" end
	local ok, why = TypeOK(s, item.classID, item.subclassID, item.equipLoc, math.max(s.level, need))
	if not ok then return false, why end
	return true, later and "later" or nil
end

-- The reason a scanned item can never be worn, from what the client knows without reading its tooltip, or nil
-- when it takes a full look. Saves reading thousands of tooltips (plate for a mage) when the scan is rated.
function Compare.QuickReject(s, link)
	local _, _, _, equipLoc, _, classID, sub = Items.GetItemInfoInstant(link)
	if not classID then return nil end
	local ahead = GL.db and GL.db.levelsAhead or 3
	local need = select(5, Items.GetItemInfo(link))
	if need and need - s.level > ahead then return "level" end
	if need then
		local ok, why = TypeOK(s, classID, sub, equipLoc, math.max(s.level, need))
		return not ok and why or nil
	end
	-- level not known yet: only what holds at every level you look ahead to
	local ok, why = TypeOK(s, classID, sub, equipLoc, s.level)
	if ok or TypeOK(s, classID, sub, equipLoc, s.level + ahead) then return nil end
	return why
end

---------------------------------------------------------------------------
-- What goes where
---------------------------------------------------------------------------
local function W(item) return GL.Character.Weapon(item) end

-- Weapons and off hands in your bags, for "a one-hander needs something in the other hand". Read once per
-- snapshot (a bag change that adds or removes one starts a new snapshot).
local function BagWeapons(s)
	if s.bagWeaponItems then return s.bagWeaponItems end
	local list, complete = {}, true
	local links = s.isAlt and (s.bagWeaponLinks or {}) or GL.Character.BagWeaponLinks()
	for _, link in ipairs(links) do
		local item = Items.Get(link)
		if item then
			local ok, why = Compare.CanUse(s, item)
			if ok and why ~= "later" then list[#list + 1] = item end
		else
			complete = false
		end
	end
	-- an item the client is still loading: look again next time
	if complete then s.bagWeaponItems = list end
	return list
end

-- Every way to put the item on: { slot, label, add = {...}, remove = {...}, weapons = {...} }.
local function Options(s, item)
	local eq, kind, out = s.equipped, item.kind, {}
	local function opt(slot, add, remove, weapons, label)
		out[#out + 1] = { slot = slot, add = add, remove = remove, weapons = weapons, label = label or SLOT_NAMES[slot] }
	end
	local function sameUnique(slot) return item.unique and eq[slot] and eq[slot].id == item.id end

	if kind == nil or kind == "relic" or kind == "ranged" then
		local slots = item.slots
		if #slots == 2 then
			local a, b = slots[1], slots[2]
			-- a unique item you already wear in one slot can only replace that copy
			if sameUnique(a) then slots = { a } elseif sameUnique(b) then slots = { b } end
		end
		for _, slot in ipairs(slots) do
			opt(slot, { item }, { eq[slot] }, kind == "ranged" and { ranged = W(item) } or nil)
		end
		return out
	end

	local mh, oh = eq[16], eq[17]
	local twoHanded = mh and mh.kind == "2h"
	if kind == "2h" then
		opt(16, { item }, { mh, oh }, { mh = W(item), oh = false }, oh and "Main + Off Hand" or "Main Hand")
		return out
	end
	if kind == "1h" or kind == "mh" then
		if twoHanded then
			-- swapping a two-hander for a one-hander: the best off hand from your bags goes with it
			opt(16, { item }, { mh }, { mh = W(item), oh = false }, "Main Hand")
			for _, other in ipairs(BagWeapons(s)) do
				local ok = other.kind == "shield" or other.kind == "held"
					or ((other.kind == "1h" or other.kind == "ohw") and s.canDualWield)
				if ok and other ~= item then
					opt(16, { item, other }, { mh }, { mh = W(item), oh = (other.kind == "1h" or other.kind == "ohw") and W(other) or false },
						"Main Hand")
				end
			end
		elseif not sameUnique(17) then
			opt(16, { item }, { mh }, { mh = W(item) })
		end
		if kind == "1h" and s.canDualWield and not twoHanded and not sameUnique(16) then
			opt(17, { item }, { oh }, { oh = W(item) })
		end
		return out
	end
	-- off hand: shield, held item or off-hand weapon
	local ohWeapon = (kind == "ohw") and W(item) or false
	if twoHanded then
		for _, other in ipairs(BagWeapons(s)) do
			if other.kind == "1h" or other.kind == "mh" then
				opt(17, { item, other }, { mh }, { mh = W(other), oh = ohWeapon }, "Off Hand")
			end
		end
	else
		opt(17, { item }, { oh }, { oh = ohWeapon })
	end
	return out
end

---------------------------------------------------------------------------
-- Rating
---------------------------------------------------------------------------
-- Result: { item, ok, reason, gain = Model.Gain of the best option, slot, label, replaced = {items},
-- perSlot = { { label, gain, replaced } } for items with two places }. nil while the item is loading.
-- s: whose gear to compare with (Character:Viewed() for an alt); your own character when left out.
function Compare:Rate(link, s)
	s = s or GL.Character:Get()
	-- gear still loading: no rating rather than one against half your gear
	if not s or s.incomplete then return nil end
	local item = Items.Get(link)
	if not item then return nil end
	local cache = caches[s]
	if not cache then cache = {}; caches[s] = cache end
	local key = link
	local hit = cache[key]
	if hit then return hit end
	local ok, reason = Compare.CanUse(s, item)
	local res = { item = item, ok = ok, reason = reason, snap = s }
	if ok then
		local x0 = Model.Calibrate(s).x0
		local best, perSlot = nil, {}
		for _, o in ipairs(Options(s, item)) do
			local removes = {}
			for _, r in pairs(o.remove) do if r then removes[#removes + 1] = r end end
			local x = Model.Apply(s, x0, o.add, removes, o.weapons)
			local g = Model.Gain(s, x)
			-- wearing the very same item already: no change
			if #removes == 1 and removes[1].link == item.link then g.total, g.dmg, g.surv, g.sus = 0, 0, 0, 0 end
			local entry = { slot = o.slot, label = o.label, gain = g, replaced = removes, with = o.add, weapons = o.weapons }
			if not perSlot[o.slot] or g.total > perSlot[o.slot].gain.total then perSlot[o.slot] = entry end
			if not best or g.total > best.gain.total then best = entry end
		end
		if best then
			res.gain, res.slot, res.label, res.replaced, res.with, res.weapons = best.gain, best.slot, best.label, best.replaced, best.with, best.weapons
			local list = {}
			for _, e in pairs(perSlot) do list[#list + 1] = e end
			table.sort(list, function(a, b) return a.slot < b.slot end)
			if #list > 1 then res.perSlot = list end
		else
			res.ok, res.reason = false, "slot"
		end
	end
	cache[key] = res
	return res
end

-- Is it worth calling an upgrade?
function Compare.IsUpgrade(res)
	return res and res.ok and res.gain and res.gain.total >= ((GL.db and GL.db.minGain) or 0.5)
end

-- How big a gain is for one item. One item rarely moves the whole character more than 1 to 3 %.
function Compare.SizeLabel(p)
	if p >= 2 then return "Big upgrade" end
	if p >= 0.8 then return "Good upgrade" end
	return "Minor upgrade"
end

-- What the worn items add to the character, in percent (taking them off loses that much).
local function Worth(s, items)
	local keys = {}
	for i, it in ipairs(items) do keys[i] = it.link or tostring(it) end
	local key = table.concat(keys, ";")
	local cache = worth[s]
	if not cache then cache = {}; worth[s] = cache end
	if cache[key] == nil then
		local eq, weapons = s.equipped, {}
		for _, it in ipairs(items) do
			if it == eq[16] then weapons.mh = false elseif it == eq[17] then weapons.oh = false
			elseif it == eq[18] then weapons.ranged = false end
		end
		local x = Model.Apply(s, Model.Calibrate(s).x0, nil, items, next(weapons) and weapons or nil)
		cache[key] = -Model.Gain(s, x).total
	end
	return cache[key]
end

-- Item vs worn: how much more the new item adds than the worn one, both measured on your character.
-- nil when the slot is empty or the worn item adds (next to) nothing.
function Compare.ItemGain(s, total, replaced)
	if not (s and replaced and #replaced > 0) then return nil end
	local w = Worth(s, replaced)
	if w < 0.05 then return nil end
	return total / w * 100
end

-- The percent shown for one item: the whole-character gain, or item vs worn when that's chosen in the settings.
-- entry: one of res.perSlot (a ring's other slot) instead of the best option.
function Compare.PctText(res, entry, decimals)
	local e = entry or res
	if GL.db and GL.db.itemPct then
		local p = Compare.ItemGain(res.snap, e.gain.total, e.replaced)
		if not p then return "New" end
		return GL.Pct(math.min(p, 999))
	end
	return GL.Pct(e.gain.total, nil, decimals)
end

-- The stats that change: { { key, delta } }, biggest change in value first is not knowable per stat,
-- so: percent stats and weapon DPS first, then by size.
function Compare.StatDiff(res)
	local d = {}
	for _, it in ipairs(res.with or { res.item }) do
		for k, v in pairs(it.stats) do if k ~= "SPEED" then d[k] = (d[k] or 0) + v end end
	end
	for _, it in ipairs(res.replaced or {}) do
		for k, v in pairs(it.stats) do if k ~= "SPEED" then d[k] = (d[k] or 0) - v end end
	end
	local list = {}
	for k, v in pairs(d) do
		if math.abs(v) >= 0.05 and Items.LABELS[k] then list[#list + 1] = { key = k, delta = v } end
	end
	local rank = function(e) return (Items.PERCENT[e.key] and 10 or 1) * math.abs(e.delta) * (e.key == "ARMOR" and 0.05 or 1) end
	table.sort(list, function(a, b) return rank(a) > rank(b) end)
	return list
end

-- Why an item is better: what each changed stat adds on its own, scaled so the parts add up to the total.
-- Returns the StatDiff list with .pct on every entry, biggest effect first. The weapon swap itself (its
-- damage per second) counts as the "DPS" entry.
function Compare.Contributions(res)
	if res.contrib then return res.contrib end
	local s = res.snap or GL.Character:Get()
	if not (s and res.ok and res.gain) then return Compare.StatDiff(res) end
	local x0 = Model.Calibrate(s).x0
	local list = {}
	-- the weapon swap itself (weapon damage, a second hand, a shield), apart from the stats on the weapons
	-- first the loadout change itself (weapon damage, one or two hands, a shield and its block), with the items'
	-- stats left out; then each stat on top of that loadout
	local function bare(items)
		local t = {}
		for _, it in ipairs(items or {}) do t[#t + 1] = { kind = it.kind, stats = {} } end
		return t
	end
	local xw = Model.Apply(s, x0, bare(res.with), bare(res.replaced), res.weapons)
	local gw = Model.Gain(s, xw).total
	local dps = 0
	for _, it in ipairs(res.with or {}) do dps = dps + (it.stats.DPS or 0) end
	for _, it in ipairs(res.replaced or {}) do dps = dps - (it.stats.DPS or 0) end
	local shieldChange = (xw.shield and true or false) ~= (x0.shield and true or false)
	if math.abs(gw) >= 0.05 then
		local twoHands = #(res.replaced or {}) > 1 or #(res.with or {}) > 1
		local text
		-- a shield on or off on its own is "Shield block" / "No shield"; with weapon damage changing too it is
		-- all one weapon swap (a two-hander for sword and board)
		if shieldChange and math.abs(dps) < 0.05 and not twoHands then text = xw.shield and "Shield block" or "No shield block"
		elseif shieldChange or twoHands or math.abs(dps) < 0.05 then text = "Weapon swap" end
		list[#list + 1] = { key = "DPS", delta = dps, pct = gw, text = text }
	end
	local sum = gw
	for _, e in ipairs(Compare.StatDiff(res)) do
		if e.key ~= "DPS" then
			local x = Model.Apply(s, xw, { { stats = { [e.key] = e.delta } } }, {})
			e.pct = Model.Gain(s, x).total - gw
			sum = sum + e.pct
			list[#list + 1] = e
		end
	end
	-- stats work together (crit is worth more with more spell damage): when the parts point the same way as the
	-- total, they are scaled to add up to it; otherwise what is left shows as its own line
	local total = res.gain.total
	if math.abs(sum) > 0.01 and sum * total > 0 then
		for _, e in ipairs(list) do e.pct = e.pct * total / sum end
	elseif math.abs(total - sum) >= 0.1 then
		list[#list + 1] = { key = "COMBINED", delta = 0, pct = total - sum, text = "Combined effect" }
	end
	table.sort(list, function(a, b) return math.abs(a.pct) > math.abs(b.pct) end)
	res.contrib = list
	return list
end

-- At most n rows for a small space: when more stats changed, the last row sums up the rest, so the rows
-- shown always add up to the total.
function Compare.TopRows(list, n)
	if #list <= n then return list end
	local out, rest = {}, 0
	for i, e in ipairs(list) do
		if i < n then out[i] = e else rest = rest + (e.pct or 0) end
	end
	out[n] = { key = "OTHER", delta = 0, pct = rest, text = "Other stats" }
	return out
end

function Compare.FormatStat(e)
	if e.text then return e.text, (e.pct or 0) >= 0 end
	local v = e.delta
	local num
	if Items.PERCENT[e.key] then num = ("%g%%"):format(math.floor(math.abs(v) * 10 + 0.5) / 10)
	elseif e.key == "DPS" then num = ("%.1f"):format(math.abs(v))
	else num = ("%d"):format(math.floor(math.abs(v) + 0.5)) end
	return (v >= 0 and "+" or "\226\136\146") .. num .. " " .. Items.LABELS[e.key], v >= 0
end

local REASON_TEXT = {
	blocked = "requirements not met",
	class = "wrong class",
	level = "level too high",
	armor = "wrong armor type",
	weapon = "can't use this weapon",
	slot = "can't equip with current gear",
	skill = "profession skill required",
}

-- /ub item <link>: the full rating in chat.
function Compare:Explain(link)
	local res = self:Rate(link)
	if not res then return GL:Print("Still loading that item. Try again.") end
	if not res.ok then return GL:Print(link .. ": can't equip (" .. (REASON_TEXT[res.reason] or tostring(res.reason)) .. ")") end
	local g = res.gain
	GL:Print(("%s in %s: %s (Damage %s, Survival %s, Mana %s)"):format(link, res.label, GL.Pct(g.total), GL.Pct(g.dmg),
		GL.Pct(g.surv), GL.Pct(g.sus)))
	for _, e in ipairs(res.perSlot or {}) do GL:Print(("  %s: %s"):format(e.label, GL.Pct(e.gain.total))) end
	local c0, c1 = g.cycle0, g.cycle
	if c0 and c1 then
		GL:Print(("  Per kill: fighting %.1f s -> %.1f s, resting %.1f s -> %.1f s, sitting %.1f s -> %.1f s, walking %.0f s"):format(
			c0.fight, c1.fight, c0.rest, c1.rest, c0.stops, c1.stops, c0.travel))
	end
	local parts = {}
	for _, e in ipairs(Compare.Contributions(res)) do parts[#parts + 1] = (Compare.FormatStat(e)) .. " " .. GL.Pct(e.pct or 0) end
	GL:Print("  " .. table.concat(parts, ", "))
end
