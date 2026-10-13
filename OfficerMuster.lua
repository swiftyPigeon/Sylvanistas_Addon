local ADDON, ns = ...
local L = ns.L
local Muster = {}
ns.OfficerMuster = Muster

-- Officer musters (1.2.21, after Olympus 1.2.1-1.2.3's OfficerMuster.lua): a quiet call to one zone
-- for 20 minutes, apart from the map's Screams: no alert, no sound, no map pin; a page of the Realm
-- tab lists the calls standing now, with how many Forsaken the census has in that zone. Who may call:
--   CHANNEL  every Sylvanistas guild: the Dark Lady (her pinned name), her Valkyr and her Dark Rangers
--            (by name; the server stamps every sender)
--   GUILD    their own guild alone: its officers (the guild master and the officer rank below), as
--            each receiver's own roster has them (the server carries GUILD between that guild's
--            members only)
-- The census's word on someone's rank is never enough: two characters can forge a report.
--   OM~1~P~<A|H>~<group>~<sequence>~<postedAt>~<guild>~<zoneID>~<title>   a call (repeated each REPEAT)
--   OM~1~E~<A|H>~<group>~<sequence>~<postedAt>                            its poster ends it
-- (The Olympus format, our own prefix: the two networks never hear each other.) Nothing here sends
-- names of who came, positions or invites.
Muster.LIFE, Muster.REPEAT, Muster.GAP = 20 * 60, 300, 60
Muster.TITLE_MAX, Muster.MAX, Muster.DATE_AHEAD = 60, 20, 60
local MAX_INT = 2147483647
local lastSent = -math.huge

local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or (GetServerTime and GetServerTime()) or ns.Now() end
local function Key(s) return ns.Fold(s) end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Int(n) return type(n) == "number" and n % 1 == 0 and n >= 1 and n <= MAX_INT end
local function Clean(s, max)
	return ns.Cut((tostring(s or ""):gsub("[~|%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")), max)
end
local function Field(s, max) return type(s) == "string" and s ~= "" and Clean(s, max) == s end
local function Faction() return ns.faction == "Horde" and "H" or (ns.faction == "Alliance" and "A" or nil) end
local function Group() return ns.group or (ns.GroupOf and ns.GroupOf(ns.realm)) end
local function Scope() local g, f = Group(), Faction(); return Field(g, 72) and f and (f .. "~" .. g) or nil end
local function Full(s)
	if not Field(s, 72) then return nil end
	local full = ns.FullName(s)
	local realm = ns.RealmOf(full)
	if not realm or ns.GroupOf(realm) ~= Group() then return nil end
	return full
end
-- A zone's map (mapType 3), not a dungeon, a continent or a city's sub-map.
local function Zone(id)
	if not Int(id) or id > 999999 or not C_Map or not C_Map.GetMapInfo then return false end
	local info = C_Map.GetMapInfo(id)
	return type(info) == "table" and info.mapType == 3
end
local function ZoneName(id) return ns.Zones.NameForKey("m" .. id) end
local function Dist(row) return row.dist or "CHANNEL" end

local function Authorized(by, guild, dist)
	if not Full(by) or not Field(guild, 72) or not ns.IsFederation(guild) then return false end
	local M = ns.Moderation
	if M and M.Hides and M.Hides(by, guild) then return false end
	if dist == "GUILD" then
		local rank = guild == GetGuildInfo("player") and ns.Roster.RankOf(by)
		return type(rank) == "number" and rank <= ns.CAPTAIN_RANK
	end
	if ns.IsKingCharacter(by) then return true end
	local K = ns.King
	return K ~= nil and ((K.IsStewardName and K.IsStewardName(by)) or (K.IsHandName and K.IsHandName(by))) and true or false
end
Muster.Authorized = Authorized -- (tests)

-- Whether this player may call, their guild, and where it goes: "CHANNEL" (every guild) or "GUILD".
function Muster.CanPost()
	if not ns.IsMember() or not Scope() then return false end
	local guild = GetGuildInfo("player")
	if Authorized(ns.me, guild, "CHANNEL") then return true, guild, "CHANNEL" end
	if Authorized(ns.me, guild, "GUILD") then return true, guild, "GUILD" end
	return false, guild
