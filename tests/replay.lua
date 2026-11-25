-- tests/replay.lua: lua5.1 tests/replay.lua [fixture]. Plays back a recording from the real client (/ub record,
-- tools/import-record.lua) instead of made-up items: real links, tooltips, auction rows and characters. Checks
-- that the offline rating matches the game's, that every saved character gets plausible upgrades, and that a full
-- scan stays within frame, time and memory budgets.
-- UB_REBASELINE=1 lua5.1 tests/replay.lua: after a deliberate model change, takes this code's ratings as the new
-- reference and writes them into the fixture (until the next /ub record brings the game's own again).
-- the recording, unpacked (tools/import-record.lua writes both; the repository keeps only the .gz)
local path = arg[1] or "tests/fixtures/forever.lua"
local rec
local f = io.open(path)
if f then
	f:close()
	rec = dofile(path)
else
	f = io.open(path .. ".gz")
	if not f then
		print("no recording at " .. path .. " (see tools/import-record.lua), skipped")
		os.exit(0)
	end
	f:close()
	local pipe = assert(io.popen(("gzip -dc %q"):format(path .. ".gz")))
	rec = assert(loadstring(pipe:read("*a"), "=" .. path .. ".gz"))()
	pipe:close()
end

package.path = "tests/?.lua;" .. package.path
local G = require("game")
local GL, T, check = G.GL, G.T, G.check

---------------------------------------------------------------------------
-- The recorded client
---------------------------------------------------------------------------
local PART, LINE, FIELD = GL.Record.PART, GL.Record.LINE, GL.Record.FIELD
local function Split(s, sep)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
	return out
end
-- recorded fields back to values; the ones in keep stay strings
local function Values(s, keep)
	local t = Split(s, FIELD)
	for i, v in ipairs(t) do
		if v == "" then t[i] = nil
		elseif v == "true" then t[i] = true
		elseif v == "false" then t[i] = false
		elseif not (keep and keep[i]) then t[i] = tonumber(v) or v end
	end
	return t
end
local INFO_TEXT, INSTANT_TEXT = { [1] = true, [2] = true, [9] = true }, { [2] = true, [3] = true, [4] = true }

local items, ids = {}, {}
local function Item(link)
	local hit = items[link]
	if hit ~= nil then return hit or nil end
	local e = rec.items[link]
	if not e then items[link] = false return nil end
	local p = Split(e, PART)
	local stats = {}
	for k, v in (p[3] or ""):gmatch("([^=,]+)=([^,]*)") do stats[k] = tonumber(v) end
	local lines
	if p[4] ~= "-" then
		lines = {}
		for _, l in ipairs(Split(p[4], LINE)) do
			local v = Values(l, { true, true, true, true })
			local function color(c)
				if not c then return nil end
				local r, g, b = c:match("([^,]+),([^,]+),([^,]+)")
				return { r = tonumber(r), g = tonumber(g), b = tonumber(b) }
			end
			lines[#lines + 1] = { leftText = v[1], rightText = v[2], leftColor = color(v[3]), rightColor = color(v[4]) }
		end
	end
	hit = { info = Values(p[1], INFO_TEXT), instant = Values(p[2], INSTANT_TEXT), stats = stats, lines = lines }
	items[link] = hit
	return hit
end
local function ID(id)
	if not id then return nil end
	local hit = ids[id]
	if hit ~= nil then return hit or nil end
	local e = rec.ids[id]
	if not e then ids[id] = false return nil end
	local p = Split(e, PART)
	hit = { instant = Values(p[1], INSTANT_TEXT), unique = Values(p[2] or "") }
	ids[id] = hit
	return hit
end

T.source = {
	GetItemInfoInstant = function(x)
		local d = type(x) == "number" and ID(x) or Item(x) or ID(tonumber(tostring(x):match("item:(%d+)")))
		if d then return unpack(d.instant, 1, 7) end
	end,
	GetItemInfo = function(link)
		local d = Item(link)
		if d then return unpack(d.info, 1, 13) end
	end,
	GetItemStats = function(link)
		local d, t = Item(link), {}
		for k, v in pairs(d and d.stats or {}) do t[k] = v end
		return t
	end,
	GetHyperlink = function(link)
		local d = Item(link)
		return d and d.lines and { lines = d.lines } or nil
	end,
}
-- decoded once up front, so the memory checks below see only what the addon holds
for link in pairs(rec.items) do Item(link) end
for id in pairs(rec.ids) do ID(id) end
C_Item.GetItemUniquenessByID = function(id)
	local d = ID(id)
	if d then return unpack(d.unique, 1, 3) end
end

local rows = {}
for i, r in ipairs(rec.rows or {}) do
	local v = Values(r, { [7] = true })
	rows[i] = { id = v[1], buyout = v[2], count = v[3], quality = v[4], mine = v[5] == 1, hasAll = v[6] == 1, link = v[7] }
end
C_AuctionHouse.GetNumReplicateItems = function() return #rows end
C_AuctionHouse.GetReplicateItemInfo = function(i)
	local r = rows[i + 1]
	return "n", nil, r.count, r.quality, true, 30, nil, 0, 0, r.buyout, 0, nil, nil, r.mine and UnitName("player") or "Seller",
		nil, nil, r.id, r.hasAll and not (r.link and T.slow[r.link])
end
C_AuctionHouse.GetReplicateItemLink = function(i) return rows[i + 1].link end

-- A game that loads items the way the real one does (only with Client() on): on request, a few per frame,
-- and only so many at once; the oldest are dropped again. It says so with GET_ITEM_INFO_RECEIVED and, while
-- the auction house is open, REPLICATE_ITEM_LIST_UPDATE.
local linksOf = {}
for link in pairs(rec.items) do
	local id = tonumber(link:match("item:(%d+)"))
	if id then linksOf[id] = linksOf[id] or {}; table.insert(linksOf[id], link) end
end
for _, r in ipairs(rows) do
	if r.link and not rec.items[r.link] then linksOf[r.id] = linksOf[r.id] or {}; table.insert(linksOf[r.id], r.link) end
end
local client
local function Client(perSecond, cap, loaded)
	client = { perFrame = perSecond / 60, cap = cap, credit = 0, wanted = {}, asked = {}, held = {}, order = {} }
	for id, links in pairs(linksOf) do
		local on = loaded(id)
		for _, l in ipairs(links) do T.slow[l] = not on or nil end
		if on then client.held[id] = true; client.order[#client.order + 1] = id end
	end
end
local function NoClient() client = nil; T.slow = {} end
C_Item.RequestLoadItemDataByID = function(id)
	if client and not client.held[id] and not client.asked[id] then
		client.asked[id] = true
		client.wanted[#client.wanted + 1] = id
	end
end
local function Deliver()
	if not client then return end
	client.credit = client.credit + client.perFrame
	local any = false
	while client.credit >= 1 and #client.wanted > 0 do
		client.credit = client.credit - 1
		local id = table.remove(client.wanted, 1)
		client.asked[id], client.held[id] = nil, true
		client.order[#client.order + 1] = id
		for _, l in ipairs(linksOf[id] or {}) do T.slow[l] = nil end
		if #client.order > client.cap then
			local old = table.remove(client.order, 1)
			client.held[old] = nil
			for _, l in ipairs(linksOf[old] or {}) do T.slow[l] = true end
		end
		GL:Fire("GET_ITEM_INFO_RECEIVED", id, true)
		any = true
	end
	if any and GL.Scanner.ahOpen then GL:Fire("REPLICATE_ITEM_LIST_UPDATE") end
end

-- Frames: timers run on a clock that moves 1/60 s per frame; each frame's real time is measured.
local queue, now = {}, 0
C_Timer.After = function(d, fn) queue[#queue + 1] = { at = now + (d or 0), fn = fn } end
GetTime = function() return now end
local frames = {}
local function RunFrames()
	frames = { n = 0, max = 0, total = 0, slow = 0 }
	while #queue > 0 or (client and #client.wanted > 0) do
		now = now + 1 / 60
		local soonest = math.huge
		for _, e in ipairs(queue) do soonest = math.min(soonest, e.at) end
		if soonest > now and not (client and #client.wanted > 0) then now = soonest end
		Deliver()
		local due, keep = {}, {}
		for _, e in ipairs(queue) do if e.at <= now then due[#due + 1] = e else keep[#keep + 1] = e end end
		queue = keep
		local t0 = os.clock()
		for _, e in ipairs(due) do e.fn() end
		local ms = (os.clock() - t0) * 1000
		frames.n, frames.total, frames.max = frames.n + 1, frames.total + ms, math.max(frames.max, ms)
		if ms > 1000 / 60 then frames.slow = frames.slow + 1 end
	end
	return frames
end

local errors = {}
GL.Error = function(_, err) errors[#errors + 1] = tostring(err) end
local function try(name, fn)
	local ok, err = pcall(fn)
	check(name, ok)
	if not ok then print("     " .. tostring(err)) end
end
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function MB() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") / 1024 end

---------------------------------------------------------------------------
-- The recorded state
---------------------------------------------------------------------------
-- the character logged in here is a fresh one; the recorded ones are its alts
T.Reset({ level = 1, class = "WARRIOR", className = "Warrior", stats = { 20, 20, 20, 20, 20 }, hp = 60, mana = 0 })
GL.Character:Invalidate()
local key = GL.RealmKey()
for k, v in pairs(rec.settings or {}) do GL.db[k] = v end
GL.db.chars = GL.db.chars or {}
GL.db.chars[key] = {}
for name, d in pairs(rec.chars) do GL.db.chars[key][name] = d end
-- the scan as far as the game delivered its items while recording (the rest can't be rated here either)
local function LinkOf(k) return rec.scan.items[k]:match("^%d+|(.+)$") end
local keys, scanned = {}, 0
for k in pairs(rec.scan.items) do
	scanned = scanned + 1
	if rec.items[LinkOf(k)] then keys[#keys + 1] = k end
end
table.sort(keys)
local function UseScan()
	local items = {}
	for _, k in ipairs(keys) do items[k] = rec.scan.items[k] end
	GL.db.scans[key] = { time = rec.scan.time, items = items }
end
UseScan()

print(("recording: %d of %d scanned items loaded (%s dropped again), %d auction rows, %d characters, %s, build %s"):format(
	#keys, scanned, tostring(rec.forgotten or "?"), #rows, Count(rec.chars), rec.player, table.concat(rec.build or {}, " ")))

-- the window must be open for a rating
GL.Window:Toggle()
RunFrames()
local frame = _G.UpgradeBrokerFrame
assert(frame and frame:IsShown(), "window open")

local rated, ratedLink = 0, {}
local realRate = GL.Compare.Rate
GL.Compare.Rate = function(self, link, ...)
	rated = rated + 1
	ratedLink[link] = (ratedLink[link] or 0) + 1
	return realRate(self, link, ...)
end

local function Fresh()
	GL.Items.ClearCache(); GL.Compare:ClearCache()
	GL.Character:Invalidate()
end
-- rates the whole scan for one saved character (switching to it starts the rating), measured
local function RateFor(name)
	Fresh()
	local r0 = rated
	GL:SetViewing(name)
	return { frames = RunFrames(), rated = rated - r0 }
end

---------------------------------------------------------------------------
-- The recording itself
---------------------------------------------------------------------------
try("recording: the game delivered most scanned items", function()
	assert(#keys >= scanned * 0.9, ("only %d of %d items loaded while recording"):format(#keys, scanned))
end)

try("every scanned item reads without an error", function()
	local bad, none = {}, 0
	for _, k in ipairs(keys) do
		local link = LinkOf(k)
		if rec.items[link] then
			local ok, item = pcall(GL.Items.Get, link)
			if not ok then bad[#bad + 1] = link .. ": " .. tostring(item) elseif not item then none = none + 1 end
		end
	end
	assert(#bad == 0, #bad .. " errors, first: " .. tostring(bad[1]))
	assert(none == 0, none .. " recorded items read as nothing")
end)

-- "Special effects are not counted" only for items that have one: every other Equip line is read as a stat.
-- A new kind of line on the auction house shows up here first.
local EFFECTS = { "^use:", "^chance on hit", "chance", "pierce", " against ", "^equip: increased [%a%- ]+ %+%d+%.?$",
	"stealth", "swim", "movement speed", "breath", "fashion", "dying", "taken increased", "weapon damage",
	"damage to your weapon", "damage done to %a+ by" }
try("every Equip line is read as a stat, or is an effect", function()
	local unknown, seen = {}, {}
	for _, k in ipairs(keys) do
		local link = LinkOf(k)
		local item = GL.Items.Get(link)
		if item and item.effect then
			local real = false
			local lines = {}
			for _, l in ipairs(Item(link).lines or {}) do
				local t = (l.leftText or ""):lower()
				if t:find("^equip:") or t:find("^use:") or t:find("^chance on hit") then
					lines[#lines + 1] = t
					for _, pat in ipairs(EFFECTS) do if t:find(pat) then real = true end end
				end
			end
			if not real then
				local text = table.concat(lines, " / "):gsub("%d+", "N")
				if not seen[text] then seen[text] = true; unknown[#unknown + 1] = text end
			end
		end
	end
	assert(#unknown == 0, #unknown .. " kinds of lines not read:\n     " .. table.concat(unknown, "\n     ", 1, math.min(8, #unknown)))
end)

---------------------------------------------------------------------------
-- Reading the auction house
---------------------------------------------------------------------------
if #rows > 0 then
	try("scan: variants of one item stay apart (of the Owl, of the Bear, ...)", function()
		GL.Scanner.ahOpen = true
		GL.db.lastReplicate = 0
		GL.Scanner.state = "idle"
		assert(GL.Scanner:Start())
		GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
		RunFrames()
		local data = GL.Scanner:Data()
		assert(data and data.items, "the scan was read")
		-- names in the auction rows, independent of how the scanner builds its keys
		local names, keysOf = {}, {}
		for _, r in ipairs(rows) do
			if r.link and not r.mine and r.count == 1 and (r.buyout or 0) > 0 and (r.quality or 0) >= 1 then
				local name = r.link:match("|h%[(.-)%]|h")
				names[r.id] = names[r.id] or {}
				if name then names[r.id][name] = true end
			end
		end
		for k in pairs(data.items) do
			local id = tonumber(k:match("^(%d+)"))
			keysOf[id] = (keysOf[id] or 0) + 1
		end
		local lost, example = 0, nil
		for id, set in pairs(names) do
			if Count(set) > (keysOf[id] or 0) then lost = lost + 1; example = example or next(set) end
		end
		assert(lost == 0, lost .. " items lost variants, e.g. " .. tostring(example))
		-- every kept auction is the cheapest of its kind
		local cheapest = {}
		for _, r in ipairs(rows) do
			local k = r.link and GL.Scanner.KeyOf(r.link)
			if k and not r.mine and r.count == 1 and (r.buyout or 0) > 0 and (r.quality or 0) >= 1 then
				cheapest[k] = math.min(cheapest[k] or math.huge, r.buyout)
			end
		end
		for k, e in pairs(data.items) do
			local price = tonumber(e:match("^(%d+)"))
			assert(price == cheapest[k], k .. " kept " .. tostring(price) .. ", cheapest " .. tostring(cheapest[k]))
		end
		GL.Scanner.ahOpen = false
		GL:Fire("AUCTION_HOUSE_CLOSED")
		UseScan()
	end)
else
	print("(no auction rows in the recording: record with the auction house open after a scan)")
end

---------------------------------------------------------------------------
-- Same answers as the game
---------------------------------------------------------------------------
-- the recording rated every scan item for every character whose gear was there, the way the game saw them
local REBASELINE = os.getenv("UB_REBASELINE") == "1"
local goldNames = {}
for name in pairs(rec.golden or {}) do goldNames[#goldNames + 1] = name end
table.sort(goldNames)
for _, who in ipairs(goldNames) do
try(("ratings match the %s for %s"):format(rec.goldenSource or "game's", who), function()
	Fresh()
	GL:SetViewing(who)
	RunFrames()
	local s = GL.Character:Viewed()
	assert(s and not s.incomplete, "snapshot of " .. who)
	local diff, compared = {}, 0
	for _, k in ipairs(keys) do
		local g = rec.golden[who][k]
		if g then
			local want = Values(g, { true, nil, nil, true })
			-- tooltips are red for what the recording character can't use; saved characters skip that line
			if not (want[1] == "no" and want[2] == "blocked") then
				local link = LinkOf(k)
				if REBASELINE then rec.golden[who][k] = GL.Record.Golden(link, s) or g end
				local reject = GL.Compare.QuickReject(s, link)
				local res = not reject and GL.Compare:Rate(link, s)
				local got
				if reject then got = { "reject", reject }
				elseif not res then got = { "missing" }
				elseif not res.ok then got = { "no", res.reason }
				else got = { "ok", res.gain.total, res.slot, res.reason } end
				compared = compared + 1
				local same = got[1] == want[1]
				if same and want[1] == "ok" then
					same = math.abs(got[2] - want[2]) < 0.01 and got[3] == want[3]
				elseif same then
					same = got[2] == want[2]
				end
				if not same and not REBASELINE then
					diff[#diff + 1] = ("%s: game %s %s, here %s %s"):format(link:match("%[(.-)%]") or k, tostring(want[1]),
						tostring(want[2]), tostring(got[1]), tostring(got[2]))
				end
			end
		end
	end
	assert(compared > 0, "nothing to compare")
	assert(#diff == 0, ("%d of %d differ:\n     %s"):format(#diff, compared, table.concat(diff, "\n     ", 1, math.min(5, #diff))))
end)
end

-- written before the tests below, which change the saved characters the recording shares with the addon
if REBASELINE then
	rec.goldenSource = "model's reference"
	local out = path:gsub("%.gz$", "")
	dofile("tools/fixture.lua").Write(rec, out)
	print("new reference ratings written to " .. out .. " and .gz")
end

---------------------------------------------------------------------------
-- Every character: plausible upgrades, within the budgets
---------------------------------------------------------------------------
-- Frames: the slices are 2 ms, so a rating fits in a 60 fps frame; a garbage collection step may make a few
-- longer, but none may cost two whole frames. Memory: what a rating keeps while the window is open, and what
-- stays after it closes.
local SLOW_SHARE, FRAME_MS, HELD_MB, LEFT_MB = 0.05, 33, 60, 5
local CLOTH = { MAGE = true, PRIEST = true, WARLOCK = true }

local names = {}
for name in pairs(rec.chars) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
	local d = rec.chars[name]
	local label = ("%s (%s %d)"):format(name, d.class, d.level)
	try(label .. ": plausible upgrades, within frame, time and memory budgets", function()
		local before = MB()
		errors = {}
		local m = RateFor(name)
		local s = GL.Character:Viewed()
		assert(s and not s.incomplete and not GL.Scanner.loadFailed, name .. "'s gear is missing in the recording")
		assert(#errors == 0, #errors .. " errors, first: " .. tostring(errors[1]))
		assert(GL.Scanner.state == "idle", "rating ended in " .. GL.Scanner.state)
		local n, bad = 0, {}
		for _, list in pairs(GL.Scanner.all or {}) do
			for _, e in ipairs(list) do
				n = n + 1
				local it = e.item
				local why
				if not (e.gain == e.gain and e.gain > 0 and e.gain < 1e6) then why = "gain " .. tostring(e.gain) end
				if CLOTH[d.class] and it.classID == 4 and it.subclassID and it.subclassID >= 2 and it.subclassID <= 4 then why = "armor type" end
				if not e.later and (it.reqLevel or 0) > d.level then why = "level " .. tostring(it.reqLevel) end
				if why then bad[#bad + 1] = it.name .. ": " .. why end
			end
		end
		assert(#bad == 0, #bad .. " implausible, first: " .. tostring(bad[1]))
		local held = MB() - before
		frame:Hide()
		RunFrames()
		local left = MB() - before
		frame:Show()
		RunFrames()
		print(("     %d upgrades of %d items; %.0f ms in %d frames (%.2f ms per item, slowest frame %.1f ms); %.1f MB held, %.1f MB left after closing")
			:format(n, #keys, m.frames.total, m.frames.n, m.frames.total / math.max(1, #keys), m.frames.max, held, left))
		assert(m.frames.max <= FRAME_MS, ("a frame took %.1f ms (budget %d)"):format(m.frames.max, FRAME_MS))
		assert(m.frames.slow <= m.frames.n * SLOW_SHARE + 2, ("%d of %d frames over 16.7 ms"):format(m.frames.slow, m.frames.n))
		assert(held <= HELD_MB, ("rating holds %.1f MB (budget %d)"):format(held, HELD_MB))
		assert(left <= LEFT_MB, ("%.1f MB stay after closing the window (budget %d)"):format(left, LEFT_MB))
	end)
end

---------------------------------------------------------------------------
-- No heavy work while playing
---------------------------------------------------------------------------
try("loot, durability and gear changes with the window closed rate nothing from the scan", function()
	GL:SetViewing(nil)
	frame:Hide()
	RunFrames()
	local before, mem = rated, MB()
	for i = 1, 30 do
		T.equipped[1] = (i % 2 == 0) and next(rec.items) or nil -- a different helmet every other event
		GL:Fire("UNIT_INVENTORY_CHANGED", "player")
		GL:Fire("BAG_UPDATE_DELAYED")
		RunFrames()
	end
	T.equipped[1] = nil
	local grown = MB() - mem
	assert(rated - before < 50, (rated - before) .. " ratings while the window was closed")
	assert(grown < 2, ("%.1f MB grew while the window was closed"):format(grown))
	frame:Show()
	RunFrames()
end)

---------------------------------------------------------------------------
-- Items the client loads late
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- A game that loads items slowly and drops them again
---------------------------------------------------------------------------
-- the character with the highest level: the most items to rate
local main = names[1]
for _, name in ipairs(names) do if rec.chars[name].level > rec.chars[main].level then main = name end end

if #rows > 0 then
	try("scan: auctions whose item loads after the read still join the scan", function()
		-- what the scan should hold: the cheapest of every kind among all auctions with a link
		local want = {}
		for _, r in ipairs(rows) do
			local k = r.link and GL.Scanner.KeyOf(r.link)
			if k and not r.mine and r.count == 1 and (r.buyout or 0) > 0 and (r.quality or 0) >= 1 then
				want[k] = math.min(want[k] or math.huge, r.buyout)
			end
		end
		-- the game has loaded half of the items when the read starts, and delivers 200 a second after that
		Client(200, 4000, function(id) return id % 2 == 0 end)
		GL:SetViewing(main)
		RunFrames()
		GL.Scanner.ahOpen = true
		GL.db.lastReplicate = 0
		GL.Scanner.state = "idle"
		assert(GL.Scanner:Start())
		GL:Fire("REPLICATE_ITEM_LIST_UPDATE")
		RunFrames()
		NoClient()
		local data = GL.Scanner:Data()
		local lost, wrong, example = 0, 0, nil
		for k, price in pairs(want) do
			local got = data.items[k] and tonumber(data.items[k]:match("^(%d+)"))
			if not got then lost = lost + 1; example = example or k elseif got ~= price then wrong = wrong + 1 end
		end
		print(("     %d kinds of gear, %d missing, %d with the wrong price, %.0f s"):format(Count(want), lost, wrong, now))
		assert(lost == 0, lost .. " kinds missing from the scan, e.g. " .. tostring(example))
		assert(wrong == 0, wrong .. " kinds without their cheapest price")
		GL.Scanner.ahOpen = false
		GL:Fire("AUCTION_HOUSE_CLOSED")
		UseScan()
	end)
end

try("a game that loads items slowly: each rated as it arrives, once, and all of them", function()
	-- nothing loaded but the gear; 150 items a second, at most 3000 held
	local worn = {}
	local function Wear(l) local id = tonumber((l:match("item:(%d+)"))) if id then worn[id] = true end end
	for _, d in pairs(rec.chars) do
		for _, l in pairs(d.equipped or {}) do Wear(l) end
		for _, l in ipairs(d.bagWeapons or {}) do Wear(l) end
	end
	Client(150, 3000, function(id) return worn[id] end)
	local states, wentBack, active, last = {}, nil, true, -1
	GL:On("GL_SCAN_STATE", function()
		if not active then return end
		if GL.Scanner.state == "rating" then
			if GL.Scanner.progress < last - 1e-9 then wentBack = ("%.3f after %.3f"):format(GL.Scanner.progress, last) end
			last = GL.Scanner.progress
		end
		states[#states + 1] = GL.Scanner.state
	end)
	Fresh()
	ratedLink = {}
	local t0 = now
	GL:SetViewing(main)
	RunFrames()
	active = false
	local waited = now - t0
	NoClient()
	assert(GL.Scanner.state == "idle", GL.Scanner.state)
	assert(not GL.Scanner.loadFailed and GL.Scanner.lastStats, "nothing was rated")
	local most, link = 0, nil
	for l, n in pairs(ratedLink) do if n > most then most, link = n, l end end
	print(("     %d items, %.0f s, %d still missing, at most %d ratings for one item"):format(#keys, waited,
		GL.Scanner.lastStats.missing, most))
	assert(not wentBack, "the bar went back: " .. tostring(wentBack))
	assert(GL.Scanner.lastStats.missing == 0, GL.Scanner.lastStats.missing .. " never rated")
	-- once while the game loads it, once when it is there (and once more if a quiet spell made it look again)
	assert(most <= 3, ("%s was rated %d times"):format(tostring(link), most))
	for i = 2, #states do assert(not (states[i - 1] == "idle" and states[i] == "rating"), "the rating started over") end
end)

local fails = G.fails()
print(fails == 0 and "all ok" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
