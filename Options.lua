-- Options.lua: the settings. One list, shown three ways: a page in the EllesmereUI options (its plugin API), a page
-- over the upgrade window (the gear button), and without EllesmereUI under Esc > Options > AddOns. "/ub set <name>"
-- toggles the on/off ones from chat.
local _, GL = ...

local Options = {}
GL.Options = Options

-- the change reaches the list through GL_CHANGED (caches cleared first, then rated again)
local function Changed()
	GL:Invalidate()
end

local function db() return GL.db end

-- kind: "section", "toggle", "choice" (values + order), "number" (min, max, step, format).
-- euiOnly: spec and mode, which the window's header already has for whoever it shows.
local LIST = {
	{ kind = "section", label = "SHOW" },
	{ kind = "toggle", key = "tooltip", label = "Upgrades in item tooltips" },
	{ kind = "toggle", key = "bagMarkers", label = "Upgrade badges in bags", after = function() GL.Bags:Refresh() end },
	{ kind = "toggle", key = "questMarkers", label = "Upgrade badges on quest rewards" },
	{ kind = "choice", label = "Upgrade percentage", values = { character = "Whole character", item = "Item vs. worn" },
		order = { "character", "item" },
		get = function() return db().itemPct and "item" or "character" end,
		set = function(v) db().itemPct = v == "item"; Changed() end },
	{ kind = "section", label = "SCORING" },
	{ kind = "choice", label = "Spec", euiOnly = true,
		values = function()
			local t, order = {}, {}
			for _, s in ipairs(GL.Specs.ForClass(GL.PlayerClass())) do t[s.key] = s.name; order[#order + 1] = s.key end
			return t, order
		end,
		get = function() return GL.Character.SpecKey(GL.PlayerClass()) end,
		set = function(v) GL:SetSpec(v) end },
	{ kind = "choice", label = "Score gear for", euiOnly = true,
		values = { auto = "Auto (Raiding at 60)", level = "Leveling", endgame = "Raiding" }, order = { "auto", "level", "endgame" },
		get = function() return GL.cdb.mode or "auto" end,
		set = function(v) GL.cdb.mode = (v ~= "auto") and v or nil; Changed() end,
		tip = "Leveling scores gear for solo questing against same-level enemies. Raiding scores gear for raid bosses." },
	{ kind = "toggle", key = "ownArmorOnly", label = "Only my main armor type", rates = true,
		tip = "Skip lighter armor types your class can technically wear (such as Mail on a level 40+ Warrior)." },
	{ kind = "number", key = "levelsAhead", label = "Levels ahead to show", min = 0, max = 10, step = 1, rates = true },
	{ kind = "number", key = "minGain", label = "Minimum upgrade (%)", min = 0.1, max = 5, step = 0.1, rates = true,
		format = function(v) return ("%.1f%%"):format(v) end },
}
Options.LIST = LIST

local function Get(o) if o.get then return o.get() end return db()[o.key] end
-- quiet: no side effects (EllesmereUI builds its pages once ahead of time for its search)
local function Set(o, v, quiet)
	if o.set then o.set(v) return end
	db()[o.key] = v
	if quiet then return end
	if o.after then o.after() end
	if o.rates then Changed() end
end
local function Values(o)
	if type(o.values) == "function" then return o.values() end
	return o.values, o.order
end

---------------------------------------------------------------------------
-- EllesmereUI
---------------------------------------------------------------------------
local function BuildPage(page, parent, y)
	local W = EllesmereUI.Widgets
	local h
	local pre = EllesmereUI.IsSearchPrebuild and EllesmereUI.IsSearchPrebuild()
	if page == "General" then
		for _, o in ipairs(LIST) do
			if o.kind == "section" then
				_, h = W:SectionHeader(parent, o.label, y)
			elseif o.kind == "toggle" then
				_, h = W:Toggle(parent, o.label, y, function() return Get(o) end,
					function(v) Set(o, v, pre) end, o.tip)
			elseif o.kind == "choice" then
				local values, order = Values(o)
				_, h = W:Dropdown(parent, o.label, y, values, function() return Get(o) end, function(v) Set(o, v) end, order, o.tip)
			elseif o.kind == "number" then
				_, h = W:Slider(parent, o.label, y, o.min, o.max, o.step, function() return Get(o) end, function(v) Set(o, v) end)
			end
			y = y - h
		end
	end
	if page == "How scores work" and not pre then
		local width = math.max(300, (parent:GetWidth() or 600) - 90)
		y = y - 10 - GL.Info.Fill(parent, width, 45, y - 10)
	end
	return math.abs(y)
end

local function UseEUI() return EllesmereUI and EllesmereUI.RegisterPlugin end

---------------------------------------------------------------------------
-- Our own page (the window's gear button; Esc > Options > AddOns without EllesmereUI)
---------------------------------------------------------------------------
local ROW, CONTROL_X = 32, 250

-- Lays the settings out in parent from the top. Returns the frame's refresh function and the height used.
function Options.Fill(parent)
	local T = GL.Theme
	local C = T.C
	local y, controls = 0, {}
	for _, o in ipairs(LIST) do
		if not o.euiOnly then
			if o.kind == "section" then
				if y < 0 then y = y - 12 end
				local h = T.Text(parent, 11, C.accent, true)
				h:SetPoint("TOPLEFT", 0, y)
				h:SetText(o.label)
				y = y - 24
			else
				local label = T.Text(parent, 12.5, C.dim)
				label:SetPoint("TOPLEFT", 0, y - 8)
				label:SetText(o.label)
				local c
				if o.kind == "toggle" then
					c = T.Switch(parent, function() return Get(o) end, function(v) Set(o, v) end)
				elseif o.kind == "choice" then
					local values, order = Values(o)
					c = T.Dropdown(parent, 170, function()
						local items = {}
						for _, k in ipairs(order) do items[#items + 1] = { k, values[k] } end
						return items
					end, function(v) Set(o, v) end)
					function c:Refresh() local v = Get(o); self:SetValue(v, values[v]) end
					c:Refresh()
				elseif o.kind == "number" then
					local steps = math.floor((o.max - o.min) / o.step + 0.5)
					local function value(step) return o.min + step * o.step end
					local fmt = o.format or function(v) return tostring(v) end
					c = T.Slider(parent, 140, 0, steps,
						function() return math.floor((Get(o) - o.min) / o.step + 0.5) end,
						function(step) Set(o, value(step)) end,
						function(step) return fmt(value(step)) end,
						function(text)
							local v = tonumber((text:gsub("[^%d%.]", "")))
							return v and math.floor((v - o.min) / o.step + 0.5) or nil
						end)
				end
				c:SetPoint("LEFT", parent, "TOPLEFT", CONTROL_X, y - ROW / 2 + 1)
				if o.tip then
					local hit = CreateFrame("Frame", nil, parent)
					hit:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 4); hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -4)
					hit:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:AddLine(o.label)
						GameTooltip:AddLine(o.tip, 1, 1, 1, true)
						GameTooltip:Show()
					end)
					hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
				controls[#controls + 1] = c
				y = y - ROW
			end
		end
	end
	local function refresh() for _, c in ipairs(controls) do c:Refresh() end end
	return refresh, -y
end

-- The page over the upgrade window's body (built on first use), like "How scores work".
function Options.Overlay(host)
	if Options.overlay then return Options.overlay end
	local T = GL.Theme
	local o = CreateFrame("Frame", nil, host)
	o:SetAllPoints()
	o:SetFrameLevel(host:GetFrameLevel() + 20)
	o:EnableMouse(true)
	T.Fill(o, { T.C.bg[1], T.C.bg[2], T.C.bg[3], 1 })
	local content = CreateFrame("Frame", nil, o)
	content:SetPoint("TOPLEFT", 24, -18); content:SetPoint("BOTTOMRIGHT", -24, 12)
	o.Refresh = Options.Fill(content)
	o:Hide()
	Options.overlay = o
	return o
end

-- Esc > Options > AddOns, only without EllesmereUI (its own options have the page). A canvas page of our own
-- widgets: Blizzard's settings rows run addon code inside its secure list and can taint it.
local function RegisterBlizzard()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local frame = CreateFrame("Frame")
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 16, -16); content:SetPoint("BOTTOMRIGHT", -16, 16)
	Options.Fill(content)
	local category = Settings.RegisterCanvasLayoutCategory(frame, "Upgrade Broker")
	Settings.RegisterAddOnCategory(category)
	Options.category = category
