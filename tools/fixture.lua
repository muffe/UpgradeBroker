-- tools/fixture.lua: writes a recording as a test fixture (tools/import-record.lua, and tests/replay.lua when it
-- takes the ratings of a changed model as the new reference). dofile("tools/fixture.lua").Write(rec, path)
local M = {}

-- a Lua table, keys sorted so a new recording gives a readable diff; next to it the packed copy the repository keeps
function M.Write(rec, to)
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
end

return M
