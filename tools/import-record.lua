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

-- write it as a Lua table, keys sorted so a new recording gives a readable diff
local out = {}
local function emit(s) out[#out + 1] = s end
local function key(k)
	if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
	return "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "]"
end
local function write(v, indent)
	if type(v) == "string" then return emit(("%q"):format(v)) end
	if type(v) ~= "table" then return emit(tostring(v)) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	emit("{\n")
	for _, k in ipairs(keys) do
		emit(indent .. "\t" .. key(k) .. " = ")
		write(v[k], indent .. "\t")
		emit(",\n")
	end
	emit(indent .. "}")
end
emit("-- recorded with /ub record, imported by tools/import-record.lua\nreturn ")
write(rec, "")
emit("\n")
local f = assert(io.open(to, "wb"))
f:write(table.concat(out))
f:close()
-- the repository keeps the packed one (tests/replay.lua reads either)
os.execute(("gzip -9 -kf %q"):format(to))

local n = 0
for _ in pairs(rec.items or {}) do n = n + 1 end
print(("%s: %d items, %d auction rows, %d characters, %.1f MB"):format(to, n, #(rec.rows or {}), #names,
	#table.concat(out) / 1048576))
