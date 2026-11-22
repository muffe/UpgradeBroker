-- tests/ui.lua: lua5.1 tests/ui.lua. Loads the whole addon against mock frames and walks through the window,
-- the auction house tab, a scan, tooltips, bags and quest rewards, to catch runtime errors outside the game.
package.path = "tests/?.lua;" .. package.path
local T = require("stubs")

---------------------------------------------------------------------------
-- Mock widgets: every method exists; a few remember state.
---------------------------------------------------------------------------
local Mock = {}
local function new(kind, name)
	local o = { _kind = kind, _shown = kind ~= "Frame-hidden", _scripts = {}, _points = 0, _name = name, _text = "", _value = 0, _w = 300, _h = 300 }
	return setmetatable(o, Mock)
end
local methods = {
	Show = function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end,
	Hide = function(self) local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end,
	IsShown = function(self) return self._shown end,
	IsVisible = function(self) return self._shown end,
	SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
	SetScript = function(self, k, fn) self._scripts[k] = fn end,
	GetScript = function(self, k) return self._scripts[k] end,
	HookScript = function() end,
	CreateTexture = function() return new("Texture") end,
	CreateFontString = function() return new("FontString") end,
	SetFont = function() return true end,
	GetStringWidth = function(self) return #(self._text or "") * 6 end,
	SetText = function(self, t) self._text = t end,
	GetText = function(self) return self._text end,
	GetWidth = function(self) return self._w end,
	GetHeight = function(self) return self._h end,
	SetSize = function(self, w, h) self._w, self._h = w, h end,
	SetWidth = function(self, w) self._w = w end,
	SetHeight = function(self, h) self._h = h end,
	GetFrameLevel = function() return 1 end,
	GetFrameStrata = function() return "HIGH" end,
	IsEnabled = function(self) return not self._disabled end,
	Enable = function(self) self._disabled = false end,
	Disable = function(self) self._disabled = true end,
	SetEnabled = function(self, v) self._disabled = not v end,
	IsMouseOver = function() return false end,
	HasFocus = function() return false end,
	GetValue = function(self) return self._value end,
	SetValue = function(self, v) self._value = v; if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v, false) end end,
	GetName = function(self) return self._name end,
	GetID = function(self) return self._id or 0 end,
	GetParent = function(self) return self._parent end,
	IsForbidden = function() return false end,
	Click = function(self) if self._scripts.OnClick then self._scripts.OnClick(self) end end,
	EnumerateValidItems = function() return function() return nil end end,
	IsObjectType = function() return true end,
}
Mock.__index = function(self, k)
	if methods[k] then return methods[k] end
	return function() end
end

CreateFrame = function(kind, name, parent)
	local f = new(kind, name)
	f._parent = parent
	if name then _G[name] = f end
	return f
end
UIParent = new("Frame")
GameTooltip = new("GameTooltip")
GameTooltip.AddLine = function(self, t) self._lines = self._lines or {}; table.insert(self._lines, t) end
GameTooltip.AddDoubleLine = function(self, a, b) self._lines = self._lines or {}; table.insert(self._lines, a .. "  " .. b) end
UISpecialFrames = {}
STANDARD_TEXT_FONT = "font"
hooksecurefunc = function(a, b, c) end
time = os.time
GetTime = os.clock
debugprofilestop = function() return os.clock() * 1000 end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
unpack = unpack or table.unpack
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Horde" end
UnitName = function() return "Hex" end
C_Item.GetItemQualityColor = function(q) return 0.1, 1, 0.1 end

-- auction house
local replicate = {}
C_AuctionHouse = {
	ReplicateItems = function() end,
	GetNumReplicateItems = function() return #replicate end,
	GetReplicateItemInfo = function(i)
		local r = replicate[i + 1]
		return "n", nil, 1, 2, true, 30, nil, 0, 0, r.price, 0, nil, nil, "Seller", nil, nil, r.id, true
	end,
	GetReplicateItemLink = function(i) return replicate[i + 1].link end,
	GetBrowseResults = function() return {} end,
}
C_Item.GetItemInfoInstant = (function(orig)
	return function(x)
		if type(x) == "number" then
			for _, r in ipairs(replicate) do if r.id == x then return orig(r.link) end end
			return nil
		end
		return orig(x)
	end
end)(C_Item.GetItemInfoInstant)