end

-- Per realm group and faction, in memory and the saved variables: the calls standing, and each
-- poster's last sequence (a call older than it is never taken again).
local function Store()
	local scope = Scope()
	if not scope or type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.officerMuster
	if type(s) ~= "table" or s.v ~= 1 or s.scope ~= scope then
		s = { v = 1, scope = scope, active = {}, floors = {}, seq = 0 }
		ns.rdb.officerMuster = s
	end
	if type(s.active) ~= "table" then s.active = {} end
	if type(s.floors) ~= "table" then s.floors = {} end
	if not Int(s.seq) then s.seq = 0 end
	return s
end
local function Valid(row)
	return type(row) == "table" and Full(row.by) == row.by and row.scope == Scope() and Int(row.seq) and Int(row.at)
		and Field(row.guild, 72) and Field(row.title, Muster.TITLE_MAX) and Zone(row.zone)
		and (row.dist == nil or row.dist == "CHANNEL" or row.dist == "GUILD")
end
local function Changed()
	ns.Fire("OFFICER_MUSTER_CHANGED")
	if ns.Views and ns.Views.PageShown and ns.Views.PageShown() == "officermuster" and ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end
-- How many Forsaken the census has in that zone now (reporters who share their zone only).
local function Headcount(row)
	local s = ns.Data and ns.Data.Summary and ns.Data.Summary()
	return s and s.zones and s.zones["m" .. row.zone] or 0
end
local function EndCall(s, key, row, reason)
	local floor = s.floors[key]
	if not floor or floor.seq <= row.seq then s.floors[key] = { seq = row.seq, at = row.at, ended = true } end
	s.active[key] = nil
	if reason then ns.Log("officer muster by %s in %s ended: %s", tostring(row.by), ZoneName(row.zone), reason) end
	Changed()
	return true
end
local function Prune(s)
	local now = Clock()
	for key, row in pairs(s.active) do
		if not Valid(row) or key ~= Key(row.by) or row.at > now + Muster.DATE_AHEAD then s.active[key] = nil
		elseif not Authorized(row.by, row.guild, Dist(row)) then EndCall(s, key, row, "no longer allowed")
		elseif now >= row.at + Muster.LIFE then EndCall(s, key, row, "expired") end
	end
	for key, f in pairs(s.floors) do
		if type(f) ~= "table" or not Int(f.seq) or not Int(f.at) or now > f.at + Muster.LIFE + Muster.DATE_AHEAD then s.floors[key] = nil end
	end
end
local function Encode(row, ending)
	local prefix = ("OM~1~%s~%s~%s~%d~%d"):format(ending and "E" or "P", Faction(), Group(), row.seq, row.at)
	return ending and prefix or (prefix .. ("~%s~%d~%s"):format(row.guild, row.zone, row.title))
end
Muster.Encode = Encode -- (tests)
local function Send(row, ending)
	local msg = Encode(row, ending)
	if #msg > 255 then return false end
	-- Logged (as a decree): the server keeps its words, so abuse can be reported.
	ns.Comm.Send(Dist(row), msg, "officermuster", nil, true)
	return true
end

