-- Scanner.lua: reads the whole auction house (C_AuctionHouse.ReplicateItems, once per 15 minutes), keeps
-- the cheapest buyout of every piece of gear, and rates it all for the upgrade list.
local _, GL = ...

local Scanner = {}
GL.Scanner = Scanner

local AH = C_AuctionHouse
local COOLDOWN = 15 * 60
-- time per frame for reading and rating: small enough that a 144 Hz frame (7 ms) keeps its pace
local BATCH_MS = 2

Scanner.state = "idle" -- idle | waiting (for the AH) | reading | rating | loading (gear)
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
	if self.state ~= "idle" and self.state ~= "loading" then return false, "busy" end
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

-- Reads the replicate list in small slices so the game never stalls. Auctions whose item the game hasn't
-- loaded yet have no link; they join the scan later (ReadLate), so the list shows right after the first pass.
local ratingRun = 0
local lastRead -- GetTime() when our last read finished
local readRun = 0
local late -- { run, rows }: auctions still without a link, looked at again while the auction house is open
local ReadLate
local function Read()
	ratingRun = ratingRun + 1 -- a rating still running belongs to the old data
	readRun = readRun + 1
	local run = readRun
	local total = AH.GetNumReplicateItems() or 0
	local player = UnitName("player")
	local best = {}
	local i, later = 0, {}
	late = nil
	SetState("reading", 0)
	local function step()
		-- the auction house closed meanwhile: the list is gone, keep the last complete scan
		if run ~= readRun then return end
		local stop = debugprofilestop() + BATCH_MS
		while i < total and debugprofilestop() < stop do
			local row = i
			i = i + 1
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
		if i < total then
			SetState("reading", i / math.max(1, total))
			C_Timer.After(0, step)
			return
		end
		local items = {}
		for key, e in pairs(best) do items[key] = e.price .. "|" .. e.link end
		GL.db.scans[RealmKey() or "unknown"] = { time = time(), items = items }
		lastRead = GetTime()
		Scanner.lastCount = total
		SetState("idle")
		Scanner:Rate()
		if #later > 0 then
			late = { run = run, rows = later }
			ReadLate()
		end
	end
	step()
end

