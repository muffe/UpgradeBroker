-- UI/Theme.lua: the look (EllesmereUI's: flat warm-dark panels, 1px borders at low white alpha, one accent
-- color, white text at a few alphas) and the small widgets the window is built from. With EllesmereUI
-- installed the accent and font follow the user's EllesmereUI theme live.
local _, GL = ...

local T = {}
GL.Theme = T

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

T.C = {
	bg      = { 0.067, 0.059, 0.047, 0.97 }, -- window (#110f0c)
	bar     = { 0.043, 0.039, 0.031, 1 },    -- title strip
	raise   = { 1, 1, 1, 0.035 },            -- hovered row
	odd     = { 0, 0, 0, 0.10 },
	border  = { 1, 1, 1, 0.07 },
	border2 = { 1, 1, 1, 0.14 },
	text    = { 1, 1, 1, 0.92 },
	dim     = { 1, 1, 1, 0.58 },
	sec     = { 1, 1, 1, 0.42 },
	up      = { 0.29, 0.87, 0.50 },          -- gains
	upSoft  = { 0.53, 0.94, 0.67 },
	down    = { 0.97, 0.44, 0.44 },
	warn    = { 0.98, 0.75, 0.14 },          -- needs a higher level
	accent  = { 0.86, 0.65, 0.50 },          -- #DCA77F, EllesmereUI's WoW Forever default
}

T.FONT = MEDIA .. "fonts\\Expressway.TTF"
-- EllesmereUI's down arrow, else Blizzard's
T.ARROW_DOWN = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI"))
	and (MEDIA .. "icons\\eui-arrow-down3.png") or "Interface\\Buttons\\Arrow-Down-Up"
T.FONT_BOLD = MEDIA .. "fonts\\Expressway Bold.ttf"

local accentWatchers = {}
-- fn(r, g, b) now and whenever the accent changes.
function T.OnAccent(fn)
	accentWatchers[#accentWatchers + 1] = fn
	fn(unpack(T.C.accent))
end
local function AccentChanged()
	for _, fn in ipairs(accentWatchers) do pcall(fn, unpack(T.C.accent)) end
end

function T.Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

if EllesmereUI and EllesmereUI.RegisterSkin then
	EllesmereUI.RegisterSkin(GL.name, function(S)
		T.skin = S
		local function pull()
			local r, g, b = S.GetAccentColor()
			if r then T.C.accent = { r, g, b } end
			local font = S.GetFont and S.GetFont()
			if font then T.FONT = font end
			AccentChanged()
		end
		pull()
		if S.OnLooksChanged then S.OnLooksChanged(pull) end
	end)
end

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
function T.Fill(frame, c, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	t:SetAllPoints()
	return t
end

-- A 1px line inside the frame's edge. side: TOP BOTTOM LEFT RIGHT.
function T.Line(frame, side, c, layer)
	local t = frame:CreateTexture(nil, layer or "BORDER")
	t:SetTexture(WHITE)
	c = c or T.C.border
	t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	if side == "TOP" or side == "BOTTOM" then
		t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
		if PixelUtil then PixelUtil.SetHeight(t, 1) else t:SetHeight(1) end
	else
		t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
		if PixelUtil then PixelUtil.SetWidth(t, 1) else t:SetWidth(1) end
	end
	return t
end

function T.Border(frame, c)
	local b = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do b[side] = T.Line(frame, side, c) end
	function b:SetColor(r, g, bl, a) for _, t in pairs(self) do if type(t) == "table" and t.SetVertexColor then t:SetVertexColor(r, g, bl, a or 1) end end end
	return b
end

function T.Text(parent, size, c, bold, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	if not fs:SetFont(bold and T.FONT_BOLD or T.FONT, size or 12, "") then
		fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
	end
	c = c or T.C.text
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	return fs
end

function T.Color(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- Square item icon with a 1px border in the item's quality color.
function T.Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	T.Fill(f, { 0, 0, 0, 1 })
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1); f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.border = T.Border(f, { 0.3, 0.3, 0.3, 1 })
	function f:SetItem(item)
		if not item then
			self.tex:SetTexture(nil)
			self.border:SetColor(1, 1, 1, 0.08)
			return
		end
		self.tex:SetTexture(item.icon)
		local r, g, b = 0.6, 0.6, 0.6
		if C_Item and C_Item.GetItemQualityColor then
			local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, item.quality or 1)
			if ok and qr then r, g, b = qr, qg, qb end
		end
		if (item.quality or 1) <= 1 then r, g, b = 0.25, 0.25, 0.25 end
		self.border:SetColor(r, g, b, 1)
	end
	return f
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- Flat button. primary: accent border and text (the one action that matters on a screen).
function T.Button(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 120, h or 24)
	b.bg = T.Fill(b, { 0.089, 0.080, 0.072, 0.6 })
	b.border = T.Border(b, { 1, 1, 1, 0.28 })
	b.label = T.Text(b, 12, T.C.dim)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.label:SetText(text)
	function b:Refresh()
		local enabled, over = self:IsEnabled(), self:IsMouseOver()
		local a = T.C.accent
		if not enabled then
			self.border:SetColor(1, 1, 1, 0.1); T.Color(self.label, T.C.sec)
		elseif self.primary then
			self.border:SetColor(a[1], a[2], a[3], over and 1 or 0.8)
			self.label:SetTextColor(a[1], a[2], a[3], 1)
			self.bg:SetVertexColor(a[1], a[2], a[3], over and 0.16 or 0.08)
			return
		else
			self.border:SetColor(1, 1, 1, over and 0.45 or 0.28)
			self.label:SetTextColor(1, 1, 1, over and 0.85 or 0.65)
		end
		self.bg:SetVertexColor(0.089, 0.080, 0.072, over and 0.75 or 0.6)
	end
	function b:SetPrimary(on) self.primary = on; self:Refresh() end
	function b:SetLabel(t) self.label:SetText(t) end
	b:SetScript("OnEnter", b.Refresh)
	b:SetScript("OnLeave", b.Refresh)
	b:SetScript("OnEnable", b.Refresh)
	b:SetScript("OnDisable", b.Refresh)
	T.OnAccent(function() b:Refresh() end)
	return b
end

-- A row of joined buttons, one of them on. items: { { key, label } }. onSelect(key).
function T.Segmented(parent, items, onSelect, h)
	local f = CreateFrame("Frame", nil, parent)
	f.buttons = {}
	local x = 0
	h = h or 22
	for i, it in ipairs(items) do
		local b = CreateFrame("Button", nil, f)
		b.key = it[1]
		b.label = T.Text(b, 11.5, T.C.dim)
		b.label:SetPoint("CENTER")
		b.label:SetText(it[2])
		local w = math.ceil(b.label:GetStringWidth()) + 18
		b:SetSize(w, h)
		b:SetPoint("LEFT", x, 0)
		b.bg = T.Fill(b, { 1, 1, 1, 0 })
		b.under = b:CreateTexture(nil, "ARTWORK")
		b.under:SetTexture(WHITE)
		b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT"); b.under:SetHeight(2)
		if i > 1 then T.Line(b, "LEFT", T.C.border) end
		b:SetScript("OnClick", function() f:Select(b.key); onSelect(b.key) end)
		b:SetScript("OnEnter", function() if f.value ~= b.key then T.Color(b.label, { 1, 1, 1, 0.8 }) end end)
		b:SetScript("OnLeave", function() f:Select(f.value) end)
		x = x + w
		f.buttons[#f.buttons + 1] = b
	end
	f:SetSize(x, h)
	T.Border(f, T.C.border2)
	function f:Select(key)
		self.value = key
		local a = T.C.accent
		for _, b in ipairs(self.buttons) do
			local on = b.key == key
			if on then T.Color(b.label, T.C.text) else T.Color(b.label, T.C.dim) end
			b.bg:SetVertexColor(a[1], a[2], a[3], on and 0.13 or 0)
			b.under:SetVertexColor(a[1], a[2], a[3], on and 1 or 0)
		end
	end
	T.OnAccent(function() f:Select(f.value) end)
	return f
end

-- Dropdown: a button with the current value; a click opens a flat list under it.
function T.Dropdown(parent, w, getItems, onSelect)
	local d = CreateFrame("Button", nil, parent)
	d:SetSize(w, 22)
	d.bg = T.Fill(d, { 0.103, 0.095, 0.088, 0.9 })
	d.border = T.Border(d, { 1, 1, 1, 0.2 })
	d.label = T.Text(d, 12, T.C.text)
	d.label:SetPoint("LEFT", 8, 0)
	d.label:SetPoint("RIGHT", -18, 0)
	-- the chevron is a texture: the UI font has no arrow glyph
	d.arrow = d:CreateTexture(nil, "OVERLAY")
	d.arrow:SetSize(10, 10)
	d.arrow:SetPoint("RIGHT", -7, 0)
	d.arrow:SetTexture(T.ARROW_DOWN)
	d.arrow:SetVertexColor(1, 1, 1, 0.6)
	-- the list lives on UIParent in its own strata, so nothing in the window draws over it
	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	if menu.SetFixedFrameStrata then menu:SetFixedFrameStrata(true) end
	menu:SetToplevel(true)
	menu:SetClampedToScreen(true)
	menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
	menu:Hide()
	T.Fill(menu, { 0.08, 0.072, 0.062, 0.98 })
	T.Border(menu, T.C.border2)
	menu.rows = {}
	d:SetScript("OnEnter", function() d.border:SetColor(1, 1, 1, 0.32) end)
	d:SetScript("OnLeave", function() d.border:SetColor(1, 1, 1, 0.2) end)
	d:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() return end
		local items = getItems()
		for i, it in ipairs(items) do
			local r = menu.rows[i]
			if not r then
				r = CreateFrame("Button", nil, menu)
				r:SetHeight(22)
				r.hl = T.Fill(r, { 1, 1, 1, 0 })
				r.label = T.Text(r, 12, T.C.text)
				r.label:SetPoint("LEFT", 8, 0)
				r.label:SetPoint("RIGHT", -8, 0)
				r:SetScript("OnEnter", function() r.hl:SetVertexColor(1, 1, 1, 0.08) end)
				r:SetScript("OnLeave", function() r.hl:SetVertexColor(1, 1, 1, 0) end)
				menu.rows[i] = r
			end
			r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
			r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
			r.label:SetText(it[2])
			T.Color(r.label, it[1] == d.value and T.C.accent or T.C.text)
			r:SetScript("OnClick", function() menu:Hide(); d:SetValue(it[1], it[2]); onSelect(it[1]) end)
			r:Show()
		end
		for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
		menu:SetSize(math.max(w, 120), #items * 22 + 2)
		menu:Show()
	end)
	d:SetScript("OnHide", function() menu:Hide() end)
	-- a click anywhere else closes the list
	-- (Escape closes the whole window, which takes the list with it; combat closes it too)
	menu:SetScript("OnShow", function()
		pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
		pcall(menu.RegisterEvent, menu, "PLAYER_REGEN_DISABLED")
	end)
	menu:SetScript("OnHide", function() menu:UnregisterAllEvents() end)
	menu:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" or not (menu:IsMouseOver() or d:IsMouseOver()) then menu:Hide() end
	end)
	function d:SetValue(key, text) self.value = key; self.label:SetText(text) end
	return d
end

-- Thin slider with an editable value next to it. Values are steps; format(step) -> text, parse(text) -> step.
function T.Slider(parent, w, minV, maxV, get, set, format, parse)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w + 72, 20)
	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(w, 14)
	s:SetPoint("LEFT")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(WHITE); track:SetVertexColor(1, 1, 1, 0.16)
	track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(WHITE)
	fill:SetPoint("LEFT", track, "LEFT"); fill:SetHeight(4)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(WHITE); thumb:SetVertexColor(1, 1, 1, 1); thumb:SetSize(4, 12)
	s:SetThumbTexture(thumb)
	T.OnAccent(function(r, g, b) fill:SetVertexColor(r, g, b, 0.75) end)
	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(64, 20)
	box:SetPoint("LEFT", s, "RIGHT", 8, 0)
	box:SetAutoFocus(false)
	if not box:SetFont(T.FONT, 12, "") then box:SetFont(STANDARD_TEXT_FONT, 12, "") end
	box:SetTextColor(1, 1, 1, 0.9)
	box:SetJustifyH("RIGHT")
	box:SetTextInsets(4, 6, 0, 0)
	T.Fill(box, { 0.03, 0.023, 0.018, 0.4 })
	T.Border(box, { 1, 1, 1, 0.12 })
	local function show(v)
		fill:SetWidth(math.max(1, (v - minV) / (maxV - minV) * w))
		if not box:HasFocus() then box:SetText(format(v)) end
	end
	s:SetScript("OnValueChanged", function(_, v, user)
		v = math.floor(v + 0.5)
		show(v)
		if user then set(v) end
	end)
	box:SetScript("OnEnterPressed", function()
		local v = parse(box:GetText())
		box:ClearFocus()
		if v then v = math.max(minV, math.min(maxV, v)); s:SetValue(v); set(v) end
		f:Refresh()
	end)
	box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
	box:SetScript("OnEditFocusLost", function() f:Refresh() end)
	function f:Refresh() local v = get(); s:SetValue(v); show(v) end
	f.slider, f.box = s, box
	f:Refresh()
	return f
end

-- Close (X) glyph button.
function T.Close(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	b.x = T.Text(b, 15, T.C.dim)
	b.x:SetPoint("CENTER", 0, 1)
	b.x:SetText("\195\151") -- multiplication sign
	b:SetScript("OnEnter", function() T.Color(b.x, T.C.text) end)
	b:SetScript("OnLeave", function() T.Color(b.x, T.C.dim) end)
	return b
end

-- A horizontal bar for a signed percentage on a shared, zero-centered scale.
function T.DeltaBar(parent, w)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, 6)
	T.Fill(f, { 1, 1, 1, 0.07 })
	local mid = f:CreateTexture(nil, "ARTWORK")
	mid:SetTexture(WHITE); mid:SetVertexColor(1, 1, 1, 0.3)
	mid:SetPoint("CENTER"); mid:SetSize(1, 12)
	local bar = f:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(WHITE)
	bar:SetHeight(6)
	function f:SetValue(v, scale)
		local half = w / 2
		local len = math.min(half, math.abs(v) / math.max(scale, 0.001) * half)
		bar:ClearAllPoints()
		if len < 0.5 then bar:Hide() return end
		bar:Show()
		bar:SetWidth(len)
		local c = v >= 0 and T.C.up or T.C.down
		bar:SetVertexColor(c[1], c[2], c[3], 0.9)
		if v >= 0 then bar:SetPoint("LEFT", f, "CENTER", 0, 0) else bar:SetPoint("RIGHT", f, "CENTER", 0, 0) end
	end
	return f
end

function T.GainColor(p, later)
	if later then return T.C.warn end
	if p >= 1 then return T.C.up end
	if p > 0 then return T.C.upSoft end
	if p < 0 then return T.C.down end
	return T.C.sec
end
