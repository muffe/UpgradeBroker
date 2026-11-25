-- Record.lua: /ub record writes down what this client really returns, so tests/replay.lua can play it back
-- outside the game: the saved scan and characters, every scanned item's info, stats and tooltip, the auction
-- house's raw rows (when it is open after a scan) and this character's rating of every scanned item.
-- It runs only when asked, a slice per frame, into UpgradeBrokerRecord; /ub record clear frees it again.
local _, GL = ...

local Record = {}
GL.Record = Record

local BATCH_MS = 4
-- separators inside the recorded strings: item parts, tooltip lines, fields (bytes item text never holds)
local PART, LINE, FIELD = "\29", "\30", "\31"
Record.PART, Record.LINE, Record.FIELD = PART, LINE, FIELD

local function Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Copy(v) end
	return c
end

local function Join(t, n)
	local out = {}
	for i = 1, n do out[i] = t[i] == nil and "" or tostring(t[i]) end
	return table.concat(out, FIELD)
end

local function Color(c)
	if type(c) ~= "table" or not c.r then return nil end
	return ("%.2f,%.2f,%.2f"):format(c.r, c.g or 0, c.b or 0)
end

-- info, instant info, stats and tooltip lines of one item; nil while the client is still loading it
local function Encode(link)
	local info = { GL.Items.GetItemInfo(link) }
	if info[1] == nil then return nil end
	local stats = {}
	local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
	for k, v in pairs(GetItemStats and GetItemStats(link) or {}) do stats[#stats + 1] = k .. "=" .. tostring(v) end
	local tip = "-"
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if ok and type(data) == "table" and type(data.lines) == "table" then
		local lines = {}
		for _, l in ipairs(data.lines) do
			lines[#lines + 1] = Join({ l.leftText, l.rightText, Color(l.leftColor), Color(l.rightColor) }, 4)
		end
		tip = table.concat(lines, LINE)
	end
	return table.concat({ Join(info, 13), Join({ GL.Items.GetItemInfoInstant(link) }, 7), table.concat(stats, ","), tip }, PART)
end

-- instant info and uniqueness of an item ID
local function EncodeID(id)
	local unique = {}
	if C_Item and C_Item.GetItemUniquenessByID then
		local ok, a, b, c = pcall(C_Item.GetItemUniquenessByID, id)
		if ok then unique = { a, b, c } end
	end
	return Join({ GL.Items.GetItemInfoInstant(id) }, 7) .. PART .. Join(unique, 3)
end

-- what this client's rating says: reject|reason, no|reason, ok|gain|slot|reason; nil while loading
local function Golden(link, s)
	local reject = GL.Compare.QuickReject(s, link)
	if reject then return "reject" .. FIELD .. reject end
	local res = GL.Compare:Rate(link, s)
	if not res then return nil end
	if not res.ok then return "no" .. FIELD .. tostring(res.reason) end
	return Join({ "ok", ("%.6g"):format(res.gain and res.gain.total or 0), res.slot, res.reason }, 4)
end
Record.Golden = Golden

local run = 0
-- fn on every entry of list, a slice per frame, then done()
local function Slices(list, fn, done)
	local i, me = 0, run
	local function step()
		if me ~= run then return end
		local stop = debugprofilestop() + BATCH_MS
		while i < #list and debugprofilestop() < stop do
			i = i + 1
			fn(list[i])
		end
		if i < #list then C_Timer.After(0, step) else done() end
	end
	step()
end

function Record:Clear()
	run = run + 1
	self.busy = false
	UpgradeBrokerRecord = nil
	GL:Print("Recording cleared.")
end

function Record:Start()
	if self.busy then return GL:Print("Already recording.") end
	local key = GL.RealmKey()
	local scan = key and GL.db.scans[key]
	local s = GL.Character:Get()
	if not scan then return GL:Print("Scan the Auction House first.") end
	if not s or s.incomplete then return GL:Print("Your gear is still loading. Try again in a moment.") end
	GL.Character:Save()
	run = run + 1
	self.busy = true
	local me = run
	local rec = { version = 1, time = time(), build = GetBuildInfo and { GetBuildInfo() } or {}, player = UnitName("player"),
		realmKey = key, settings = {}, charSettings = Copy(GL.cdb), chars = Copy(GL.db.chars and GL.db.chars[key]),
		scan = Copy(scan), items = {}, ids = {}, rows = {}, browse = {}, golden = {} }
	for k, v in pairs(GL.db) do if type(v) ~= "table" then rec.settings[k] = v end end

	local seen, ids = {}, {}
	local function Want(list, link)
		if type(link) ~= "string" or seen[link] then return end
		seen[link] = true
		list[#list + 1] = link
		local id = tonumber(link:match("item:(%d+)"))
		if id then ids[id] = true end
	end
	-- the gear of every saved character first (their ratings need it), then the scan
	local gear, links = {}, {}
	for _, d in pairs(rec.chars or {}) do
		for _, l in pairs(d.equipped or {}) do Want(gear, l) end
		for _, l in ipairs(d.bagWeapons or {}) do Want(gear, l) end
	end
	local keys = {}
	for k, e in pairs(scan.items) do keys[#keys + 1] = k; Want(links, e:match("^%d+|(.+)$")) end
	table.sort(keys)

	local AH = C_AuctionHouse
	if GL.Scanner.ahOpen and AH and AH.GetBrowseResults then
		local ok, results = pcall(AH.GetBrowseResults)
		for _, r in ipairs(ok and type(results) == "table" and results or {}) do
			local k = r.itemKey or {}
			rec.browse[#rec.browse + 1] = Join({ k.itemID, k.itemLevel, k.itemSuffix, k.battlePetSpeciesID, r.minPrice, r.totalQuantity }, 6)
		end
	end
	local rows = {}
	if GL.Scanner.ahOpen and AH and AH.GetNumReplicateItems then
		for i = 0, (AH.GetNumReplicateItems() or 0) - 1 do rows[#rows + 1] = i end
	end
	local player = UnitName("player")
	GL:Print(("Recording %d items and %d auction rows..."):format(#gear + #links, #rows))

	-- scan keys by link, so an item is rated the moment its data is there
	local keysOf = {}
	for _, k in ipairs(keys) do
		local link = scan.items[k]:match("^%d+|(.+)$")
		if link then keysOf[link] = keysOf[link] or {}; table.insert(keysOf[link], k) end
	end
	local snaps, golden = {}, 0
	local function Finish(missing)
		-- how many items the game has dropped again since they were read (it keeps only so many loaded)
		local forgotten, read = 0, {}
		for link in pairs(rec.items) do read[#read + 1] = link end
		Slices(read, function(link) if GL.Items.GetItemInfo(link) == nil then forgotten = forgotten + 1 end end, function()
			rec.forgotten = forgotten
			local list = {}
			for id in pairs(ids) do list[#list + 1] = id end
			Slices(list, function(id) rec.ids[id] = EncodeID(id) end, function()
				rec.missing = missing
				UpgradeBrokerRecord = rec
				self.busy = false
				GL:Print(("Recorded %d items (%d never loaded, %d dropped again), %d auction rows, %d ratings. /reload saves it."):format(
					#gear + #links - missing, missing, forgotten, #rec.rows, golden))
			end)
		end)
	end
	-- passes over what is still loading, as long as the game keeps delivering; done(still loading)
	local function Items(todo, done, pass, before)
		pass, before = pass or 1, before or math.huge
		local later = {}
		Slices(todo, function(link)
			local e = Encode(link)
			if e then
				rec.items[link] = e
				for _, k in ipairs(keysOf[link] or {}) do
					for name, snap in pairs(snaps) do
						rec.golden[name][k] = Golden(link, snap)
						if rec.golden[name][k] then golden = golden + 1 end
					end
				end
				return
			end
			later[#later + 1] = link
			local id = tonumber(link:match("item:(%d+)"))
			if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		end, function()
			if #later > 0 and #later < before and pass < 40 then
				GL:Print(("Recording: %d items still loading..."):format(#later))
				C_Timer.After(3, function() if me == run then Items(later, done, pass + 1, #later) end end)
			else
				done(#later)
			end
		end)
	end
	-- every character whose gear is there gets rated: you as you are, the others as saved
	local function Characters(gearMissing)
		for name, d in pairs(rec.chars or {}) do
			local snap = name == player and s or GL.Character.FromSaved(d)
			if snap and not snap.incomplete then snaps[name] = snap; rec.golden[name] = {} end
		end
		Items(links, function(missing) Finish(missing + gearMissing) end)
	end
	Slices(rows, function(row)
		local _, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAll = AH.GetReplicateItemInfo(row)
		if not itemID then return end
		local _, _, _, equipLoc = GL.Items.GetItemInfoInstant(itemID)
		if not (equipLoc and GL.Items.EQUIP[equipLoc]) then return end
		local link = hasAll and AH.GetReplicateItemLink(row) or nil
		ids[itemID] = true
		rec.rows[#rec.rows + 1] = Join({ itemID, buyout, count, quality, owner == player and 1 or 0, hasAll and 1 or 0, link }, 7)
	end, function() Items(gear, Characters) end)
end
