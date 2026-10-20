local ADDON, ns = ...
local L = ns.L

-- (Message types NQ, NB: not FQ, FB, the dues' of 1.1, which older clients still read.)
-- Fellow Forsaken (1.3.0, the user's design): guildmates in our zone below our level, wherever they
-- are in it, so a higher level can find them and help kill their mobs, without grouping or chatting. Inspecting reaches 28 yards and the game
-- tells an addon nobody's position, so each guildmate's own addon says where it is, over GUILD
-- (our guild alone, never the Sylvanistas channel or anyone outside it), and only when asked:
--   NQ~<zone>~<level>          our addon, while Fellow Forsaken is on (every ASK_EVERY): who is in
--                              this zone below this level?
--   NB~<map>~<x>~<y>~<0|1>~<level>~<class>~<0|1: in combat>
--                              a guildmate's addon that matches (same zone, a lower level, its
--                              player's yes on the privacy page: Fellows.Sharing), every
--                              BEACON_EVERY for BEACON_FOR after the last ask it heard: where it
--                              is and whether it wears the guild tabard (its own slot, nothing
--                              inspected).
-- On our map: a tabard on the world map and the minimap for those wearing it; for the others, a
-- light violet arrow on the minimap's edge that points at them (on the minimap itself once near).
-- Nothing is kept past the session.
local Fellows = {}
ns.Fellows = Fellows

Fellows.ASK_EVERY = 60
Fellows.BEACON_EVERY = 10
Fellows.BEACON_FOR = 120
Fellows.EXPIRE = 45          -- a guildmate not heard from this long leaves the list and the map
Fellows.GUILD_TABARD = 5976  -- the guild tabard's item id
Fellows.ARROW_COLOR = { 0.80, 0.62, 1.00 }

local Pins = ns.Pins()
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local looking = false
local lastAsk = -math.huge
local beaconUntil, lastBeacon = 0, -math.huge
local found = {}   -- [short name] = { mapID, x, y, tabard, level, class, t }
local pins = {}    -- [short name] = { world, mini, arrow }

-- Our player's yes on the privacy page: on unless a No (the user's call, like the chats).
function Fellows.Sharing() return ns.db ~= nil and ns.db.fellowsShare ~= false end

-- A map's zone: up its parents to the zone (a city's own map counts as its zone's).
local function ZoneOf(mapID)
	local seen = 0
	while mapID and seen < 6 do
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		if not info then return mapID end
		if info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3) then return mapID end
		local parent = info.parentMapID
		if not parent or parent == 0 then return mapID end
		local p = C_Map.GetMapInfo(parent)
		if not p or p.mapType ~= (Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3) and p.mapType ~= 6 then return mapID end
		mapID, seen = parent, seen + 1
	end
	return mapID
end
Fellows.ZoneOf = ZoneOf

local function Here()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return nil end
	return mapID, x, y
end

local function Tabard()
	local id = GetInventoryItemID and GetInventoryItemID("player", 19)
	return id == Fellows.GUILD_TABARD
end

---------------------------------------------------------------------------
-- Asking (our side) and answering (theirs)
---------------------------------------------------------------------------

local function Ask()
	local mapID = Here()
	if not mapID or not IsInGuild() or IsInInstance() then return end
	lastAsk = ns.Now()
	ns.Comm.Send("GUILD", ("NQ~%d~%d"):format(ZoneOf(mapID), UnitLevel("player") or 0), "fellows")
end

function Fellows.IsLooking() return looking end
function Fellows.SetLooking(on)
	looking = on and true or false
	if looking then Ask() else
		wipe(found)
		Fellows.RefreshPins()
	end
	ns.Fire("FELLOWS_CHANGED")
end

local function Beacon(force)
	local now = ns.Now()
	if now > beaconUntil or not Fellows.Sharing() or IsInInstance() then return end
	if not force and now - lastBeacon < Fellows.BEACON_EVERY then return end
	local mapID, x, y = Here()
	if not mapID then return end
	lastBeacon = now
	local _, classFile = UnitClass("player")
	ns.Comm.Send("GUILD", ("NB~%d~%d~%d~%d~%d~%s~%d"):format(mapID, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5),
		Tabard() and 1 or 0, UnitLevel("player") or 0, ns.Roster.ClassCode(classFile) or "",
		UnitAffectingCombat and UnitAffectingCombat("player") and 1 or 0), "fellows")
end

ns.Comm.Handle("NQ", function(dist, sender, text)
	if dist ~= "GUILD" or ns.FullName(sender) == ns.me then return end
	local zone, level = tostring(text):match("^NQ~(%d+)~(%d+)$")
	zone, level = tonumber(zone), tonumber(level)
	if not zone or not Fellows.Sharing() then return end
	local mapID = Here()
	if not mapID or ZoneOf(mapID) ~= zone or (UnitLevel("player") or 0) >= level then return end
	local fresh = ns.Now() > beaconUntil
	beaconUntil = ns.Now() + Fellows.BEACON_FOR
	if fresh then Beacon(true) end
end)

