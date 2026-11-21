local ADDON, ns = ...
local L = ns.L

-- Nearby (1.3.6, the user's call): a tab that lists everyone the game's /who finds, guild or not,
-- with class and level, so a leader (the Underground's alts above all) can pull a group together
-- out in the world. Sylvanistas players (the house first: Sylvanistas, then the Underground) get
-- a section of their own on top, everyone else below.
--
-- What it searches, picked on the tab (the first button cycles): the zone the player stands in,
-- the levels around his own (SPREAD either way, the whole realm), or both at once. One /who per
-- click of Search, through Who.lua like every search of ours: never from a timer, COOLDOWN apart
-- from any other, Blizzard's who list kept from opening (Who.Search, `open`).
--
-- Past the cap: the server lists at most 50 per answer. A capped answer makes the next clicks
-- search smaller level ranges of the same search (the zone: ranges cut where its players' levels
-- split evenly, Who.Brackets; the levels: one level each) and add who they find, as the census
-- Refresh does. A new mode, a new zone, a new level of his own, Clear, or ROUND_TTL starts over.
--
-- A row: the name in its class color, the guild, the level and the zone. A click opens the person
-- card (Whisper, Invite, Who), as on every other tab; the row's own Whisper and Invite words act at
-- once, Invite asking once more first (a stranger misclicked is not invited); a right-click opens
-- a small menu of ours. Not the game's own player menu: opened from addon code, its Whisper writes
-- the chat box's globals and taints what the player types next (PlayerMenu.lua, ChatWindow.lua).
-- Nothing is sent to anyone by searching, and nothing found is saved: the list lives for the session.

local Finder = {}
ns.Finder = Finder

Finder.MODES = { "zone", "level", "both" }
Finder.SPREAD = 3          -- the level search: this many levels either side of the player's
Finder.CONFIRM_FOR = 5     -- an Invite word waits this long for its second click
Finder.ROUND_TTL = 15 * 60 -- a round older than this starts over (like Who.ROUND_TTL)

local Grey = function(s) return "|cff9d9d9d" .. s .. "|r" end
local Gold = function(s) return "|cffffd200" .. s .. "|r" end
local Blood = function(s) return "|cffc41f3b" .. s .. "|r" end -- the Underground's (Crafters board)

local mode = "zone"
local round   -- { mode, zone, lo, hi, base, list, byName, steps, step, done, capped, rangeCapped, t, answers, shown, total }
local confirm = {} -- [name .. "|" .. what] = GetTime() of the first Invite or Recruit click

local function Changed() ns.Fire("FINDER_CHANGED") end

local function MyLevel() return tonumber(UnitLevel and UnitLevel("player")) or 1 end
local function MyZone()
	local z = GetRealZoneText and GetRealZoneText() or ""
	if z == "" and GetZoneText then z = GetZoneText() or "" end
	return z
end

function Finder.Mode() return mode end
function Finder.Round() return round end -- (tests)

function Finder.ModeLabel()
	return mode == "zone" and L.FINDER_MODE_ZONE or mode == "level" and L.FINDER_MODE_LEVEL or L.FINDER_MODE_BOTH
end

function Finder.NextMode()
	for i, m in ipairs(Finder.MODES) do
		if m == mode then
			mode = Finder.MODES[i % #Finder.MODES + 1]
			break
		end
	end
	Changed()
end

-- The search the next click sends goes on with the round shown (same mode, zone and level, a level
-- range left to search)?
local function Continues(zone, lo, hi)
	local r = round
	if not r or r.done or r.step == 0 then return false end
	if r.mode ~= mode or GetTime() - r.t > Finder.ROUND_TTL then return false end
	if mode ~= "level" and r.zone ~= zone then return false end
	if mode ~= "zone" and (r.lo ~= lo or r.hi ~= hi) then return false end
	return true
end

local function Range()
	local me, top = MyLevel(), ns.Who.MaxLevel()
	return math.max(1, me - Finder.SPREAD), math.min(math.max(top, me), me + Finder.SPREAD)
end

function Finder.SearchLabel()
	local lo, hi = Range()
	if Continues(MyZone(), lo, hi) then return L.FINDER_SEARCH_MORE end
	return L.FINDER_SEARCH_BTN
end

-- A zone's name inside z-"...": nothing that would end the quote.
local function Quoted(s) return (tostring(s or ""):gsub('"', "")) end

-- Round `r`'s search for level range `b` (nil: its first, broad one).
local function Query(r, b)
	if not b then return r.base end
	local range = b[1] .. "-" .. b[2]
	if r.mode == "zone" then return r.base .. " " .. range end
	-- (The level searches: the range replaces the base's own.)
	return (r.mode == "both" and ('z-"%s" '):format(Quoted(r.zone)) or "") .. range
end

local function Merge(r, rows)
	for _, p in ipairs(rows) do
		local known = r.byName[p.name]
		if known then
			for k, v in pairs(p) do known[k] = v end -- a newer level or zone
		else
			r.byName[p.name] = p
			r.list[#r.list + 1] = p
		end
	end
end

-- The answer to step `step` of round `r`.
local function OnAnswer(r, step, rows, shown, total, first)
	if r ~= round then return end -- Clear, or a new round, since it was sent
	Merge(r, rows)
	if first then
		r.answers = r.answers + 1
		local capped = shown >= ns.Who.MAX or total > shown
		if step == 0 then
			r.shown, r.total, r.capped = shown, total, capped
			if capped then
				if r.mode == "zone" then
					local levels = {}
					for _, p in ipairs(rows) do levels[#levels + 1] = p.level end
					r.steps = ns.Who.Brackets(levels, ns.Who.MaxLevel(), ns.Who.BRACKETS)
				else
					r.steps = {}
					for l = r.lo, r.hi do r.steps[#r.steps + 1] = { l, l } end
				end
				r.step = 1
			else
				r.done = true
			end
		else
			r.rangeCapped = r.rangeCapped or capped
			r.step = step + 1
			if r.step > #r.steps then r.done = true end
		end
	end
	Changed()
end

-- From the Search button (a click: /who needs one). Returns true if a search was sent.
function Finder.Search()
	if not ns.Who then return false end
	local zone, lo, hi = MyZone(), Range()
	if mode ~= "level" and zone == "" then
		ns.Print(L.FINDER_NO_ZONE)
		return false
	end
	local r
	if Continues(zone, lo, hi) then
		r = round
	else
		local base
		if mode == "zone" then base = ('z-"%s"'):format(Quoted(zone))
		elseif mode == "level" then base = lo .. "-" .. hi
		else base = ('z-"%s" %d-%d'):format(Quoted(zone), lo, hi) end
		r = { mode = mode, zone = zone, lo = lo, hi = hi, base = base, list = {}, byName = {}, step = 0,
			done = false, answers = 0, shown = 0, total = 0 }
	end
	local step = r.step
	local query = Query(r, step > 0 and r.steps[step] or nil)
	local sent = ns.Who.Search(false, nil, nil, { query = query, onAnswer = function(...) OnAnswer(r, step, ...) end })
	if sent then
		-- A new round shows from its first answer on: the old list stays until then.
		if r ~= round then
			round = r
			wipe(confirm)
		end
		if step == 0 then r.t = GetTime() end
		Changed()
	end
	return sent
end

function Finder.Clear()
	round = nil
	wipe(confirm)
	Changed()
end

---------------------------------------------------------------------------
-- What a row does
---------------------------------------------------------------------------

local function Whisper(name)
	if ns.UI and ns.UI.WhisperWindow then ns.UI.WhisperWindow(ns.TellName(name)) end
end

local function Invite(name)
	if ns.DemoBlocked and ns.DemoBlocked() then return end -- (/syl demo sends nothing)
	name = ns.TellName(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
	ns.Print(L.FINDER_INVITED:format(ns.DisplayName(name) or name))
end

-- 1.3.6 (the user's call): a guild invite to our own guild, through Recruit.Accept (the officer's
-- yes to a join request: it checks the game's permission, and warns first about someone the
-- moderators took off the network). Shown only to who may invite, for players in no guild.
local function CanRecruit(p)
	local R = ns.Recruit
	return p.guild == nil and type(R) == "table" and type(R.CanInvite) == "function" and R.CanInvite() == true
		and ns.GuildInfo("player") ~= nil
end

local function Recruit(name)
	local own = ns.GuildInfo("player")
	if not own or type(ns.Recruit) ~= "table" or type(ns.Recruit.Accept) ~= "function" then return end
	ns.Recruit.Accept({ name = name, guild = own })
end

local function Asking(name, what)
	local t = confirm[name .. "|" .. what]
	return t ~= nil and GetTime() - t <= Finder.CONFIRM_FOR
end

-- A row's Invite or Recruit word: the first click asks, a second within CONFIRM_FOR acts.
local function Confirmed(name, what, act)
	local key = name .. "|" .. what
	if Asking(name, what) then
		confirm[key] = nil
		act(name)
	else
		confirm[key] = GetTime()
		-- (Back to "Invite" once the time is up.)
		ns.After(Finder.CONFIRM_FOR + 0.1, "finder confirm", Changed)
	end
	Changed()
end

local function AddFriend(name)
	name = ns.TellName(name)
	if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(name) elseif AddFriend then AddFriend(name) end
end

local function Person(p)
	return { name = p.name, class = p.class, level = p.level, guild = p.guild, online = true,
		zone = p.zone and ns.Zones and ns.Zones.KeyForName and ns.Zones.KeyForName(p.zone) or nil }
end

-- Our own small menu (Blizzard_Menu's MenuUtil), the person card where the client has none.
local function Menu(owner, p)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		if ns.UI and ns.UI.ShowPerson then ns.UI.ShowPerson(Person(p)) end
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(ns.Codec.Plain(ns.DisplayName(p.name) or p.name))
		root:CreateButton(L.WHISPER, function() ns.SafeCall("finder whisper", Whisper, p.name) end)
		root:CreateButton(L.INVITE, function() ns.SafeCall("finder invite", Invite, p.name) end)
		if CanRecruit(p) then
			root:CreateButton(L.FINDER_RECRUIT_MENU:format(ns.Codec.Plain(ns.GuildInfo("player") or "?")),
				function() ns.SafeCall("finder recruit", Recruit, p.name) end)
		end
		root:CreateButton(L.FINDER_ADD_FRIEND, function() ns.SafeCall("finder friend", AddFriend, p.name) end)
		root:CreateButton(L.FINDER_SHOW_CARD, function() if ns.UI and ns.UI.ShowPerson then ns.UI.ShowPerson(Person(p)) end end)
	end)
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- 0: Sylvanistas, 1: the Underground, 2: another Sylvanistas guild, nil: not Sylvanistas.
local function House(guild)
	if not guild then return nil end
	if ns.IsKingGuild and ns.IsKingGuild(guild) then return 0 end
	if ns.IsAltGuild and ns.IsAltGuild(guild) then return 1 end
	if ns.IsFederation and ns.IsFederation(guild) then return 2 end
	return nil
end

local function GuildTag(p, house)
	if not p.guild then return "" end
	local g = "<" .. ns.Codec.Plain(p.guild) .. ">"
	if house == 1 then return "  " .. Blood(g) end
	if house then return "  " .. Gold(g) end
	return "  " .. Grey(g)
end

local function Row(p, house, me)
	local name = p.name
	local asking = Asking(name, "invite")
	local alt = house ~= nil and ns.Views.AltTag and ns.Views.AltTag(name) or ""
	local right = p.level and L.LEVEL_N:format(p.level) or ""
	if round.mode == "level" and p.zone then right = right .. "  " .. Grey(ns.Codec.Plain(p.zone)) end
	local diff = p.level and (p.level - me)
	return {
		key = "finder:" .. name,
		text = ns.Views.ClassColored(ns.DisplayName(name) or name, p.class) .. alt .. GuildTag(p, house),
		right = right,
		onClick = function() if ns.UI and ns.UI.ShowPerson then ns.UI.ShowPerson(Person(p)) end end,
		onRightClick = function(owner) Menu(owner, p) end,
		tooltip = function(tt)
			tt:AddLine(ns.Codec.Plain(ns.DisplayName(name) or name), 1, 0.82, 0)
			if p.guild then tt:AddLine("<" .. ns.Codec.Plain(p.guild) .. ">", 1, 1, 1) end
			local cls = p.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class or ""
			tt:AddLine(((p.level and (L.LEVEL_N:format(p.level) .. " ")) or "") .. cls, 1, 1, 1)
			if diff and diff ~= 0 then tt:AddLine(L.FINDER_DIFF:format(diff > 0 and ("+" .. diff) or tostring(diff)), 0.6, 0.6, 0.6) end
			if p.zone then tt:AddLine(ns.Codec.Plain(p.zone), 0.6, 0.6, 0.6) end
			tt:AddLine(" ")
			tt:AddLine(L.FINDER_ROW_HINT, 0.25, 1, 0.25, true)
		end,
		actions = {
			{ text = L.WHISPER, onClick = function() Whisper(name) end },
			{ text = asking and L.FINDER_INVITE_SURE or L.INVITE, onClick = function() Confirmed(name, "invite", Invite) end,
				color = asking and { 0.25, 1, 0.25 } or nil,
				tooltip = asking and L.FINDER_INVITE_SURE_TIP or L.FINDER_INVITE_TIP },
		},
	}
end

-- The row's Recruit word, after Invite, for who may invite and players in no guild.
local function AddRecruit(line, p)
	if not CanRecruit(p) then return line end
	local asking = Asking(p.name, "recruit")
	local own = ns.Codec.Plain(ns.GuildInfo("player") or "?")
	line.actions[#line.actions + 1] = {
		text = asking and L.FINDER_INVITE_SURE or L.FINDER_RECRUIT, onClick = function() Confirmed(p.name, "recruit", Recruit) end,
		color = asking and { 0.25, 1, 0.25 } or { 0.4, 0.8, 1 },
		tooltip = asking and L.FINDER_RECRUIT_SURE_TIP:format(own) or L.FINDER_RECRUIT_TIP:format(own),
	}
	return line
end

-- Closest level to the player's first, then higher, then by name.
local function Sorted(list, me, houseFirst)
	table.sort(list, function(a, b)
		if houseFirst and a.house ~= b.house then return a.house < b.house end
		local da, db = math.abs((a.p.level or 0) - me), math.abs((b.p.level or 0) - me)
		if da ~= db then return da < db end
		if (a.p.level or 0) ~= (b.p.level or 0) then return (a.p.level or 0) > (b.p.level or 0) end
		return a.p.name < b.p.name
	end)
	return list
end

local function Status()
	local r = round
	local where = r.mode == "level" and L.FINDER_WHERE_LEVEL:format(r.lo, r.hi)
		or r.mode == "zone" and ns.Codec.Plain(r.zone)
		or L.FINDER_WHERE_BOTH:format(ns.Codec.Plain(r.zone), r.lo, r.hi)
	if r.answers == 0 then return L.FINDER_STATUS_WAIT:format(where) end
	local mins = math.floor((GetTime() - r.t) / 60)
	return L.FINDER_STATUS:format(where, #r.list, mins < 1 and L.FINDER_JUST_NOW or L.FINDER_MIN_AGO:format(mins))
end

function Finder.Build()
	local lines = {}
	if not round then
		lines[#lines + 1] = { text = Gold(Finder.ModeLabel()), header = true }
		lines[#lines + 1] = { text = Grey(L.FINDER_EMPTY), wrap = true }
		return lines, L.TAB_FINDER, L.FINDER_DETAIL
	end
	local me = MyLevel()
	local myName = ns.me
	local ours, others = {}, {}
	for _, p in ipairs(round.list) do
		if not (myName and ns.FullName(p.name) == myName) then
			local house = House(p.guild)
			local e = { p = p, house = house }
			if house then ours[#ours + 1] = e else others[#others + 1] = e end
		end
	end
	lines[#lines + 1] = { text = Status(), gapAfter = true }
	lines[#lines + 1] = { text = L.FINDER_OURS:format(#ours), header = true }
	if #ours == 0 then lines[#lines + 1] = { text = Grey(L.FINDER_NONE_OURS), indent = 1 } end
	for _, e in ipairs(Sorted(ours, me, true)) do
		local line = Row(e.p, e.house, me)
		line.indent = 1
		lines[#lines + 1] = line
	end
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { text = L.FINDER_OTHERS:format(#others), header = true }
	if #others == 0 then lines[#lines + 1] = { text = Grey(round.answers == 0 and "..." or L.FINDER_NONE), indent = 1 } end
	for _, e in ipairs(Sorted(others, me, false)) do
		local line = AddRecruit(Row(e.p, nil, me), e.p)
		line.indent = 1
		lines[#lines + 1] = line
	end
	-- How far a capped round got.
	if round.capped then
		lines[#lines].gapAfter = true
		local text
		if not round.done then
			local b = round.steps[round.step]
			text = L.FINDER_MORE:format(ns.Who.MAX, b[1] == b[2] and tostring(b[1]) or (b[1] .. "-" .. b[2]), round.step, #round.steps)
		elseif round.rangeCapped then
			text = L.FINDER_DONE_CAPPED:format(ns.Who.MAX)
		else
			text = L.FINDER_DONE
		end
		lines[#lines + 1] = { text = Grey(text), wrap = true }
	end
	return lines, L.TAB_FINDER, L.FINDER_DETAIL
end
