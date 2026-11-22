-- UI/Window.lua: the upgrade window. Left: the best upgrade per slot. Right: the options for the chosen slot,
-- and why the chosen one is better. Shown as an auction house tab, or on its own with /ub.
local _, GL = ...

local Window = {}
GL.Window = Window

local T = GL.Theme
local C = T.C
local Scanner = GL.Scanner

local f
local LEFT_W, TOP_H = 330, 40
local rows, candRows = {}, {}
local selectedGroup, selectedLink, candOffset = nil, nil, 0

-- Max price steps (copper); the last one means no limit.
local PRICE_STEPS = { 1000, 2000, 5000, 10000, 20000, 30000, 50000, 70000, 100000, 150000, 200000, 300000,
	500000, 750000, 1000000, 1500000, 2000000, 3000000, 5000000, 10000000, 1e12 }
local function StepOf(copper)
	for i, v in ipairs(PRICE_STEPS) do if copper <= v then return i end end
	return #PRICE_STEPS
end
-- The exact limit: 12g 34s, 50s 50c, 10g.
local function PriceText(copper)
	if copper >= 1e12 then return "Any" end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end
-- "10" (gold), "12.5g", "12g 34s", "50s", "any"
local function ParsePrice(text)
	text = (text or ""):lower()
	if text:find("^%s*any%s*$") or text:find("^%s*$") then GL.db.maxPrice = PRICE_STEPS[#PRICE_STEPS] return #PRICE_STEPS end
	local copper
	local plain = tonumber(text:match("^%s*([%d%.]+)%s*$"))
	if plain then
		copper = plain * 10000
	else
		local rest = text:gsub("([%d%.]+)%s*([gsc])", function(n, unit)
			copper = (copper or 0) + (tonumber(n) or 0) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
			return ""
		end)
		if rest:find("%S") then return nil end
	end
	copper = copper and math.floor(copper + 0.5)
	if not copper or copper <= 0 then return nil end
	GL.db.maxPrice = copper
	return StepOf(GL.db.maxPrice)
end

local function Results() return Scanner.results end

-- The slot list is always in equipment order, so a slot is always in the same place; the order switch only
-- decides which item each slot shows (best value or biggest upgrade).
local function GroupList() return Scanner.GROUPS end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function ShowItemTip(owner, link)
	if not link then return end
	-- the tooltip rates for whoever the window shows (an alt), not for the character you play
	GL.tipSnap, GL.tipOwner = GL.Character:Viewed(), owner
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

local function MakeSlotRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r.odd = T.Fill(r, { 0, 0, 0, 0 })
	r.hl = T.Fill(r, { 1, 1, 1, 0 }, "BORDER")
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetTexture("Interface\\Buttons\\WHITE8X8")
	r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
	r.slot = T.Text(r, 11.5, C.dim)
	r.slot:SetPoint("LEFT", 12, 0); r.slot:SetWidth(62)
	r.icon = T.Icon(r, 18)
	r.icon:SetPoint("LEFT", 76, 0)
	-- the level needed, on the icon, for gear you can't wear yet
	r.lvl = r.icon:CreateFontString(nil, "OVERLAY")
	if not r.lvl:SetFont(T.FONT_BOLD, 9, "OUTLINE") then r.lvl:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE") end
	r.lvl:SetPoint("BOTTOMRIGHT", 2, -1)
	T.Color(r.lvl, C.warn)
	r.price = T.Text(r, 11.5, C.dim)
	r.price:SetPoint("RIGHT", -12, 0); r.price:SetJustifyH("RIGHT"); r.price:SetWidth(40)
	r.gain = T.Text(r, 12.5, C.up, true)
	r.gain:SetPoint("RIGHT", r.price, "LEFT", -6, 0); r.gain:SetJustifyH("RIGHT"); r.gain:SetWidth(44)
	r.name = T.Text(r, 12.5, C.text)
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0)
	r.name:SetPoint("RIGHT", r.gain, "LEFT", -6, 0)
	r:SetScript("OnEnter", function(self)
		if not self.selected then self.hl:SetVertexColor(1, 1, 1, 0.04) end
		if self.entry then ShowItemTip(self, self.entry.link) end
	end)
	r:SetScript("OnLeave", function(self)
		if not self.selected then self.hl:SetVertexColor(1, 1, 1, 0) end
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(self)
		selectedGroup, selectedLink, candOffset = self.group, nil, 0
		Window:Refresh()
	end)
	return r
end