function Muster.Handle(dist, sender, text)
	if (dist ~= "CHANNEL" and dist ~= "GUILD") or type(text) ~= "string" or #text > 255 then return false, "shape" end
	local by = Full(sender)
	if not by then return false, "realm" end
	local op, faction, group, seq, at, rest = text:match("^OM~1~([PE])~([AH])~([^~]+)~(%d+)~(%d+)(.*)$")
	seq, at = tonumber(seq), tonumber(at)
	if not op or faction ~= Faction() or group ~= Group() then return false, "scope" end
	if not Int(seq) or not Int(at) then return false, "shape" end
	local now = Clock()
	if at > now + Muster.DATE_AHEAD or now >= at + Muster.LIFE then return false, "time" end
	local row
	if op == "P" then
		local guild, zone, title = rest:match("^~([^~]+)~(%d+)~([^~]+)$")
		row = { by = by, scope = Scope(), seq = seq, at = at, guild = guild, zone = tonumber(zone), title = title, dist = dist }
		if not Valid(row) then return false, "shape" end
		if not Authorized(by, guild, dist) then return false, "role" end
	elseif rest ~= "" then return false, "shape" end
	local s, key = Store(), Key(by)
	if not s then return false, "store" end
	Prune(s)
	local old, floor = s.active[key], s.floors[key]
	if op == "E" then
		if floor and floor.seq >= seq and floor.ended then return true, "repeat" end
		if not old or old.seq ~= seq or old.at ~= at or Dist(old) ~= dist then return false, "unknown" end
		return EndCall(s, key, old, "withdrawn")
	end
	if floor and seq <= floor.seq then
		if old and old.seq == seq and old.at == at and old.title == row.title and old.zone == row.zone then return true, "repeat" end
		return false, "older"
	end
	if floor and at - floor.at < Muster.GAP then return false, "rate" end
	if not old and Count(s.active) >= Muster.MAX then return false, "full" end
	if old then EndCall(s, key, old, "replaced") end
	s.active[key], s.floors[key] = row, { seq = seq, at = at }
	Changed()
	return true
end

function Muster.Post(title, zone)
	local can, guild, dist = Muster.CanPost()
	if not can then return false, "role" end
	title = Clean(title, Muster.TITLE_MAX)
	if not Field(title, Muster.TITLE_MAX) then return false, "title" end
	if not Zone(zone) then return false, "zone" end
	local s, key, at = Store(), Key(ns.me), math.floor(Clock())
	if not s then return false, "store" end
	Prune(s)
	local old, floor = s.active[key], s.floors[key]
	if floor and at - floor.at < Muster.GAP then return false, "rate" end
	local seq = math.max(at, s.seq + 1, floor and floor.seq + 1 or 1)
	local row = { by = ns.me, scope = Scope(), seq = seq, at = at, guild = guild, zone = zone, title = title, dist = dist }
	if not Send(row) then return false, "queue" end
	if old then EndCall(s, key, old, "replaced") end
	s.seq, s.active[key], s.floors[key], lastSent = seq, row, { seq = seq, at = at }, ns.Now()
	ns.Print(L.OFFICER_MUSTER_POSTED:format(ZoneName(zone), dist == "GUILD" and L.OFFICER_MUSTER_TO_GUILD:format(guild) or L.OFFICER_MUSTER_TO_ALL))
	Changed()
	return true
end

function Muster.Withdraw()
	local s, key = Store(), ns.me and Key(ns.me)
	if s then Prune(s) end
	local row = s and key and s.active[key]
	if not row or not Valid(row) then return false, "absent" end
	Send(row, true)
	return EndCall(s, key, row, "withdrawn")
end

function Muster.List()
	local s, out = Store(), {}
	if not s then return out end
	Prune(s)
	for _, row in pairs(s.active) do out[#out + 1] = row end
	table.sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end; return a.by < b.by end)
	return out
end

-- Every 30 s: calls run out, and our own is said again each REPEAT for whoever logged in since.
function Muster.Tick()
	local s = Store()
	if not s then return end
	Prune(s)
	local own = ns.me and s.active[Key(ns.me)]
	if own and ns.Now() - lastSent >= Muster.REPEAT and Muster.CanPost() and Send(own) then lastSent = ns.Now() end
	Changed()
end

local function Ask()
	local zone = ns.Layers and ns.Layers.CurrentMap and ns.Layers.CurrentMap()
	if not Zone(zone) then return ns.Print(L.OFFICER_MUSTER_NO_ZONE) end
	ns.ShowDialog("SYLVANISTAS_OFFICER_MUSTER", ZoneName(zone), nil, { zone = zone })
