local ADDON, ns = ...
local L = ns.L

-- Grouped with the guild (1.3.7, the user's call): for promotions, officers see on the Members
-- page how many times each member grouped with at least one Sylvanistas player over the last
-- 4 weeks (Members.lua, its "Grouped" view).
--
-- Every client (its player's yes on the privacy page: on unless switched off) watches its group:
-- a session starts once a player of any Sylvanistas guild is in it with us (WeekLog's GroupMate,
-- any guild), and ends once none is left, the group is left, or we log out. A session of
-- MIN_SESSION or more is kept (KEEP) and told once to the guild:
--   Z1~<start>~<seconds>~<name>,<name>,...   the Sylvanistas players grouped with us (GUILD)
-- An officer's client asks, after its login, for what it missed (members answer once a GAP,
-- whoever asked: every officer online hears the answers, which go over GUILD too):
--   ZQ~<since>                                (GUILD, from an officer of our roster only)
-- Only officers' clients keep what they hear (MemberCounts). A session counts once for a member
-- whether they told it or someone in it named them, so members without the add-on count too;
-- what several clients told of one group merges by time. A count is what members' clients say:
-- the tooltip says how many sessions two or more clients told ("confirmed").
-- Nothing else is sent: no zone, no position, no chat.

local Grouped = {}
ns.Grouped = Grouped

Grouped.SAMPLE = 60              -- seconds between looks at the group
Grouped.MIN_SESSION = 5 * 60     -- shorter groups do not count (a quick invite)
Grouped.KEEP = 28 * 24 * 3600    -- the last 4 weeks
Grouped.MERGE_GAP = 120          -- two reports of one group: overlapping, or this close
Grouped.ANSWER_GAP = 10 * 60     -- a member answers an officer's ask at most this often
Grouped.ASK_GAP = 10 * 60        -- an officer asks at most this often
Grouped.MAX_NAMES = 20           -- names in one Z1 (a raid's: the first 20 kept)
Grouped.MAX_ANSWER = 60          -- sessions sent in one answer
Grouped.MAX_HEARD = 4000         -- reports kept by an officer's client (oldest dropped)

local current          -- the session going on: { t, last, w = { [name] = true } }
local lastAnswer, lastAsk = -math.huge, -math.huge

local function Plain(s)
	if type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return nil end
	return s
end

-- One key for a name however it came: "First Surname-Realm".
function Grouped.Key(name)
	if type(name) ~= "string" or name == "" then return nil end
	return ns.FullName(ns.Normal(name))
end

-- The player's yes (the privacy page): on unless switched off.
function Grouped.Sharing() return type(ns.db) == "table" and ns.db.shareGroups ~= false end
function Grouped.SetSharing(on)
	ns.db.shareGroups = on and true or false
	if not on then current = nil end
end

local function Mine()
	ns.db.groupLog = type(ns.db.groupLog) == "table" and ns.db.groupLog or {}
	return ns.db.groupLog
end

local function Prune(list, now)
	for i = #list, 1, -1 do
		local e = list[i]
		if type(e) ~= "table" or type(e.t) ~= "number" or now - e.t > Grouped.KEEP then table.remove(list, i) end
	end
end

---------------------------------------------------------------------------
-- Our own sessions
---------------------------------------------------------------------------

local function Encode(e)
	local names = {}
	for _, n in ipairs(e.w or {}) do
		local clean = Plain(n) and n:gsub("[~,|%c]", "")
		if clean and clean ~= "" then names[#names + 1] = clean end
	end
	local msg = ("Z1~%d~%d~"):format(e.t, e.d)
	local out = {}
	for _, n in ipairs(names) do
		if #out >= Grouped.MAX_NAMES or #msg + #table.concat(out, ",") + #n + 1 > 250 then break end
		out[#out + 1] = n
	end
	return msg .. table.concat(out, ",")
end

local function Tell(e)
	if not Grouped.Sharing() or not ns.InGuild() then return end
	if ns.DemoBlocked and ns.DemoBlocked() then return end
	ns.Comm.Send("GUILD", Encode(e), "grouped")
end

-- The session told: once it reaches MIN_SESSION (the user: it counts then, not at its end), and
-- again when it ends, with its length and everyone met. One session, one entry (`s.entry`); an
-- officer's client keeps one per reporter and start, its length growing.
local function Record(s, now)
	local d = math.floor((s.last or s.t) - s.t)
	if d < Grouped.MIN_SESSION then return end
	local names = {}
	for n in pairs(s.w) do names[#names + 1] = n end
	table.sort(names)
	local e = s.entry
	if not e then
		e = { c = ns.me, t = s.t }
		s.entry = e
		local list = Mine()
		list[#list + 1] = e
		Prune(list, now)
	end
	if e.d == d and e.n == #names then return end
	e.d, e.w, e.n = d, names, #names
	ns.Log("grouped: a session of %d min with %d of us", math.floor(d / 60), #names)
	Tell(e)
	-- (An officer hears their own sessions too, as any member's.)
	Grouped.Heard(ns.me, e.t, e.d, names)
end

local function Finish(now)
	local s = current
	current = nil
	if s then Record(s, now) end
end

-- The Sylvanistas players in our group now (never ourselves), by key.
function Grouped.Mates()
	local out = {}
	if not (IsInGroup and IsInGroup()) then return out end
	local Log = ns.WeekLog
	if not (Log and Log.GroupMate) then return out end
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local me = Grouped.Key(ns.me)
	for i = 1, n do
		local unit = raid and ("raid" .. i) or (i <= 4 and ("party" .. i))
		local name = unit and Log.GroupMate(unit, true)
		local key = name and Grouped.Key(name)
		if key and key ~= me then out[#out + 1] = key end
	end
	return out
end

function Grouped.Sample()
	if not Grouped.Sharing() or not ns.IsMember() then
		if current then Finish(ns.Now()) end
		return
	end
	local now = ns.Now()
	local mates = Grouped.Mates()
	if #mates == 0 then
		if current then Finish(now) end
		return
	end
	if not current then current = { t = now, last = now, w = {} } end
	current.last = now
	local added = false
	for _, k in ipairs(mates) do
		if not current.w[k] then current.w[k], added = true, true end
	end
	-- Told the minute it reaches MIN_SESSION, and again if someone new of us joins later.
	if not current.entry or added then Record(current, now) end
end

---------------------------------------------------------------------------
-- What an officer's client hears
---------------------------------------------------------------------------

local function IsOfficer() return ns.Roster and ns.Roster.IsOfficer and ns.Roster.IsOfficer() == true end

local function Heard()
	local guild = ns.GuildInfo("player")
	if not guild then return nil end
	ns.db.groupHeard = type(ns.db.groupHeard) == "table" and ns.db.groupHeard or {}
	local g = ns.db.groupHeard[guild]
	if type(g) ~= "table" then g = { list = {}, seen = {}, allTime = {} }; ns.db.groupHeard[guild] = g end
	g.list, g.seen, g.allTime = g.list or {}, g.seen or {}, g.allTime or {}
	return g
end

-- A session told by `reporter`: kept by officers' clients only, once each.
function Grouped.Heard(reporter, t, d, names)
	if not IsOfficer() then return false end
	local g = Heard()
	if not g then return false end
	local r = Grouped.Key(reporter)
	if not r then return false end
	local id = r .. "@" .. t
	if g.seen[id] then
		-- The same session told again (at its end, or someone new joined): its length and names.
		for i = #g.list, 1, -1 do
			local e = g.list[i]
			if e.r == r and e.t == t then
				if d <= e.d and #names <= #(e.w or {}) then return false end
				e.d, e.w = math.max(d, e.d), #names >= #(e.w or {}) and names or e.w
				ns.Fire("GROUPED_CHANGED")
				return true
			end
		end
		return false
	end
	g.seen[id] = true
	g.list[#g.list + 1] = { r = r, t = t, d = d, w = names }
	if #g.list > Grouped.MAX_HEARD then
		local old = table.remove(g.list, 1)
		if old then g.seen[old.r .. "@" .. old.t] = nil end
	end
	ns.Fire("GROUPED_CHANGED")
	return true
end

function Grouped.HandleReport(dist, sender, text)
	if dist ~= "GUILD" or not IsOfficer() then return end
	sender = Grouped.Key(sender)
	if not sender or not (ns.Roster.RankOf and ns.Roster.RankOf(sender)) then return end -- (our roster only)
	local t, d, list = tostring(text):match("^Z1~(%d+)~(%d+)~(.*)$")
	t, d = tonumber(t), tonumber(d)
	if not t or not d then return end
	local now = ns.Now()
	if t > now + 300 or now - t > Grouped.KEEP or d < Grouped.MIN_SESSION or d > 24 * 3600 then return end
	local names = {}
	for n in tostring(list or ""):gmatch("[^,]+") do
		if #names >= Grouped.MAX_NAMES then break end
		local k = Grouped.Key(ns.Codec.Plain(n):sub(1, 64))
		if k and k ~= sender then names[#names + 1] = k end
	end
	if #names == 0 then return end
	Grouped.Heard(sender, t, d, names)
end

-- An officer asks what they missed: our sessions since then, at most once a GAP.
function Grouped.HandleAsk(dist, sender, text)
	if dist ~= "GUILD" or not Grouped.Sharing() then return end
	sender = Grouped.Key(sender)
	local rank = sender and ns.Roster.RankOf and ns.Roster.RankOf(sender)
	if not rank or rank > ns.CAPTAIN_RANK then return end -- (an officer of our roster)
	local since = tonumber(tostring(text):match("^ZQ~(%d+)$"))
	if not since then return end
	local now = ns.Now()
	if now - lastAnswer < Grouped.ANSWER_GAP then return end
	lastAnswer = now
	local list, sent = Mine(), 0
	Prune(list, now)
	local me = Grouped.Key(ns.me)
	ns.After(2 + math.random() * 18, "grouped answer", function()
		for _, e in ipairs(list) do
			if sent >= Grouped.MAX_ANSWER then break end
			if Grouped.Key(e.c) == me and e.t >= since then
				Tell(e)
				sent = sent + 1
			end
		end
		if sent > 0 then ns.Log("grouped: %d session(s) told after an officer's ask", sent) end
	end)
end

function Grouped.Ask()
	if not IsOfficer() then return end
	local now = ns.Now()
	if now - lastAsk < Grouped.ASK_GAP then return end
	lastAsk = now
	local g = Heard()
	if not g then return end
	local newest = 0
	for _, e in ipairs(g.list) do if e.t > newest then newest = e.t end end
	local since = math.max(now - Grouped.KEEP, newest - 3600)
	ns.Comm.Send("GUILD", ("ZQ~%d"):format(since), "grouped ask")
end

---------------------------------------------------------------------------
-- The counts (officers)
---------------------------------------------------------------------------

-- Reports older than KEEP leave the list; what they counted goes to allTime first.
local function Age(g, now)
	local old = {}
	for i = #g.list, 1, -1 do
		local e = g.list[i]
		if now - e.t > Grouped.KEEP then
			old[#old + 1] = e
			table.remove(g.list, i)
			g.seen[e.r .. "@" .. e.t] = nil
		end
	end
	if #old == 0 then return end
	for key, n in pairs(Grouped.Count(old)) do g.allTime[key] = (g.allTime[key] or 0) + n.count end
end

-- { [member key] = { count, confirmed, last, with = { [key] = sessions } } } from a list of reports:
-- each member's sessions (as reporter or named), merged where they overlap.
function Grouped.Count(list)
	local per = {}
	local function Add(key, e)
		per[key] = per[key] or {}
		local p = per[key]
		p[#p + 1] = e
	end
	for _, e in ipairs(list) do
		Add(e.r, e)
		for _, n in ipairs(e.w or {}) do Add(n, e) end
	end
	local out = {}
	for key, es in pairs(per) do
		table.sort(es, function(a, b) return a.t < b.t end)
		local count, confirmed, last, with = 0, 0, nil, {}
		local runEnd, reporters, mates = nil, nil, nil
		local function Close()
			if not runEnd then return end
			count = count + 1
			local n = 0
			for _ in pairs(reporters) do n = n + 1 end
			if n >= 2 then confirmed = confirmed + 1 end
			for m in pairs(mates) do with[m] = (with[m] or 0) + 1 end
		end
		for _, e in ipairs(es) do
			local s, f = e.t, e.t + e.d
			if runEnd and s <= runEnd + Grouped.MERGE_GAP then
				runEnd = math.max(runEnd, f)
			else
				Close()
				runEnd, reporters, mates = f, {}, {}
			end
			reporters[e.r] = true
			if e.r ~= key then mates[e.r] = true end
			for _, n in ipairs(e.w or {}) do if n ~= key then mates[n] = true end end
			last = math.max(last or 0, f)
		end
		Close()
		out[key] = { count = count, confirmed = confirmed, last = last, with = with }
	end
	return out
end

-- The counts for our guild's members, the last KEEP (officers only; nil otherwise).
function Grouped.MemberCounts()
	if not IsOfficer() then return nil end
	local g = Heard()
	if not g then return nil end
	Age(g, ns.Now())
	local counts = Grouped.Count(g.list)
	for key, c in pairs(counts) do c.allTime = (g.allTime[key] or 0) + c.count end
	return counts, g.allTime
end

---------------------------------------------------------------------------
-- The count beside each name in the game's guild roster (officers; the user's call, 1.3.7)
---------------------------------------------------------------------------
-- The Guild & Communities window is Blizzard's: nothing of it is changed or hooked. A frame of
-- ours, while that roster shows, reads which member rows are on screen (their member info) and
-- lays a small number of ours just left of each name, on our own frame above the window, never
-- taking a click. Every read is guarded: another build of the window, and nothing shows.

Grouped.ROSTER_EVERY = 0.2   -- how often the labels follow the list (scrolling, sorting)
Grouped.COUNTS_EVERY = 60    -- the counts worked out again at most this often (or on a new report)

local overlay, labels, cached, cachedAt = nil, {}, nil, -math.huge
local warned = false

local function Counts()
	local now = GetTime()
	if not cached or now - cachedAt > Grouped.COUNTS_EVERY then
		cached = Grouped.MemberCounts() or {}
		cachedAt = now
	end
	return cached
end
ns.On("GROUPED_CHANGED", function()
	cached = nil
	-- (The Guilds page's numbers, Views.GroupedMark: drawn again.)
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end)

local function RosterList()
	local cf = _G.CommunitiesFrame
	if type(cf) ~= "table" or not cf.IsShown or not cf:IsShown() then return nil end
	local ml = cf.MemberList
	local box = type(ml) == "table" and ml.ScrollBox
	if type(box) ~= "table" or not box.ForEachFrame or not (ml.IsVisible and ml:IsVisible()) then return nil end
	-- The guild's roster only (not a community's): the club shown is our guild.
	local club = cf.GetSelectedClubId and cf:GetSelectedClubId()
	local guildClub = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
	if club and guildClub and club ~= guildClub then return nil end
	return box
end

local function Label(i)
	local fs = labels[i]
	if fs then return fs end
	fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetJustifyH("RIGHT")
	fs:SetShadowOffset(1, -1)
	labels[i] = fs
	return fs
end

local function Place()
	for _, fs in ipairs(labels) do fs:Hide() end
	if not IsOfficer() then return end
	local box = RosterList()
	if not box then return end
	local counts, n = Counts(), 0
	local ok, err = pcall(box.ForEachFrame, box, function(row)
		if not (row and row.IsVisible and row:IsVisible()) then return end
		local info = row.GetMemberInfo and row:GetMemberInfo() or row.memberInfo
		local name = type(info) == "table" and Plain(info.name)
		local key = name and Grouped.Key(name)
		if not key then return end
		local anchor = (type(row.NameFrame) == "table" and row.NameFrame) or row
		n = n + 1
		local fs = Label(n)
		local c = counts[key]
		local count = c and c.count or 0
		fs:SetText(count > 0 and tostring(count) or "0")
		if count > 0 then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.45, 0.45, 0.45) end
		fs:ClearAllPoints()
		fs:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
		fs:Show()
	end)
	if not ok and not warned then
		warned = true
		ns.Log("grouped: the roster could not be read (%s): no counts beside the names", tostring(err))
	end
end

function Grouped.RosterLabels()
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("HIGH")
	overlay:EnableMouse(false)
	local acc = 0
	overlay:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + (elapsed or 0)
		if acc < Grouped.ROSTER_EVERY then return end
		acc = 0
		ns.SafeCall("grouped roster", Place)
	end)
	return overlay
end

function Grouped.ResetForTests()
	current, lastAnswer, lastAsk = nil, -math.huge, -math.huge
end

ns.Comm.Handle("Z1", function(...) Grouped.HandleReport(...) end)
ns.Comm.Handle("ZQ", function(...) Grouped.HandleAsk(...) end)

ns.On("LOGIN", function()
	ns.Every(Grouped.SAMPLE, "grouped", function() ns.SafeCall("grouped", Grouped.Sample) end)
	pcall(ns.RegisterEvent, "GROUP_ROSTER_UPDATE", function() ns.SafeCall("grouped", Grouped.Sample) end)
	ns.RegisterEvent("PLAYER_LOGOUT", function()
		if current then current.last = ns.Now() Finish(ns.Now()) end
	end)
	Grouped.RosterLabels()
	-- An officer's client asks what it missed, once the roster is read.
	ns.After(45, "grouped ask", function() ns.SafeCall("grouped ask", Grouped.Ask) end)
end)