ns.Comm.Handle("NB", function(dist, sender, text)
	if dist ~= "GUILD" or not looking then return end
	local mapID, x, y, tabard, level, class, fighting = tostring(text):match("^NB~(%d+)~(%d+)~(%d+)~([01])~(%d+)~(%w*)~([01])$")
	if not mapID then return end
	x, y = tonumber(x), tonumber(y)
	if x > 1000 or y > 1000 then return end
	found[ns.ShortName(ns.DisplayName(sender))] = { mapID = tonumber(mapID), x = x / 1000, y = y / 1000, tabard = tabard == "1",
		level = tonumber(level), class = class ~= "" and class or nil, fighting = fighting == "1", t = ns.Now() }
	ns.Fire("FELLOWS_CHANGED")
end)

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- Yards from us, or nil.
local function Distance(f)
	local mapID, x, y = Here()
	if not (mapID and HBD and HBD.GetZoneDistance) then return nil end
	local ok, d = pcall(HBD.GetZoneDistance, HBD, mapID, x, y, f.mapID, f.x, f.y)
	return ok and d or nil
end

-- Who answered and is still current, the nearest first: { name, level, class, tabard, yards, t }.
function Fellows.List()
	local out, now = {}, ns.Now()
	for name, f in pairs(found) do
		if now - f.t <= Fellows.EXPIRE then
			out[#out + 1] = { name = name, level = f.level, class = f.class, tabard = f.tabard, fighting = f.fighting,
				yards = Distance(f), t = f.t, mapID = f.mapID }
		end
	end
	table.sort(out, function(a, b)
		if (a.yards or math.huge) ~= (b.yards or math.huge) then return (a.yards or math.huge) < (b.yards or math.huge) end
		return a.name < b.name
	end)
	return out
end

---------------------------------------------------------------------------
-- The map: tabards, and violet arrows on the minimap
---------------------------------------------------------------------------

local function Icon(size, texture)
	local f = CreateFrame("Frame", nil, UIParent)
	f.sylvanistas = true
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexture(texture)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.label or "?")
		GameTooltip:AddLine(L.FELLOW_TITLE, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end
local TABARD_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
local ARROW = "Interface\\Minimap\\MinimapArrow"

local function Label(name, f)
	return ("%s  %s%s"):format(name, L.LEVEL_N:format(f.level or 0), f.fighting and ("  |cffff4040" .. L.FELLOW_FIGHTING .. "|r") or "")
end

local function RefreshNow()
	if not Pins then return end
	local world = ns.WorldMapIcons(Pins, Fellows)
	local now = ns.Now()
	for name, p in pairs(pins) do
		local f = found[name]
		if not looking or not f or now - f.t > Fellows.EXPIRE then
			if world then Pins:RemoveWorldMapIcon(Fellows, p.world) end
			Pins:RemoveMinimapIcon(Fellows, p.mini)
			Pins:RemoveMinimapIcon(Fellows, p.arrow)
			p.world:Hide(); p.mini:Hide(); p.arrow:Hide()
		end
	end
	if not looking then return end
	local px, py, inst = HBD and HBD:GetPlayerWorldPosition()
	local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
	local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
	for name, f in pairs(found) do
		if now - f.t <= Fellows.EXPIRE then
			local p = pins[name]
			if not p then
				p = { world = Icon(14, TABARD_ICON), mini = Icon(12, TABARD_ICON), arrow = Icon(14, ARROW) }
				p.arrow.tex:SetDesaturated(true)
				p.arrow.tex:SetVertexColor(unpack(Fellows.ARROW_COLOR))
				pins[name] = p
			end
			p.world.label, p.mini.label, p.arrow.label = Label(name, f), Label(name, f), Label(name, f)
			if f.tabard then
				Pins:RemoveMinimapIcon(Fellows, p.arrow)
				p.arrow:Hide()
				if world then Pins:AddWorldMapIconMap(Fellows, p.world, f.mapID, f.x, f.y, SHOW_FLAG) end
				Pins:AddMinimapIconMap(Fellows, p.mini, f.mapID, f.x, f.y, true, false)
			else
				if world then Pins:RemoveWorldMapIcon(Fellows, p.world) end
				Pins:RemoveMinimapIcon(Fellows, p.mini)
				p.world:Hide(); p.mini:Hide()
				-- Pointing at them: the world's angle from us (HereBeDragons), turned with the minimap.
				local tx, ty = HBD:GetWorldCoordinatesFromZone(f.x, f.y, f.mapID)
				if px and tx and p.arrow.tex.SetRotation then
					local angle = HBD:GetWorldVector(inst, px, py, tx, ty)
					if angle then p.arrow.tex:SetRotation(angle - facing) end
				end
				Pins:AddMinimapIconMap(Fellows, p.arrow, f.mapID, f.x, f.y, true, true)
			end
		end
	end
end
function Fellows.RefreshPins() ns.SafeCall("fellows pins", RefreshNow) end

ns.On("LOGIN", function()
	-- (A fight starting while we answer: said at once, so a helper sees it.)
	ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() ns.SafeCall("fellows fight", Beacon, true) end)
	ns.Every(1, "fellows", function()
		local now = ns.Now()
		if looking and now - lastAsk >= Fellows.ASK_EVERY then Ask() end
		Beacon(false)
		if looking then RefreshNow() end
	end)
end)

-- The privacy page's line (Consent.lua is loaded after us: registered once it is).
ns.On("LOGIN", function()
	if not (ns.Consent and ns.Consent.Register) then return end
	ns.Consent.Register({
		key = "fellows", label = "CONSENT_FELLOWS", text = "CONSENT_FELLOWS_TEXT",
		get = function() return ns.db.fellowsShare ~= false end,
		set = function(on)
			ns.db.fellowsShare = on and true or false
			if not on then beaconUntil = 0 end
		end,
	})
end)
