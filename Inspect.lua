local ADDON, ns = ...
local L = ns.L

-- The patrol behind the Regalia tab: inspects nearby Sylvanistas members and notes who wears the
-- guild's tabard (never who doesn't). "Patrol" mode scans target, mouseover, party/raid and
-- friendly nameplates on its own. Kept in SylvanistasDB.inspect.
-- (1.3.0: the original's strict tabard inspection is gone, the user's call: no marks, no
-- officers' shared list, no Wall of Shame, no Royal Inspection.)

local Inspect = {}
ns.Inspect = Inspect

-- The tab is Regalia (Views.lua, RegaliaLines).
L.TAB_HERALDRY = L.REGALIA_TAB
L.HELP_TAB_HERALDRY = L.HELP_TAB_REGALIA

local TABARD_SLOT = INVSLOT_TABARD or 19
Inspect.GUILD_TABARDS = { [5976] = true } -- "Guild Tabard"
local RECHECK = 10 * 60   -- do not re-inspect the same player on patrol for 10 minutes
local INTERVAL = 1.5      -- one inspect request at a time, spaced out
local TIMEOUT = 4

local STATUS_ORDER = { NONE = 1, OTHER = 2, UNKNOWN = 3, UNCHECKED = 4, GUILD = 5 }
Inspect.STATUS_ORDER = STATUS_ORDER

local patrol = false
local queue, queued = {}, {}
local pending -- { guid, unit, at }
Inspect.stats = { requests = 0, ready = 0, timeouts = 0 }

-- Kept per realm (ns.rdb): the players of one realm say nothing about another one.
local function Store()
	local db = ns.rdb
	db.inspect = db.inspect or {}
	db.inspect.players = db.inspect.players or {}
	db.inspect.guildMarks = db.inspect.guildMarks or {}
	return db.inspect
end

local Source = Store

-- Every player a patrol ever checked stays in the saved variables, and the Tabards tab draws a
-- line for each: after a few weeks of patrols in a crowded capital that is thousands. Kept:
-- the last MAX_AGE, and at most MAX_PLAYERS of them, those with kept gear first, then the newest.
Inspect.MAX_AGE = 14 * 86400
Inspect.MAX_PLAYERS = 2000
local function Keep(p) return p.gear and 1 or 2 end
function Inspect.Prune()
	local players, now, n = Store().players, ns.Now(), 0
	for name, p in pairs(players) do
		local age = now - (tonumber(type(p) == "table" and p.t) or 0)
		-- (Entries another officer passed on before 1.3.0 go with the first prune.)
		if type(p) ~= "table" or age > Inspect.MAX_AGE or (p.shared and not p.gear) then
			players[name] = nil
		else
			n = n + 1
		end
	end
	if n <= Inspect.MAX_PLAYERS then return end
	local list = {}
	for name, p in pairs(players) do list[#list + 1] = { name = name, keep = Keep(p), t = tonumber(p.t) or 0 } end
	table.sort(list, function(a, b)
		if a.keep ~= b.keep then return a.keep < b.keep end
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	for i = Inspect.MAX_PLAYERS + 1, #list do players[list[i].name] = nil end
end

-- The gear an officer's click kept (1.1, request #28): at most GEAR_MAX players carry it, the
-- oldest gear dropped first (the player's inspection stays).
Inspect.GEAR_MAX = 200
function Inspect.PruneGear()
	local list = {}
	for name, p in pairs(Store().players) do
		if type(p) == "table" and p.gear ~= nil then
			if type(p.gear) ~= "table" or type(p.gear.items) ~= "table" then p.gear = nil
			else list[#list + 1] = { name = name, t = tonumber(p.gear.t) or 0 } end
		end
	end
	if #list <= Inspect.GEAR_MAX then return end
	table.sort(list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	for i = Inspect.GEAR_MAX + 1, #list do Store().players[list[i].name].gear = nil end
end

-- itemID nil + some other gear visible = really no tabard. Nothing visible at all usually
-- means the inspect data did not load, so we call it UNKNOWN instead of accusing anyone.
function Inspect.Classify(tabardID, anyGearVisible)
	if tabardID then return Inspect.GUILD_TABARDS[tabardID] and "GUILD" or "OTHER" end
	return anyGearVisible and "NONE" or "UNKNOWN"
end

function Inspect.IsPatrolling() return patrol end

-- Everyone the patrol saw on this realm group.
function Inspect.Players() return Store().players end

-- One key per player in the store: "Name" for our realm, "Name-Realm" for another, whatever
-- the name came from (a unit, what 0.8.1 saved). On Forever, "First Surname".
local function Key(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.DisplayName(ns.FullName(ns.Normal(name)))
end
Inspect.Key = Key

-- The tabard nudge (Inspect.Nudge) waits for this level.
Inspect.MIN_LEVEL = 15

function Inspect.Record(name, guild, classFile, level, tabardID, anyGear)
	name = Key(name)
	if not name then return nil end
	local s = Store()
	local p = s.players[name] or {}
	local previous = p.status
	p.name, p.guild, p.class, p.level = name, guild, classFile, level
	p.item = tabardID
	p.status = Inspect.Classify(tabardID, anyGear)
	p.t = ns.Now()
	-- 1.2.2 (Forsaken Regalia): where they were seen (within inspect range: our own zone), and each
	-- day they were seen in the guild's tabard (Loyalists, Inspect.IsLoyalist).
	p.zone = GetRealZoneText and GetRealZoneText() or p.zone
	if p.status == "GUILD" then
		local day = date("%Y-%m-%d")
		if p.loyalDay ~= day then p.loyalDay, p.loyalDays = day, (tonumber(p.loyalDays) or 0) + 1 end
	end
	p.shared, p.by, p.marked, p.note = nil, nil, nil, nil -- (left from before 1.3.0)
	s.players[name] = p
	ns.Log("inspect %s <%s>: %s (%s)", name, tostring(guild), p.status, tostring(tabardID))
	if not previous then Inspect.Prune() end -- (only a new player makes the store grow)
	ns.Fire("INSPECT_CHANGED")
	return p
end

-- gear (1.1): an officer's click asks for the gear too (Inspect.InspectGear); the same queue and
-- pace as every other request, first in line.
local function Enqueue(unit, force, gear)
	if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
	local guid = UnitGUID(unit)
	if not guid then return end
	if gear then
		-- Already waiting (a patrol's) or asked: that request brings the gear too.
		if pending and pending.guid == guid then pending.gear = true return end
		for i, item in ipairs(queue) do
			if item.guid == guid then
				table.remove(queue, i)
				item.gear, item.unit = true, unit
				table.insert(queue, 1, item)
				return
			end
		end
	end
	if queued[guid] or (pending and pending.guid == guid) then return end
	local guild = GetGuildInfo(unit)
	if not force and not ns.IsFederation(guild) then return end
	-- Sylvanistas guilds of the other faction are not ours to inspect (the Horde has its own too).
	if not force and UnitFactionGroup and UnitFactionGroup(unit) ~= UnitFactionGroup("player") then return end
	if not force then
		local p = Store().players[Key(ns.UnitFullName(unit))]
		if p and p.status ~= "UNKNOWN" and p.status ~= "UNCHECKED" and ns.Now() - (p.t or 0) < RECHECK then return end
	end
	queued[guid] = true
	table.insert(queue, force and 1 or #queue + 1, { unit = unit, guid = guid, gear = gear or nil })
end

local function ScanNearby()
	Enqueue("target")
	Enqueue("mouseover")
	if IsInRaid() then
		for i = 1, 40 do Enqueue("raid" .. i) end
	else
		for i = 1, 4 do Enqueue("party" .. i) end
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then Enqueue(unit) end
	end
end

local function Pump()
	if pending then
		if GetTime() - pending.at < TIMEOUT then return end
		Inspect.stats.timeouts = Inspect.stats.timeouts + 1
		pending = nil
	end
	if InCombatLockdown() then return end
	if InspectFrame and InspectFrame:IsShown() then return end -- the player is inspecting by hand
	if patrol then ScanNearby() end
	while #queue > 0 do
		local item = table.remove(queue, 1)
		queued[item.guid] = nil
		local unit = item.unit
		if UnitGUID(unit) == item.guid and CanInspect(unit) and CheckInteractDistance(unit, 1) then
			pending = { guid = item.guid, unit = unit, at = GetTime(), gear = item.gear }
			Inspect.stats.requests = Inspect.stats.requests + 1
			NotifyInspect(unit)
			return
		end
	end
end
Inspect.Pump = Pump -- (tests)

local function FindUnit(guid, hint)
	if hint and UnitGUID(hint) == guid then return hint end
	for _, u in ipairs({ "target", "mouseover", "focus" }) do
		if UnitGUID(u) == guid then return u end
	end
	for i = 1, 40 do
		if UnitGUID("nameplate" .. i) == guid then return "nameplate" .. i end
	end
	return nil
end

-- The items a unit wears, as the inspection gave them (1.1): slot -> the item's own string (its id,
-- enchant and suffix, "item:19019:..."; its id alone when the client gave no link yet). What did not
-- load is left out, never guessed. Nothing else: no item level, no score.
local GEAR_SLOTS = 19
local function ReadGear(unit)
	local items, n = {}, 0
	for slot = 1, GEAR_SLOTS do
		local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot)
		local item = type(link) == "string" and link:match("item:[%-%d:]+") or nil
		if item then item = item:gsub(":+$", "") end
		if not item then
			local id = GetInventoryItemID(unit, slot)
			if type(id) == "number" and id > 0 then item = "item:" .. math.floor(id) end
		end
		if item and #item <= 120 then items[slot], n = item, n + 1 end
	end
	return items, n
end

local function OnInspectReady(guid)
	if not pending or pending.guid ~= guid then return end
	local unit = FindUnit(guid, pending.unit)
	local gear = pending.gear
	pending = nil
	Inspect.stats.ready = Inspect.stats.ready + 1
	if unit then
		local anyGear = false
		for slot = 1, 18 do
			if GetInventoryItemID(unit, slot) then anyGear = true break end
		end
		local _, classFile = UnitClass(unit)
		local name = ns.UnitFullName(unit)
		local p = Inspect.Record(name, GetGuildInfo(unit), classFile, UnitLevel(unit),
			GetInventoryItemID(unit, TABARD_SLOT), anyGear)
		-- An officer's click (Inspect.InspectGear): the gear kept with the inspection.
		if gear and p then
			local items, n = ReadGear(unit)
			if n > 0 then
				p.gear = { t = ns.Now(), items = items }
				Inspect.PruneGear()
				ns.Print(L.GEAR_SAVED:format(ns.ShortName(p.name), n))
				ns.Fire("INSPECT_CHANGED")
			else
				ns.Print(L.GEAR_NOT_LOADED:format(ns.ShortName(p.name)))
			end
		end
	elseif gear then
		ns.Print(L.GEAR_GONE)
	end
	if not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then ClearInspectPlayer() end
end
Inspect.OnInspectReady = OnInspectReady -- (tests)

function Inspect.SetPatrol(on)
	if on and not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	patrol = on and true or false
	if ns.Fellows then ns.Fellows.SetLooking(patrol) end -- (1.3.0: guildmates in our zone below our level)
	ns.Print(patrol and L.FELLOW_ON or L.FELLOW_OFF)
	ns.Log("patrol = %s", tostring(patrol))
	ns.Fire("INSPECT_CHANGED")
end

function Inspect.InspectTarget()
	if not UnitIsPlayer("target") then
		ns.Print(L.NEED_PLAYER_TARGET)
		return
	end
	Enqueue("target", true)
	Pump()
end

-- 1.1 (request #28): an officer's click keeps the gear of the player he targets, in range, as the
-- game's inspection shows it: one request in the same queue and pace as the patrol's (one
-- NotifyInspect at a time, never in combat or while the game's inspect window is open). Kept in
-- his saved variables with the inspection, for a raid signup days later without pulling the player
-- again. Nothing scored, nothing sent, nobody told how to play. Officers: the guild master and the
-- officer rank right below (Roster.IsOfficer).
function Inspect.InspectGear()
	if not ns.IsMember() then return ns.Print(L.MEMBERS_ONLY) end
	if not ns.Roster.IsOfficer() then return ns.Print(L.GEAR_OFFICERS_ONLY) end
	if not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return ns.Print(L.NEED_PLAYER_TARGET) end
	local name = ns.ShortName(ns.UnitFullName("target") or "?")
	-- (In combat the game keeps the distance to itself: the request waits in line, and the pump
	-- looks at the range once the fight is over, as for every inspection.)
	local fighting = InCombatLockdown and InCombatLockdown()
	if not fighting and (not CanInspect("target") or not CheckInteractDistance("target", 1)) then return ns.Print(L.GEAR_OUT_OF_RANGE:format(name)) end
	Enqueue("target", true, true)
	ns.Print(L.GEAR_ASKING:format(name))
	Pump()
end

-- The players whose gear is kept, newest first: { { name, guild, class, level, t, items } }.
function Inspect.GearList()
	local out = {}
	for _, p in pairs(Source().players) do
		if type(p) == "table" and type(p.gear) == "table" and type(p.gear.items) == "table" then
			out[#out + 1] = { name = p.name, guild = p.guild, class = p.class, level = p.level, t = tonumber(p.gear.t) or 0, items = p.gear.items }
		end
	end
	table.sort(out, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

function Inspect.Clear()
	local s = Store()
	wipe(s.players)
	wipe(s.guildMarks)
	ns.Fire("INSPECT_CHANGED")
end

-- Only good news on a player's tooltip, and nothing at all for the rest.
function Inspect.TooltipLine(name)
	local p = Source().players[Key(name)]
	if not p or p.status ~= "GUILD" then return nil end
	return "|cff40ff40" .. L.REGALIA_TIP_LINE .. "|r" .. (Inspect.IsLoyalist(p.name) and ("  " .. Inspect.LOYAL_MARK .. "|cffffd200" .. L.LOYALIST .. "|r") or "")
		.. "  |cff9d9d9d" .. ns.Ago(p.t) .. "|r"
end

---------------------------------------------------------------------------
-- Forsaken Regalia (1.2.2): the patrol, read the other way round.
-- Who was seen in the guild's tabard (tonight, per zone, per guild), the Loyalists (seen in it on
-- LOYAL_DAYS days or more) and Fellow Forsaken (who is around now). What
-- this client's own patrol saw, never sent; nobody is ever listed for not wearing it.
---------------------------------------------------------------------------

Inspect.LOYAL_DAYS = 3                -- days seen in regalia to count as a Loyalist
Inspect.LOYAL_MARK = "|TInterface\\Icons\\INV_Shirt_GuildTabard_01:12:12|t "
Inspect.TONIGHT = 12 * 3600           -- "tonight": seen in the last 12 hours
Inspect.FELLOW_WINDOW = 15 * 60       -- Fellow Forsaken: seen in the last 15 minutes
Inspect.ASSEMBLY_KEEP = 60 * 60       -- an assembly's count runs as long as its call (Decree.lua)

function Inspect.IsLoyalist(name)
	local p = Source().players[Key(name)]
	return type(p) == "table" and (tonumber(p.loyalDays) or 0) >= Inspect.LOYAL_DAYS
end

local function Ours(p) return type(p) == "table" and p.name and ns.IsFederation(p.guild) end

-- Tonight's regalia: { inRegalia, seen, zones = { {zone, n} }, guilds = { {name, n, seen} }, loyalists = { p } }.
function Inspect.Regalia()
	local now, out = ns.Now(), { inRegalia = 0, seen = 0, zones = {}, guilds = {}, loyalists = {} }
	local zones, guilds = {}, {}
	for _, p in pairs(Source().players) do
		if Ours(p) then
			if now - (p.t or 0) <= Inspect.TONIGHT and p.status ~= "UNKNOWN" and p.status ~= "UNCHECKED" then
				out.seen = out.seen + 1
				local g = guilds[p.guild] or { name = p.guild, n = 0, seen = 0 }
				guilds[p.guild] = g
				g.seen = g.seen + 1
				if p.status == "GUILD" then
					out.inRegalia, g.n = out.inRegalia + 1, g.n + 1
					if p.zone and p.zone ~= "" then zones[p.zone] = (zones[p.zone] or 0) + 1 end
				end
			end
			if (tonumber(p.loyalDays) or 0) >= Inspect.LOYAL_DAYS then out.loyalists[#out.loyalists + 1] = p end
		end
	end
	for zone, n in pairs(zones) do out.zones[#out.zones + 1] = { zone = zone, n = n } end
	table.sort(out.zones, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.zone < b.zone end)
	for _, g in pairs(guilds) do out.guilds[#out.guilds + 1] = g end
	table.sort(out.guilds, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
	table.sort(out.loyalists, function(a, b)
		if (a.loyalDays or 0) ~= (b.loyalDays or 0) then return (a.loyalDays or 0) > (b.loyalDays or 0) end
		return a.name < b.name
	end)
	return out
end

-- Fellow Forsaken: guildmates the patrol saw in the last FELLOW_WINDOW, newest first.
function Inspect.Fellows()
	local now, out = ns.Now(), {}
	for _, p in pairs(Source().players) do
		if Ours(p) and now - (p.t or 0) <= Inspect.FELLOW_WINDOW then out[#out + 1] = p end
	end
	table.sort(out, function(a, b)
		if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
		return a.name < b.name
	end)
	return out
end

-- Assemble the Loyal: from our call (Decree.Send), our patrol counts who comes in regalia.
local assembly -- { at }
function Inspect.StartAssembly()
	assembly = { at = ns.Now() }
	if not patrol and ns.IsMember() then Inspect.SetPatrol(true) end
	ns.Fire("INSPECT_CHANGED")
end
-- { at, n }: our assembly running (or nil), and how many came in regalia since its call.
function Inspect.Assembly()
	if not assembly or ns.Now() - assembly.at > Inspect.ASSEMBLY_KEEP then return nil end
	local n = 0
	for _, p in pairs(Source().players) do
		if Ours(p) and p.status == "GUILD" and (p.t or 0) >= assembly.at then n = n + 1 end
	end
	return { at = assembly.at, n = n }
end

-- The Dark Lady's thanks: the Loyalists named in guild chat, from her click (casual).
Inspect.THANKS_NAMES = 8
function Inspect.ThankLoyal()
	local r = Inspect.Regalia()
	if #r.loyalists == 0 then return ns.Print(L.LOYALISTS_NONE) end
	local names = {}
	for i = 1, math.min(Inspect.THANKS_NAMES, #r.loyalists) do names[#names + 1] = ns.ShortName(r.loyalists[i].name) end
	SendChatMessage(L.LOYALISTS_THANKS:format(table.concat(names, ", ")), "GUILD")
end

-- The private nudge: once a session, a few seconds after login, our own client looks at our own
-- tabard slot. Not the guild's tabard: one friendly line, to us alone. Nothing is sent or kept.
Inspect.NUDGE_AFTER = 20
function Inspect.Nudge()
	if not ns.IsMember() then return false end
	if UnitLevel and UnitLevel("player") < Inspect.MIN_LEVEL then return false end
	local id = GetInventoryItemID("player", TABARD_SLOT)
	if id and Inspect.GUILD_TABARDS[id] then return false end
	ns.Print(L.REGALIA_NUDGE)
	return true
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function OnTooltipUnit(tooltip)
	if tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	if not unit or not UnitIsPlayer(unit) then return end
	local name = ns.UnitFullName(unit)
	local line = Inspect.TooltipLine(name)
	if line then tooltip:AddLine(line) end
	-- The Treasurer of Sylvanistas: his name and the game's own word on his guild.
	if ns.IsTreasurer(name, GetGuildInfo(unit)) then tooltip:AddLine(ns.COIN .. L.TREASURER_TITLE, 1, 0.82, 0) end
	if patrol then Enqueue(unit) end
end

ns.On("INIT", function() Inspect.Prune(); Inspect.PruneGear() end) -- (Prune makes the store too)

ns.On("LOGIN", function()
	ns.After(Inspect.NUDGE_AFTER, "regalia nudge", Inspect.Nudge)
	ns.RegisterEvent("INSPECT_READY", OnInspectReady)
	ns.Every(INTERVAL, "inspect pump", Pump)
	local hooked = false
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
			ns.SafeCall("tooltip", OnTooltipUnit, tt)
		end)
	end
	if not hooked then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt)
			ns.SafeCall("tooltip", OnTooltipUnit, tt)
		end)
	end
	ns.Log("tooltip hook: %s", hooked and "TooltipDataProcessor" or "OnTooltipSetUnit")
end)

