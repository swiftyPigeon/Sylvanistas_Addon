local ADDON, ns = ...

-- 1.3.2: /syl demo, a test tool. The character acts as a member of <Sylvanistas> at a rank it
-- picks, with a pretend roster, so every tab can be looked at on a client where it isn't in the
-- guild (the MoP test client). Local only: while it's on the addon joins no channel, sends and
-- hears nothing, and keeps its own saved data (Core.lua, Stores). Never while the character is
-- really in a Sylvanistas guild. (Not the old demo data, removed in 0.7.9: that showed to everyone.)
--
-- The rest of the addon asks these instead of the game's guild functions (ns.GuildInfo for
-- GetGuildInfo, ns.InGuild for IsInGuild, and so on); with the demo off they are the game's, and
-- return nothing on a client without that function (the checks they replaced: "GetGuildInfo and ...").
local function Game(name, ...)
	local f = _G[name]
	if type(f) ~= "function" then return nil end
	return f(...)
end

-- The launch ranks (NEXT-STEPS 2b), as Guild Control would name them.
ns.DEMO_RANKS = { "Banshee Janitor", "Dreadguard", "Ranger/Val'kyr", "Forsaken" }
ns.DEMO_GUILD = "Sylvanistas"

-- The pretend guildmates: name, rank, level, class, zone, online, days offline.
local MATES = {
	{ "Morvaine", 0, 60, "WARLOCK", "Undercity", true, 0 },
	{ "Ashgrave", 1, 60, "WARRIOR", "Orgrimmar", true, 0 },
	{ "Velyth", 1, 58, "PRIEST", "Tirisfal Glades", false, 1 },
	{ "Corvane", 2, 60, "ROGUE", "Stranglethorn Vale", true, 0 },
	{ "Nyxra", 2, 55, "MAGE", "The Barrens", true, 0 },
	{ "Thessaly", 2, 47, "SHAMAN", "Ashenvale", false, 3 },
	{ "Grimlow", 3, 42, "HUNTER", "Silverpine Forest", true, 0 },
	{ "Duskhallow", 3, 38, "DRUID", "The Barrens", true, 0 },
	{ "Ravel", 3, 33, "WARRIOR", "Hillsbrad Foothills", false, 9 },
	{ "Sarnis", 3, 24, "PRIEST", "Tirisfal Glades", true, 0 },
	{ "Moldra", 3, 18, "MAGE", "Silverpine Forest", false, 34 },
	{ "Kethril", 3, 12, "ROGUE", "Durotar", true, 0 },
}

-- Saved per character (SylvanistasDB is the account's): the other characters stay as they are.
local function Key()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function Saved()
	local all = SylvanistasDB and SylvanistasDB.demoMode
	return type(all) == "table" and all[Key()] or nil
end

-- The demo's settings ({ rank = 0..3 }), or nil when it's off. A character found really in a
-- Sylvanistas guild loses its demo for good. (The game's own functions here: never the ones below.)
function ns.Demo()
	local d = Saved()
	if type(d) ~= "table" or type(d.rank) ~= "number" then return nil end
	if Game("IsInGuild") and ns.IsFederation and ns.IsFederation((Game("GetGuildInfo", "player"))) == true then
		SylvanistasDB.demoMode[Key()] = nil
		return nil
	end
	return d
end

local roster -- built once per session: the character first, then the mates
local function Roster()
	if roster then return roster end
	local d = ns.Demo()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
	local _, class = UnitClass("player")
	roster = { { UnitName("player"), d.rank, UnitLevel("player") or 1, class, GetZoneText() or "", true, 0 } }
	for _, m in ipairs(MATES) do
		-- Rank 0 is the character's when it plays the leader: the pretend leader steps down to rank 1.
		if not (m[2] == 0 and d.rank == 0) then roster[#roster + 1] = m end
	end
	-- "Name-Realm", as the server gives roster names.
	for _, m in ipairs(roster) do
		if not m[1]:find("-", 1, true) then m[1] = m[1] .. "-" .. realm end
	end
	return roster
end

function ns.GuildInfo(unit)
	local d = unit == "player" and ns.Demo()
	if not d then return Game("GetGuildInfo", unit) end
	return ns.DEMO_GUILD, ns.DEMO_RANKS[d.rank + 1], d.rank, nil
end

function ns.InGuild()
	if ns.Demo() then return true end
	return Game("IsInGuild")
end

function ns.NumGuildMembers()
	if not ns.Demo() then return Game("GetNumGuildMembers") end
	local r, online = Roster(), 0
	for _, m in ipairs(r) do if m[6] then online = online + 1 end end
	return #r, online, online
end

-- As GetGuildRosterInfo: name, rankName, rankIndex, level, class, zone, note, officerNote, online,
-- status, classFile (the rest nil).
function ns.GuildRosterInfo(i)
	if not ns.Demo() then return Game("GetGuildRosterInfo", i) end
	local m = Roster()[i]
	if not m then return nil end
	return m[1], ns.DEMO_RANKS[m[2] + 1], m[2], m[3], m[4], m[5], "", "", m[6], 0, m[4]
end

function ns.GuildRosterLastOnline(i)
	if not ns.Demo() then return Game("GetGuildRosterLastOnline", i) end
	local m = Roster()[i]
	if not m or m[6] then return nil end
	return 0, 0, m[7], 0
end

function ns.GuildRankCount()
	if not ns.Demo() then return Game("GuildControlGetNumRanks") end
	return #ns.DEMO_RANKS
end

function ns.GuildRankName(i)
	if not ns.Demo() then return Game("GuildControlGetRankName", i) end
	return ns.DEMO_RANKS[i]
end

-- Sends, invites and removals ask this first: true in the demo (nothing goes out), with one
-- line in chat at most every 10 seconds.
local lastNote = 0
function ns.DemoBlocked()
	if not ns.Demo() then return false end
	if GetTime() - lastNote > 10 then
		lastNote = GetTime()
		ns.Print(ns.L.DEMO_BLOCKED)
	end
	return true
end

-- /syl demo [0-3|off]: starting or ending it reloads the interface, so every part of the addon
-- starts as a member (or not) from the beginning.
function ns.DemoCommand(rest)
	local L = ns.L
	rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local d = Saved()
	if rest == "off" then
		if not d then return ns.Print(L.DEMO_NOT_ON) end
		SylvanistasDB.demoMode[Key()] = nil
		return ReloadUI()
	end
	local rank = tonumber(rest)
	if not rank then
		if ns.Demo() then ns.Print(L.DEMO_ON:format(d.rank, ns.DEMO_RANKS[d.rank + 1])) end
		return ns.Print(L.DEMO_USAGE)
	end
	if rank < 0 or rank > #ns.DEMO_RANKS - 1 or rank % 1 ~= 0 then return ns.Print(L.DEMO_USAGE) end
	if Game("IsInGuild") and ns.IsFederation((Game("GetGuildInfo", "player"))) == true then return ns.Print(L.DEMO_REAL_MEMBER) end
	if not SylvanistasDB then return end
	if type(SylvanistasDB.demoMode) ~= "table" then SylvanistasDB.demoMode = {} end
	SylvanistasDB.demoMode[Key()] = { rank = rank }
	ReloadUI()
end

ns.On("LOGIN", function()
	local d = ns.Demo()
	if d then ns.Print(ns.L.DEMO_ON:format(d.rank, ns.DEMO_RANKS[d.rank + 1])) end
end)
