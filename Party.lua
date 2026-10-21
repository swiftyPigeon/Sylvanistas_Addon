local ADDON, ns = ...
local L = ns.L

-- Party invites (Sylvanistas): a leader gathers a party of guildmates who are solo in the same
-- zone and said yes to it, with one click; officers can gather the whole zone; anyone can send a
-- Party Scream that solo players in the zone answer with one click.
--
-- Who is free: each player who said yes tells the guild, over GUILD alone (the server stamps the
-- sender, and our roster vouches for them), that they are solo in a zone, and says so again when
-- that changes. Nobody who said no, or never answered, sends or receives anything of it.
--   PA~1~<mapID>~<zoneUID>~<level>~<class>   I'm solo here and take party invites (GUILD)
--   PA~0                                     not any more (GUILD)
--   PI~<id>                                  an invite from me is coming (WHISPER, leader -> player)
--   PS~<id>~<mapID>~<note>                   a Party Scream: forming a party here (GUILD)
--   PQ~<id>                                  please invite me (WHISPER, player -> screamer)
-- The invitee's addon joins on its own only with auto-join on, only for an invite a guildmate
-- announced with PI just before, never during a layer hop of its own (Hop.lua handles those), and
-- never with the gamepad UI (the game's own invite window answers there). Nobody is invited in an
-- instance, in combat or while Busy, nor while already in a group.

local Party = {}
ns.Party = Party

Party.ANNOUNCE_EVERY = 60  -- an available player repeats "free here" this often
Party.FRESH = 150          -- an announcement counts this long
Party.INVITE_GAP = 1.5     -- seconds between two invites
Party.NOTICE_FOR = 30      -- an invite notice lets auto-join take the invite this long
Party.SCREAM_GAP = 120     -- one Party Scream per player this often
Party.SCREAM_FOR = 300     -- a Party Scream can be answered this long
Party.MAX_PARTY = 5
Party.MAX_RAID = 40
Party.PENDING_FOR = 60      -- an invite not answered counts as a place this long
Party.WAIT_RAID_FOR = 90    -- a zone gather waits this long for someone to accept before it gives up
Party.SCREAM_TOAST_FOR = 30 -- the Join window stays this long (the Scream itself counts SCREAM_FOR)
local HEALERS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }

local avail = {}     -- [Name-Realm] = { mapID, zoneUID, level, class, t }
local notices = {}   -- [Name-Realm] = t: that guildmate announced an invite to us
local queue = {}     -- names still to invite, in order
local queueZone      -- true while the queue is a zone-wide gather
local running = false
local pending = {}   -- [Name-Realm] = t: invited, not in the group yet (counts for PENDING_FOR)
local startedAt = -math.huge
local sentState, sentAt = nil, -math.huge
local lastScream = -math.huge
local myScream       -- { id, t, mapID }
local answered = {}  -- [scream id] = true: asked or shown once
local watch = {}     -- [Name-Realm] = t: invited by us, waiting to hear whether they join (1.3.0)

local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end

local Names
local function Changed() ns.Fire("BOARD_CHANGED") ns.Fire("PARTY_CHANGED") end

