-- tools/import-record.lua: turns a /ub record from the game's SavedVariables into a test fixture.
--   lua5.1 tools/import-record.lua "<WoW>/_forever_/WTF/Account/<account>/SavedVariables/UpgradeBroker.lua" [tests/fixtures/forever.lua] [rows-from]
-- rows-from: an earlier fixture of the same scan, for a recording made without the auction house open (the scan
-- cooldown, or after a /reload) to take its auction rows from.
-- Character names become Char1, Char2, ... and the realm is dropped (the faction stays), so the fixture can be
-- shared. Afterwards /ub record clear in the game frees the memory again.
local from, to, rowsFrom = arg[1], arg[2] or "tests/fixtures/forever.lua", arg[3]
if not from then
	io.stderr:write("usage: lua5.1 tools/import-record.lua <SavedVariables/UpgradeBroker.lua> [fixture]\n")
	os.exit(2)
end

local env = {}
local chunk = assert(loadfile(from))
setfenv(chunk, env)
chunk()
local rec = env.UpgradeBrokerRecord
if type(rec) ~= "table" then
	io.stderr:write("no recording in " .. from .. ": /ub record in the game, wait for \"Recorded\", then /reload\n")
	os.exit(1)
end

if rowsFrom and #(rec.rows or {}) == 0 then
	local other = dofile(rowsFrom)
	if other.scan.time ~= rec.scan.time then
		io.stderr:write(rowsFrom .. " is from another scan; its auction rows don't fit\n")
		os.exit(1)
	end
	rec.rows, rec.browse = other.rows, other.browse
	-- the auction rows' item IDs (equipment slot and the like)
	for id, e in pairs(other.ids or {}) do if not rec.ids[id] then rec.ids[id] = e end end
end

-- names
local names, rename = {}, {}
for name in pairs(rec.chars or {}) do names[#names + 1] = name end
table.sort(names)
for i, name in ipairs(names) do rename[name] = "Char" .. i end
local chars = {}
for name, d in pairs(rec.chars or {}) do
	d.name = rename[name]
	chars[rename[name]] = d
end
rec.chars = chars
local golden = {}
for name, g in pairs(rec.golden or {}) do golden[rename[name] or name] = g end
rec.golden = golden
rec.player = rename[rec.player] or "Char0"
rec.realmKey = "-" .. (rec.realmKey or ""):match("([^-]*)$")
rec.charSettings = rec.charSettings or {}

dofile("tools/fixture.lua").Write(rec, to)

local n = 0
for _ in pairs(rec.items or {}) do n = n + 1 end
print(("%s: %d items, %d auction rows, %d characters"):format(to, n, #(rec.rows or {}), #names))