local function MakeCandRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r.hl = T.Fill(r, { 1, 1, 1, 0 }, "BORDER")
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetTexture("Interface\\Buttons\\WHITE8X8")
	r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
	r.icon = T.Icon(r, 20)
	r.icon:SetPoint("LEFT", 16, 0)
	r.price = T.Text(r, 11.5, C.dim); r.price:SetPoint("RIGHT", -16, 0); r.price:SetWidth(64); r.price:SetJustifyH("RIGHT")
	r.gain = T.Text(r, 12.5, C.up, true); r.gain:SetPoint("RIGHT", r.price, "LEFT", -8, 0); r.gain:SetWidth(54); r.gain:SetJustifyH("RIGHT")
	r.tag = T.Text(r, 10.5, C.warn)
	r.name = T.Text(r, 12.5, C.text)
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.tag:SetPoint("RIGHT", r.gain, "LEFT", -8, 0); r.tag:SetJustifyH("RIGHT")
	r.name:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
	r:SetScript("OnEnter", function(self)
		if not self.selected then self.hl:SetVertexColor(1, 1, 1, 0.04) end
		if self.entry then ShowItemTip(self, self.entry.link) end
	end)
	r:SetScript("OnLeave", function(self)
		if not self.selected then self.hl:SetVertexColor(1, 1, 1, 0) end
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(self) selectedLink = self.entry and self.entry.link; Window:Refresh() end)
	-- the rows cover the list, so they pass the wheel on
	r:EnableMouseWheel(true)
	r:SetScript("OnMouseWheel", function(self, delta) self:GetParent():GetScript("OnMouseWheel")(self:GetParent(), delta) end)
	return r
end

