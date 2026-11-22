-- UI/Quest.lua: on quest rewards, the gain for every piece of gear and a frame around the best choice. When no
-- choice makes you stronger, a coin marks the one that sells for the most.
local _, GL = ...

local T = GL.Theme
local C = T.C

local marks = {} -- [button] = frame

local function Mark(button)
	local m = marks[button]
	if m then return m end
	local icon = button.Icon or button.icon or _G[(button:GetName() or "") .. "IconTexture"] or button
	m = CreateFrame("Frame", nil, button)
	m:SetFrameLevel(button:GetFrameLevel() + 5)
	m:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	m:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	m.border = T.Border(m, C.up)
	m.text = m:CreateFontString(nil, "OVERLAY")
	if not m.text:SetFont(T.FONT_BOLD, 10, "") then m.text:SetFont(STANDARD_TEXT_FONT, 10, "") end
	m.text:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -2, 2)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	m.bg:SetVertexColor(0, 0, 0, 0.85)
	m.bg:SetPoint("TOPLEFT", m.text, "TOPLEFT", -2, 1)
	m.bg:SetPoint("BOTTOMRIGHT", m.text, "BOTTOMRIGHT", 1, -1)
	m.coin = m:CreateTexture(nil, "OVERLAY")
	m.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	m.coin:SetSize(12, 12)
	m.coin:SetPoint("TOPRIGHT", -2, -2)
	marks[button] = m
	return m
end

local function LinkOf(button, fromLog)
	-- currency and spell rewards share button IDs with items; only items have links here
	if type(button.objectType) == "string" and button.objectType ~= "item" then return nil end
	local kind, index = button.type, button:GetID()
	if not (kind and index and index > 0) then return nil end
	if kind ~= "choice" and kind ~= "reward" then return nil end
	if fromLog then return GetQuestLogItemLink and GetQuestLogItemLink(kind, index) end
	return GetQuestItemLink and GetQuestItemLink(kind, index)
end

-- What the reward sells for: unit price times how many you get. nil while the client loads the item.
local function SellPrice(link, button, fromLog)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, _, _, _, _, _, _, _, _, unit = get(link)
	if not name then return nil end
	unit = unit or 0
	local count
	if fromLog and GetQuestLogChoiceInfo then
		count = select(3, GetQuestLogChoiceInfo(button:GetID()))
	elseif GetQuestItemInfo then
		count = select(3, GetQuestItemInfo("choice", button:GetID()))
	end
	return unit * math.max(1, tonumber(count) or 1)
end

-- One reward frame: the quest giver's (QuestInfoRewardsFrame) or the map's quest details.
local function UpdateFrame(rf, fromLog)
	local best, bestGain, richest, richestSell = nil, nil, nil, 0
	local rated, choiceUpgrades, unknownPrice = {}, 0, false
	for _, b in ipairs(rf.RewardButtons) do
		local link = b:IsVisible() and LinkOf(b, fromLog)
		-- an item choice whose link isn't there yet: its value is unknown, so no coin for now
		if not link and b:IsVisible() and b.type == "choice" and (b.objectType == nil or b.objectType == "item") then
			unknownPrice = true
		end
		if link then
			local res = GL.Compare:Rate(link)
			if res and GL.Compare.IsUpgrade(res) then
				rated[#rated + 1] = { b = b, res = res }
				if b.type == "choice" then choiceUpgrades = choiceUpgrades + 1 end
				-- the frame goes to the best reward you can wear now
				if b.type == "choice" and res.reason ~= "later" and (not bestGain or res.gain.total > bestGain) then
					best, bestGain = b, res.gain.total
				end
			end
			if b.type == "choice" then
				local sell = SellPrice(link, b, fromLog)
				if not sell then unknownPrice = true
				elseif sell > richestSell then richest, richestSell = b, sell end
			end
		end
	end
	for _, r in ipairs(rated) do
		local m = Mark(r.b)
		local later = r.res.reason == "later"
		m.text:SetText(GL.Pct(r.res.gain.total))
		T.Color(m.text, later and C.warn or C.up)
		m.text:Show(); m.bg:Show(); m.coin:Hide()
		m.frameAlpha = r.b == best and 1 or 0
		m.border:SetColor(C.up[1], C.up[2], C.up[3], m.frameAlpha)
		m:Show()
	end
	-- no choice makes you stronger: point at the one that sells best
	if choiceUpgrades == 0 and richest and not unknownPrice then
		local m = Mark(richest)
		m.text:Hide(); m.bg:Hide(); m.coin:Show()
		m.frameAlpha = 0
		m.border:SetColor(1, 0.82, 0, 0)
		m:Show()
	end
end

local function Update()
	for _, m in pairs(marks) do m:Hide() end
	if not (GL.db and GL.db.questMarkers) then return end
	local qf = QuestInfoRewardsFrame
	if qf and qf:IsVisible() and type(qf.RewardButtons) == "table" then
		UpdateFrame(qf, QuestInfoFrame and QuestInfoFrame.questLog)
	end
	local mf = MapQuestInfoRewardsFrame
	if mf and mf:IsVisible() and type(mf.RewardButtons) == "table" then UpdateFrame(mf, true) end
end

GL.Quest = { Update = Update, marks = marks }

local function Soon() C_Timer.After(0, function() pcall(Update) end) end

if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", Soon) end
GL:On("QUEST_COMPLETE", Soon)
GL:On("QUEST_DETAIL", Soon)
GL:On("GET_ITEM_INFO_RECEIVED", function()
	if (QuestInfoFrame and QuestInfoFrame:IsVisible()) or (MapQuestInfoRewardsFrame and MapQuestInfoRewardsFrame:IsVisible()) then Soon() end
end)
