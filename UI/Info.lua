-- UI/Info.lua: the "How scores work" page (text in UI/InfoText.lua). Shown over the window's body from the
-- "?" button, and as a page in the EllesmereUI options.
local _, GL = ...

local Info = {}
GL.Info = Info

local T = GL.Theme
local C = T.C

-- Lays the text out in parent, width wide, from the top. Returns the height used.
function Info.Fill(parent, width, x, y)
	local text = GL.InfoText
	if not text then return 0 end
	x, y = x or 0, y or 0
	local top = y
	for _, sec in ipairs(text.sections or {}) do
		local h = T.Text(parent, 11, C.accent, true)
		h:SetPoint("TOPLEFT", x, y)
		h:SetText((sec.heading or ""):upper())
		y = y - 18
		local b = T.Text(parent, 12.5, C.dim)
		b:SetPoint("TOPLEFT", x, y)
		b:SetWidth(width)
		b:SetWordWrap(true)
		b:SetSpacing(3)
		b:SetText(sec.body or "")
		y = y - math.ceil(b:GetStringHeight()) - 18
	end
	return top - y
end

-- The overlay inside the upgrade window (built on first use).
function Info.Overlay(host)
	if Info.overlay then return Info.overlay end
	local o = CreateFrame("Frame", nil, host)
	o:SetAllPoints()
	o:SetFrameLevel(host:GetFrameLevel() + 20)
	o:EnableMouse(true)
	T.Fill(o, { C.bg[1], C.bg[2], C.bg[3], 1 })
	local scroll = CreateFrame("ScrollFrame", nil, o)
	scroll:SetPoint("TOPLEFT", 24, -18)
	scroll:SetPoint("BOTTOMRIGHT", -24, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(560, 10)
	scroll:SetScrollChild(content)
	o:SetScript("OnShow", function()
		if not content.filled then
			content:SetWidth(math.max(300, scroll:GetWidth()))
			content:SetHeight(Info.Fill(content, content:GetWidth()) + 10)
			content.filled = true
		end
		scroll:SetVerticalScroll(0)
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
	end)
	o:Hide()
	Info.overlay = o
	return o
end