-- The auctions that had no link yet: those whose item the game has loaded since join the scan (cheapest per
-- kind) and the rating. Runs when the game says it loaded more, and every few seconds while that finds some.
local lateBusy, lateSoon, lateAgain = false, false, false
ReadLate = function()
	if lateBusy then lateAgain = true return end
	if not late then return end
	if late.run ~= readRun or not Scanner.ahOpen then late = nil return end
	lateBusy = true
	local job, data = late, Scanner:Data()
	local rows, still, found, i = job.rows, {}, {}, 0
	local function step()
		if late ~= job or job.run ~= readRun or not Scanner.ahOpen or not data then
			lateBusy = false
			if late == job then late = nil end
			return
		end
		local stop = debugprofilestop() + BATCH_MS
		while i < #rows and debugprofilestop() < stop do
			i = i + 1
			local row = rows[i]
			local _, _, _, _, _, _, _, _, _, buyout, _, _, _, _, _, _, _, hasAll = AH.GetReplicateItemInfo(row)
			local link = hasAll and AH.GetReplicateItemLink(row)
			local key = link and KeyOf(link)
			if not key then
				still[#still + 1] = row
			elseif buyout then
				local old = data.items[key] and tonumber(data.items[key]:match("^(%d+)"))
				if not old or buyout < old then
					data.items[key] = buyout .. "|" .. link
					found[#found + 1] = key
				end
			end
		end
		if i < #rows then C_Timer.After(0, step) return end
		lateBusy = false
		job.rows = still
		if #found > 0 then Scanner:RateMore(found) end
		if #still == 0 then late = nil return end
		-- the game may load items without telling; keep looking while that finds some
		if (#found > 0 or lateAgain) and not lateSoon then
			lateAgain = false
			lateSoon = true
			C_Timer.After(3, function() lateSoon = false; ReadLate() end)
		end
	end
	step()
end

-- The answer to our scan, or a full scan another addon (Auctionator) just made: that one is read as well,
-- once the list has stopped changing. While the game loads items after our read it fires this too: then the
-- auctions still without a link are looked at again (a new full scan can't come within 15 minutes of ours).
local SETTLE = 3
local settleToken = 0
local lateEvent = false
GL:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if Scanner.state == "waiting" then Read() return end
	if not Scanner.ahOpen or Scanner.state == "reading" then return end
	if lastRead and GetTime() - lastRead < COOLDOWN then
		if late and not lateEvent then
			lateEvent = true
			C_Timer.After(1, function() lateEvent = false; ReadLate() end)
		end
		return
	end
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
			-- upgrades in the same 0.05 % step count as equal: the cheaper one first (steps, not "within 0.05 % of
			-- each other", so the order stays consistent and table.sort can't fail)
			local sa, sb = math.floor(a.gain * 20 + 0.5), math.floor(b.gain * 20 + 0.5)
			if sa ~= sb then return sa > sb end
			return a.price < b.price
		end
		if a.perGold ~= b.perGold then return a.perGold > b.perGold end
		return a.gain > b.gain
	end
end
Scanner.Better = Better

-- Every upgrade the slot list shows, worn together: { n, gain, price }. The model rates them as one set, so
-- the gain is not a sum. Gear that needs a higher level is left out; where two compete for the same hand
-- (a two-hander and an off hand), the bigger gain stays.
function Scanner:Total()
	local res = self.results
	if not res then return nil end
	local entries = {}
	for _, g in ipairs(Scanner.GROUPS) do
		local e = res[g.key] and res[g.key][1]
		if e and not e.later then entries[#entries + 1] = e end
	end
	if #entries == 0 then return { n = 0 } end
	table.sort(entries, function(a, b) return a.gain > b.gain end)
	local s = entries[1].res.snap
	local add, remove, weapons, used, price, n = {}, {}, {}, {}, 0, 0
	for _, e in ipairs(entries) do
		local r = e.res
		local with = r.with or { e.item }
		local clash = false
		for _, it in ipairs(r.replaced or {}) do if used[it] then clash = true end end
		for _, it in ipairs(with) do if used[it] then clash = true end end
		for k in pairs(r.weapons or {}) do if weapons[k] ~= nil then clash = true end end
		if not clash then
			for _, it in ipairs(r.replaced or {}) do used[it] = true; remove[#remove + 1] = it end
			for _, it in ipairs(with) do used[it] = true; add[#add + 1] = it end
			for k, v in pairs(r.weapons or {}) do weapons[k] = v end
			price, n = price + e.price, n + 1
		end
	end
	local Model = GL.Model
	local x = Model.Apply(s, Model.Calibrate(s).x0, add, remove, next(weapons) and weapons or nil)
	return { n = n, gain = Model.Gain(s, x).total, price = price }
end

function Scanner:Sort()
	if not self.results then self.total = nil return end
	local cmp = Better(GL.db.order == "gain" and "gain" or "value")
	for _, list in pairs(self.results) do table.sort(list, cmp) end
	self.total = self:Total()
	GL:Fire("GL_RESULTS")
end

-- Rates every scanned item against your gear, a slice per frame. Runs again after gear changes.
function Scanner:Rate()
	-- a scan in progress rates when it is done; starting now would make it miss its answer
	if self.state == "waiting" or self.state == "reading" then self.rateAfter = true return end
	self.rateAfter = false
	-- only for the open window: a saved scan holds thousands of items, and gear changes all the time while
	-- you level (loot, durability). The window rates when it opens.
	local f = _G.UpgradeBrokerFrame
	if not (f and f:IsVisible()) then self.stale = true return end
	self.stale = false
	local data = self:Data()
	ratingRun = ratingRun + 1
	local run = ratingRun
	self.all = nil
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
	local total = #keys
	-- queue: items to rate now; waitingFor: those the game is still loading, by item ID
	local all, queue, qi, waitingFor, nWaiting = {}, keys, 0, {}, 0
	local maxPrice = GL.db.maxPrice
	local stats = { priced = 0, missing = 0, unusable = {}, small = 0, upgrades = 0, near = {} }
	-- false while the game is still loading the item
	local function RateOne(key)
		local entry = data.items[key] -- (gone when it sold meanwhile)
		local price, link
		if entry then price, link = entry:match("^(%d+)|(.+)$") end
		price = tonumber(price)
		if not price then return true end
		-- everything is rated; what costs more than your limit only fills slots that have nothing within it
		local within = price <= maxPrice
		-- gear this character can never wear is left out before its tooltip is read
		local reject = GL.Compare.QuickReject(who, link)
		local res = not reject and GL.Compare:Rate(link, who)
		if not reject and not res then return false end
		if within then stats.priced = stats.priced + 1 end
		if reject then
			if within then stats.unusable[reject] = (stats.unusable[reject] or 0) + 1 end
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
			if g then
				all[g] = all[g] or {}
				table.insert(all[g], { link = link, key = key, item = res.item, res = res, price = price,
					gain = res.gain.total, perGold = res.gain.total / math.max(0.01, price / 10000),
					later = res.reason == "later" })
			end
		end
		return true
	end
	-- one bar for the whole run: the share of items rated so far
	local function Progress() return (total - nWaiting - (#queue - qi)) / math.max(1, total) end
	-- the game says it has loaded an item (or nothing came for a while): rate what waited for it, right away,
	-- before it drops the item again to make room for others
	local stepping, lastArrival, watch, lastSweep = false, GetTime(), 0, math.huge
	local step
	local function Kick()
		if stepping then return end
		stepping = true
		C_Timer.After(0, step)
	end
	local function Watch()
		watch = watch + 1
		local token, since = watch, lastArrival
		C_Timer.After(3, function()
			if run ~= ratingRun or token ~= watch or nWaiting == 0 or stepping then return end
			if lastArrival ~= since then return Watch() end
			-- quiet for a while: look over the rest once (some load without a word); stop when that finds nothing
			if nWaiting >= lastSweep then SetState("idle") return end
			lastSweep = nWaiting
			for _, list in pairs(waitingFor) do for _, k in ipairs(list) do queue[#queue + 1] = k end end
			waitingFor, nWaiting = {}, 0
			Kick()
		end)
	end
	step = function()
		if run ~= ratingRun then return end
		local stop = debugprofilestop() + BATCH_MS
		while qi < #queue and debugprofilestop() < stop do
			qi = qi + 1
			local key = queue[qi]
			if not RateOne(key) then
				local id = tonumber(key:match("^(%d+)")) or 0
				waitingFor[id] = waitingFor[id] or {}
				table.insert(waitingFor[id], key)
				nWaiting = nWaiting + 1
			end
		end
		if qi < #queue then
			SetState("rating", Progress())
			C_Timer.After(0, step)
			return
		end
		stepping = false
		queue, qi = {}, 0
		-- what is rated so far shows right away
		self.all = all
		stats.missing = nWaiting
		self.lastStats = stats
		self:Split()
		if nWaiting == 0 then SetState("idle") return end
		SetState("rating", Progress())
		Watch()
	end
	self.current = {
		run = run,
		Arrived = function(id)
			local list = waitingFor[id]
			if not list then return end
			waitingFor[id] = nil
			nWaiting = nWaiting - #list
			lastArrival = GetTime()
			for _, k in ipairs(list) do queue[#queue + 1] = k end
			Kick()
		end,
		-- new auctions (or cheaper ones of a kind already there) join this run
		Add = function(more)
			local gone = {}
			for _, k in ipairs(more) do gone[k] = true end
			for _, list in pairs(all) do
				for n = #list, 1, -1 do if gone[list[n].key] then table.remove(list, n) end end
			end
			for _, k in ipairs(more) do queue[#queue + 1] = k end
			total = total + #more
			Kick()
		end,
	}
	SetState("rating", 0)
	stepping = true
	step()
end

-- Auctions that joined the scan after its rating: rated into the same list when it is open, else on opening.
function Scanner:RateMore(keys)
	local f = _G.UpgradeBrokerFrame
	if self.current and self.current.run == ratingRun and not self.stale and f and f:IsVisible() then
		self.current.Add(keys)
	else
		self:Rate()
	end
end
GL:On("GL_ITEM_LOADED", function(id)
	if Scanner.current and Scanner.current.run == ratingRun then Scanner.current.Arrived(id) end
end)

-- Splits the rated upgrades by your max price: within it they make the list; above it they only fill slots
-- with nothing within it, cheapest first. A new limit needs no new rating.
function Scanner:Split()
	if not self.all then return end
	local maxPrice = GL.db.maxPrice
	local out, above = {}, {}
	for g, list in pairs(self.all) do
		for _, e in ipairs(list) do
			local into = e.price <= maxPrice and out or above
			into[g] = into[g] or {}
			into[g][#into[g] + 1] = e
		end
	end
	for g in pairs(above) do if out[g] then above[g] = nil end end
	for _, list in pairs(above) do
		table.sort(list, function(a, b)
			if a.later ~= b.later then return not a.later end
			if a.price ~= b.price then return a.price < b.price end
			return a.gain > b.gain
		end)
	end
	self.results, self.above = out, above
	self:Sort()
end

-- The max price changed: split again when the last rating still holds, else rate.
function Scanner:SetMaxPrice()
	if self.all and not self.stale and self.state ~= "rating" and self.state ~= "loading" then self:Split() else self:Rate() end
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
	-- every result is in and ours isn't there: it sold meanwhile. Stop looking, so a later search isn't hijacked,
	-- and take it off the list so the next one moves up.
	if full then
		local gone = pending
		pending = nil
		Scanner:Drop(gone.key)
		GL:Print(("%s is no longer on the Auction House and was removed from the upgrade list."):format(gone.link))
	end
end

-- Removes one scanned item (sold) from the saved scan and the list.
function Scanner:Drop(key)
	local data = self:Data()
	if data and key then data.items[key] = nil end
	for _, list in pairs(self.all or {}) do
		for k = #list, 1, -1 do if list[k].key == key then table.remove(list, k) end end
	end
	self:Split()
end
-- Every search in the auction house (yours, a shopping list, Search Auction House) brings fresh lowest prices;
-- they replace the scan's for items with a single variant, so the list doesn't keep a price that has changed.
local priceSoon
-- itemID -> keys of the saved scan, built once per scan
local index
local function KeysById(data)
	if index and index.data == data then return index.map end
	local map = {}
	for key in pairs(data.items) do
		local id = tonumber(key:match("^(%d+)"))
		if id then map[id] = map[id] or {}; table.insert(map[id], key) end
	end
	index = { data = data, map = map }
	return map
end
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
	local keysOf = KeysById(data)
	local changed = false
	for id, price in pairs(fresh) do
		local keys = keysOf[id]
		-- only when the item has one variant on both sides; "of the Owl" and "of the Bear" can't be told apart here
		if keys and #keys == 1 and variants[id] == 1 and data.items[keys[1]] then
			local old, link = data.items[keys[1]]:match("^(%d+)|(.+)$")
			if tonumber(old) ~= price then
				data.items[keys[1]] = price .. "|" .. link
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

-- results come a page at a time; their prices are taken at most every 0.3 s
local browseSoon
local function OnBrowse()
	OpenPending()
	if browseSoon then return end
	browseSoon = true
	C_Timer.After(0.3, function() browseSoon = false; TakeBrowsePrices() end)
end
GL:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
GL:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)
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
	local this = { id = tonumber(id), suffix = tonumber(suffix) or 0, untilT = GetTime() + 10, key = key, link = link }
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