local function Build()
	f = CreateFrame("Frame", "UpgradeBrokerFrame", UIParent)
	f:SetSize(800, 540)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:Hide()
	tinsert(UISpecialFrames, "UpgradeBrokerFrame")
	f.bg = T.Fill(f, C.bg)
	f.border = T.Border(f, C.border2)

	-- title strip
	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(TOP_H)
	T.Fill(top, C.bar)
	T.Line(top, "BOTTOM", C.border)
	top:EnableMouse(true)
	top:RegisterForDrag("LeftButton")
	top:SetScript("OnDragStart", function() if not f.inAH then f:StartMoving() end end)
	top:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	f.top = top

	local title = T.Text(top, 15, C.text, true)
	title:SetPoint("LEFT", 14, 0)
	T.OnAccent(function() title:SetText("Upgrade " .. T.Hex(C.accent) .. "Broker|r") end)

	-- whose upgrades: you, or another character you have logged in on (same realm and faction)
	local function ClassName(name, class, level)
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		-- long names are cut so the level always shows
		-- count letters, not bytes (names like Übergroßer)
		local letters = {}
		for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do letters[#letters + 1] = ch end
		if #letters > 10 then name = table.concat(letters, "", 1, 9) .. "\226\128\166" end
		local text = ("%s (%d)"):format(name, level or 0)
		return c and ("|c%s%s|r"):format(c.colorStr or "ffffffff", text) or text
	end
	Window.ClassName = ClassName
	f.who = T.Dropdown(top, 124, function()
		local items = { { "", ClassName(UnitName("player") or "?", GL.PlayerClass(), GL.PlayerLevel()) } }
		for _, d in ipairs(GL.Character:Alts()) do items[#items + 1] = { d.name, ClassName(d.name, d.class, d.level) } end
		return items
	end, function(key) GL:SetViewing(key ~= "" and key or nil) end)
	f.who:SetPoint("LEFT", title, "RIGHT", 14, 0)

	f.spec = T.Dropdown(top, 130, function()
		local items = {}
		local s = GL.Character:Viewed()
		for _, sp in ipairs(GL.Specs.ForClass(s and s.class or GL.PlayerClass())) do items[#items + 1] = { sp.key, sp.name } end
		return items
	end, function(key) GL:SetSpec(key) end)
	f.spec:SetPoint("LEFT", f.who, "RIGHT", 8, 0)

	f.mode = T.Segmented(top, { { "level", "Leveling" }, { "endgame", "Raiding" } }, function(key) GL:SetMode(key) end)
	f.mode:SetPoint("LEFT", f.spec, "RIGHT", 8, 0)

	f.close = T.Close(top)
	f.close:SetPoint("RIGHT", -8, 0)
	f.close:SetScript("OnClick", function() Window:Hide() end)

	f.scan = T.Button(top, "Scan", 64, 24)
	f.scan:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
	if f.scan.SetMotionScriptsWhileDisabled then f.scan:SetMotionScriptsWhileDisabled(true) end
	f.scan:SetScript("OnClick", function()
		local ok, why, left = Scanner:Start()
		if not ok and why == "cooldown" then
			GL:Print(("You can scan the Auction House once every 15 minutes. Try again in %d min."):format(math.ceil(left / 60)))
		end
	end)
	f.scan:SetScript("OnEnter", function(self)
		self:Refresh()
		local ok, why, left = Scanner:CanScan()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Scan Auction House")
		if why == "closed" then GameTooltip:AddLine("Open the Auction House first.", 1, 1, 1, true)
		elseif why == "cooldown" then GameTooltip:AddLine(("Ready in %d min."):format(math.ceil(left / 60)), 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	f.scan:SetScript("OnLeave", function(self) self:Refresh(); GameTooltip:Hide() end)

	f.status = T.Text(top, 11.5, C.sec)
	-- "?": how the scores are worked out, over the window's body
	f.info = T.Button(top, "?", 24, 24)
	f.info:SetPoint("RIGHT", f.scan, "LEFT", -6, 0)
	f.info:SetScript("OnClick", function()
		local o = GL.Info.Overlay(f.body)
		o:SetShown(not o:IsShown())
		f.info:SetPrimary(o:IsShown())
	end)
	f.info:SetScript("OnEnter", function(self)
		self:Refresh()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine((GL.InfoText and GL.InfoText.title) or "How scores work")
		GameTooltip:Show()
	end)
	f.info:SetScript("OnLeave", function(self) self:Refresh(); GameTooltip:Hide() end)
	f.status:SetPoint("RIGHT", f.info, "LEFT", -10, 0)
	f.status:SetPoint("LEFT", f.mode, "RIGHT", 8, 0) -- long texts are cut instead of running over the toggle
	f.status:SetJustifyH("RIGHT")

	f.progress = top:CreateTexture(nil, "OVERLAY")
	f.progress:SetTexture("Interface\\Buttons\\WHITE8X8")
	f.progress:SetPoint("BOTTOMLEFT", 0, 0); f.progress:SetHeight(2)
	T.OnAccent(function(r, g, b) f.progress:SetVertexColor(r, g, b, 1) end)

	-- everything below the title strip (the info page covers it)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", 0, -TOP_H); f.body:SetPoint("BOTTOMRIGHT")

	-- left: filters and the slot list
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", 0, -TOP_H); left:SetPoint("BOTTOMLEFT"); left:SetWidth(LEFT_W)
	T.Line(left, "RIGHT", C.border)
	f.left = left

	local priceLabel = T.Text(left, 11.5, C.dim)
	priceLabel:SetPoint("TOPLEFT", 12, -14)
	priceLabel:SetText("Max per item")
	f.price = T.Slider(left, 140, 1, #PRICE_STEPS,
		function() return StepOf(GL.db.maxPrice) end,
		function(step)
			GL.db.maxPrice = PRICE_STEPS[step]
			Scanner:Rate()
		end,
		function(step)
			local v = GL.db.maxPrice
			if StepOf(v) ~= step then v = PRICE_STEPS[step] end
			return PriceText(v)
		end,
		function(text)
			-- typed prices are kept exactly (12g stays 12g); the slider shows the nearest step
			local step = ParsePrice(text)
			if step then Scanner:Rate() end
			return nil
		end)
	f.price:SetPoint("LEFT", priceLabel, "RIGHT", 12, 0)

	f.order = T.Segmented(left, { { "value", "Best value" }, { "gain", "Biggest upgrade" } }, function(key)
		GL.db.order = key
		Scanner:Sort()
		selectedGroup, selectedLink, candOffset = nil, nil, 0
		Window:Refresh()
	end, 22)
	f.order:SetPoint("TOPLEFT", 12, -44)

	f.list = CreateFrame("Frame", nil, left)
	f.list:SetPoint("TOPLEFT", 0, -76); f.list:SetPoint("BOTTOMRIGHT", -1, 6)
	for i = 1, #Scanner.GROUPS do rows[i] = MakeSlotRow(f.list) end

	-- right: what you wear, the options, and why
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", LEFT_W, -TOP_H); right:SetPoint("BOTTOMRIGHT")
	f.right = right

	-- what you wear in that slot; rings and trinkets show both, the one that goes out marked
	local eq = CreateFrame("Frame", nil, right)
	eq:SetPoint("TOPLEFT"); eq:SetPoint("TOPRIGHT"); eq:SetHeight(54)
	T.Line(eq, "BOTTOM", C.border)
	eq.halves = {}
	for i = 1, 2 do
		local h = CreateFrame("Button", nil, eq)
		h:SetHeight(54)
		h.icon = T.Icon(h, 30); h.icon:SetPoint("LEFT", 16, 0)
		h.l1 = T.Text(h, 10.5, C.sec); h.l1:SetPoint("TOPLEFT", h.icon, "TOPRIGHT", 10, -1)
		h.l2 = T.Text(h, 13.5, C.text); h.l2:SetPoint("BOTTOMLEFT", h.icon, "BOTTOMRIGHT", 10, 1)
		h.l2:SetPoint("RIGHT", -8, 0)
		h:SetScript("OnEnter", function(self) if self.link then ShowItemTip(self, self.link) end end)
		h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		eq.halves[i] = h
	end
	f.eq = eq

	local head = CreateFrame("Frame", nil, right)
	head:SetPoint("TOPLEFT", 0, -60); head:SetPoint("TOPRIGHT", 0, -60); head:SetHeight(18)
	local function H(text, anchor, x, w)
		local t = T.Text(head, 10, C.sec)
		t:SetText(text)
		if w then t:SetWidth(w); t:SetJustifyH("RIGHT") end
		t:SetPoint(anchor, x, 0)
		return t
	end
	local hItem = H("ITEM", "LEFT", 44)
	local hPrice = H("PRICE", "RIGHT", -16, 64)
	local hGain = T.Text(head, 10, C.sec); hGain:SetText("UPGRADE"); hGain:SetWidth(54); hGain:SetJustifyH("RIGHT")
	hGain:SetPoint("RIGHT", hPrice, "LEFT", -8, 0)
	f.head = head

	f.cands = CreateFrame("Frame", nil, right)
	f.cands:SetPoint("TOPLEFT", 0, -80); f.cands:SetPoint("TOPRIGHT", 0, -80); f.cands:SetHeight(6 * 26)
	f.cands:EnableMouseWheel(true)
	f.cands:SetScript("OnMouseWheel", function(_, delta)
		candOffset = math.max(0, candOffset - delta)
		Window:Refresh()
		-- the tooltip follows the row now under the mouse
		for _, r in ipairs(candRows) do
			if r:IsShown() and r:IsMouseOver() and r.entry then ShowItemTip(r, r.entry.link) end
		end
	end)
	for i = 1, 6 do
		candRows[i] = MakeCandRow(f.cands)
		candRows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
		candRows[i]:SetPoint("TOPRIGHT", 0, -(i - 1) * 26)
		candRows[i]:SetHeight(26)
	end
	f.candLine = T.Line(f.cands, "BOTTOM", C.border)
	f.thumb = f.cands:CreateTexture(nil, "OVERLAY")
	f.thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
	f.thumb:SetVertexColor(1, 1, 1, 0.35)
	f.thumb:SetWidth(2)

	-- the decision: how much, instead of what, and where to buy it
	local why = CreateFrame("Frame", nil, right)
	why:SetPoint("TOPLEFT", f.cands, "BOTTOMLEFT", 0, -1)
	why:SetPoint("BOTTOMRIGHT")
	f.why = why
	why.big = T.Text(why, 28, C.up, true)
	why.big:SetPoint("TOPLEFT", 16, -18)
	why.metric = T.Text(why, 12, C.dim)
	why.metric:SetPoint("TOPLEFT", why.big, "TOPRIGHT", 10, -3)
	why.metric:SetPoint("RIGHT", why, "RIGHT", -200, 0)
	why.vs = T.Text(why, 11.5, C.sec)
	why.vs:SetPoint("TOPLEFT", why.metric, "BOTTOMLEFT", 0, -3)
	why.vs:SetPoint("RIGHT", why, "RIGHT", -200, 0)
	why.find = T.Button(why, "Search Auction House", 170, 28)
	why.find:SetPrimary(true)
	why.find:SetPoint("TOPRIGHT", -16, -18)
	why.find:SetScript("OnClick", function()
		local e = Window.current
		if e and Scanner:Find(e.link) then Window:Hide() end
	end)
	why.bars = {}
	for i, key in ipairs({ "dmg", "surv", "sus" }) do
		local b = {}
		b.label = T.Text(why, 12, C.dim)
		b.label:SetPoint("TOPLEFT", 16, -70 - (i - 1) * 22)
		b.label:SetWidth(80)
		b.bar = T.DeltaBar(why, 260)
		b.bar:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
		b.value = T.Text(why, 12.5, C.up, true)
		b.value:SetPoint("LEFT", b.bar, "RIGHT", 10, 0)
		b.value:SetWidth(60); b.value:SetJustifyH("RIGHT")
		b.key = key
		-- a text row in place of a bar ("fighting -0.5 s, resting -0.2 s")
		b.wide = T.Text(why, 12, C.dim)
		b.wide:SetPoint("LEFT", b.bar, "LEFT", 0, 0)
		b.wide:SetWidth(330)
		b.wide:Hide()
		why.bars[i] = b
	end
	-- what each stat adds: two columns, "+14 Shadow Damage" and its share of the total
	why.statsHolder = CreateFrame("Frame", nil, why)
	why.statsHolder:SetPoint("TOPLEFT", 16, -142)
	why.statsHolder:SetPoint("RIGHT", -16, 0)
	why.statsHolder:SetHeight(3 * 17)
	why.stats = {}
	for i = 1, 6 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local name = T.Text(why.statsHolder, 12, C.dim)
		local pct = T.Text(why.statsHolder, 12, C.up, true)
		pct:SetJustifyH("RIGHT"); pct:SetWidth(48)
		name:SetPoint("TOPLEFT", col * 218, -row * 17)
		pct:SetPoint("TOPLEFT", col * 218 + 152, -row * 17)
		name:SetWidth(148)
		why.stats[i] = { name = name, pct = pct }
	end
	why.note = T.Text(why, 11.5, C.sec)
	why.note:SetPoint("TOPLEFT", why.statsHolder, "BOTTOMLEFT", 0, -6)
	why.note:SetPoint("RIGHT", -16, 0)
	why.note:SetWordWrap(true)

	-- nothing to show yet
	f.empty = T.Text(right, 13, C.dim)
	f.empty:SetPoint("CENTER", 0, 10)
	f.empty:SetJustifyH("CENTER")
	f.empty:SetWidth(380); f.empty:SetWordWrap(true)

	f:SetScript("OnShow", function() Window:Layout(); Window:Refresh() end)
	f:SetScript("OnSizeChanged", function() Window:Layout() end)
end

---------------------------------------------------------------------------
-- Layout (the auction house gives a little less room than the window)
---------------------------------------------------------------------------
function Window:Layout()
	if not f then return end
	-- five option rows in the auction house (less height), six in the window
	local rowsShown = (f.right:GetHeight() > 0 and f.right:GetHeight() < 480) and 5 or 6
	local changed = f.visibleRows ~= rowsShown
	f.visibleRows = rowsShown
	if changed and f:IsShown() then C_Timer.After(0, function() Window:Refresh() end) end
	f.cands:SetHeight(rowsShown * 26)
	for i, r in ipairs(candRows) do if i > rowsShown then r:Hide() end end
	local listH = f.list:GetHeight()
	local n = #Scanner.GROUPS
	local h = math.max(20, math.min(28, math.floor(listH / n)))
	for i, r in ipairs(rows) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -(i - 1) * h)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * h)
		r:SetHeight(h)
	end
end

---------------------------------------------------------------------------
-- Filling
---------------------------------------------------------------------------
local function Age(sec)
	if not sec then return nil end
	if sec < 90 then return "just now" end
	if sec < 3600 then return ("%dm ago"):format(sec / 60) end
	if sec < 86400 then return ("%dh ago"):format(sec / 3600) end
	return ("%dd ago"):format(sec / 86400)
end

local function SetGainText(fs, gain, later)
	fs:SetText(GL.Pct(gain))
	T.Color(fs, T.GainColor(gain, later))
end

local function FillHeader()
	local s = GL.Character:Viewed()
	if s then
		f.spec:SetValue(s.spec.key, s.spec.name)
		f.mode:Select(s.mode)
		local name = s.isAlt and s.altName or (UnitName("player") or "?")
		f.who:SetValue(s.isAlt and s.altName or "", Window.ClassName(name, s.class, s.level))
	end
	local st = Scanner.state
	local age = Scanner:Age()
	if st == "waiting" then f.status:SetText("Waiting for AH...")
	elseif st == "reading" then f.status:SetText(("Scanning %d%%"):format(Scanner.progress * 100))
	elseif st == "rating" then f.status:SetText(("Finding upgrades %d%%"):format(Scanner.progress * 100))
	elseif st == "items" then f.status:SetText(("Loading items %d%%"):format(Scanner.progress * 100))
	elseif st == "loading" then f.status:SetText("Loading gear...")
	elseif age then f.status:SetText("Scanned " .. Age(age))
	else f.status:SetText("") end
	local busy = st ~= "idle"
	f.progress:SetShown(busy)
	if busy then f.progress:SetWidth(math.max(1, f.top:GetWidth() * (st == "waiting" and 0.02 or Scanner.progress))) end
	local can = Scanner:CanScan()
	f.scan:SetEnabled(Scanner.ahOpen and not busy)
	f.scan:SetLabel((st == "waiting" or st == "reading") and "Wait..." or "Scan")
	-- the scan only asks for attention when there is nothing recent to show
	f.scan:SetPrimary(can and (not age or age > 2 * 3600))
	f.close:SetShown(not f.inAH)
	f.scan:ClearAllPoints()
	if f.inAH then f.scan:SetPoint("RIGHT", f.top, "RIGHT", -12, 0) else f.scan:SetPoint("RIGHT", f.close, "LEFT", -8, 0) end
end

local function FillList()
	local res = Results() or {}
	local groups = GroupList()
	if not selectedGroup or not res[selectedGroup] then
		selectedGroup, selectedLink, candOffset = nil, nil, 0
		for _, g in ipairs(groups) do
			if res[g.key] then selectedGroup = g.key break end
		end
	end
	local a = C.accent
	for i, r in ipairs(rows) do
		local g = groups[i]
		local list = g and res[g.key]
		local e = list and list[1]
		r.group, r.entry = g and g.key, e
		r.slot:SetText(g and g.label or "")
		r.odd:SetVertexColor(0, 0, 0, (i % 2 == 1) and 0.10 or 0)
		r.selected = g and g.key == selectedGroup and e ~= nil
		r.hl:SetVertexColor(a[1], a[2], a[3], r.selected and 0.10 or 0)
		r.mark:SetVertexColor(a[1], a[2], a[3], r.selected and 1 or 0)
		if e then
			T.Color(r.slot, C.dim)
			r.icon:Show(); r.icon:SetItem(e.item)
			r.lvl:SetText(e.later and tostring(e.item.reqLevel) or "")
			r.name:SetText(e.item.name)
			SetGainText(r.gain, e.gain, e.later)
			r.price:SetText(GL.MoneyShort(e.price))
			r:Enable()
		else
			T.Color(r.slot, C.sec)
			r.icon:Hide()
			r.name:SetText("")
			r.gain:SetText("\226\128\147") -- en dash
			T.Color(r.gain, C.sec)
			r.price:SetText("")
			r:Disable()
		end
	end
end

local function ReplacedText(e)
	local names = {}
	for _, it in ipairs(e.res.replaced or {}) do names[#names + 1] = it.name end
	return #names > 0 and table.concat(names, " + ") or nil
end

local function FillDetail()
	local res = Results()
	local list = selectedGroup and res and res[selectedGroup]
	local has = list and #list > 0
	f.eq:SetShown(has); f.head:SetShown(has); f.cands:SetShown(has); f.why:SetShown(has)
	f.empty:SetShown(not has)
	if not has then
		Window.current = nil
		local st = Scanner.state
		-- something is still on its way: say what, so an empty list doesn't look like "no upgrades"
		local busyText = {
			waiting = "Waiting for the Auction House to respond.\nKeep it open until the scan finishes.",
			reading = "Scanning the Auction House.\nKeep it open until the scan finishes.",
			rating = "Finding upgrades.\nResults will appear in a moment.",
			items = "The game is still loading scanned items.\nUpgrades will appear as they load.",
			loading = "Loading character gear.\nUpgrades will appear in a moment.",
		}
		if busyText[st] then
			f.empty:SetText(busyText[st])
		elseif Scanner.loadFailed then
			f.empty:SetText(("Couldn't load %s's gear. Try again in a moment."):format(Scanner.loadFailed))
		elseif not Scanner:Data() then
			if Scanner.ahOpen then
				f.empty:SetText("Click Scan to find upgrades on the Auction House.")
			else
				f.empty:SetText("Open the Auction House and click Scan to find upgrades.")
			end
		else
			f.empty:SetText(("No upgrades found %s."):format(GL.db.maxPrice >= 1e12 and "on the Auction House" or ("under " .. GL.Money(GL.db.maxPrice, true))))
		end
		return
	end

	local selectedIndex
	if selectedLink then
		for i, c in ipairs(list) do if c.link == selectedLink then selectedIndex = i break end end
		-- the chosen option is gone (price limit, new gear): back to the best one, scrolled to the top
		if not selectedIndex then selectedLink, candOffset = nil, 0 end
	end
	selectedIndex = selectedIndex or 1
	local e = list[selectedIndex]
	Window.current = e

	-- what it replaces: for rings and trinkets both you wear, the one that goes out in full color
	local replaced = e.res.replaced or {}
	local first = replaced[1]
	local viewed = GL.Character:Viewed()
	local SLOT = GL.Compare.SLOT_NAMES
	local shown = {}
	if selectedGroup == "RING" or selectedGroup == "TRINKET" or #replaced > 1 then
		local pair = selectedGroup == "RING" and { 11, 12 } or selectedGroup == "TRINKET" and { 13, 14 } or { 16, 17 }
		for _, slot in ipairs(pair) do
			local item = viewed and viewed.equipped[slot]
			local out = (slot == e.res.slot) or (#replaced > 1 and item ~= nil)
			for _, r in ipairs(replaced) do if r == item then out = true end end
			shown[#shown + 1] = { item = item, label = SLOT[slot], out = out }
		end
	else
		shown[1] = { item = first, label = e.res.label, out = true }
	end
	local halfW = (f.eq:GetWidth() > 0 and f.eq:GetWidth() or 470) / #shown
	for i, h in ipairs(f.eq.halves) do
		local d = shown[i]
		h:SetShown(d ~= nil)
		if d then
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", (i - 1) * halfW, 0)
			h:SetWidth(halfW)
			h.icon:SetItem(d.item)
			h.icon:SetAlpha(d.out and 1 or 0.45)
			h.link = d.item and d.item.link
			h.l1:SetText((d.label or ""):upper() .. (d.item and d.out and #shown > 1 and "  \194\183  REPLACED" or ""))
			h.l2:SetText(d.item and d.item.name or "Empty slot")
			T.Color(h.l2, (d.item and d.out) and C.text or C.sec)
		end
	end

	-- the options
	local visible = f.visibleRows or #candRows
	candOffset = math.max(0, math.min(candOffset, #list - visible))
	local a = C.accent
	for i, r in ipairs(candRows) do
		if i > visible then break end
		local idx = i + candOffset
		local c = list[idx]
		r.entry, r.index = c, idx
		if c then
			r:Show()
			r.icon:SetItem(c.item)
			r.name:SetText(c.item.name)
			r.tag:SetText(c.later and ("Level " .. c.item.reqLevel) or "")
			SetGainText(r.gain, c.gain, c.later)
			r.price:SetText(GL.Money(c.price))
			r.selected = idx == selectedIndex
			r.hl:SetVertexColor(a[1], a[2], a[3], r.selected and 0.10 or 0)
			r.mark:SetVertexColor(a[1], a[2], a[3], r.selected and 1 or 0)
		else
			r:Hide()
		end
	end
	-- a thin scroll thumb when there are more options than rows
	if #list > visible then
		local h = f.cands:GetHeight()
		local th = math.max(12, h * visible / #list)
		f.thumb:ClearAllPoints()
		f.thumb:SetPoint("TOPRIGHT", f.cands, "TOPRIGHT", -3, -((h - th) * candOffset / (#list - visible)))
		f.thumb:SetHeight(th)
		f.thumb:Show()
	else
		f.thumb:Hide()
	end

	-- why
	local w = f.why
	local g = e.res.gain
	SetGainText(w.big, g.total, e.later)
	local s = GL.Character:Viewed()
	local cyc0, cyc = g.cycle0, g.cycle
	-- the total also counts survival a little; the kills per hour on their own are in brackets
	local metric
	if cyc then
		metric = "better for leveling"
	elseif s and s.spec.role == "healer" and s.mode ~= "endgame" then
		metric = "better for leveling" -- healing and the damage a healer does alone, see the rows below
	else
		metric = (s and s.mode) == "endgame" and "stronger for raiding" or "stronger for leveling"
	end
	-- gear that needs a higher level says so where you decide, so it isn't bought by mistake (for an alt too)
	if e.later and s then
		local who = s.isAlt and s.altName or "you"
		metric = T.Hex(C.warn) .. ("Needs level %d (%s %s %d)"):format(e.item.reqLevel, who, s.isAlt and "is" or "are", s.level) .. "|r"
	end
	w.metric:SetText(metric)
	local vs = first and ("Replaces " .. ReplacedText(e)) or ("Fills empty " .. (e.res.label or ""):lower() .. " slot")
	if first and e.res.perSlot then vs = "Replaces " .. e.res.label .. ": " .. ReplacedText(e) end
	-- two items go out (a two-hander for main and off hand): their names are in the row above
	if #replaced > 1 then vs = "Replaces both hands" end
	w.vs:SetText(vs)
	w.find:SetEnabled(Scanner.ahOpen == true)
	w.find:SetPrimary(not e.later) -- not the obvious next step for gear you can't wear yet
	w.find:SetLabel(Scanner.ahOpen and "Search Auction House" or "Requires Auction House")
	local healer = s and s.spec.role == "healer"
	local hasMana = s and GL.Classes.stats[s.class].mana
	if cyc then
		-- leveling: where the time per kill goes. Shorter is better, so the bars point right when time drops.
		-- kills per hour and survival make up the total; the line under them says where the time per kill goes
		local kills = (cyc0.total / cyc.total - 1) * 100
		local fight, rest = cyc.fight - cyc0.fight, (cyc.rest + cyc.stops) - (cyc0.rest + cyc0.stops)
		local rows = {
			{ "Kills/hour", nil, kills },
			{ "Survival", nil, g.surv },
			{ "Per kill", ("Fighting %s, resting %s"):format(GL.Seconds(fight), GL.Seconds(rest)) },
		}
		for i, b in ipairs(w.bars) do
			local r = rows[i]
			b.label:Show(); b.label:SetText(r[1])
			b.wide:SetShown(r[2] ~= nil); b.bar:SetShown(r[2] == nil); b.value:SetShown(r[2] == nil)
			if r[2] then
				b.wide:SetText(r[2])
			else
				b.bar:SetValue(r[3], math.max(2, math.abs(kills), math.abs(g.surv)))
				b.value:SetText(GL.Pct(r[3]))
				T.Color(b.value, math.abs(r[3]) < 0.05 and C.sec or (r[3] > 0 and C.up or C.down))
			end
		end
	else
		for _, b in ipairs(w.bars) do b.wide:Hide() end
		-- healers: healing on its own; while leveling also the damage they do alone (wand, Smite)
		local labels = { dmg = "Damage", surv = "Survival", sus = "Mana" }
		local values = { dmg = g.dmg, surv = g.surv, sus = g.sus }
		if healer and g.heal then
			labels.dmg, values.dmg = "Healing", g.heal
			if g.solo then labels.surv, values.surv = "Damage", g.solo end
		end
		local scale = math.max(2, math.abs(values.dmg), math.abs(values.surv), hasMana and math.abs(values.sus) or 0)
		for _, b in ipairs(w.bars) do
			local v = values[b.key]
			local show = b.key ~= "sus" or hasMana
			b.label:SetShown(show); b.bar:SetShown(show); b.value:SetShown(show)
			if show then
				b.label:SetText(labels[b.key])
				b.bar:SetValue(v, scale)
				b.value:SetText(GL.Pct(v))
				T.Color(b.value, math.abs(v) < 0.05 and C.sec or (v > 0 and C.up or C.down))
			end
		end
	end
	local threeRows = cyc or hasMana
	w.statsHolder:ClearAllPoints()
	w.statsHolder:SetPoint("TOPLEFT", 16, threeRows and -142 or -120)
	w.statsHolder:SetPoint("RIGHT", -16, 0)
	local list = GL.Compare.TopRows(GL.Compare.Contributions(e.res), #w.stats)
	w.statsHolder:SetHeight(math.max(1, math.ceil(math.min(#list, #w.stats) / 2)) * 17)
	for i, cell in ipairs(w.stats) do
		local d = list[i]
		if d then
			local text = GL.Compare.FormatStat(d)
			local p = d.pct or 0
			cell.name:SetText(text)
			cell.pct:SetText(math.abs(p) < 0.05 and "0%" or GL.Pct(p))
			local c = math.abs(p) < 0.05 and C.sec or (p > 0 and C.up or C.down)
			T.Color(cell.pct, c)
			T.Color(cell.name, math.abs(p) < 0.05 and C.sec or C.dim)
			cell.name:Show(); cell.pct:Show()
		else
			cell.name:Hide(); cell.pct:Hide()
		end
	end
	local notes = {}
	if e.later then notes[#notes + 1] = T.Hex(C.warn) .. "Requires Level " .. e.item.reqLevel .. "|r" end
	for _, it in ipairs(e.res.with or {}) do
		if it ~= e.item then notes[#notes + 1] = "Paired with " .. it.name .. " from your bags." end
	end
	if e.item.effect then notes[#notes + 1] = "Special effects are not counted." end
	if e.item.set then notes[#notes + 1] = "Set bonuses are not counted." end
	w.note:SetText(table.concat(notes, "  "))
end

function Window:Refresh()
	if not (f and f:IsShown()) then return end
	FillHeader()
	FillList()
	FillDetail()
	f.order:Select(GL.db.order)
	f.price:Refresh()
end

local throttled
local function RefreshSoon()
	if throttled then return end
	throttled = true
	C_Timer.After(0.1, function() throttled = false; Window:Refresh() end)
end
GL:On("GL_RESULTS", RefreshSoon)
GL:On("GL_SCAN_STATE", RefreshSoon)
GL:On("GL_CHANGED", RefreshSoon)
GL:On("GL_AH", RefreshSoon)

---------------------------------------------------------------------------
-- Standalone window and auction house tab
---------------------------------------------------------------------------
function Window:Show()
	if not f then Build() Window:Layout() end
	if Scanner.ahOpen and Window.ahHolder and Window.SelectAHTab then
		Window.SelectAHTab()
		return
	end
	Window:Mount(nil)
	f:Show()
end
function Window:Hide()
	if not f then return end
	if f.inAH and Window.ahHolder and Window.ahHolder:IsShown() then
		-- leave the auction house on its Buy view instead of an empty frame
		local ok = AuctionHouseFrameDisplayMode and pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
		if not ok then return end -- keep our view rather than leave an empty auction house
		Window.ahHolder:Hide()
	end
	f:Hide()
end
function Window:Toggle()
	if f and f:IsShown() then Window:Hide() else Window:Show() end
end

-- host nil: free window. host frame: fill it (the auction house content area).
function Window:Mount(host)
	f:ClearAllPoints()
	if host then
		f:SetParent(host)
		f:SetAllPoints(host)
		f:SetFrameStrata(host:GetFrameStrata())
		f:SetFrameLevel(host:GetFrameLevel() + 2)
		f.inAH = true
		f.border.TOP:Hide()
		-- Escape closes the auction house itself; our frame must not vanish from inside it
		for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == "UpgradeBrokerFrame" then table.remove(UISpecialFrames, i) end end
	else
		f:SetParent(UIParent)
		f:SetSize(800, 540)
		f:SetPoint("CENTER")
		f:SetFrameStrata("HIGH")
		f.inAH = false
		f.border.TOP:Show()
		local listed = false
		for _, n in ipairs(UISpecialFrames) do if n == "UpgradeBrokerFrame" then listed = true end end
		if not listed then tinsert(UISpecialFrames, "UpgradeBrokerFrame") end
	end
	Window:Layout()
end

local function SetupAHTab()
	if Window.ahHolder or not AuctionHouseFrame then return end
	if not f then Build() end
	local holder = CreateFrame("Frame", nil, AuctionHouseFrame)
	holder:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -24)
	holder:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)
	holder:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 20)
	holder:EnableMouse(true)
	holder:Hide()
	holder:SetScript("OnShow", function()
		Window:Mount(holder)
		f:Show()
		Window:Refresh()
	end)
	holder:SetScript("OnHide", function() if f.inAH then f:Hide() end end)
	Window.ahHolder = holder

	local lib = LibStub and LibStub("LibAHTab-1-0", true)
	if lib then
		lib:CreateTab("UpgradeBroker", holder, "Upgrades", "Upgrade Broker")
		Window.SelectAHTab = function() lib:SetSelected("UpgradeBroker") end
		return
	end
	-- no Auctionator: a tab of our own after Blizzard's
	local tabs = type(AuctionHouseFrame.Tabs) == "table" and AuctionHouseFrame.Tabs or {}
	local ok, tab = pcall(CreateFrame, "Button", "UpgradeBrokerAHTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
	if not ok then return end
	tab:SetText("Upgrades")
	if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 20, nil, 70) end
	local last = tabs[#tabs]
	if last then tab:SetPoint("TOPLEFT", last, "TOPRIGHT", 3, 0) end
	if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
	local function select()
		pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, {})
		for _, t in ipairs(tabs) do pcall(PanelTemplates_DeselectTab, t) end
		pcall(PanelTemplates_SelectTab, tab)
		holder:Show()
	end
	tab:SetScript("OnClick", select)
	Window.SelectAHTab = select
	hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
		if type(mode) == "table" and #mode > 0 then
			holder:Hide()
			pcall(PanelTemplates_DeselectTab, tab)
		end
	end)
end

GL:On("AUCTION_HOUSE_SHOW", function()
	SetupAHTab()
	-- a free window that was open moves into the auction house
	if f and f:IsShown() and not f.inAH and Window.SelectAHTab then f:Hide(); Window.SelectAHTab() end
end)
GL:On("AUCTION_HOUSE_CLOSED", function()
	if Window.ahHolder then Window.ahHolder:Hide() end
	if f and f.inAH then f:Hide(); Window:Mount(nil) end
end)
