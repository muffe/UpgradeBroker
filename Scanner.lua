-- Scanner.lua: reads the whole auction house (C_AuctionHouse.ReplicateItems, once per 15 minutes), keeps
-- the cheapest buyout of every piece of gear, and rates it all for the upgrade list.
local _, GL = ...

local Scanner = {}
GL.Scanner = Scanner

local AH = C_AuctionHouse
local COOLDOWN = 15 * 60
-- time per frame for reading and rating: small enough that a 144 Hz frame (7 ms) keeps its pace
local BATCH_MS = 2

Scanner.state = "idle" -- idle | waiting (for the AH) | reading | rating | items (the game still loads items) | loading (gear)
Scanner.progress = 0

local function RealmKey() return GL.RealmKey() end

function Scanner:Data()
	local key = RealmKey()
	return key and GL.db.scans[key]
end

function Scanner:Age()
	local d = self:Data()
	return d and (time() - (d.time or 0)) or nil
end

-- Auctionator's full scan, when it is installed: our Scan button starts that one, so a single scan fills
-- Auctionator's price database and Upgrade Broker's list alike. (Auctionator has no public API for this; its own
-- Scan button calls the same function, and everything here falls back to our own scan.)
local function AuctionatorScanner()
	local ref = _G.Auctionator and Auctionator.State and Auctionator.State.FullScanFrameRef
	if type(ref) == "table" and type(ref.InitiateScan) == "function" then return ref end
end

-- The last full scan by anyone we know of (the server allows one per 15 minutes per character).
local function LastScan()
	local last = GL.db.lastReplicate or 0
	local ref = AuctionatorScanner()
	local theirs = ref and type(ref.state) == "table" and tonumber(ref.state.TimeOfLastReplicateScan)
	return math.max(last, theirs or 0)
end

function Scanner:CanScan()
	if not (AH and AH.ReplicateItems) then return false, "unavailable" end
	if not self.ahOpen then return false, "closed" end
	if self.state ~= "idle" and self.state ~= "loading" and self.state ~= "items" then return false, "busy" end
	local last = LastScan()
	if time() - last < COOLDOWN then return false, "cooldown", COOLDOWN - (time() - last) end
	return true
end

