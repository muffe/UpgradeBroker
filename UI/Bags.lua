-- UI/Bags.lua: a small "+3%" in the corner of gear in your bags that makes you stronger. Green: wear it now.
-- Amber: once you reach its level. Works on Blizzard's bags and EllesmereUI Bags.
local _, GL = ...

local T = GL.Theme
local C = T.C

local Bags = {}
GL.Bags = Bags

local badges = {} -- [button] = { bg, text }

-- the same rounding as everywhere else (+0.6%, +4.8%, +12%)
local function BadgeText(g) return GL.Pct(g) end

local function Badge(button, parent)
	local b = badges[button]
	if b then return b end
	parent = parent or button
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(button)
	holder:SetFrameLevel(parent:GetFrameLevel() + 5)
	local text = holder:CreateFontString(nil, "OVERLAY")
	if not text:SetFont(T.FONT_BOLD, 10, "") then text:SetFont(STANDARD_TEXT_FONT, 10, "") end
	text:SetPoint("BOTTOMRIGHT", -2, 2)
	local bg = holder:CreateTexture(nil, "ARTWORK")
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	bg:SetVertexColor(0, 0, 0, 0.85)
	bg:SetPoint("TOPLEFT", text, "TOPLEFT", -2, 1)
	bg:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 1, -1)
	b = { holder = holder, text = text, bg = bg }
	badges[button] = b
	return b
end

local function Paint(button, link, parent)
	local res = link and GL.db.bagMarkers and GL.Compare:Rate(link)
	local show = res and GL.Compare.IsUpgrade(res)
	if not show then
		if badges[button] then badges[button].holder:Hide() end
		return
	end
	local b = Badge(button, parent)
	local later = res.reason == "later"
	b.text:SetText(BadgeText(res.gain.total))
	T.Color(b.text, later and C.warn or C.up)
	b.holder:Show()
end

-- Blizzard bags
local function PaintFrame(frame)
	if not (frame and frame.EnumerateValidItems and frame:IsShown()) then return end
	for _, button in frame:EnumerateValidItems() do
		local bag, slot = button.GetBagID and button:GetBagID(), button:GetID()
		local link = bag and C_Container.GetContainerItemLink(bag, slot)
		Paint(button, link)
	end
end

local hooked = {}
local function BlizzFrames()
	local list = {}
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local fr = _G["ContainerFrame" .. i]
		if fr then list[#list + 1] = fr end
	end
	if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
	return list
end

function Bags:Refresh()
	for _, fr in ipairs(BlizzFrames()) do PaintFrame(fr) end
	local eui = _G.EUI_Bags
	if eui and eui.IsVisible and eui:IsVisible() and eui.RefreshInventory then pcall(eui.RefreshInventory, eui) end
end

local function Hook()
	for _, fr in ipairs(BlizzFrames()) do
		if not hooked[fr] and fr.UpdateItems then
			hooked[fr] = true
			hooksecurefunc(fr, "UpdateItems", PaintFrame)
		end
	end
	local eui = _G.EUI_Bags
	if eui and eui.RegisterItemOverlayIcon and not hooked.eui then
		hooked.eui = true
		eui.RegisterItemOverlayIcon("UpgradeBroker", function(btn, data)
			Paint(btn, data and data.itemLink, btn._textOverlay or btn)
		end)
	end
end

GL:On("PLAYER_LOGIN", function() Hook() end)
local soon
GL:On("GL_CHANGED", function()
	if soon then return end
	soon = true
	C_Timer.After(0.3, function() soon = false; Bags:Refresh() end)
end)
-- items arrive by the thousand after a scan; repaint open bags at most every two seconds
local function AnyBagOpen()
	for _, fr in ipairs(BlizzFrames()) do if fr:IsShown() then return true end end
	local eui = _G.EUI_Bags
	return eui and eui.IsVisible and eui:IsVisible() or false
end
GL:On("GL_ITEM_LOADED", function()
	if soon or not AnyBagOpen() then return end
	soon = true
	C_Timer.After(2, function() soon = false; Bags:Refresh() end)
end)