---------------------------------------------------------------------------
-- Load in TOC order
---------------------------------------------------------------------------
local GL = {}
local toc = io.open("UpgradeBroker.toc"):read("*a")
for line in toc:gmatch("[^\r\n]+") do
	if line:match("%.lua$") then
		local path = line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("UpgradeBroker", GL)
	end
end
GL:Fire("ADDON_LOADED", "UpgradeBroker")
GL:Fire("PLAYER_LOGIN")

local fails = 0
local function check(name, cond) if cond then print("ok   " .. name) else fails = fails + 1 print("FAIL " .. name) end end
local function try(name, fn)
	local ok, err = pcall(fn)
	check(name, ok)
	if not ok then print("     " .. tostring(err)) end
end

-- the level 35 warlock from run.lua
T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800,
	spAll = 20, scrit = 6, armor = 420, regen = 14, regenIC = 0 })
GL.cdb.spec = "DEMO"
T.equipped[5] = T.Item("robe-old", { name = "Old Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1,
	stats = { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 6 } })
T.equipped[11] = T.Item("ring-old", { name = "Copper Band", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_STAMINA_SHORT = 2 } })
local function add(id, def, price)
	local link = "|cff1eff00|Hitem:" .. id .. "::::::0:::35|h[" .. def.name .. "]|h|r"
	T.Item(link, def)
	replicate[#replicate + 1] = { id = id, link = link, price = price }
end
add(101, { name = "Robe of the Moccasin", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1, stats = { ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_INTELLECT_SHORT = 8 } }, 34000)
add(102, { name = "Twilight Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1, stats = { ITEM_MOD_STAMINA_SHORT = 14, ITEM_MOD_INTELLECT_SHORT = 10 } }, 87500)
add(103, { name = "Robe of Evocation", equipLoc = "INVTYPE_ROBE", classID = 4, subclassID = 1, reqLevel = 37, stats = { ITEM_MOD_STAMINA_SHORT = 15, ITEM_MOD_INTELLECT_SHORT = 15 } }, 61000)
add(104, { name = "Jade Ring", equipLoc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_INTELLECT_SHORT = 7, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 4 } }, 10500)
add(105, { name = "Gravestone Scepter", equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 } }, 79000)
add(106, { name = "Plate Helm", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, stats = { ITEM_MOD_STAMINA_SHORT = 30 } }, 5000)
add(107, { name = "Shadow Cowl", equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 1, stats = {}, lines = { "Equip: Increases damage done by Shadow spells and effects by up to 9." } }, 400000)

try("window opens without an auction house", function() GL.Window:Show() end)
check("window shows the empty state", UpgradeBrokerFrame:IsShown())

try("auction house opens and gets a tab", function()
	AuctionHouseFrame = new("Frame", "AuctionHouseFrame")
	AuctionHouseFrame.Tabs = { new("Button") }
	AuctionHouseFrame.SearchBar = new("Frame"); AuctionHouseFrame.SearchBar.SearchBox = new("EditBox")
	AuctionHouseFrameDisplayMode = { Buy = { "Buy" } }
	GL:Fire("AUCTION_HOUSE_SHOW")
end)
try("scan reads and rates", function()
	GL.db.lastReplicate = 0
	assert(GL.Scanner:Start())
	GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
end)
local res = GL.Scanner.results or {}
do
	local d = GL.Scanner:Data(); local nn = 0
	for k, v in pairs(d and d.items or {}) do
		nn = nn + 1
		local r = GL.Compare:Rate(v:match("|(.+)$"))
		print("     scanned", k, r and r.ok, r and r.reason, r and r.gain and r.gain.total)
	end
	print("     items", nn, GL.Scanner.state)
end
check("chest group has upgrades", res.CHEST and #res.CHEST >= 2)
check("plate helm left out", not (res.HEAD and res.HEAD[1] and res.HEAD[1].item.name == "Plate Helm"))
check("shadow cowl over the price limit left out", not res.HEAD)
check("ring compared against the empty ring slot or the band", res.RING and res.RING[1] ~= nil)
check("future robe sorted after wearable ones", res.CHEST and not res.CHEST[1].later)
if res.CHEST then for i, e in ipairs(res.CHEST) do print(("     chest %d: %s %.2f%% %s %.2f/g%s"):format(i, e.item.name, e.gain, GL.Money(e.price, true), e.perGold, e.later and " (later)" or "")) end end

try("window in the auction house refreshes", function() GL.Window:Show(); GL.Window:Refresh() end)
try("order: gain, slot, value", function()
	for _, o in ipairs({ "gain", "slot", "value" }) do GL.db.order = o; GL.Scanner:Sort(); GL.Window:Refresh() end
end)
try("mode switch re-rates", function() GL:SetMode("endgame"); GL:SetMode("level") end)
try("price typed as text", function() UpgradeBrokerFrame.left:GetWidth() end)
try("search the auction house", function()
	assert(GL.Scanner:Find(res.CHEST[1].link))
	assert(AuctionHouseFrame.SearchBar.SearchBox:GetText():find(res.CHEST[1].item.name, 1, true))
end)
try("tooltip lines", function()
	local link = res.RING[1].link
	GameTooltip.GetItem = function() return "Jade Ring", link end
	GameTooltip.GetOwner = function() return nil end
	GameTooltip._lines = {}
	-- call the post hook directly
	local hookFn
	TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) hookFn = fn end }
	Enum = { TooltipDataType = { Item = 0 } }
	assert(loadfile("UI/Tooltip.lua"))("UpgradeBroker", GL)
	hookFn(GameTooltip, {})
	for _, l in ipairs(GameTooltip._lines) do print("     tip: " .. l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	assert(#GameTooltip._lines >= 2)
end)
try("bags refresh", function() GL.Bags:Refresh() end)
try("scan button during the cooldown says so instead of erroring", function()
	GL.db.lastReplicate = time()
	local ok, why, left = GL.Scanner:Start()
	assert(not ok and why == "cooldown" and left and left > 0)
	UpgradeBrokerFrame.scan:Click()
end)
try("budget change while waiting for a scan keeps the scan alive", function()
	GL.db.lastReplicate = 0
	assert(GL.Scanner:Start())
	GL.Scanner:Rate()
	assert(GL.Scanner.state == "waiting", GL.Scanner.state)
	GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
	assert(GL.Scanner.state == "idle" and GL.Scanner.results.CHEST)
end)
try("typed prices round-trip (12.5g, any, 50s)", function()
	local box = UpgradeBrokerFrame.price.box
	for _, case in ipairs({ { "12.5g", 125000, "12g 50s" }, { "12.34g", 123400, "12g 34s" }, { "50.5s", 5050, "50s 50c" },
		{ "any", 1e12, "Any" }, { "50s", 5000, "50s" }, { "10", 100000, "10g" }, { "1g 2s 3c", 10203, "1g 2s 3c" } }) do
		box:SetText(case[1]); box._scripts.OnEnterPressed(box)
		assert(GL.db.maxPrice == case[2], case[1] .. " -> " .. GL.db.maxPrice)
		assert(box:GetText() == case[3], case[1] .. " shows " .. tostring(box:GetText()))
	end
end)
try("quest rewards: best usable choice framed", function()
	local function btn(i) local b = new("Button"); b.type = "choice"; b._id = i; return b end
	QuestInfoRewardsFrame = new("Frame"); QuestInfoRewardsFrame.RewardButtons = { btn(1), btn(2), btn(3) }
	QuestInfoFrame = new("Frame"); QuestInfoFrame.questLog = false
	local links = { res.RING[1].link, res.CHEST[#res.CHEST].link, res.CHEST[1].link }
	GetQuestItemLink = function(kind, i) return links[i] end
	-- mock border: remember the alpha it was given
	GL.Quest.Update()
	local bs = QuestInfoRewardsFrame.RewardButtons
	local function shown(b) local m = GL.Quest.marks[b] return m and m:IsShown() end
	assert(shown(bs[1]) and shown(bs[2]) and shown(bs[3]), "every upgrade gets a badge")
	local best = 0
	for i = 1, 3 do if GL.Quest.marks[bs[i]].frameAlpha == 1 then best = i end end
	assert(best == 1 or best == 3, "the frame goes to a usable upgrade, got " .. best)
	assert(GL.Quest.marks[bs[2]].frameAlpha == 0, "the level 37 robe gets no frame")
end)
try("a full scan by another addon is read too", function()
	local realGetTime = GetTime
	GetTime = function() return realGetTime() + 1000 end -- well after our own last read
	add(108, { name = "Fresh Gloves", equipLoc = "INVTYPE_HAND", classID = 4, subclassID = 1, stats = { ITEM_MOD_STAMINA_SHORT = 9, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 6 } }, 3000)
	GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
	T.RunLater()
	GetTime = realGetTime
	assert(GL.Scanner.results.HANDS and GL.Scanner.results.HANDS[1].item.name == "Fresh Gloves", "gloves from the other scan")
end)
try("Scan uses Auctionator's full scan when it is there", function()
	local started = false
	Auctionator = { State = { FullScanFrameRef = { state = {}, CanInitiate = function() return true end,
		InitiateScan = function(self) started = true; self.state.TimeOfLastReplicateScan = time() end } } }
	GL.db.lastReplicate = 0
	assert(GL.Scanner:Start())
	assert(started, "Auctionator's scan was started")
	GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
	assert(GL.Scanner.state == "idle")
	local ok, why = GL.Scanner:CanScan()
	assert(not ok and why == "cooldown", "Auctionator's scan counts for the 15 minutes")
	Auctionator = nil
end)
try("alts: shop for the warlock from a paladin bank character", function()
	GL.db.maxPrice = 1e12
	GL.Character:Invalidate(); GL.Character:Get(); GL.Character:Save()
	assert(GL.db.chars["Realm-Horde"].Hex, "warlock saved")
	-- log in on another character
	UnitName = function() return "Banky" end
	T.Reset({ level = 12, class = "PALADIN", className = "Paladin", stats = { 30, 20, 30, 20, 20 }, hp = 300, mana = 300, ap = 60, armor = 300 })
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	GL.Scanner:Rate()
	assert(not (GL.Scanner.results.CHEST), "cloth robes are no upgrade for a level 12 paladin")
	GL:SetViewing("Hex")
	assert(GL.Character:Viewed().isAlt and GL.Character:Viewed().class == "WARLOCK")
	GL.Scanner:Rate()
	assert(GL.Scanner.results.CHEST and #GL.Scanner.results.CHEST >= 1, "robes are upgrades for the warlock")
	local alts = GL.Character:Alts()
	assert(#alts == 1 and alts[1].name == "Hex", "the warlock is listed as an alt")
	GL:SetSpec("DESTRO")
	assert(GL.Character:AltData("Hex").spec == "DESTRO" and GL.cdb.spec ~= "DESTRO", "spec choice goes to the alt")
	GL.Window:Refresh()
	GL:SetViewing(nil)
	UnitName = function() return "Hex" end
end)
try("alts: weapons in the bags are saved, loaded or not", function()
	local warm = T.Item("bag-sword", { name = "Sword", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } })
	local realNum, realLink = C_Container.GetContainerNumSlots, C_Container.GetContainerItemLink
	C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
	C_Container.GetContainerItemLink = function(bag, slot) return slot == 1 and warm or "cold-shield" end
	local realInstant = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function(x) if x == "cold-shield" then return 2, nil, nil, "INVTYPE_SHIELD" end return realInstant(x) end
	GL.Items.GetItemInfoInstant = C_Item.GetItemInfoInstant
	GL.Character:Invalidate(); GL.Character:Get(); GL.Character:Save()
	local d = GL.db.chars["Realm-Horde"][UnitName("player")]
	C_Container.GetContainerNumSlots, C_Container.GetContainerItemLink = realNum, realLink
	C_Item.GetItemInfoInstant = realInstant; GL.Items.GetItemInfoInstant = realInstant
	assert(#d.bagWeapons == 2, "saved " .. #d.bagWeapons .. " bag weapons")
end)
try("the ? button opens the scoring page", function()
	GL.Window:Show()
	UpgradeBrokerFrame.info:Click()
	assert(GL.Info.overlay and GL.Info.overlay:IsShown(), "overlay shown")
	UpgradeBrokerFrame.info:Click()
	assert(not GL.Info.overlay:IsShown(), "overlay hidden again")
end)
try("no realm name (WoW Forever): characters are still saved and listed", function()
	local real = GetRealmName
	GetRealmName = function() return "" end
	GL.Character:Invalidate(); GL.Character:Get(); GL.Character:Save()
	assert(GL.db.chars["-Horde"] and GL.db.chars["-Horde"][UnitName("player")], "saved under -Horde")
	GetRealmName = real
end)
try("items the client loads late are rated on later passes", function()
	GL.db.maxPrice = 1e12
	local slow = {}
	for n = 1, 3 do
		local id = 200 + n
		add(id, { name = "Slow Gloves " .. n, equipLoc = "INVTYPE_HAND", classID = 4, subclassID = 1,
			stats = { ITEM_MOD_STAMINA_SHORT = 5 + n, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 8 + n } }, 2000)
		slow[replicate[#replicate].link] = true
	end
	T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800,
		spAll = 20, scrit = 6, armor = 420, regen = 14, regenIC = 0 })
	GL:SetViewing(nil)
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	for link in pairs(slow) do T.slow[link] = true end
	GL.db.lastReplicate = 0
	GL.Scanner.state = "idle"
	assert(GL.Scanner:Start()); GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
	-- the client delivers one item per pass
	for link in pairs(slow) do
		T.slow[link] = nil
		T.RunLater()
	end
	T.RunLater()
	local hands = GL.Scanner.results and GL.Scanner.results.HANDS or {}
	local n = 0
	for _, e in ipairs(hands) do if e.item.name:find("^Slow Gloves") then n = n + 1 end end
	assert(n == 3, "rated " .. n .. " of 3 late items")
	GL.Scanner:Explain()
end)
try("a search in the auction house updates the scan's price", function()
	local wand = replicate[5] -- Gravestone Scepter, 7g 90s in the scan
	C_AuctionHouse.GetBrowseResults = function() return { { itemKey = { itemID = wand.id }, minPrice = 39900, totalQuantity = 1 } } end
	GL:Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	local key = GL.Scanner.KeyOf(wand.link)
	assert(GL.Scanner:Data().items[key]:match("^(%d+)") == "39900", GL.Scanner:Data().items[key])
	C_AuctionHouse.GetBrowseResults = function() return {} end
end)
try("a slot with nothing under the limit shows where upgrades start", function()
	T.Reset({ level = 35, class = "WARLOCK", className = "Warlock", stats = { 30, 35, 80, 110, 105 }, hp = 1300, mana = 1800,
		spAll = 20, scrit = 6, armor = 420, regen = 14, regenIC = 0 })
	GL:SetViewing(nil); GL.Character:Invalidate(); GL.Compare:ClearCache()
	GL.db.maxPrice = 20000 -- 2g: the robes (3g 40s and up) are above it
	GL.Scanner:Rate()
	assert(not (GL.Scanner.results or {}).CHEST, "no chest within 2g")
	local chest = GL.Scanner.above and GL.Scanner.above.CHEST
	assert(chest and chest[1].price == 34000, "cheapest chest above the limit first")
	GL.Window:Show(); GL.Window:Refresh()
	GL.db.maxPrice = 1e12
end)
try("auction house closes", function() GL:Fire("AUCTION_HOUSE_CLOSED") end)
try("debug dump", function() GL.Character:Dump() end)
try("explain", function() GL.Compare:Explain(res.CHEST[1].link) end)

print(fails == 0 and "all ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
