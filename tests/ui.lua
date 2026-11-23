-- tests/ui.lua: lua5.1 tests/ui.lua. Loads the whole addon against mock frames and walks through the window,
-- the auction house tab, a scan, tooltips, bags and quest rewards, to catch runtime errors outside the game.
package.path = "tests/?.lua;" .. package.path
local G = require("game")
local GL, T, replicate, new, check, try = G.GL, G.T, G.replicate, G.new, G.check, G.try

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
do
	-- the footer: every upgrade the list shows, worn together
	local t, n, price, best = GL.Scanner.total, 0, 0, 0
	for _, g in ipairs(GL.Scanner.GROUPS) do
		local e = res[g.key] and res[g.key][1]
		if e and not e.later then n, price, best = n + 1, price + e.price, math.max(best, e.gain) end
	end
	print(("     total: %d upgrades %.2f%% %s"):format(t and t.n or -1, t and t.gain or 0, t and GL.Money(t.price or 0, true) or "-"))
	check("total counts the wearable upgrades the list shows", t and t.n == n and t.price == price)
	check("total is at least the best single upgrade", t and t.gain >= best - 1e-9)
	check("size labels", GL.Compare.SizeLabel(2) == "Big upgrade" and GL.Compare.SizeLabel(1.2) == "Good upgrade"
		and GL.Compare.SizeLabel(0.6) == "Minor upgrade")
	local chest = res.CHEST and res.CHEST[1]
	local ig = chest and GL.Compare.ItemGain(chest.res.snap, chest.gain, chest.res.replaced)
	print(("     chest item vs worn: %s (character %.2f%%)"):format(tostring(ig), chest and chest.gain or 0))
	check("item vs worn is bigger than the character gain", ig and ig > chest.gain)
	check("item vs worn: nothing to compare with in an empty slot", GL.Compare.ItemGain(chest.res.snap, 1, {}) == nil)
end
if res.CHEST then for i, e in ipairs(res.CHEST) do print(("     chest %d: %s %.2f%% %s %.2f/g%s"):format(i, e.item.name, e.gain, GL.Money(e.price, true), e.perGold, e.later and " (later)" or "")) end end

