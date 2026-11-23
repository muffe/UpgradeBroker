-- Core.lua: namespace, saved settings, a tiny event bus and the slash command.
local ADDON, GL = ...
_G.UpgradeBroker = GL

GL.name = ADDON
GL.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local DEFAULTS = {
	maxPrice = 10 * 10000,   -- copper
	ownArmorOnly = true,     -- only the armor type a class is meant to wear from level 40 (mail / plate)
	levelsAhead = 3,         -- also list gear you can wear within this many levels
	minGain = 0.5,           -- percent; smaller gains are not called upgrades
	order = "value",         -- slot list order: value | gain | slot
	bagMarkers = true,
	questMarkers = true,
	tooltip = true,
	itemPct = false,         -- show item vs worn instead of the whole-character gain
	scans = {},              -- [realm-faction] = { time = t, items = { [key] = "price|link" } }
}
local CHAR_DEFAULTS = {
	spec = nil,              -- spec key; nil = detect
	mode = nil,              -- "level" | "endgame"; nil = by level
}

local function Fill(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then dst[k] = {} Fill(dst[k], v) else dst[k] = v end
		end
	end
end

---------------------------------------------------------------------------
-- Events: GL:On(event, fn) for game events and our own messages (GL:Fire).
---------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame")
GL.eventFrame = frame

function GL:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^GL_") then pcall(frame.RegisterEvent, frame, event) end
	end
	table.insert(handlers[event], fn)
end

function GL:Fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then GL:Error(err) end
	end
end

frame:SetScript("OnEvent", function(_, event, ...) GL:Fire(event, ...) end)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
function GL:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffdca77fUpgrade Broker|r " .. tostring(msg))
end

local lastError
function GL:Error(err)
	if err ~= lastError then
		lastError = err
		GL:Print("|cffff6060" .. tostring(err) .. "|r")
	end
end

-- 12g 40s 5c; zero parts are left out.
function GL.Money(c, plain)
	c = math.floor((c or 0) + 0.5)
	local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local G, S, C = "|cffffd100", "|cffc7c7cf", "|cffeda55f"
	if plain then G, S, C = "", "", "" end
	local E = plain and "" or "|r"
	local out = {}
	if g > 0 then out[#out + 1] = G .. g .. "g" .. E end
	if s > 0 and g < 100 then out[#out + 1] = S .. s .. "s" .. E end
	if (cu > 0 and g == 0) or #out == 0 then out[#out + 1] = C .. cu .. "c" .. E end
	return table.concat(out, " ")
end

-- Short price for tight columns: 7.9g, 12g, 85s, 40c.
function GL.MoneyShort(c, plain)
	c = math.floor((c or 0) + 0.5)
	local text, color
	if c >= 100000 then text, color = ("%dg"):format(c / 10000), "ffd100"
	elseif c >= 10000 then text, color = (("%.1f"):format(c / 10000):gsub("%.0$", "")) .. "g", "ffd100"
	elseif c >= 100 then text, color = ("%ds"):format(c / 100), "c7c7cf"
	else text, color = ("%dc"):format(c), "eda55f" end
	if plain then return text end
	return "|cff" .. color .. text .. "|r"
end

-- "+1.0 s", "−0.3 s", "0.0 s"
function GL.Seconds(v)
	local s = ("%.1f s"):format(math.abs(v))
	if v >= 0.05 then return "+" .. s end
	if v <= -0.05 then return "\226\136\146" .. s end
	return s
end

-- "+4.8%", "+0.6%", "-1.2%" (one decimal; whole numbers from 10 up)
-- decimals: 2 to tell apart neighbours that look equal with one (+0.72% / +0.68%)
function GL.Pct(p, signed, decimals)
	if math.abs(p) < (decimals == 2 and 0.005 or 0.05) then return "0%" end
	local s = math.abs(p) >= 9.95 and ("%.0f"):format(p) or (decimals == 2 and ("%.2f"):format(p) or ("%.1f"):format(p))
	if signed ~= false and p > 0 then s = "+" .. s end
	return (s:gsub("^%-", "\226\136\146")) .. "%" -- a real minus sign
end

function GL.PlayerLevel() return UnitLevel("player") or 1 end

-- "Realm-Faction" for saved scans and characters. WoW Forever reports no realm name at all (empty), so the key
-- is then "-Horde": one list per faction, as before. nil only before the faction is known.
function GL.RealmKey()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
	if realm == "" then realm = GetRealmName() or "" end
	local faction = UnitFactionGroup("player")
	if not faction then return nil end
	return realm .. "-" .. faction
end

-- data saved under an empty realm name by earlier versions moves to the real one
GL:On("PLAYER_ENTERING_WORLD", function()
	local key, faction = GL.RealmKey(), UnitFactionGroup("player")
	if not (key and faction and GL.db) or key == "-" .. faction then return end
	for _, field in ipairs({ "chars", "scans" }) do
		local t = GL.db[field]
		local old = t and t["-" .. faction]
		if old then
			t[key] = t[key] or {}
			if field == "chars" then for name, d in pairs(old) do t[key][name] = t[key][name] or d end else t[key] = t[key].items and t[key] or old end
			t["-" .. faction] = nil
		end
	end
end)
function GL.PlayerClass() local _, c = UnitClass("player"); return c end

-- Values the client hides from addons (in combat) count as missing.
function GL.Plain(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
	return v
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- The alt the window shows (GL.viewing), or nil for the character you play.
local function ViewedAlt() return GL.viewing and GL.Character and GL.Character:AltData(GL.viewing) end

-- Leveling or endgame: your choice, else by level. For the character you play unless alt is true.
function GL:Mode(alt)
	local d = alt ~= false and ViewedAlt()
	if alt and d then return d.mode or (d.level >= 60 and "endgame" or "level") end
	local m = UpgradeBrokerCharDB and UpgradeBrokerCharDB.mode
	if m then return m end
	return GL.PlayerLevel() >= 60 and "endgame" or "level"
end

-- Spec and mode set in the window apply to whoever it shows.
function GL:SetMode(m)
	local d = ViewedAlt()
	if d then d.mode = m else UpgradeBrokerCharDB.mode = m end
	GL:Invalidate()
end

function GL:SetSpec(key)
	local d = ViewedAlt()
	if d then d.spec = key
	else
		-- remembered for the talents you have now; after a respec the detected spec is back
		UpgradeBrokerCharDB.spec = key
		UpgradeBrokerCharDB.specFor = GL.Character.DetectSpec(GL.PlayerClass())
	end
	GL:Invalidate()
end

function GL:SetViewing(name)
	GL.viewing = name
	-- the list belongs to whoever it was rated for
	if GL.Scanner then
		GL.Scanner:CancelRating()
		GL.Scanner.results, GL.Scanner.above, GL.Scanner.all = nil, nil, nil
		GL.Scanner.loadTries = 0; GL.Scanner.loadFailed = nil
		GL:Fire("GL_RESULTS")
	end
	GL:Invalidate()
end

-- Something that changes every rating happened (gear, spec, mode, level): drop caches and tell the UI.
-- In combat it waits for the fight to end: the client hides some totals in combat, and a snapshot built then
-- would rate everything against them.
local pending, afterCombat
function GL:Invalidate()
	if InCombatLockdown and InCombatLockdown() then afterCombat = true return end
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		if GL.Character then GL.Character:Invalidate() end
		if GL.Compare then GL.Compare:ClearCache() end
		GL:Fire("GL_CHANGED")
	end)
end
GL:On("PLAYER_REGEN_ENABLED", function()
	if afterCombat then afterCombat = false; GL:Invalidate() end
end)

GL:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	UpgradeBrokerDB = UpgradeBrokerDB or {}
	UpgradeBrokerCharDB = UpgradeBrokerCharDB or {}
	Fill(UpgradeBrokerDB, DEFAULTS)
	Fill(UpgradeBrokerCharDB, CHAR_DEFAULTS)
	if UpgradeBrokerDB.order == "slot" then UpgradeBrokerDB.order = "value" end -- the list is always in slot order now
	GL.db, GL.cdb = UpgradeBrokerDB, UpgradeBrokerCharDB
	GL:Fire("GL_LOADED")
end)

function GL.FillDefaults() Fill(UpgradeBrokerDB, DEFAULTS) end

for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
	"ACTIVE_TALENT_GROUP_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
	GL:On(e, function(unit)
		if e == "UNIT_INVENTORY_CHANGED" then
			-- it also fires for loot and durability; only a change in what you wear counts
			if unit ~= "player" then return end
			local links = {}
			for slot = 1, 19 do links[slot] = GetInventoryItemLink("player", slot) or "" end
			local worn = table.concat(links, ";")
			if worn == GL.lastWorn then return end
			GL.lastWorn = worn
		end
		GL:Invalidate()
	end)
end
GL:On("PLAYER_ENTERING_WORLD", function() GL:Invalidate() end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_UPGRADEBROKER1, SLASH_UPGRADEBROKER2 = "/upgradebroker", "/ub"
SlashCmdList.UPGRADEBROKER = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "options" or msg == "config" then
		GL:OpenOptions()
	elseif msg:find("^item") or msg:find("|Hitem:") then
		local link = msg:match("(|c.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
		if link and GL.Compare then GL.Compare:Explain(link) end
	elseif msg == "why" then
		GL.Scanner:Explain()
	elseif msg:find("^forget ") then
		local name = msg:match("^forget%s+(.+)$")
		local saved = GL.Character:Forget(name)
		if saved then
			if GL.viewing == saved then GL:SetViewing(nil) end
			GL:Print("Removed " .. saved .. " from saved characters.")
		else
			GL:Print("No saved character named " .. tostring(name) .. ".")
		end
	elseif msg:find("^set ") then
		GL.Options:Toggle(msg:match("^set%s+(%S+)"))
	elseif msg == "debug" then
		GL.Character:Dump()
	else
		GL.Window:Toggle()
	end
end

function UpgradeBroker_OnCompartmentClick() GL.Window:Toggle() end

function GL:OpenOptions()
	if EllesmereUI and EllesmereUI.OpenPlugin and EllesmereUI.IsPluginRegistered and EllesmereUI.IsPluginRegistered(ADDON) then
		EllesmereUI.OpenPlugin(ADDON)
	elseif GL.Options and GL.Options.Open then
		GL.Options:Open()
	end
end
