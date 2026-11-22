-- Options.lua: settings live in the EllesmereUI options panel (its plugin API). Without EllesmereUI,
-- "/ub options" lists the settings and "/ub set <name>" toggles them.
local _, GL = ...

local Options = {}
GL.Options = Options

-- the change reaches the list through GL_CHANGED (caches cleared first, then rated again)
local function Changed()
	GL:Invalidate()
end

local function BuildPage(page, parent, y)
	local W = EllesmereUI.Widgets
	local h
	local pre = EllesmereUI.IsSearchPrebuild and EllesmereUI.IsSearchPrebuild()
	local db, cdb = GL.db, GL.cdb
	if page == "General" then
		_, h = W:SectionHeader(parent, "SHOW", y); y = y - h
		_, h = W:Toggle(parent, "Upgrades in item tooltips", y, function() return db.tooltip end,
			function(v) db.tooltip = v end); y = y - h
		_, h = W:Toggle(parent, "Upgrade badges in bags", y, function() return db.bagMarkers end,
			function(v) db.bagMarkers = v; if not pre then GL.Bags:Refresh() end end); y = y - h
		_, h = W:Toggle(parent, "Upgrade badges on quest rewards", y, function() return db.questMarkers end,
			function(v) db.questMarkers = v end); y = y - h

		_, h = W:SectionHeader(parent, "SCORING", y); y = y - h
		local specs, order = {}, {}
		for _, s in ipairs(GL.Specs.ForClass(GL.PlayerClass())) do specs[s.key] = s.name; order[#order + 1] = s.key end
		_, h = W:Dropdown(parent, "Spec", y, specs, function() return GL.Character.SpecKey(GL.PlayerClass()) end,
			function(v) GL:SetSpec(v) end, order); y = y - h
		_, h = W:Dropdown(parent, "Score gear for", y, { auto = "Auto (Raiding at 60)", level = "Leveling", endgame = "Raiding" },
			function() return cdb.mode or "auto" end,
			function(v) cdb.mode = (v ~= "auto") and v or nil; Changed(true) end, { "auto", "level", "endgame" },
			"Leveling scores gear for solo questing against same-level enemies. Raiding scores gear for raid bosses."); y = y - h
		_, h = W:Toggle(parent, "Only my main armor type", y, function() return db.ownArmorOnly end,
			function(v) db.ownArmorOnly = v; Changed(true) end,
			"Skip lighter armor types your class can technically wear (such as Mail on a level 40+ Warrior)."); y = y - h
		_, h = W:Slider(parent, "Levels ahead to show", y, 0, 10, 1, function() return db.levelsAhead end,
			function(v) db.levelsAhead = v; Changed(true) end); y = y - h
		_, h = W:Slider(parent, "Minimum upgrade (%)", y, 0.1, 5, 0.1, function() return db.minGain end,
			function(v) db.minGain = v; Changed(true) end); y = y - h
	end
	if page == "How scores work" and not pre then
		local width = math.max(300, (parent:GetWidth() or 600) - 90)
		y = y - 10 - GL.Info.Fill(parent, width, 45, y - 10)
	end
	return math.abs(y)
end

function Options:Register()
	if not (EllesmereUI and EllesmereUI.RegisterPlugin) then return end
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
					Changed(true)
				end },
		},
	})
end

-- Without EllesmereUI
local TOGGLES = { tooltip = "Upgrades in item tooltips", bagMarkers = "Upgrade badges in bags", questMarkers = "Upgrade badges on quest rewards",
	ownArmorOnly = "Only my main armor type" }
function Options:Open()
	GL:Print("Settings (type /ub set <name> to toggle):")
	for k, label in pairs(TOGGLES) do GL:Print(("  %s  %s: %s"):format(k, label, GL.db[k] and "on" or "off")) end
end
function Options:Toggle(name)
	for k in pairs(TOGGLES) do
		if k:lower() == (name or ""):lower() then
			GL.db[k] = not GL.db[k]
			GL:Print(("%s: %s"):format(TOGGLES[k], GL.db[k] and "on" or "off"))
			Changed(true)
			return
		end
	end
	Options:Open()
end

GL:On("GL_LOADED", function() Options:Register() end)