try("window in the auction house refreshes", function() GL.Window:Show(); GL.Window:Refresh() end)
try("order: gain, slot, value", function()
	for _, o in ipairs({ "gain", "slot", "value" }) do GL.db.order = o; GL.Scanner:Sort(); GL.Window:Refresh() end
end)
try("item vs worn everywhere", function()
	GL.db.itemPct = true
	GL.Window:Refresh()
	local txt = UpgradeBrokerFrame.why.big:GetText()
	print("     decision in item mode: " .. tostring(txt) .. " / " .. tostring(UpgradeBrokerFrame.why.metric:GetText()))
	assert(txt == "New" or txt:find("%%"))
	GL.db.itemPct = false
	GL.Window:Refresh()
	print("     footer: " .. tostring(UpgradeBrokerFrame.foot.label:GetText()) .. " " .. tostring(UpgradeBrokerFrame.foot.gain:GetText())
		.. " " .. tostring(UpgradeBrokerFrame.foot.price:GetText()))
	assert(UpgradeBrokerFrame.foot.label:GetText():find("upgrade"))
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
try("the gear button opens the settings in the window", function()
	GL.Window:Show()
	UpgradeBrokerFrame.info:Click()
	UpgradeBrokerFrame.gear:Click()
	assert(GL.Options.overlay and GL.Options.overlay:IsShown(), "settings shown")
	assert(not GL.Info.overlay:IsShown(), "one page at a time")
	UpgradeBrokerFrame.gear:Click()
	assert(not GL.Options.overlay:IsShown(), "settings hidden again")
end)
try("without EllesmereUI the settings are under Esc > Options > AddOns", function()
	local registered = G.settings()
	assert(registered and registered.name == "Upgrade Broker", "category registered")
	GL:OpenOptions()
	assert(select(2, G.settings()) == 42, "/ub options opens it")
end)
try("/ub set toggles a setting", function()
	local before = GL.db.bagMarkers
	SlashCmdList.UPGRADEBROKER("set bagmarkers")
	assert(GL.db.bagMarkers == not before)
	SlashCmdList.UPGRADEBROKER("set itempct")
	assert(GL.db.itemPct == true)
	SlashCmdList.UPGRADEBROKER("set itempct")
	GL.db.bagMarkers = before
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
	-- one run: the bar only moves forward, and later passes rate only the late items
	local seen, last, rated = {}, -1, {}
	local realRate = GL.Compare.Rate
	GL.Compare.Rate = function(self, link, ...) rated[#rated + 1] = link; return realRate(self, link, ...) end
	GL:On("GL_SCAN_STATE", function()
		local st = GL.Scanner.state
		if st == "rating" then
			assert(GL.Scanner.progress >= last, ("bar went back from %.2f to %.2f"):format(last, GL.Scanner.progress))
			last = GL.Scanner.progress
		end
		seen[#seen + 1] = st
	end)
	assert(GL.Scanner:Start()); GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
	-- the client delivers one item per pass
	for link in pairs(slow) do
		rated = {}
		T.slow[link] = nil
		T.RunLater()
		for _, l in ipairs(rated) do assert(slow[l], "a later pass rated " .. l .. " again") end
	end
	T.RunLater()
	GL.Compare.Rate = realRate
	local after = false
	for _, st in ipairs(seen) do
		if st == "rating" then after = true elseif after then assert(st == "idle" and seen[#seen] == "idle", "rating stopped before the end") end
	end
	assert(GL.Scanner.state == "idle", GL.Scanner.state)
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
try("/ub record, the importer and the replay fit together", function()
	GL.Scanner.state = "idle"
	SlashCmdList.UPGRADEBROKER("record")
	for _ = 1, 10 do if UpgradeBrokerRecord then break end T.RunLater() end
	local rec = assert(UpgradeBrokerRecord, "recording finished")
	assert(next(rec.items) and #rec.rows > 0 and next(rec.golden), "items, auction rows and ratings recorded")
	-- as the game saves it, then through the importer into the replay
	local out = {}
	local function write(v)
		if type(v) == "string" then out[#out + 1] = ("%q"):format(v)
		elseif type(v) ~= "table" then out[#out + 1] = tostring(v)
		else
			out[#out + 1] = "{"
			for k, x in pairs(v) do
				out[#out + 1] = "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "]="
				write(x)
				out[#out + 1] = ","
			end
			out[#out + 1] = "}"
		end
	end
	write(rec)
	local sv, fixture = os.tmpname(), os.tmpname()
	local f = assert(io.open(sv, "wb")); f:write("UpgradeBrokerRecord = " .. table.concat(out)); f:close()
	local ok = os.execute(("lua5.1 tools/import-record.lua %q %q > /dev/null"):format(sv, fixture)) == 0
		and os.execute(("lua5.1 tests/replay.lua %q > %q.log 2>&1"):format(fixture, fixture)) == 0
	local log = io.open(fixture .. ".log"):read("*a")
	os.remove(sv); os.remove(fixture); os.remove(fixture .. ".gz"); os.remove(fixture .. ".log")
	assert(ok, "replay failed:\n" .. log)
	SlashCmdList.UPGRADEBROKER("record clear")
	assert(UpgradeBrokerRecord == nil)
end)
try("auction house closes", function() GL:Fire("AUCTION_HOUSE_CLOSED") end)
try("no rating while the window is closed", function()
	GL.Window:Hide()
	local before = GL.Scanner.results
	local rated = 0
	local orig = GL.Compare.Rate
	GL.Compare.Rate = function(...) rated = rated + 1 return orig(...) end
	-- looting or losing durability fires this without a change in what you wear
	GL.lastWorn = nil
	GL:Fire("UNIT_INVENTORY_CHANGED", "player")
	GL:Fire("UNIT_INVENTORY_CHANGED", "player")
	GL:Fire("GL_CHANGED")
	assert(rated == 0, "rated " .. rated .. " items with the window closed")
	assert(GL.Scanner.stale, "marked for the next open")
	GL.Window:Show()
	assert(rated > 0 and not GL.Scanner.stale, "rates when the window opens")
	GL.Compare.Rate = orig
end)
try("closing the window stops a rating in progress", function()
	GL.Window:Show()
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	-- one item per slice, and slices wait for the next frame
	local queue, clock = {}, 0
	local realAfter, realClock = C_Timer.After, debugprofilestop
	C_Timer.After = function(d, fn) table.insert(queue, fn) end
	debugprofilestop = function() clock = clock + 5 return clock end
	GL.Scanner:Rate()
	assert(GL.Scanner.state == "rating", "rating started: " .. tostring(GL.Scanner.state))
	local rated = 0
	local orig = GL.Compare.Rate
	GL.Compare.Rate = function(...) rated = rated + 1 return orig(...) end
	GL.Window:Hide()
	for _, fn in ipairs(queue) do fn() end
	C_Timer.After, debugprofilestop = realAfter, realClock
	GL.Compare.Rate = orig
	assert(rated == 0, "rated " .. rated .. " items after the window closed")
	assert(GL.Scanner.stale and GL.Scanner.state == "idle", "starts over on the next open")
	GL.Window:Show()
	assert(not GL.Scanner.stale and GL.Scanner.results, "rated on open")
end)
try("a new max price needs no new rating", function()
	local rated = 0
	local orig = GL.Compare.Rate
	GL.Compare.Rate = function(...) rated = rated + 1 return orig(...) end
	GL.db.maxPrice = 20000
	GL.Scanner:SetMaxPrice()
	assert(rated == 0, "rated " .. rated)
	assert(not (GL.Scanner.results or {}).CHEST and GL.Scanner.above.CHEST, "robes above 2g")
	GL.db.maxPrice = 1e12
	GL.Scanner:SetMaxPrice()
	assert(GL.Scanner.results.CHEST and not GL.Scanner.above.CHEST, "robes back in the list")
	GL.Compare.Rate = orig
end)
try("gain order has no cycle", function()
	local cmp = GL.Scanner.Better("gain")
	local a, b, c = { gain = 0.60, price = 1 }, { gain = 0.64, price = 2 }, { gain = 0.68, price = 3 }
	assert(not (cmp(a, b) and cmp(b, c) and cmp(c, a)))
end)
try("gear changes in combat wait for the fight to end", function()
	local changed = 0
	GL:On("GL_CHANGED", function() changed = changed + 1 end)
	InCombatLockdown = function() return true end
	GL:Fire("PLAYER_EQUIPMENT_CHANGED")
	assert(changed == 0, "changed in combat")
	InCombatLockdown = function() return false end
	GL:Fire("PLAYER_REGEN_ENABLED")
	assert(changed == 1, "changed after combat: " .. changed)
end)
try("bags are read once per snapshot for one-handers", function()
	T.equipped[16] = T.Item("staff", { name = "Staff", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } })
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	local reads = 0
	local realNum = C_Container.GetContainerNumSlots
	C_Container.GetContainerNumSlots = function(bag) reads = reads + 1 return 0 end
	for i = 1, 5 do
		GL.Compare:Rate(T.Item("dagger" .. i, { name = "Dagger " .. i, equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 + i } }))
	end
	C_Container.GetContainerNumSlots = realNum
	T.equipped[16] = nil
	GL.Character:Invalidate(); GL.Compare:ClearCache()
	assert(reads <= 5, "bag reads: " .. reads)
end)
try("a sold item leaves the list", function()
	GL:Fire("AUCTION_HOUSE_SHOW")
	AuctionHouseFrame:Show()
	local ring = GL.Scanner.results.RING[1]
	C_AuctionHouse.GetBrowseResults = function() return {} end
	C_AuctionHouse.HasFullBrowseResults = function() return true end
	AuctionHouseFrame.SearchBar.StartSearch = function() end
	assert(GL.Scanner:Find(ring.link), "search started")
	GL:Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	assert(not GL.Scanner:Data().items[ring.key], "gone from the scan")
	for _, e in ipairs(GL.Scanner.results.RING or {}) do assert(e.key ~= ring.key, "gone from the list") end
	GL:Fire("AUCTION_HOUSE_CLOSED")
end)
try("debug dump", function() GL.Character:Dump() end)
try("explain", function() GL.Compare:Explain(res.CHEST[1].link) end)

local fails = G.fails()
print(fails == 0 and "all ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
