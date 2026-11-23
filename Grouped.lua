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
Grouped.MERGE_GAP = 30 * 60      -- a member's sessions this close, with someone in common, count as one (a regroup)
Grouped.SLACK = 120              -- clock and sampling slack in the checks below
Grouped.MAX_RELAY = 300          -- reports one officer hands another in one answer (newest first)
Grouped.ANSWER_GAP = 10 * 60     -- a member answers an officer's ask at most this often
Grouped.ASK_GAP = 10 * 60        -- an officer asks at most this often
Grouped.MAX_NAMES = 20           -- names in one Z1 (a raid's: the first 20 kept)
Grouped.MAX_ANSWER = 60          -- sessions sent in one answer
Grouped.MAX_HEARD = 4000         -- reports kept by an officer's client (oldest dropped)

local current          -- the session going on: { t, last, w = { [name] = true } }
local lastAnswer, lastAsk = -math.huge, -math.huge
local lastRelay = -math.huge  -- when this officer last handed reports to another
local relayHeardAt = -math.huge -- GetTime() of the last report another officer handed on

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
	if dist ~= "GUILD" then return end
	sender = Grouped.Key(sender)
	local rank = sender and ns.Roster.RankOf and ns.Roster.RankOf(sender)
	if not rank or rank > ns.CAPTAIN_RANK then return end -- (an officer of our roster)
	local since = tonumber(tostring(text):match("^ZQ~(%d+)$"))
	if not since then return end
	if sender ~= Grouped.Key(ns.me) then Grouped.Relay(since) end
	if not Grouped.Sharing() then return end
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

-- Officers hand each other what they heard (1.3.7, the user's call): another officer asked
-- (ZQ), so one officer online answers with every report held since then, the newest first,
--   Z2~<reporter>~<start>~<seconds>~<name>,<name>,...   (GUILD; officers only send or keep it)
-- Each waits a few random seconds and stays quiet if another officer started handing on first.
function Grouped.Relay(since)
	if not IsOfficer() then return end
	local askedAt = GetTime()
	if askedAt - lastRelay < Grouped.ANSWER_GAP then return end
	ns.After(3 + math.random() * 9, "grouped relay", function()
		if relayHeardAt >= askedAt then return end -- (another officer is on it)
		if ns.DemoBlocked and ns.DemoBlocked() then return end
		local g = Heard()
		if not g then return end
		lastRelay = GetTime()
		local list = {}
		for _, e in ipairs(g.list) do if e.t >= since then list[#list + 1] = e end end
		table.sort(list, function(a, b) return a.t > b.t end)
		local sent = 0
		for _, e in ipairs(list) do
			if sent >= Grouped.MAX_RELAY then break end
			local head = ("Z2~%s~%d~%d~"):format(tostring(e.r):gsub("[~,|%c]", ""), e.t, e.d)
			local out = {}
			for _, n in ipairs(e.w or {}) do
				local clean = tostring(n):gsub("[~,|%c]", "")
				if #out >= Grouped.MAX_NAMES or #head + #table.concat(out, ",") + #clean + 1 > 250 then break end
				out[#out + 1] = clean
			end
			if #out > 0 then
				ns.Comm.Send("GUILD", head .. table.concat(out, ","), "grouped relay")
				sent = sent + 1
			end
		end
		if sent > 0 then ns.Log("grouped: %d report(s) handed to another officer", sent) end
	end)
end

-- A report another officer handed on: kept as its reporter's own (reporter of our roster only).
function Grouped.HandleRelay(dist, sender, text)
	if dist ~= "GUILD" then return end
	sender = Grouped.Key(sender)
	local rank = sender and ns.Roster.RankOf and ns.Roster.RankOf(sender)
	if not rank or rank > ns.CAPTAIN_RANK or sender == Grouped.Key(ns.me) then return end
	relayHeardAt = GetTime()
	if not IsOfficer() then return end
	local reporter, t, d, list = tostring(text):match("^Z2~([^~]+)~(%d+)~(%d+)~(.*)$")
	t, d = tonumber(t), tonumber(d)
	reporter = reporter and Grouped.Key(ns.Codec.Plain(reporter):sub(1, 64))
	if not reporter or not t or not d then return end
	if not (ns.Roster.RankOf and ns.Roster.RankOf(reporter)) then return end
	local now = ns.Now()
	if t > now + 300 or now - t > Grouped.KEEP or d < Grouped.MIN_SESSION or d > 24 * 3600 then return end
	local names = {}
	for n in tostring(list or ""):gmatch("[^,]+") do
		if #names >= Grouped.MAX_NAMES then break end
		local k = Grouped.Key(ns.Codec.Plain(n):sub(1, 64))
		if k and k ~= reporter then names[#names + 1] = k end
	end
	if #names == 0 then return end
	Grouped.Heard(reporter, t, d, names)
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
-- Who was online (officers): what the roster scans showed while this officer was on
---------------------------------------------------------------------------
-- Kept as flat lists of { from, to, from, to, ... }: the times this client watched the roster
-- (cover) and, per member, the times the roster showed them online. A report is checked
-- against them only where this client was watching (Covered); elsewhere it is taken as told.

local function Extend(list, now)
	local n = #list
	if n >= 2 and now - list[n] <= 3 * Grouped.SAMPLE then list[n] = now
	else list[n + 1], list[n + 2] = now, now end
end
local function PruneFlat(list, now)
	local keep = {}
	for i = 1, #list - 1, 2 do
		if now - list[i + 1] <= Grouped.KEEP then keep[#keep + 1], keep[#keep + 2] = list[i], list[i + 1] end
	end
	return keep
end

-- Alts named in guild and officer notes: "alt of Steveo", "Steveo's alt", "alt: Steveo",
-- "Alt - Steveo Rino", "ALT Steveo", "Steveo alt" (any case). A name only counts when it is a
-- guildmate's (first name alone only when one guildmate has it). A note that only starts with
-- "alt" (the user: officers may just write ALT, alt or Alt - ...) says "an alt" without whose:
-- then NoteMain gives true, and Presence looks for the main by the second name (Forever's names
-- are two words, and a player's characters share the second: Danzig, Gage, Maldric Gloomvein).
local NOTE_PATTERNS = { "alt%s+of%s+([%a][%a' ]-)%s*$", "alt%s+of%s+([%a][%a']+)", "([%a][%a']+)'s%s+alt", "alt%s*[:%-]%s*([%a][%a' ]-)%s*$",
	"alt%s*[:%-]%s*([%a][%a']+)", "^%s*alt%s+([%a][%a' ]-)%s*$", "^%s*alt%s+([%a][%a']+)", "^%s*([%a][%a']+)%s+alt%s*$" }
function Grouped.NoteMain(note, byShort, byFirst)
	if type(note) ~= "string" or note == "" then return nil end
	local lower = note:lower()
	for _, pat in ipairs(NOTE_PATTERNS) do
		local who = lower:match(pat)
		if who then
			who = who:gsub("^%s+", ""):gsub("%s+$", "")
			local k = byShort[who] or byFirst[who]
			if k then return k end
		end
	end
	-- "ALT", "alt.", "Alt - healer", "alt (bank)": an alt, the main not named.
	if lower:match("^%s*alt%f[%A]") then return true end
	return nil
end

-- The second word of a name ("Gloomvein" of "Danzig Gloomvein-Realm"), lower case, or nil.
function Grouped.SecondName(key)
	local short = type(key) == "string" and ns.ShortName(key) or nil
	local second = short and short:match("^%S+%s+(%S+)$")
	return second and second:lower() or nil
end

function Grouped.Presence()
	if not IsOfficer() then return end
	local members = ns.Roster and ns.Roster.members
	if type(members) ~= "table" or #members == 0 then return end
	local g = Heard()
	if not g then return end
	local now = ns.Now()
	g.cover = type(g.cover) == "table" and g.cover or {}
	g.online = type(g.online) == "table" and g.online or {}
	Extend(g.cover, now)
	for _, m in ipairs(members) do
		if m.online then
			local key = Grouped.Key(m.raw)
			if key then
				g.online[key] = type(g.online[key]) == "table" and g.online[key] or {}
				Extend(g.online[key], now)
			end
		end
	end
	-- Tidied once an hour or so.
	if not g.tidyAt or now - g.tidyAt > 3600 then
		g.tidyAt = now
		g.cover = PruneFlat(g.cover, now)
		for key, list in pairs(g.online) do
			local kept = PruneFlat(list, now)
			g.online[key] = #kept > 0 and kept or nil
		end
	end
	-- Alts from the notes (the roster's own: public notes, and officer notes an officer may read).
	if ns.NumGuildMembers and ns.GuildRosterInfo and (not g.notesAt or now - g.notesAt > 600) then
		g.notesAt = now
		local byShort, byFirst = {}, {}
		for _, m in ipairs(members) do
			local key = Grouped.Key(m.raw)
			if key then
				local short = ns.ShortName(key):lower()
				byShort[short] = key
				local first = short:match("^(%S+)")
				if first then byFirst[first] = byFirst[first] == nil and key or false end -- (a first name two share: neither)
			end
		end
		for k, v in pairs(byFirst) do if v == false then byFirst[k] = nil end end
		local notes, unnamed, notAlt = {}, {}, {}
		local total = ns.NumGuildMembers() or 0
		for i = 1, total do
			local ok, name, _, _, _, _, _, note, officerNote = pcall(ns.GuildRosterInfo, i)
			local key = ok and Plain(name) and Grouped.Key(name)
			if key then
				local a = Grouped.NoteMain(Plain(note), byShort, byFirst)
				local b = Grouped.NoteMain(Plain(officerNote), byShort, byFirst)
				local main = (type(a) == "string" and a) or (type(b) == "string" and b) or nil
				if main and main ~= key then notes[key] = main
				elseif a == true or b == true then unnamed[#unnamed + 1] = key
				else notAlt[#notAlt + 1] = key end
			end
		end
		-- "ALT" alone: the main is the one guildmate of the same second name whose notes say no
		-- alt. None, or several: no guess (the alt counts alone).
		local bySecond = {}
		for _, key in ipairs(notAlt) do
			local sn = Grouped.SecondName(key)
			if sn then bySecond[sn] = bySecond[sn] == nil and key or false end
		end
		for _, key in ipairs(unnamed) do
			local sn = Grouped.SecondName(key)
			local main = sn and bySecond[sn]
			if main and main ~= key then notes[key] = main end
		end
		g.noteMains = notes
	end
end

local function Covered(g, a, b)
	local list = g and g.cover
	if type(list) ~= "table" then return false end
	for i = 1, #list - 1, 2 do
		if list[i] <= a + Grouped.SLACK and list[i + 1] >= b - Grouped.SLACK then return true end
	end
	return false
end
local function WasOnline(g, key, a, b)
	local list = g and g.online and g.online[key]
	if type(list) ~= "table" then return false end
	for i = 1, #list - 1, 2 do
		if list[i] <= b + Grouped.SLACK and list[i + 1] >= a - Grouped.SLACK then return true end
	end
	return false
end

-- The person a character is: its main by the alt links (Alts.lua), else by a note, else itself.
function Grouped.PersonOf(key, g)
	local Alts = ns.Alts
	if Alts and Alts.Group then
		local ok, grp = pcall(Alts.Group, key)
		if ok and type(grp) == "table" and type(grp.main) == "string" then
			local main = Grouped.Key(grp.main)
			if main then return main, "link" end
		end
	end
	local notes = g and g.noteMains
	if type(notes) == "table" and notes[key] then return notes[key], "note" end
	return key, nil
end

---------------------------------------------------------------------------
-- The counts (officers)
---------------------------------------------------------------------------

-- The reports that pass the checks, each with the names that do (`names`):
--   one reporter is in one group at a time: a report overlapping an earlier one of the same
--   reporter is dropped; where this officer watched the roster, a reporter shown offline the whole
--   time is dropped, and so is a named member shown offline (their credit only).
function Grouped.Checked(list, g)
	local byReporter = {}
	for _, e in ipairs(list) do
		byReporter[e.r] = byReporter[e.r] or {}
		local l = byReporter[e.r]
		l[#l + 1] = e
	end
	local out, dropped = {}, 0
	for r, es in pairs(byReporter) do
		table.sort(es, function(a, b) return a.t < b.t end)
		local lastEnd
		for _, e in ipairs(es) do
			local a, b = e.t, e.t + e.d
			local ok = not (lastEnd and a < lastEnd - Grouped.SLACK)
			local covered = ok and Covered(g, a, b)
			local inRoster = ns.Roster.RankOf and ns.Roster.RankOf(r) ~= nil
			if ok and covered and inRoster and not WasOnline(g, r, a, b) then ok = false end
			if ok then
				lastEnd = math.max(lastEnd or 0, b)
				local names = {}
				for _, n in ipairs(e.w or {}) do
					local mine = ns.Roster.RankOf and ns.Roster.RankOf(n) ~= nil
					if not (covered and mine and not WasOnline(g, n, a, b)) then names[#names + 1] = n end
				end
				out[#out + 1] = { r = e.r, t = e.t, d = e.d, w = names }
			else
				dropped = dropped + 1
			end
		end
	end
	return out, dropped
end

local function Day(t) return date and date("%Y-%m-%d", t) or tostring(math.floor(t / 86400)) end

-- One set of characters' sessions (a member, or a person and their alts), merged by time: reports
-- that overlap are one group (told twice, or by two clients); a later one within MERGE_GAP is the
-- same group re-formed only when it has someone in common with it (the user: a group with William,
-- then one with Steveo a few minutes later, are two groups). Counted once each.
local function Tally(es, selves)
	table.sort(es, function(a, b) return a.t < b.t end)
	local c = { count = 0, confirmed = 0, byOthers = 0, selfOnly = 0, with = {}, days = {}, vouchers = {}, last = nil }
	local runEnd, reporters, mates
	local function Close()
		if not runEnd then return end
		c.count = c.count + 1
		local n, others = 0, false
		for rep in pairs(reporters) do
			n = n + 1
			if not selves[rep] then others = true; c.vouchers[rep] = true end
		end
		if n >= 2 then c.confirmed = c.confirmed + 1 end
		if others then c.byOthers = c.byOthers + 1 else c.selfOnly = c.selfOnly + 1 end
		for m in pairs(mates) do c.with[m] = (c.with[m] or 0) + 1 end
	end
	for _, e in ipairs(es) do
		local a, b = e.t, e.t + e.d
		local here = {}
		if not selves[e.r] then here[e.r] = true end
		for _, n in ipairs(e.w or {}) do if not selves[n] then here[n] = true end end
		local same = false
		if runEnd then
			if a <= runEnd + Grouped.SLACK then same = true
			elseif a <= runEnd + Grouped.MERGE_GAP then
				for n in pairs(here) do if mates[n] then same = true break end end
			end
		end
		if same then
			runEnd = math.max(runEnd, b)
		else
			Close()
			runEnd, reporters, mates = b, {}, {}
		end
		reporters[e.r] = true
		for n in pairs(here) do mates[n] = true end
		c.days[Day(a)] = true
		c.last = math.max(c.last or 0, b)
	end
	Close()
	local function Size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	c.mates, c.dayCount, c.vouched = Size(c.with), Size(c.days), Size(c.vouchers)
	return c
end

-- { [character key] = counts } from checked reports. A character with alts (links or notes) gets
-- its person's counts (main and alts together, merged by time), with .own (its own) and .person,
-- .chars (the person's characters) and .via ("link" or "note").
function Grouped.Count(list, g)
	local perChar = {}
	local function Add(key, e)
		perChar[key] = perChar[key] or {}
		local l = perChar[key]
		if l[#l] ~= e then l[#l + 1] = e end
	end
	for _, e in ipairs(list) do
		Add(e.r, e)
		for _, n in ipairs(e.w or {}) do Add(n, e) end
	end
	local persons, out = {}, {}
	for key in pairs(perChar) do
		local p, via = Grouped.PersonOf(key, g)
		persons[p] = persons[p] or { chars = {}, via = nil }
		persons[p].chars[key] = true
		if via then persons[p].via = via end
	end
	for p, info in pairs(persons) do
		local n = 0
		for _ in pairs(info.chars) do n = n + 1 end
		local whole
		if n > 1 or not info.chars[p] then
			local seen, es = {}, {}
			for key in pairs(info.chars) do
				for _, e in ipairs(perChar[key]) do
					if not seen[e] then seen[e] = true; es[#es + 1] = e end
				end
			end
			whole = Tally(es, info.chars)
		end
		for key in pairs(info.chars) do
			local own = Tally(perChar[key], { [key] = true })
			local c = whole or own
			if whole then
				c = setmetatable({ own = own, person = p, chars = info.chars, via = info.via }, { __index = whole })
			end
			out[key] = c
		end
	end
	return out
end

-- Reports older than KEEP leave the list; what they counted goes to allTime (per character) first.
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
	local checked = Grouped.Checked(old, g)
	for key, c in pairs(Grouped.Count(checked, g)) do
		local own = c.own or c
		g.allTime[key] = (g.allTime[key] or 0) + own.count
	end
end

-- The counts for our guild's members, the last KEEP (officers only; nil otherwise). A count with
-- alts adds the alts' all-time totals too.
function Grouped.MemberCounts()
	if not IsOfficer() then return nil end
	local g = Heard()
	if not g then return nil end
	Age(g, ns.Now())
	local checked, dropped = Grouped.Checked(g.list, g)
	local counts = Grouped.Count(checked, g)
	for key, c in pairs(counts) do
		local all = 0
		for k in pairs(c.chars or { [key] = true }) do all = all + (g.allTime[k] or 0) end
		rawset(c, "allTime", all + c.count)
	end
	Grouped.dropped = dropped
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
	current, lastAnswer, lastAsk, lastRelay, relayHeardAt = nil, -math.huge, -math.huge, -math.huge, -math.huge
end

ns.Comm.Handle("Z1", function(...) Grouped.HandleReport(...) end)
ns.Comm.Handle("ZQ", function(...) Grouped.HandleAsk(...) end)
ns.Comm.Handle("Z2", function(...) Grouped.HandleRelay(...) end)

ns.On("LOGIN", function()
	ns.Every(Grouped.SAMPLE, "grouped", function()
		ns.SafeCall("grouped", Grouped.Sample)
		ns.SafeCall("grouped presence", Grouped.Presence)
	end)
	pcall(ns.RegisterEvent, "GROUP_ROSTER_UPDATE", function() ns.SafeCall("grouped", Grouped.Sample) end)
	ns.RegisterEvent("PLAYER_LOGOUT", function()
		if current then current.last = ns.Now() Finish(ns.Now()) end
	end)
	Grouped.RosterLabels()
	-- An officer's client asks what it missed, once the roster is read.
	ns.After(45, "grouped ask", function() ns.SafeCall("grouped ask", Grouped.Ask) end)
end)