-- 1.3.0: the one who sends it sees it (the user's call): each click, each answer, in the chat and
-- in the small silver window (ns.Toast).
local ICON = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude"
local function Tell(text)
	ns.Print(text)
	if ns.Toast then ns.Toast(text, (not GetFileIDFromPath or GetFileIDFromPath(ICON)) and ICON or nil) end
end

---------------------------------------------------------------------------
-- Settings: on until the player says no (the Screams tab's cog, the privacy page, /syl party)
---------------------------------------------------------------------------

-- (1.3.0: on unless the player turned it off, the user's call; auto-join stays off until asked.)
function Party.On() return ns.db ~= nil and ns.db.partyInvites ~= false end
function Party.Auto() return Party.On() and ns.db.partyAuto == true end

function Party.Set(on, quiet)
	if not ns.db then return end
	ns.db.partyInvites = on and true or false
	if not quiet then ns.Print(on and L.PARTY_ON or L.PARTY_OFF) end
	ns.SafeCall("party announce", Party.Announce, true)
	Changed()
end

function Party.SetAuto(on, quiet)
	if not ns.db then return end
	ns.db.partyAuto = on and true or false
	if not quiet then ns.Print(on and L.PARTY_AUTO_ON or L.PARTY_AUTO_OFF) end
	Changed()
end

---------------------------------------------------------------------------
-- Where we are, and whether we are free
---------------------------------------------------------------------------

local function MapID()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function ZoneUID(mapID)
	local mine = ns.Layers and ns.Layers.Mine and ns.Layers.Mine()
	if type(mine) == "table" and mine.mapID == mapID and mine.zoneUID then return tostring(mine.zoneUID) end
	return ""
end

local function ZoneName(mapID)
	local name = mapID and ns.Zones and ns.Zones.NameForKey and ns.Zones.NameForKey("m" .. mapID)
	if type(name) ~= "string" or name == "" then
		local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		name = info and info.name
	end
	return name or "?"
end

local function Busy()
	if not UnitIsDND then return false end
	local ok, dnd = pcall(UnitIsDND, "player")
	return ok and dnd == true
end

local function InInstance()
	if not IsInInstance then return false end
	local inside, kind = IsInInstance()
	return inside and kind ~= "none"
end

local function InCombat() return UnitAffectingCombat and UnitAffectingCombat("player") and true or false end
local function Grouped() return IsInGroup and IsInGroup() and true or false end

-- Free for an invite: solo, not in an instance, not in combat, not Busy.
function Party.Free()
	return not Grouped() and not InInstance() and not InCombat() and not Busy()
end
-- What we tell the guild: the same without combat (a fight is short; our status would flicker).
local function Available() return not Grouped() and not InInstance() and not Busy() end

local function Guildmate(name) return ns.Roster and ns.Roster.RankOf and ns.Roster.RankOf(name) ~= nil end

-- Guildmates online in our zone (the game's guild roster), us aside: what "nobody here" means.
local function GuildHere()
	local zone = GetRealZoneText and GetRealZoneText()
	if not (zone and zone ~= "" and GetNumGuildMembers and GetGuildRosterInfo) then return 0 end
	local n = 0
	for i = 1, (GetNumGuildMembers()) or 0 do
		local name, _, _, _, _, z, _, _, online = GetGuildRosterInfo(i)
		if online and z == zone and name and ns.FullName(name) ~= ns.me then n = n + 1 end
	end
	return n
end

local function Nobody(mapID)
	local here = GuildHere()
	if here == 0 then return Tell(L.PARTY_NOBODY_GUILD:format(ZoneName(mapID))) end
	Tell(L.PARTY_NOBODY_OFF:format(ZoneName(mapID), here))
end

---------------------------------------------------------------------------
-- Telling the guild we are free (only while the switch is on)
---------------------------------------------------------------------------

function Party.Announce(force)
	if not (ns.IsMember() and ns.Comm and ns.Comm.Send) then return end
	local mapID = MapID()
	local msg
	if Party.On() and Available() and mapID then
		local _, class = UnitClass("player")
		msg = ("PA~1~%d~%s~%d~%s"):format(mapID, ZoneUID(mapID), UnitLevel("player") or 0, class or "")
	else
		msg = "PA~0"
	end
	local now = ns.Now()
	if msg == sentState and not (msg ~= "PA~0" and now - sentAt >= Party.ANNOUNCE_EVERY) and not force then return end
	-- Never told anyone we were free: nothing to take back.
	if msg == "PA~0" and sentState == nil then sentState = msg return end
	if msg == "PA~0" and sentState == "PA~0" then return end
	sentState, sentAt = msg, now
	ns.Comm.Send("GUILD", msg, "party")
end

ns.Comm.Handle("PA", function(dist, sender, text)
	if dist ~= "GUILD" or not Guildmate(sender) then return end
	local on, mapID, zoneUID, level, class = text:match("^PA~([01])~?(%d*)~?([^~]*)~?(%d*)~?(%u*)$")
	if on == "1" and tonumber(mapID) then
		avail[sender] = { mapID = tonumber(mapID), zoneUID = zoneUID ~= "" and zoneUID or nil,
			level = tonumber(level) or 0, class = class ~= "" and class or nil, t = ns.Now() }
	else
		avail[sender] = nil
	end
	Changed()
end)

-- Already in our group (the game's check, safe for any name).
local function InMyGroup(name)
	if not (UnitInParty and Grouped()) then return false end
	local ok, yes = pcall(UnitInParty, ns.ShortName(name))
	return ok and yes and true or false
end

-- Guildmates free in this zone, best first: same layer, then closest level, a healer kept in.
function Party.Candidates(mapID)
	local now, out = ns.Now(), {}
	local myLevel = UnitLevel("player") or 0
	local myUID = ZoneUID(mapID)
	for name, a in pairs(avail) do
		if now - a.t > Party.FRESH or not Guildmate(name) then
			avail[name] = nil
		elseif a.mapID == mapID and name ~= ns.me and not InMyGroup(name) then
			out[#out + 1] = { name = name, sameLayer = myUID ~= "" and a.zoneUID == myUID, gap = math.abs((a.level or 0) - myLevel),
				healer = a.class and HEALERS[a.class] or false }
		end
	end
	table.sort(out, function(x, y)
		if x.sameLayer ~= y.sameLayer then return x.sameLayer end
		if x.gap ~= y.gap then return x.gap < y.gap end
		return x.name < y.name
	end)
	return out
end

local function KeepHealer(list, slots)
	if slots < 1 or #list <= slots then return list end
	for i = 1, slots do if list[i].healer then return list end end
	for i = slots + 1, #list do
		if list[i].healer then
			local h = table.remove(list, i)
			table.insert(list, slots, h)
			break
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Inviting
---------------------------------------------------------------------------

-- Members in our group (1 alone) and whether we may invite (leader, or alone).
local function Room()
	if not Grouped() then return 1, true end
	local n = GetNumGroupMembers and GetNumGroupMembers() or 1
	local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
	if not lead and IsInRaid and IsInRaid() and UnitIsGroupAssistant then lead = UnitIsGroupAssistant("player") end
	return n, lead and true or false
end

local function Max() return (IsInRaid and IsInRaid()) and Party.MAX_RAID or Party.MAX_PARTY end

-- Invites still out (not answered, not expired), counted as places in the group.
local function Pending()
	local now, n = ns.Now(), 0
	for name, t in pairs(pending) do
		if now - t > Party.PENDING_FOR or InMyGroup(name) then pending[name] = nil else n = n + 1 end
	end
	return n
end

local function InviteNow(name)
	pending[name] = ns.Now()
	watch[name] = ns.Now()
	local target = ns.TellName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end
	ns.Log("party: invited %s", tostring(name))
end

local function Pump()
	if #queue == 0 then running = false Changed() return end
	local n, lead = Room()
	if not lead then queue = {} running = false return end
	if n + Pending() >= Max() then
		if queueZone and not (IsInRaid and IsInRaid()) then
			-- A raid needs a group first: wait for someone to accept, then ask the leader once.
			if not Grouped() then
				if ns.Now() - startedAt > Party.WAIT_RAID_FOR then
					ns.Print(L.PARTY_FULL) queue = {} running = false
				else
					ns.After(5, "party wait", Pump)
				end
				return
			end
			running = false
			ns.Print(L.PARTY_FULL_RAID:format(#queue))
			ns.ShowDialog("SYLVANISTAS_PARTY_RAID", tostring(#queue))
		else
			ns.Print(L.PARTY_FULL)
			queue = {} running = false
		end
		return
	end
	local name = table.remove(queue, 1)
	pending[name] = ns.Now() -- (a place already, while the notice goes out)
	local id = math.random(100000, 999999)
	-- The notice first, so their addon knows this invite is ours; the invite once it has left.
	local sentOnce = false
	ns.Comm.Whisper(name, "PI~" .. id, nil, true, nil, function()
		if sentOnce then return end
		sentOnce = true
		ns.After(0.5, "party invite", function() InviteNow(name) end)
	end)
	ns.After(Party.INVITE_GAP + 1, "party next", Pump)
end

-- "Bob, Ann and 3 more", for the toast.
function Names(names)
	local shown = {}
	for i = 1, math.min(3, #names) do shown[i] = ns.DisplayName(names[i]) or names[i] end
	local s = table.concat(shown, ", ")
	if #names > 3 then s = s .. L.PARTY_AND_MORE:format(#names - 3) end
	return s
end

local function Start(names, zoneWide)
	for _, nm in ipairs(names) do queue[#queue + 1] = nm end
	queueZone = zoneWide and true or nil
	startedAt = ns.Now()
	if not running then running = true Pump() end
end

local function CanGather()
	if InInstance() then ns.Print(L.PARTY_NOT_HERE) return false end
	local _, lead = Room()
	if not lead then ns.Print(L.PARTY_NOT_LEADER) return false end
	if not MapID() then ns.Print(L.PARTY_NO_ZONE) return false end
	return true
end

-- One party: up to the free places, best first.
function Party.Gather()
	if not (ns.IsMember() and CanGather()) then return end
	local mapID = MapID()
	local n = Room()
	local slots = Max() - n - Pending() - #queue
	local list = KeepHealer(Party.Candidates(mapID), slots)
	if slots < 1 then return Tell(L.PARTY_FULL) end
	if #list == 0 then return Nobody(mapID) end
	local names = {}
	for i = 1, math.min(slots, #list) do names[#names + 1] = list[i].name end
	Tell(L.PARTY_INVITING_WHO:format(Names(names), ZoneName(mapID)))
	Start(names, false)
end

-- The whole zone: rank 1 (Dreadguards in the house, Dark Rangers elsewhere), the Dark Lady and her
-- Deathstalkers. Past a party of
-- five, the leader is asked (a click) to turn the group into a raid, then it goes on.
function Party.CanZone()
	if not ns.IsMember() then return false end
	if ns.Roster and ns.Roster.MyRank and (ns.Roster.MyRank() or 99) <= ns.CAPTAIN_RANK then return true end
	local K = ns.King
	return K ~= nil and not K.missing and ((K.IsKing and K.IsKing()) or (K.IsHand and K.IsHand())) and true or false
end

function Party.GatherZone()
	if not Party.CanZone() then return ns.Print(L.PARTY_ZONE_ONLY) end
	if not CanGather() then return end
	local mapID = MapID()
	local list = Party.Candidates(mapID)
	if #list == 0 then return Nobody(mapID) end
	local names = {}
	for i = 1, math.min(#list, Party.MAX_RAID - 1) do names[i] = list[i].name end
	Tell(L.PARTY_INVITING_WHO:format(Names(names), ZoneName(mapID)))
	Start(names, true)
end

StaticPopupDialogs["SYLVANISTAS_PARTY_RAID"] = {
	text = L.PARTY_RAID_CONFIRM,
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		ns.SafeCall("party raid", function()
			if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() elseif ConvertToRaid then ConvertToRaid() end
			ns.After(1.5, "party resume", function() if #queue > 0 and not running then running = true Pump() end end)
		end)
	end,
	OnCancel = function() queue = {} running = false end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Being invited: auto-join (only with the switch on, only for an announced invite)
---------------------------------------------------------------------------

ns.Comm.Handle("PI", function(dist, sender, text)
	if dist ~= "WHISPER" or not Guildmate(sender) then return end
	notices[sender] = ns.Now()
end)

local function HopBusy()
	local s = ns.Hop and not ns.Hop.missing and ns.Hop.State and ns.Hop.State()
	return type(s) == "table" and (s.phase == "requested" or s.phase == "accepted")
end

function Party.OnInvite(name)
	if not Party.Auto() or HopBusy() or ns.GamepadUI() then return end
	if InInstance() or InCombat() or Busy() then return end
	local from = ns.FullName(ns.Normal(name))
	local at = notices[from]
	if not at or ns.Now() - at > Party.NOTICE_FOR or not Guildmate(from) then return end
	notices[from] = nil
	local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
	if dialog then dialog.inviteAccepted = 1 end
	if AcceptGroup then AcceptGroup() end
	if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
	ns.Print(L.PARTY_JOINED:format(ns.DisplayName(from) or "?"))
end

---------------------------------------------------------------------------
-- The Party Scream: "forming a party here", answered with one click
---------------------------------------------------------------------------

function Party.Scream(note)
	if not (ns.IsMember() and CanGather()) then return end
	local now = ns.Now()
	if now - lastScream < Party.SCREAM_GAP then
		return Tell(L.PARTY_SCREAM_WAIT:format(math.ceil(Party.SCREAM_GAP - (now - lastScream))))
	end
	local n = Room()
	if n >= Max() then return Tell(L.PARTY_FULL) end
	note = tostring(note or ""):gsub("[~|\n]", ""):sub(1, 60)
	local mapID = MapID()
	local id = math.random(100000, 999999)
	lastScream, myScream = now, { id = id, t = now, mapID = mapID }
	ns.Comm.Send("GUILD", ("PS~%d~%d~%s"):format(id, mapID, note), nil, nil, true)
	local free = #Party.Candidates(mapID)
	if free > 0 then Tell(L.PARTY_SCREAM_SENT_N:format(ZoneName(mapID), free))
	else
		local here = GuildHere()
		Tell(here > 0 and L.PARTY_SCREAM_SENT_OFF:format(ZoneName(mapID), here) or L.PARTY_SCREAM_SENT_NONE:format(ZoneName(mapID)))
	end
	Changed()
end

ns.Comm.Handle("PS", function(dist, sender, text)
	if dist ~= "GUILD" or not Guildmate(sender) or not Party.On() then return end
	local id, mapID, note = text:match("^PS~(%d+)~(%d+)~(.*)$")
	id, mapID = tonumber(id), tonumber(mapID)
	if not id or answered[id] then return end
	answered[id] = true
	if mapID ~= MapID() or not Party.Free() then return end
	local who = ns.DisplayName(sender) or "?"
	note = (note or ""):gsub("[|\n]", ""):sub(1, 60)
	local where = ZoneName(mapID)
	ns.Print(L.PARTY_SCREAM_LINE:format(who, where) .. (note ~= "" and (' "' .. note .. '"') or ""))
	if ns.PlayAlert then ns.PlayAlert("soft", "muster") end
	-- (1.3.0: the small silver window with a Join button, not the game's popup: the user's call.)
	local data = { sender = sender, id = id }
	if ns.Toast then
		ns.Toast(L.PARTY_SCREAM_LINE:format(who, where) .. (note ~= "" and ('\n"' .. note .. '"') or ""),
			(not GetFileIDFromPath or GetFileIDFromPath(ICON)) and ICON or nil,
			{ seconds = Party.SCREAM_TOAST_FOR, button = { label = L.PARTY_JOIN, onClick = function() Party.Join(data) end } })
	else
		ns.ShowDialog("SYLVANISTAS_PARTY_SCREAM", who, where, data)
	end
end)

function Party.Join(data)
	if type(data) == "table" and data.sender and data.id and Party.Free() then
		ns.Comm.Whisper(data.sender, "PQ~" .. data.id, nil, true)
		ns.Print(L.PARTY_JOIN_ASKED:format(ns.DisplayName(data.sender) or "?"))
	end
end

StaticPopupDialogs["SYLVANISTAS_PARTY_SCREAM"] = {
	text = L.PARTY_SCREAM_ASK,
	button1 = L.PARTY_JOIN,
	button2 = NO or "No",
	OnAccept = function(self, data) Party.Join(data or (self and self.data)) end,
	timeout = Party.SCREAM_FOR,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

ns.Comm.Handle("PQ", function(dist, sender, text)
	if dist ~= "WHISPER" or not Guildmate(sender) then return end
	local id = tonumber(text:match("^PQ~(%d+)$"))
	if not (id and myScream and myScream.id == id and ns.Now() - myScream.t <= Party.SCREAM_FOR) then return end
	local n, lead = Room()
	if not lead then return end
	local who = ns.DisplayName(sender) or "?"
	if n + Pending() + #queue >= Max() then return Tell(L.PARTY_ASKED_FULL:format(who)) end
	Tell(L.PARTY_ASKED:format(who))
	Start({ sender }, false)
end)

---------------------------------------------------------------------------
-- Commands, the Board's section, the privacy page
---------------------------------------------------------------------------

function Party.Slash(rest)
	local word, more = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "on" then Party.Set(true)
	elseif word == "off" then Party.Set(false)
	elseif word == "gather" or word == "go" then Party.Gather()
	elseif word == "zone" then Party.GatherZone()
	elseif word == "scream" then Party.Scream(more)
	else
		ns.Print(L.PARTY_STATUS:format(Party.On() and L.PARTY_WORD_ON or L.PARTY_WORD_OFF, Party.Auto() and L.PARTY_WORD_ON or L.PARTY_WORD_OFF))
		ns.Print(L.HELP_PARTY)
	end
end

function Party.SlashAuto(rest)
	local word = tostring(rest or ""):match("^%s*(%S*)"):lower()
	if word == "on" then
		if not Party.On() then Party.Set(true, true) end
		Party.SetAuto(true)
	elseif word == "off" then Party.SetAuto(false)
	else ns.Print(L.PARTY_STATUS:format(Party.On() and L.PARTY_WORD_ON or L.PARTY_WORD_OFF, Party.Auto() and L.PARTY_WORD_ON or L.PARTY_WORD_OFF)) end
end

-- The Board's section (Board.Lines): the switches, then the leader's buttons.
-- 1.3.0: the Screams tab's buttons (UI.lua): their words show what is going on.
local function Clock(sec)
	sec = math.max(0, math.ceil(sec))
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

function Party.ScreamLabel()
	local left = Party.SCREAM_GAP - (ns.Now() - lastScream)
	if left > 0 then return L.PARTY_SCREAM_BTN_WAIT:format(Clock(left)) end
	return L.PARTY_SCREAM_BTN
end

function Party.GatherLabel(zoneWide)
	if running and (queueZone and true or false) == zoneWide then
		return L.PARTY_BTN_INVITING:format(#queue + Pending())
	end
	return zoneWide and L.PARTY_ZONE_BTN or L.PARTY_GATHER_BTN
end

function Party.Tooltip(tt, which)
	local mapID = MapID()
	local free = mapID and #Party.Candidates(mapID) or 0
	local title = which == "scream" and L.PARTY_SCREAM or which == "zone" and L.PARTY_ZONE or L.PARTY_GATHER
	local tip = which == "scream" and L.PARTY_SCREAM_TIP or which == "zone" and L.PARTY_ZONE_TIP or L.PARTY_GATHER_TIP
	tt:AddLine(title, 1, 0.82, 0)
	tt:AddLine(tip, 1, 1, 1, true)
	tt:AddLine(" ")
	tt:AddLine(L.PARTY_FREE_TIP:format(free, mapID and ZoneName(mapID) or "?", GuildHere()), 0.6, 0.8, 1, true)
	if not Party.On() then tt:AddLine(L.PARTY_OFF_TIP, 1, 0.5, 0.3, true) end
end

if ns.Consent and not ns.Consent.missing and ns.Consent.Register then
	ns.Consent.Register({ key = "party", label = "PARTY_CONSENT", text = "PARTY_CONSENT_TEXT",
		shown = function() return ns.IsMember() end,
		get = function() return Party.On() end,
		set = function(on) Party.Set(on, true) end })
	ns.Consent.Register({ key = "partyauto", label = "PARTY_AUTO_CONSENT", text = "PARTY_AUTO_CONSENT_TEXT",
		shown = function() return ns.IsMember() and Party.On() end,
		get = function() return Party.Auto() end,
		set = function(on) Party.SetAuto(on, true) end })
end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------

function Party.Tick()
	if not ns.IsMember() then return end
	Party.Announce(false)
	local now = ns.Now()
	for name, t in pairs(notices) do if now - t > Party.NOTICE_FOR then notices[name] = nil end end
	for name, a in pairs(avail) do if now - a.t > Party.FRESH then avail[name] = nil end end
	for name, t in pairs(watch) do
		if now - t > Party.PENDING_FOR then
			watch[name] = nil
			ns.Print(L.PARTY_NO_ANSWER:format(ns.DisplayName(name) or "?"))
		end
	end
end

-- 1.3.0: who joined, who said no, for the one who invited (only those our addon invited).
function Party.CheckJoined()
	for name in pairs(watch) do
		if InMyGroup(name) then
			watch[name] = nil
			Tell(L.PARTY_JOINED_YOU:format(ns.DisplayName(name) or "?"))
		end
	end
	Changed()
end

local function Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
end
local NO_PATTERNS -- { pattern, text } for the game's answers to an invite
function Party.SystemMessage(text)
	if type(text) ~= "string" or not next(watch) then return end
	NO_PATTERNS = NO_PATTERNS or {
		{ Pattern(ERR_DECLINE_GROUP_S or "%s declines your group invitation."), L.PARTY_DECLINED },
		{ Pattern(ERR_ALREADY_IN_GROUP_S or "%s is already in a group."), L.PARTY_ALREADY_GROUPED },
	}
	for _, p in ipairs(NO_PATTERNS) do
		local who = p[1] and text:match(p[1])
		if who then
			who = ns.Normal and ns.Normal(who) or who
			for name in pairs(watch) do
				if ns.ShortName(name) == ns.ShortName(who) then
					watch[name], pending[name] = nil, nil
					Tell(p[2]:format(ns.DisplayName(name) or who))
					Changed()
					return
				end
			end
		end
	end
end

-- Once a second while a button has a state to show (the Scream's wait, a gather under way).
local function Relabel()
	if running or ns.Now() - lastScream <= Party.SCREAM_GAP + 1 then ns.Fire("PARTY_CHANGED") end
end

ns.RegisterEvent("PARTY_INVITE_REQUEST", function(name) Party.OnInvite(name) end)
ns.On("LOGIN", function()
	ns.Every(15, "party", Party.Tick)
	ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
		ns.SafeCall("party announce", Party.Announce, false)
		ns.SafeCall("party joined", Party.CheckJoined)
	end)
	ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text) ns.SafeCall("party answers", Party.SystemMessage, text) end)
	ns.Every(1, "party buttons", Relabel)
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() ns.After(3, "party zone", function() Party.Announce(false) end) end)
end)