end

function Options:Register()
	if not UseEUI() then RegisterBlizzard() return end
	EllesmereUI.RegisterPlugin(GL.name, {
		label = "Upgrade Broker",
		modules = {
			{ key = "General", title = "Upgrade Broker", description = "Shows gear upgrades in tooltips, bags, quest rewards, and the Auction House.",
				pages = { "General", "How scores work" }, buildPage = BuildPage,
				onReset = function()
					-- settings only: scans and remembered characters stay
					local scans, chars = GL.db.scans, GL.db.chars
					wipe(GL.db)
					GL.db.scans, GL.db.chars = scans, chars
					GL.FillDefaults()
					Changed()
				end },
		},
	})
end

---------------------------------------------------------------------------
-- From chat
---------------------------------------------------------------------------
-- "/ub options": the AddOns page without EllesmereUI (or the list in chat, if the client has none)
function Options:Open()
	if Options.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.category:GetID())
		return
	end
	GL:Print("Settings (type /ub set <name> to toggle):")
	for _, o in ipairs(LIST) do
		if o.kind == "toggle" then GL:Print(("  %s  %s: %s"):format(o.key, o.label, Get(o) and "on" or "off")) end
	end
	GL:Print(("  itemPct  Upgrade percentage: %s"):format(GL.db.itemPct and "Item vs. worn" or "Whole character"))
end

function Options:Toggle(name)
	name = (name or ""):lower()
	if name == "itempct" then
		GL.db.itemPct = not GL.db.itemPct
		GL:Print("Upgrade percentage: " .. (GL.db.itemPct and "Item vs. worn" or "Whole character"))
		Changed()
		return
	end
	for _, o in ipairs(LIST) do
		if o.kind == "toggle" and o.key:lower() == name then
			Set(o, not Get(o))
			GL:Print(("%s: %s"):format(o.label, Get(o) and "on" or "off"))
			Changed()
			return
		end
	end
	Options:Open()
end

GL:On("GL_LOADED", function() Options:Register() end)
