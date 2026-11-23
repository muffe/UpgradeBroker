-- tests/game.lua: the game outside the game. Mock widgets, the auction house, Blizzard settings, and the whole
-- addon loaded in TOC order. require("game") returns { GL, T, replicate, new, check, try, fails, settings }.
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
		if type(x) == "number" and not T.source then
			for _, r in ipairs(replicate) do if r.id == x then return orig(r.link) end end
			return nil
		end
		return orig(x)
	end
end)(C_Item.GetItemInfoInstant)

---------------------------------------------------------------------------
-- Blizzard's settings (no EllesmereUI in these tests)
local registered, openedID
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name, GetID = function() return 42 end } end,
	RegisterAddOnCategory = function(c) registered = c end,
	OpenToCategory = function(id) openedID = id end,
}

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

return {
	GL = GL, T = T, replicate = replicate, new = new, check = check, try = try,
	fails = function() return fails end,
	-- what the addon did with Blizzard's settings: the category it registered, the one it opened
	settings = function() return registered, openedID end,
}
