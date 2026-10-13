local ADDON, ns = ...
local L = ns.L

-- The week, read-only (1.2.21, after Olympus 1.2.1's WeeklyBrief.lua): facts this client already
-- holds, nothing asked of anyone, nothing sent, no sharing switch touched.
--   * "The week" (a page the Board links): the Forsaken's count and how it moved since last week
--     (only when the same guilds reported both weeks: missing history stays unknown, never zero),
--     our guild's place by size, the week's events and the last public Voice of the Forsaken.
--   * "Your week, in five lines" (a page the Realm links): the next event and our signup, what is
--     open now (the Dark Lady's Conclave, a poll), guildmates online, a sister guild's member on
--     our layer, and whether our addon is up to date.
-- Two local week snapshots are kept (ns.rdb.weeklyBrief), never sent.
local Brief = {}
ns.WeeklyBrief = Brief

local function Plain(s, n)
	return ns.Cut((tostring(s or ""):gsub("[|%c]", " "):gsub("%s+", " ")), n or 160)
end
local function Number(n)
	return type(n) == "number" and n == n and n >= 0 and n < math.huge and math.floor(n) or nil
end
local function Store()
	if not ns.rdb then return nil end
	if type(ns.rdb.weeklyBrief) ~= "table" then ns.rdb.weeklyBrief = {} end
	local s = ns.rdb.weeklyBrief
	if type(s.weeks) ~= "table" then s.weeks = {} end
	for key, row in pairs(s.weeks) do
		if type(row) ~= "table" or not Number(row.total) or not Number(row.known) or row.known < 1
			or row.total > row.known * ns.Codec.GUILD_CAP or not Number(row.at)
			or type(row.coverage) ~= "string" or row.coverage == "" or #row.coverage > 16000 then s.weeks[key] = nil end
	end
	if type(s.vox) ~= "table" or type(s.vox.q) ~= "string" or type(s.vox.verdict) ~= "string" or not Number(s.vox.at) then s.vox = nil end
	return s
end
local function Week() return ns.Dues and ns.Dues.Week and ns.Dues.Week() or nil end
local function Census()
	local D = ns.Data
	if not D or not D.Summary or (D.Rebuilding and D.Rebuilding() ~= nil) then return nil end
	local summary, names, own, sizes = D.Summary(), {}, GetGuildInfo("player"), {}
	for _, e in ipairs(summary.guilds or {}) do
		local size = e.counted and type(e.g) == "table" and Number(e.g.total)
		if size then names[#names + 1] = e.name; sizes[e.name] = math.min(size, ns.Codec.GUILD_CAP) end
	end
	if #names == 0 or not Number(summary.total) then return nil end
	table.sort(names)
	local rank
	if sizes[own] then
		rank = 1
		for _, size in pairs(sizes) do if size > sizes[own] then rank = rank + 1 end end
	end
	return { total = Number(summary.total), known = #names, coverage = table.concat(names, "|"), at = ns.Now(), rank = rank }
end

-- The last poll whose result went to everyone (never a guild's, a Dark Ranger's or a hidden one).
local function PublicResult(s)
	local V = ns.Vox
	if not V or not V.State or (ns.King and ns.King.Preview and ns.King.Preview()) then return end
	local poll, history, shown = V.State()
	local candidates = {}
	for _, h in ipairs(history or {}) do candidates[#candidates + 1] = h end
	if poll and poll.closed and not poll.preview then candidates[#candidates + 1] = poll end
	if shown and shown.counts and not shown.hidden then candidates[#candidates + 1] = shown end
	for _, h in ipairs(candidates) do
		if h.to == "E" and not h.hidden and type(h.q) == "string" and type(h.answers) == "table"
			and type(h.counts) == "table" and Number(h.voters) then
			local at = Number(h.resultsAt or h.t or h.at)
			if at and (not s.vox or at > (tonumber(s.vox.at) or 0)) then
				s.vox = { q = Plain(h.q), verdict = Plain(V.Verdict(h.answers, h.counts, h.voters, h.multi)), at = at }
			end
		end
	end
end

function Brief.Capture()
	if not ns.IsMember() then return nil end
	local week, s = Week(), Store()
	if not Number(week) or not s then return nil end
	for key in pairs(s.weeks) do
		if key ~= week and key ~= week - 1 then s.weeks[key] = nil end
	end
	local c = Census()
	if c then s.weeks[week] = { total = c.total, known = c.known, coverage = c.coverage, at = c.at } end
	ns.SafeCall("weekly vox", PublicResult, s)
	return s.weeks[week], s.weeks[week - 1], c
end

---------------------------------------------------------------------------
-- The week (the Board's link)
---------------------------------------------------------------------------

function Brief.Link()
	return { text = ns.Views.Gold("> " .. L.BRIEF_TITLE), gapAfter = true,
		onClick = function() ns.Views.ShowPage("weeklybrief") end,
		tooltip = function(tt) tt:AddLine(L.BRIEF_TITLE, 1, 0.82, 0); tt:AddLine(L.BRIEF_NOTE, 1, 1, 1, true) end }
end

function Brief.Lines(q)
	local V = ns.Views
	local now, prior, census = Brief.Capture()
	local lines = { { text = V.Gold(L.BRIEF_BACK), onClick = function() ns.Views.ShowBoard(true) end, gapAfter = true },
		{ header = true, text = L.BRIEF_TITLE } }
	V.GreyRows(lines, L.BRIEF_NOTE)
	lines[#lines].gapAfter = true
	local function Row(label, value)
		if not q or ns.Holds(q, label, value) then lines[#lines + 1] = { text = label, right = value } end
	end
	local size = type(now) == "table" and Number(now.total)
	Row(L.BRIEF_ARMY, size and ns.FormatNumber(size) or V.Grey(L.BRIEF_UNKNOWN))
	if size and Number(now.known) and Number(now.at) then
		lines[#lines + 1] = { indent = 1, text = V.Grey(L.BRIEF_COVERAGE:format(now.known, ns.Ago(now.at))) }
	end
	local before = type(prior) == "table" and Number(prior.total)
	local comparable = size and before and type(now.coverage) == "string" and now.coverage == prior.coverage
	Row(L.BRIEF_PREVIOUS, comparable and ("%+d"):format(size - before) or V.Grey(L.BRIEF_UNKNOWN))
	Row(L.BRIEF_RANK, census and census.rank and L.BRIEF_RANK_VALUE:format(census.rank, census.known) or V.Grey(L.BRIEF_UNKNOWN))
	lines[#lines].gapAfter = true
	lines[#lines + 1] = { header = true, text = L.BRIEF_EVENTS }
	local entries = ns.Week and ns.Week.Entries and ns.Week.Entries() or {}
	for _, e in ipairs(entries) do
		local text = Plain(e.title) .. "  " .. V.Grey(ns.Week.DayLabel(e.at) .. " " .. ns.Week.TimeLabel(e.at))
		if not q or ns.Holds(q, text) then lines[#lines + 1] = { indent = 1, text = text } end
	end
	if #entries == 0 then lines[#lines + 1] = { indent = 1, text = V.Grey(L.BRIEF_NO_WEEK) } end
	lines[#lines].gapAfter = true
	local s, F = Store(), ns.Filter
	local v = s and type(s.vox) == "table" and s.vox or nil
	local result = v and (Plain(v.q) .. " - " .. Plain(v.verdict)) or L.BRIEF_UNKNOWN
	if v and F and F.Hides and (F.Hides(v.q) or F.Hides(v.verdict)) then result = L.FILTER_WORDS_HIDDEN_SHORT end
	lines[#lines + 1] = { header = true, text = L.BRIEF_VOX }
	V.GreyRows(lines, result, { indent = 1 })
	return lines
end

---------------------------------------------------------------------------
-- Your week, in five lines (the Realm's link)
---------------------------------------------------------------------------

-- A member of another Sylvanistas guild on our layer, as this client heard it (never a claim that
-- nobody is there).
local function Companion()
	local layers = ns.Layers
	if not layers or not layers.Sharing or not layers.Sharing() then return L.BRIEF_LOCATION_PRIVATE end
	local mine = layers.Mine and layers.Mine()
	local map = layers.CurrentMap and layers.CurrentMap()
	if not mine or mine.mapID ~= map or not layers.ForMap then return L.BRIEF_UNKNOWN end
	local guild = GetGuildInfo("player")
	for _, layer in ipairs(layers.ForMap(map)) do
		local h = layer.head
		if h and h.guild ~= guild and ns.IsFederation(h.guild) then
			return Plain(h.name, 64) .. " <" .. Plain(h.guild, 40) .. ">"
		end
	end
	return L.BRIEF_UNKNOWN
end

-- Our addon against what this client heard: the author's release, or two or more guildmates.
local function UpToDate()
	local W = ns.Workshop
	local behind = W and ((W.Behind and W.Behind()) or (W.PeersAhead and W.PeersAhead()))
	if behind then return L.BRIEF_VERSION_BEHIND:format(ns.VERSION, behind) end
	return L.BRIEF_VERSION_OK:format(ns.VERSION)
end

local function PersonalValues()
	local now, nextEntry = ns.Now(), nil
	for _, e in ipairs(ns.Week and ns.Week.Entries and ns.Week.Entries() or {}) do
		if e.at >= now and (not nextEntry or e.at < nextEntry.at) then nextEntry = e end
	end
	local nextText = L.BRIEF_NONE
	if nextEntry then
		local role = ns.Week.MySignup and ns.Week.MySignup(nextEntry.id)
		local signup = role and L.BRIEF_SIGNED:format(Plain(L["SIGN_ROLE_" .. role] or role, 40)) or L.BRIEF_UNSIGNED
		nextText = Plain(nextEntry.title, 60) .. " - " .. ns.Week.DayLabel(nextEntry.at) .. " " .. ns.Week.TimeLabel(nextEntry.at) .. "; " .. signup
	end
	local open = {}
	local C = ns.Court
	if C and ((C.Current and C.Current()) or (C.Holding and C.Holding())) then open[#open + 1] = L.BRIEF_COURT_OPEN end
	if ns.Vox and ns.Vox.State then
		local poll = ns.Vox.State()
		if poll and not poll.closed and not poll.preview then open[#open + 1] = L.BRIEF_VOX_OPEN end
	end
	local online = ns.Roster and type(ns.Roster.online) == "table" and tostring(#ns.Roster.online) or L.BRIEF_UNKNOWN
	return { nextText, #open > 0 and table.concat(open, ", ") or L.BRIEF_NONE, online, Companion(), UpToDate() }
end
Brief.PersonalValues = PersonalValues -- (tests)

function Brief.PersonalLink()
	if not ns.IsMember() then return nil end
	return { text = "|TInterface\\Icons\\INV_Scroll_04:14:14|t " .. ns.Views.Gold(L.BRIEF_PERSONAL_TITLE),
		onClick = function() ns.Views.ShowPage("personalbrief") end,
		tooltip = function(tt) tt:AddLine(L.BRIEF_PERSONAL_TITLE, 1, 0.82, 0); tt:AddLine(L.BRIEF_PERSONAL_NOTE, 1, 1, 1, true) end }
end

function Brief.PersonalPage(q)
	if not ns.IsMember() then return {} end
	local V = ns.Views
	local lines = { { text = V.Gold(L.BRIEF_PERSONAL_BACK), onClick = function() ns.Views.ShowPage(nil) end, gapAfter = true },
		{ header = true, text = L.BRIEF_PERSONAL_TITLE } }
	V.GreyRows(lines, L.BRIEF_PERSONAL_NOTE)
	lines[#lines].gapAfter = true
	local titles = { L.BRIEF_NEXT_TITLE, L.BRIEF_OPEN_TITLE, L.BRIEF_ONLINE_TITLE, L.BRIEF_COMPANION_TITLE, L.BRIEF_VERSION_TITLE }
	for index, value in ipairs(PersonalValues()) do
		if not q or ns.Holds(q, titles[index], value) then
			lines[#lines + 1] = { text = V.Gold(index .. ". " .. titles[index]) }
			lines[#lines + 1] = { indent = 1, text = value, gapAfter = true }
		end
	end
	return lines
end

ns.RealmPages = ns.RealmPages or {}
table.insert(ns.RealmPages, { key = "weeklybrief", Lines = Brief.Lines, tip = "BRIEF" })
table.insert(ns.RealmPages, { key = "personalbrief", Link = Brief.PersonalLink, Lines = Brief.PersonalPage, tip = "BRIEF_PERSONAL" })
ns.On("LOGIN", function()
	ns.After(210, "weekly brief snapshot", Brief.Capture) -- after the census rebuilds
	ns.Every(60, "weekly brief snapshot", Brief.Capture)
end)