end
StaticPopupDialogs["SYLVANISTAS_OFFICER_MUSTER"] = {
	text = L.OFFICER_MUSTER_ASK,
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	maxLetters = Muster.TITLE_MAX,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("") eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		local ok, why = Muster.Post(eb and eb:GetText() or "", data and data.zone)
		if not ok then ns.Print(L.OFFICER_MUSTER_ERROR:format(L["OFFICER_MUSTER_WHY_" .. tostring(why):upper()] or tostring(why))) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local b = parent and (parent.button1 or (parent.GetButton1 and parent:GetButton1()))
		if b and b.Click then b:Click() end
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- The Realm tab's link (only once a call stands, or for who may call) and its page.
function Muster.Link()
	if not ns.IsMember() then return nil end
	local n = #Muster.List()
	if n == 0 and not Muster.CanPost() then return nil end
	return { text = "|cffffd200> " .. L.OFFICER_MUSTER_TITLE .. (n > 0 and (" (" .. n .. ")") or "") .. "|r",
		onClick = function() ns.Views.ShowPage("officermuster") end,
		tooltip = function(tt)
			tt:AddLine(L.OFFICER_MUSTER_TITLE, 1, 0.82, 0)
			tt:AddLine(L.OFFICER_MUSTER_HINT, 1, 1, 1, true)
		end }
end
function Muster.Lines(q)
	if not ns.IsMember() then return {} end
	local V = ns.Views
	local lines = { { text = V.Gold(L.OFFICER_MUSTER_BACK), onClick = function() ns.Views.ShowPage(nil) end, gapAfter = true },
		{ header = true, text = L.OFFICER_MUSTER_TITLE } }
	V.GreyRows(lines, L.OFFICER_MUSTER_HINT)
	lines[#lines].gapAfter = true
	local can, guild, dist = Muster.CanPost()
	if not q and can then
		local zone = ns.Layers and ns.Layers.CurrentMap and ns.Layers.CurrentMap()
		lines[#lines + 1] = { text = V.Gold(L.OFFICER_MUSTER_POST:format(Zone(zone) and ZoneName(zone) or "?")),
			onClick = Ask,
			tooltip = function(tt)
				tt:AddLine(L.OFFICER_MUSTER_TITLE, 1, 0.82, 0)
				tt:AddLine(dist == "GUILD" and L.OFFICER_MUSTER_GUILD_ONLY:format(guild) or L.OFFICER_MUSTER_ALL_TIP, 1, 1, 1, true)
			end, gapAfter = true }
	end
	local shown = 0
	for _, row in ipairs(Muster.List()) do
		local title = row.title
		local F = ns.Filter
		if F and F.Hides and F.Hides(title) then title = L.FILTER_WORDS_HIDDEN_SHORT or "..." end
		local zone, who = ZoneName(row.zone), ns.DisplayName(row.by)
		if not q or ns.Holds(q, title, zone, who) then
			shown = shown + 1
			local left = math.max(0, math.ceil((row.at + Muster.LIFE - Clock()) / 60))
			lines[#lines + 1] = { text = V.Gold(ns.Codec.Plain(title)) .. "  -  " .. zone,
				right = V.Grey(L.OFFICER_MUSTER_OBSERVED:format(Headcount(row), left)) }
			lines[#lines + 1] = { indent = 1, text = V.Grey(Dist(row) == "GUILD" and L.OFFICER_MUSTER_BY_GUILD:format(who, row.guild)
				or L.OFFICER_MUSTER_BY:format(who)) }
			if row.by == ns.me then lines[#lines + 1] = { indent = 1, text = V.Gold(L.OFFICER_MUSTER_END), onClick = Muster.Withdraw } end
		end
	end
	if shown == 0 then lines[#lines + 1] = { text = V.Grey(q and L.SEARCH_NO_MATCH or L.OFFICER_MUSTER_EMPTY) } end
	return lines
end

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "officermuster", Link = Muster.Link, Lines = Muster.Lines, tip = "OFFICER_MUSTER" })
ns.Comm.Handle("OM", Muster.Handle)
ns.On("LOGIN", function() ns.Every(30, "officer muster", Muster.Tick) end)