-- itemID:suffix, so "of the Owl" and "of the Bear" are kept apart
-- itemID:suffix:bonus IDs. On WoW Forever "of the Whale" and friends are bonus IDs in the link
-- (item:12030::::::::35:1490:::1:12719), so they are part of the key; otherwise every variant of an item would
-- collapse into its cheapest one.
local function KeyOf(link)
	local id, rest = link:match("item:(%d+):([^|]*)")
	if not id then return nil end
	local fields = {}
	for f in (rest .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
	local suffix = fields[6] ~= "" and fields[6] or "0"
	local n = tonumber(fields[12] or "") or 0
	local bonus = {}
	for i = 1, n do bonus[#bonus + 1] = fields[12 + i] or "" end
	return id .. ":" .. suffix .. (n > 0 and (":" .. table.concat(bonus, ".")) or "")
end
Scanner.KeyOf = KeyOf

-- the window follows the progress four times a second, not every frame
local lastFire = 0
local function SetState(state, progress)
	local changed = state ~= Scanner.state
	Scanner.state, Scanner.progress = state, progress or 0
	local now = GetTime()
	if changed or now - lastFire >= 0.25 then
		lastFire = now
		GL:Fire("GL_SCAN_STATE")
	end
end

function Scanner:Start()
	local ok, why, left = self:CanScan()
	if not ok then return false, why, left end
	SetState("waiting")
	local ref = AuctionatorScanner()
	local fine = false
	if ref then
		local okCan, can = true, true
		if type(ref.CanInitiate) == "function" then okCan, can = pcall(ref.CanInitiate, ref) end
		if okCan and can then fine = pcall(ref.InitiateScan, ref) end
	end
	if not fine then fine = pcall(AH.ReplicateItems) end
	if not fine then SetState("idle") return false, "error" end
	GL.db.lastReplicate = time()
	-- the answer can take a while; give up after a minute
	C_Timer.After(60, function()
		if Scanner.state == "waiting" then
			SetState("idle")
			if Scanner.rateAfter then Scanner:Rate() end
		end
	end)
	return true
end

-- Reads the replicate list in small slices so the game never stalls. Rows whose item the client hasn't
-- loaded yet are read again (up to three times) once it has.
local ratingRun = 0
local lastRead -- GetTime() when our last read finished
local readRun = 0
local function Read()
	ratingRun = ratingRun + 1 -- a rating still running belongs to the old data
	readRun = readRun + 1
	local run = readRun
	local total = AH.GetNumReplicateItems() or 0
	local player = UnitName("player")
	local best = {}
	local todo = {}
	for i = 0, total - 1 do todo[#todo + 1] = i end
	local pass, i, later = 1, 0, {}
	SetState("reading", 0)
	local finish
	local function step()
		-- the auction house closed meanwhile: the list is gone, keep the last complete scan
		if run ~= readRun then return end
		local stop = debugprofilestop() + BATCH_MS
		while i < #todo and debugprofilestop() < stop do
			i = i + 1
			local row = todo[i]
			local _, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAll = AH.GetReplicateItemInfo(row)
			if buyout and buyout > 0 and (count or 1) == 1 and (quality or 0) >= 1 and owner ~= player and itemID then
				local _, _, _, equipLoc = GL.Items.GetItemInfoInstant(itemID)
				if equipLoc and GL.Items.EQUIP[equipLoc] then
					local link = hasAll and AH.GetReplicateItemLink(row)
					local key = link and KeyOf(link)
					if key then
						if not best[key] or buyout < best[key].price then best[key] = { price = buyout, link = link } end
					else
						later[#later + 1] = row
						if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
					end
				end
			end
		end
		if i < #todo then
			SetState("reading", (pass - 1) / 4 + i / #todo / 4 * (pass == 1 and 3 or 1))
			C_Timer.After(0, step)
		elseif #later > 0 and pass < 4 then
			todo, later, i, pass = later, {}, 0, pass + 1
			C_Timer.After(1.5, step)
		else
			finish()
		end
	end
	finish = function()
		local items = {}
		for key, e in pairs(best) do items[key] = e.price .. "|" .. e.link end
		GL.db.scans[RealmKey() or "unknown"] = { time = time(), items = items }
		lastRead = GetTime()
		Scanner.lastCount = total
		SetState("idle")
		Scanner:Rate()
	end
	step()
end

-- The answer to our scan, or a full scan another addon (Auctionator) just made: that one is read as well,
-- once the list has stopped changing. Our own reading makes the client fire this event too; those are ignored.
local SETTLE = 3
local settleToken = 0
GL:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if Scanner.state == "waiting" then Read() return end
	if not Scanner.ahOpen or Scanner.state == "reading" then return end
	-- the client keeps firing this while it loads items, also after our own read; a new full scan can't come
	-- sooner than 15 minutes, so a minute of quiet after our last read is safe
	if lastRead and GetTime() - lastRead < 60 then return end
	settleToken = settleToken + 1
	local token = settleToken
	C_Timer.After(SETTLE, function()
		if token ~= settleToken or not Scanner.ahOpen or Scanner.state == "reading" or Scanner.state == "waiting" then return end
		local n = AH.GetNumReplicateItems() or 0
		if n == 0 then return end
		GL.db.lastReplicate = time() -- the 15 minute limit started with their scan
		Read()
	end)
end)
GL:On("AUCTION_HOUSE_SHOW", function() Scanner.ahOpen = true; GL:Fire("GL_AH", true) end)
GL:On("AUCTION_HOUSE_CLOSED", function()
	Scanner.ahOpen = false
	Scanner.CancelFind()
	settleToken = settleToken + 1 -- a foreign scan waiting to settle is gone with the list
	if Scanner.state == "reading" or Scanner.state == "waiting" then
		readRun = readRun + 1
		Scanner.state = "idle"
		GL:Fire("GL_SCAN_STATE")
	end
	-- a rating that waited for the scan runs on the last complete one
	if Scanner.rateAfter then Scanner:Rate() end
	GL:Fire("GL_AH", false)
end)

---------------------------------------------------------------------------
-- Rating the scan
---------------------------------------------------------------------------
-- Upgrade groups, in equipment order.
Scanner.GROUPS = {
	{ key = "HEAD", label = "Head", slots = { 1 } }, { key = "NECK", label = "Neck", slots = { 2 } },
	{ key = "SHOULDER", label = "Shoulder", slots = { 3 } }, { key = "BACK", label = "Back", slots = { 15 } },
	{ key = "CHEST", label = "Chest", slots = { 5 } }, { key = "WRIST", label = "Wrist", slots = { 9 } },
	{ key = "HANDS", label = "Hands", slots = { 10 } }, { key = "WAIST", label = "Waist", slots = { 6 } },
	{ key = "LEGS", label = "Legs", slots = { 7 } }, { key = "FEET", label = "Feet", slots = { 8 } },
	{ key = "RING", label = "Ring", slots = { 11, 12 } }, { key = "TRINKET", label = "Trinket", slots = { 13, 14 } },
	{ key = "MAINHAND", label = "Main Hand", slots = { 16 } }, { key = "OFFHAND", label = "Off Hand", slots = { 17 } },
	{ key = "RANGED", label = "Ranged", slots = { 18 } },
}
local GROUP_OF = {}
for _, g in ipairs(Scanner.GROUPS) do for _, s in ipairs(g.slots) do GROUP_OF[s] = g.key end end
Scanner.GROUP_OF = GROUP_OF

Scanner.results = nil -- [groupKey] = { entries sorted best first }

-- /ub why: what the last rating did with the scanned items
function Scanner:Explain()
	local st = self.lastStats
	if not st then return GL:Print("No rating yet. Scan the Auction House first.") end
	local unusable, parts = 0, {}
	for reason, n in pairs(st.unusable) do unusable = unusable + n; parts[#parts + 1] = ("%s %d"):format(reason, n) end
	GL:Print(("%d items under your max price: %d upgrades, %d below %s, %d can't be used (%s), %d still loading."):format(
		st.priced, st.upgrades, st.small, GL.Pct(GL.db.minGain), unusable, table.concat(parts, ", "), st.missing))
	table.sort(st.near, function(a, b) return a.gain > b.gain end)
	for k = 1, math.min(5, #st.near) do GL:Print(("  %s %s"):format(st.near[k].link, GL.Pct(st.near[k].gain))) end
end

-- stops a rating that is still running (its results would belong to another character)
function Scanner:CancelRating()
	ratingRun = ratingRun + 1
	if self.state == "rating" or self.state == "loading" then self.state = "idle" end
end

-- Value of an entry: percent per gold. Gear that needs a few more levels goes after what you can wear now.
local function Better(order)
	return function(a, b)
		if a.later ~= b.later then return not a.later end
		if order == "gain" then
			-- upgrades within 0.05 % of each other count as equal: the cheaper one first
			if math.abs(a.gain - b.gain) >= 0.05 then return a.gain > b.gain end
			return a.price < b.price
		end
		if a.perGold ~= b.perGold then return a.perGold > b.perGold end
		return a.gain > b.gain
	end
end
Scanner.Better = Better

function Scanner:Sort()
	if not self.results then return end
	local cmp = Better(GL.db.order == "gain" and "gain" or "value")
	for _, list in pairs(self.results) do table.sort(list, cmp) end
	GL:Fire("GL_RESULTS")
end

-- Rates every scanned item against your gear, a slice per frame. Runs again after gear changes.
function Scanner:Rate()
	-- a scan in progress rates when it is done; starting now would make it miss its answer
	if self.state == "waiting" or self.state == "reading" then self.rateAfter = true return end
	self.rateAfter = false
	local data = self:Data()
	ratingRun = ratingRun + 1
	local run = ratingRun
	if not data then self.results = nil GL:Fire("GL_RESULTS") return end
	local who = GL.Character:Viewed()
	-- the gear to compare with is still loading: wait for it instead of rating against half of it
	if who and who.incomplete then
		self.results = nil
		SetState("loading")
		self.loadTries = (self.loadTries or 0) + 1
		if self.loadTries <= 20 then
			C_Timer.After(1.5, function() if run == ratingRun then GL.Character:Invalidate(); self:Rate() end end)
		else
			-- give up for now; the next change (item loaded, gear, a click) tries again
			self.loadTries, self.loadFailed = 0, who.altName or UnitName("player")
			SetState("idle")
			GL:Fire("GL_RESULTS")
		end
		return
	end
	self.loadTries, self.loadFailed = 0, nil
	local keys = {}
	for key in pairs(data.items) do keys[#keys + 1] = key end
	local out, above, missing, i = {}, {}, 0, 0
	local stats = { priced = 0, missing = 0, unusable = {}, small = 0, upgrades = 0, near = {} }
	local maxPrice = GL.db.maxPrice
	SetState("rating", 0)
	local function step()
		if run ~= ratingRun then return end
		local stop = debugprofilestop() + BATCH_MS
		while i < #keys and debugprofilestop() < stop do
			i = i + 1
			local price, link = data.items[keys[i]]:match("^(%d+)|(.+)$")
			price = tonumber(price)
			-- everything is rated; what costs more than your limit only fills slots that have nothing within it
			local within = price and price <= maxPrice
			if price then
				local res = GL.Compare:Rate(link, who)
				if within then stats.priced = stats.priced + 1 end
				if not res then
					missing = missing + 1
				elseif not within then
					-- (not counted in /ub why, which is about the items within your limit)
				elseif not res.ok then
					stats.unusable[res.reason or "?"] = (stats.unusable[res.reason or "?"] or 0) + 1
				elseif not GL.Compare.IsUpgrade(res) then
					stats.small = stats.small + 1
					if res.gain and res.gain.total > 0 then
						table.insert(stats.near, { link = link, gain = res.gain.total })
					end
				end
				if res and GL.Compare.IsUpgrade(res) then
					if within then stats.upgrades = stats.upgrades + 1 end
					local g = GROUP_OF[res.slot]
					local into = within and out or above
					if g then
						into[g] = into[g] or {}
						table.insert(into[g], { link = link, item = res.item, res = res, price = price, gain = res.gain.total,
							perGold = res.gain.total / math.max(0.01, price / 10000), later = res.reason == "later" })
					end
				end
			end
		end
		if i < #keys then
			SetState("rating", i / #keys)
			C_Timer.After(0, step)
		else
			self.results = out
			-- above the limit, only for slots with nothing within it; cheapest first
			for g in pairs(above) do if out[g] then above[g] = nil end end
			for _, list in pairs(above) do
				table.sort(list, function(a, b)
					if a.later ~= b.later then return not a.later end
					if a.price ~= b.price then return a.price < b.price end
					return a.gain > b.gain
				end)
			end
			self.above = above
			-- still waiting for the game to load some items: say so (with how far it got) until the last pass
			local waitingForItems = missing > 0 and not self.retry and missing < (self.lastMissing or math.huge)
			SetState(waitingForItems and "items" or "idle", (#keys - missing) / math.max(1, #keys))
			self:Sort()
			stats.missing = missing
			self.lastStats = stats
			-- items the client was still loading: rate again while it keeps delivering them (a full scan can
			-- hold thousands the client has never seen; one retry left most of them out)
			if missing > 0 and not self.retry and missing < (self.lastMissing or math.huge) then
				self.retry = true
				self.lastMissing = missing
				C_Timer.After(3, function() self.retry = false; if run == ratingRun then self:Rate() end end)
			else
				self.lastMissing = nil
			end
		end
	end
	step()
end

GL:On("GL_CHANGED", function() if Scanner:Data() then Scanner:Rate() end end)
GL:On("GL_LOADED", function() C_Timer.After(2, function() if Scanner:Data() then Scanner:Rate() end end) end)

---------------------------------------------------------------------------
-- Finding an item in the auction house's own Buy view (addons can't buy on WoW Forever)
---------------------------------------------------------------------------
local pending
function Scanner.CancelFind() pending = nil end
local function OpenPending()
	if pending then pending.answered = true end
	if not pending or not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or GetTime() > pending.untilT then pending = nil return end
	local ok, results = pcall(AH.GetBrowseResults)
	if not ok or type(results) ~= "table" then return end
	local full = AH.HasFullBrowseResults and AH.HasFullBrowseResults()
	for _, r in ipairs(results) do
		local k = r.itemKey
		if k and k.itemID == pending.id and (pending.suffix == 0 or (k.itemSuffix or 0) == pending.suffix) then
			pending = nil
			pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, r)
			return
		end
	end
	-- every result is in and ours isn't there (sold meanwhile): stop looking, so a later search isn't hijacked
	if full then pending = nil end
end
-- Every search in the auction house (yours, a shopping list, Search Auction House) brings fresh lowest prices;
-- they replace the scan's for items with a single variant, so the list doesn't keep a price that has changed.
local priceSoon
local function TakeBrowsePrices()
	local data = Scanner:Data()
	if not data then return end
	local ok, results = pcall(AH.GetBrowseResults)
	if not ok or type(results) ~= "table" then return end
	local fresh, variants = {}, {}
	for _, r in ipairs(results) do
		local id = r.itemKey and r.itemKey.itemID
		if id and r.minPrice and r.minPrice > 0 then
			variants[id] = (variants[id] or 0) + 1
			fresh[id] = r.minPrice
		end
	end
	if not next(fresh) then return end
	local keysOf = {}
	for key in pairs(data.items) do
		local id = tonumber(key:match("^(%d+)"))
		if id and fresh[id] then keysOf[id] = keysOf[id] or {}; table.insert(keysOf[id], key) end
	end
	local changed = false
	for id, keys in pairs(keysOf) do
		-- only when the item has one variant on both sides; "of the Owl" and "of the Bear" can't be told apart here
		if #keys == 1 and variants[id] == 1 then
			local price, link = data.items[keys[1]]:match("^(%d+)|(.+)$")
			if tonumber(price) ~= fresh[id] then
				data.items[keys[1]] = fresh[id] .. "|" .. link
				changed = true
			end
		end
	end
	if changed and not priceSoon then
		priceSoon = true
		C_Timer.After(0.5, function() priceSoon = false; if Scanner.state == "idle" then Scanner:Rate() end end)
	end
end
Scanner.TakeBrowsePrices = TakeBrowsePrices

GL:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() OpenPending(); TakeBrowsePrices() end)
GL:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() OpenPending(); TakeBrowsePrices() end)
-- a search the player starts by hand cancels ours
GL:On("AUCTION_HOUSE_SHOW", function()
	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	if bar and bar.StartSearch and not Scanner.searchHooked then
		Scanner.searchHooked = true
		local function cancel() if not Scanner.ownSearch then pending = nil end end
		hooksecurefunc(bar, "StartSearch", cancel)
		if bar.StartFavoritesSearch then hooksecurefunc(bar, "StartFavoritesSearch", cancel) end
	end
end)
GL:On("AUCTION_HOUSE_BROWSE_FAILURE", function()
	if pending then pending = nil; GL:Print("Auction House search failed. Try again.") end
end)

function Scanner:Find(link)
	if not (self.ahOpen and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
	local bar = AuctionHouseFrame.SearchBar
	if not (bar and bar.SearchBox and bar.StartSearch and AuctionHouseFrameDisplayMode) then return false end
	local item = GL.Items.Get(link)
	local key = KeyOf(link)
	if not (item and key) then return false end
	local id, suffix = key:match("^(%d+):(%-?%d+)")
	local query = '"' .. item.name .. '"'
	local this = { id = tonumber(id), suffix = tonumber(suffix) or 0, untilT = GetTime() + 10 }
	pending = nil
	local ok, err = pcall(function()
		AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
		bar.SearchBox:SetText(query)
		if bar.SearchBox:GetText() ~= query then error("couldn't fill the search box") end
		-- search everything: no category, no level or other filters that could hide the item
		local cats = AuctionHouseFrame.CategoriesList
		if type(cats) == "table" and cats.SetSelectedCategory then pcall(cats.SetSelectedCategory, cats, nil) end
		local fb = bar.FilterButton
		if type(fb) == "table" then
			for _, m in ipairs({ "Reset", "ResetFilters", "ClearFilters" }) do
				if type(fb[m]) == "function" then pcall(fb[m], fb) break end
			end
		end
		Scanner.ownSearch = true
		pending = this
		bar:StartSearch()
	end)
	Scanner.ownSearch = false
	if not ok then
		if pending == this then pending = nil end
		GL:Error("Couldn't search the Auction House: " .. tostring(err))
		return false
	end
	-- no answer from the auction house within a few seconds: say so instead of leaving you waiting
	C_Timer.After(4, function()
		if pending == this and not this.answered then
			pending = nil
			GL:Print("Auction House search timed out. Try again.")
		end
	end)
	return true
end

-- gave up waiting for a character's gear: try again once the game delivers items
GL:On("GL_ITEM_LOADED", function()
	if Scanner.loadFailed and Scanner.state == "idle" then
		Scanner.loadFailed = nil
		C_Timer.After(0.5, function() GL.Character:Invalidate(); Scanner:Rate() end)
	end
end)
