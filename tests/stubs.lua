-- tests/stubs.lua: just enough of the WoW API to load the rating code outside the game.
local T = {}

T.items = {}   -- [link] = { name, equipLoc, classID, subclassID, reqLevel, quality, stats = {ITEM_MOD_...}, lines = {...} }
T.equipped = {} -- [slot] = link
T.player = {}

function T.Reset(p)
	T.player = p
	T.equipped = {}
end

local function frame()
	return { RegisterEvent = function() end, SetScript = function() end, UnregisterEvent = function() end }
end
CreateFrame = function() return frame() end
T.later = {}
-- short delays run at once; long ones (timeouts, retries) wait for T.RunLater()
C_Timer = { After = function(d, fn) if d <= 0.5 then fn() else table.insert(T.later, fn) end end }
function T.RunLater() local l = T.later; T.later = {}; for _, fn in ipairs(l) do fn() end end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print((m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end }
InCombatLockdown = function() return false end
SlashCmdList = {}
NUM_BAG_SLOTS = 4
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemLink = function() return nil end }

UnitLevel = function() return T.player.level end
UnitName = UnitName or function() return "Hex" end
time = time or os.time
GetRealmName = GetRealmName or function() return "Realm" end
UnitFactionGroup = UnitFactionGroup or function() return "Horde" end
UnitClass = function() return T.player.className, T.player.class end
UnitStat = function(_, i) local v = T.player.stats[i] return v, v, 0, 0 end
UnitAttackPower = function() return T.player.ap or 0, 0, 0 end
UnitRangedAttackPower = function() return T.player.rap or 0, 0, 0 end
GetSpellBonusDamage = function(i) return (T.player.sp and T.player.sp[i]) or T.player.spAll or 0 end
GetSpellBonusHealing = function() return T.player.heal or 0 end
GetCritChance = function() return T.player.crit or 5 end
GetRangedCritChance = function() return T.player.crit or 5 end
GetSpellCritChance = function() return T.player.scrit or 5 end
GetHitModifier = function() return T.player.hit or 0 end
GetSpellHitModifier = function() return T.player.shit or 0 end
UnitArmor = function() return T.player.armor, T.player.armor end
UnitHealthMax = function() return T.player.hp end
UnitPowerMax = function() return T.player.mana or 0 end
GetDodgeChance = function() return T.player.dodge or 5 end
GetParryChance = function() return T.player.parry or 0 end
GetBlockChance = function() return T.player.block or 0 end
GetShieldBlock = function() return T.player.blockval or 0 end
GetManaRegen = function() return T.player.regen or 0, T.player.regenIC or 0 end
CanDualWield = function() return T.player.dw or false end
GetInventoryItemLink = function(_, slot) return T.equipped[slot] end

-- T.source: recorded game data (tests/replay.lua) that answers the item functions instead of T.items
T.source = nil
C_Item = {}
C_Item.GetItemInfoInstant = function(link)
	if T.source then return T.source.GetItemInfoInstant(link) end
	local d = T.items[link]
	if not d then return nil end
	return tonumber(link:match("item:(%d+)")) or 1, nil, nil, d.equipLoc, nil, d.classID, d.subclassID
end
T.slow = {} -- links the "client" hasn't loaded yet
C_Item.GetItemInfo = function(link)
	if T.slow[link] then return nil end
	if T.source then return T.source.GetItemInfo(link) end
	local d = T.items[link]
	if not d then return nil end
	return d.name, link, d.quality or 2, d.ilvl or 30, d.reqLevel or 1, nil, nil, 1, d.equipLoc, 0, 100, d.classID, d.subclassID
end
C_Item.GetItemStats = function(link)
	if T.source then return T.source.GetItemStats(link) end
	local d = T.items[link]
	local t = {}
	for k, v in pairs(d and d.stats or {}) do t[k] = v end
	return t
end
C_TooltipInfo = {
	GetHyperlink = function(link)
		if T.source then return T.source.GetHyperlink(link) end
		local d = T.items[link]
		local lines = { { leftText = d and d.name or "?" } }
		for _, l in ipairs(d and d.lines or {}) do
			if type(l) == "table" then lines[#lines + 1] = l else lines[#lines + 1] = { leftText = l } end
		end
		return { lines = lines }
	end,
}

function T.Item(link, def) T.items[link] = def; return link end

function T.Load(root)
	local GL = {}
	for _, f in ipairs({ "Core.lua", "Data/Classes.lua", "Data/Specs.lua", "Data/Leveling.lua", "Items.lua", "Character.lua", "Model.lua", "Compare.lua" }) do
		local chunk = assert(loadfile(root .. "/" .. f))
		chunk("UpgradeBroker", GL)
	end
	GL:Fire("ADDON_LOADED", "UpgradeBroker")
	return GL
end

return T
