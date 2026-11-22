-- UI/Tooltip.lua: the rating under every gear tooltip. The total, the stats that make it (each with its share),
-- while leveling the seconds per kill it saves, and for rings, trinkets and one-handers a line per slot.
local _, GL = ...

local T = GL.Theme
local C = T.C

local function Hex(c) return T.Hex(c) end

local function Add(tip, res)
	local g = res.gain
	local color = T.GainColor(g.total, res.reason == "later")
	local s = res.snap or GL.Character:Get()
	if not s then return end
	local brand = Hex(C.accent) .. "Upgrade Broker|r"
	if s.isAlt then brand = brand .. Hex(C.sec) .. " for " .. s.altName .. "|r" end
	tip:AddLine(" ")
	if math.abs(g.total) < 0.05 then
		tip:AddDoubleLine(brand, Hex(C.sec) .. "No change|r")
		return
	end
	if g.total < ((GL.db and GL.db.minGain) or 0.5) and g.total > 0 then
		-- too small to call an upgrade: shown, but quiet
		tip:AddDoubleLine(brand, Hex(C.sec) .. GL.Pct(g.total) .. "|r")
		return
	end
	if g.total < 0 then
		-- a downgrade stays quiet
		tip:AddDoubleLine(brand, Hex(C.sec) .. GL.Pct(g.total) .. "|r")
		return
	end
	local right = Hex(color) .. GL.Pct(g.total) .. " upgrade|r"
	if res.reason == "later" then right = Hex(C.warn) .. "Level " .. res.item.reqLevel .. "  |r" .. right end
	tip:AddDoubleLine(brand, right)
	-- why: the stats that make the difference, with their share
	-- the three biggest, and the rest summed up so the lines add up to the total
	local rows, rest = {}, 0
	for _, d in ipairs(GL.Compare.Contributions(res)) do
		if #rows < 3 and math.abs(d.pct or 0) >= 0.1 then rows[#rows + 1] = d else rest = rest + (d.pct or 0) end
	end
	if math.abs(rest) >= 0.1 then rows[#rows + 1] = { key = "OTHER", delta = 0, pct = rest, text = "Other stats" } end
	for _, d in ipairs(rows) do
		local p = d.pct or 0
		local pc = p > 0 and C.upSoft or { 0.99, 0.65, 0.65 }
		tip:AddDoubleLine(Hex(C.dim) .. (GL.Compare.FormatStat(d)) .. "|r", Hex(pc) .. GL.Pct(p) .. "|r")
	end
	if g.cycle then
		local c0, c1 = g.cycle0, g.cycle
		local fight, rest = c1.fight - c0.fight, (c1.rest + c1.stops) - (c0.rest + c0.stops)
		tip:AddLine(Hex(C.sec) .. "Per kill: fighting " .. GL.Seconds(fight) .. ", resting " .. GL.Seconds(rest) .. "|r")
	end
	if res.perSlot then
		for _, e in ipairs(res.perSlot) do
			local name = e.replaced[1] and e.replaced[1].name or "Empty"
			tip:AddDoubleLine(Hex(C.dim) .. e.label .. ": " .. Hex(C.sec) .. name .. "|r",
				Hex(e.gain.total < 0 and C.sec or T.GainColor(e.gain.total, res.reason == "later")) .. GL.Pct(e.gain.total) .. "|r")
		end
	end
end

local function OnItem(tip, data)
	if not (GL.db and GL.db.tooltip) or tip:IsForbidden() then return end
	if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
	local _, link = tip:GetItem()
	link = GL.Plain(link)
	if not link then return end
	-- your own equipped items compare with themselves
	local owner = tip:GetOwner()
	local name = owner and owner.GetName and owner:GetName()
	if name and name:find("^Character.+Slot$") then return end
	-- opened from the upgrade window: rated for whoever the window shows (an alt)
	local who = GL.tipSnap and owner and GL.tipOwner == owner and GL.tipSnap or nil
	local res = GL.Compare:Rate(link, who)
	if not (res and res.ok and res.gain) then return end
	Add(tip, res)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
end
