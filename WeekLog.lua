local ADDON, ns = ...
local L = ns.L

-- Your week, the recap (1.3.0, the user's design): three parts under "Your week, in five lines",
-- recorded by this client as its player plays, every character of the account in one recap (the
-- account's saved variables), each line tagged with the character. Nothing is sent, except the
-- player's own click on Share (guild chat or [Sylvanistas]).
--   Dungeons    each run this week (5-player dungeons): bosses killed, completed (its last boss
--               down), and the rare and better items (blue, purple, orange) this character got there.
--               The game tells boss kills in raids alone (ENCOUNTER_END; the wiki's
--               DungeonEncounterID note), so in a dungeon a boss counts once this client sees it
--               dead (target, focus, mouseover, nameplates) by its English name (BOSSES below,
--               warcraft.wiki.gg's Classic list): a client in another language only sees the run.
--   Newly Discovered  zones, subzones and cities this character entered for the first time
--               (from 1.3.0 on: before it, everything counts as new once).
--   Guild Life  the guildmates grouped with most this week, by time together (every SAMPLE).
-- The week is the game's weekly reset (Weeks.Week). Two weeks are kept (this one and the last).
local Log = {}
ns.WeekLog = Log

Log.SAMPLE = 60          -- seconds between looks at the group
Log.RUN_GAP = 30 * 60    -- back in the same dungeon within this: the same run
Log.KEEP_WEEKS = 2
Log.MATES_SHOWN = 5
Log.PLACES_SHOWN = 12

-- The Classic dungeons' bosses (warcraft.wiki.gg, DungeonEncounterID, Classic), by English name; the
-- last of each wing ends it ("completed"). The Stockade and Scholomance were not on that list: their
-- last bosses by name alone.
local LAST = {}
local BOSS = {}  -- [lower name] = true
local function Wing(names, ...)
	for _, n in ipairs(names) do BOSS[n:lower()] = true end
	for _, last in ipairs({ ... }) do LAST[last:lower()] = true end
end
Wing({ "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }, "Bazzalan")
Wing({ "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" }, "Mutanus the Devourer")
Wing({ "Rhahk'zor", "Sneed", "Gilnid", "Mr. Smite", "Cookie", "Captain Greenskin", "Edwin VanCleef" }, "Edwin VanCleef")
Wing({ "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" }, "Archmage Arugal")
Wing({ "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai" }, "Aku'mai")
Wing({ "Bazil Thredd" }, "Bazil Thredd")
Wing({ "Viscous Fallout", "Grubbis", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg" }, "Mekgineer Thermaplugg")
Wing({ "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Charlga Razorflank" }, "Charlga Razorflank")
Wing({ "Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey", "Arcanist Doan", "Herod", "High Inquisitor Fairbanks", "High Inquisitor Whitemane" },
	"Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane")
Wing({ "Tuten'kash", "Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer" }, "Amnennar the Coldbringer")
Wing({ "Revelosh", "Ironaya", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" }, "Archaedas")
Wing({ "Hydromancer Velratha", "Ghaz'rilla", "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Chief Ukorz Sandscalp" }, "Chief Ukorz Sandscalp")
Wing({ "Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" }, "Princess Theradras")
Wing({ "Dreamscythe", "Weaver", "Jammal'an the Prophet", "Morphaz", "Hazzas", "Avatar of Hakkar", "Shade of Eranikus" }, "Shade of Eranikus")
Wing({ "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss",
	"Fineous Darkvire", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot",
	"Plugger Spazzring", "Ambassador Flamelash", "Magmus", "Emperor Dagran Thaurissan" }, "Emperor Dagran Thaurissan")
Wing({ "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris",
	"Gizrul the Slavener", "Halycon", "Overlord Wyrmthalak", "Pyroguard Emberseer", "Solakar Flamewreath", "Warchief Rend Blackhand",
	"The Beast", "General Drakkisath" }, "Overlord Wyrmthalak", "General Drakkisath")
Wing({ "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar",
	"Tendris Warpwood", "Prince Tortheldrin", "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
	"Cho'Rush the Observer", "King Gordok" }, "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok")
Wing({ "Darkmaster Gandling" }, "Darkmaster Gandling")
Wing({ "The Unforgiven", "Hearthsinger Forresten", "Timmy the Cruel", "Willey Hopebreaker", "Commander Malor", "Instructor Galford",
	"Balnazzar", "Baroness Anastari", "Nerub'enkan", "Maleki the Pallid", "Magistrate Barthilas", "Ramstein the Gorger", "Lord Aurius Rivendare" },
	"Balnazzar", "Lord Aurius Rivendare")

---------------------------------------------------------------------------
-- The store: ns.db.weekLog = { [week] = { runs = { ... }, places = { ... }, mates = { [name] = { s, by } } } }
---------------------------------------------------------------------------

local function Week()
	if ns.Weeks and ns.Weeks.Week then
		local ok, w = pcall(ns.Weeks.Week)
		if ok and w then return w end
	end
	return math.floor(((GetServerTime and GetServerTime() or time()) - 4 * 86400) / (7 * 86400))
end
function Log.Week() return Week() end
local function Char() return ns.ShortName(ns.me or "?") end

local function Store()
	local db = ns.db
	if not db then return nil end
	if type(db.weekLog) ~= "table" then db.weekLog = {} end
	local w = Week()
	local t = db.weekLog[w]
	if type(t) ~= "table" then
		t = { runs = {}, places = {}, mates = {} }
		db.weekLog[w] = t
		for k in pairs(db.weekLog) do
			if type(k) ~= "number" or k <= w - Log.KEEP_WEEKS then db.weekLog[k] = nil end
		end
	end
	return t
end
local function Seen()
	local db = ns.db
	if type(db.placesSeen) ~= "table" then db.placesSeen = {} end
	local c = Char()
	if type(db.placesSeen[c]) ~= "table" then db.placesSeen[c] = {} end
	return db.placesSeen[c]
end

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------

local run -- this character's current run (a table inside the store), or nil outside a dungeon
local function Dungeon()
	if not GetInstanceInfo then return nil end
	local ok, name, kind = pcall(GetInstanceInfo)
	if ok and kind == "party" and type(name) == "string" and name ~= "" then return name end
	return nil
end
local function Entered()
	local name = Dungeon()
	if not name then run = nil return end
	local t = Store()
	if not t then return end
	local now, c = ns.Now(), Char()
	for i = #t.runs, 1, -1 do
		local r = t.runs[i]
		if r.char == c and r.where == name and now - (r.last or r.t) < Log.RUN_GAP then run = r r.last = now return end
	end
	run = { char = c, where = name, t = now, last = now, bosses = {}, loot = {} }
	t.runs[#t.runs + 1] = run
end
local function Boss(name)
	if not run or type(name) ~= "string" or name == "" then return end
	for _, b in ipairs(run.bosses) do if b == name then return end end
	run.bosses[#run.bosses + 1] = name
	run.last = ns.Now()
	if LAST[name:lower()] then run.done = true end
	ns.Fire("WEEKLOG_CHANGED")
end
Log.Boss = Boss -- (tests)
function Log.OnEncounter(_, name, _, _, success)
	if success == 1 or success == true then Boss(name) end
end
-- Once a second in a dungeon: a boss seen dead (Forever forbids the combat log).
local UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end
function Log.LookForBosses()
	if not run then return end
	for _, u in ipairs(UNITS) do
		local ok, name = pcall(function()
			if UnitExists(u) and UnitIsDead(u) and not UnitIsPlayer(u) then return UnitName(u) end
		end)
		if ok and type(name) == "string" and BOSS[name:lower()] then Boss(name) end
	end
end

-- Our own loot line, rare and better, in a run.
local function Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	return "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
end
local RARE_COLORS = { ff0070dd = true, ffa335ee = true, ffff8000 = true, ffe6cc80 = true }
function Log.OnLoot(text)
	if not run or type(text) ~= "string" then return end
	local mine
	for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE }) do
		local p = Pattern(fmt)
		if p and text:match(p) then mine = true break end
	end
	if not mine then return end
	local link = text:match("|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r")
	local id = link and tonumber(link:match("|Hitem:(%d+)"))
	if not id then return end
	local quality
	if GetItemInfo then
		local ok, _, _, q = pcall(GetItemInfo, link)
		if ok then quality = q end
	end
	local color = link:match("^|c(%x%x%x%x%x%x%x%x)")
	if not ((quality and quality >= 3) or (not quality and color and RARE_COLORS[color:lower()])) then return end
	run.loot[#run.loot + 1] = id
	ns.Fire("WEEKLOG_CHANGED")
end

---------------------------------------------------------------------------
-- Newly Discovered
---------------------------------------------------------------------------

local function Place(name, zone)
	if type(name) ~= "string" or name == "" then return end
	local key = (zone and zone ~= name) and (zone .. "/" .. name) or name
	local seen = Seen()
	if seen[key] then return end
	seen[key] = true
	local t = Store()
	if not t then return end
	t.places[#t.places + 1] = { name = name, zone = zone ~= name and zone or nil, char = Char(), t = ns.Now() }
	ns.Fire("WEEKLOG_CHANGED")
end
function Log.Moved()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	local sub = GetSubZoneText and GetSubZoneText() or ""
	if zone ~= "" then Place(zone) end
	if sub ~= "" then Place(sub, zone) end
end

---------------------------------------------------------------------------
-- Guild Life
---------------------------------------------------------------------------

function Log.SampleGroup()
	if not (IsInGroup and IsInGroup()) then return end
	local t = Store()
	if not t then return end
	local raid = IsInRaid and IsInRaid()
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	local c = Char()
	for i = 1, n do
		local unit = raid and ("raid" .. i) or (i <= 4 and ("party" .. i))
		local ok, name = pcall(function() return unit and UnitName(unit) end)
		if ok and type(name) == "string" and name ~= "" and ns.Roster.RankOf(ns.FullName(name)) ~= nil then
			local key = ns.ShortName(name)
			if key ~= c then
				local m = t.mates[key] or { s = 0, by = {} }
				m.s = (m.s or 0) + Log.SAMPLE
				m.by[c] = true
				t.mates[key] = m
			end
		end
	end
end

---------------------------------------------------------------------------
-- The page's lines (under the five lines) and Share
---------------------------------------------------------------------------

local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end
local function Hours(s)
	local m = math.floor((s or 0) / 60 + 0.5)
	if m < 60 then return L.WEEKLOG_MIN:format(m) end
	return L.WEEKLOG_HOURS:format(math.floor(m / 60), m % 60)
end
local function ItemText(id)
	local name, link = GetItemInfo and GetItemInfo(id)
	return link or name or ("item " .. id)
end

-- (1.3.0: a guildmate's linked characters add up on one line, under their main: Alts.Person.)
local function Mates(t)
	local out, at = {}, {}
	for name, m in pairs(t.mates or {}) do
		local person = ns.Alts and ns.Alts.Person and ns.Alts.Person(name) or name
		local e = at[person]
		if not e then
			e = { name = person, s = 0, by = {} }
			at[person] = e
			out[#out + 1] = e
		end
		e.s = e.s + (m.s or 0)
		for c in pairs(m.by or {}) do e.by[c] = true end
	end
	table.sort(out, function(a, b) if a.s ~= b.s then return a.s > b.s end return a.name < b.name end)
	return out
end
function Log.Summary()
	local t = Store() or { runs = {}, places = {}, mates = {} }
	local done, loot, places = 0, 0, #t.places
	local cleared = {}
	for _, r in ipairs(t.runs) do
		if r.done then done = done + 1 cleared[#cleared + 1] = r.where end
		loot = loot + #(r.loot or {})
	end
	local mates = Mates(t)
	return { runs = #t.runs, done = done, cleared = cleared, loot = loot, places = places, best = mates[1] and mates[1].name }
end
function Log.ShareText()
	local s = Log.Summary()
	local parts = {}
	if s.done > 0 then parts[#parts + 1] = L.WEEKLOG_SHARE_CLEARED:format(s.done, table.concat(s.cleared, ", ")) end
	if s.loot > 0 then parts[#parts + 1] = L.WEEKLOG_SHARE_LOOT:format(s.loot) end
	if s.places > 0 then parts[#parts + 1] = L.WEEKLOG_SHARE_PLACES:format(s.places) end
	if s.best then parts[#parts + 1] = L.WEEKLOG_SHARE_MATE:format(s.best) end
	if #parts == 0 then return nil end
	return ns.Cut(L.WEEKLOG_SHARE:format(table.concat(parts, "; ")), 250)
end
function Log.Share(where)
	local text = Log.ShareText()
	if not text then return ns.Print(L.WEEKLOG_NOTHING) end
	if where == "guild" then
		if not IsInGuild() then return end
		SendChatMessage(text, "GUILD")
	elseif ns.Channels and ns.Channels.Send then
		ns.Channels.Send("A", text)
	end
end

function Log.Lines(lines, q)
	local t = Store()
	if not t then return lines end
	local function Want(...) return not q or ns.Holds(q, ...) end
	-- Dungeons
	lines[#lines + 1] = { header = true, text = L.WEEKLOG_DUNGEONS, right = Grey(tostring(#t.runs)),
		tooltip = function(tt) tt:AddLine(L.WEEKLOG_DUNGEONS, 1, 0.82, 0); tt:AddLine(L.WEEKLOG_DUNGEONS_TIP, 1, 1, 1, true) end }
	if #t.runs == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WEEKLOG_NO_RUNS) } end
	for i = #t.runs, 1, -1 do
		local r = t.runs[i]
		if Want(r.where, r.char) then
			local state = r.done and Green(L.WEEKLOG_COMPLETED) or Grey(L.WEEKLOG_NOT_DONE)
			lines[#lines + 1] = { indent = 1, text = Gold(r.where) .. "  " .. Grey("(" .. r.char .. ")"),
				right = state .. "  " .. Grey(L.WEEKLOG_BOSSES:format(#r.bosses)),
				tooltip = function(tt)
					tt:AddLine(r.where, 1, 0.82, 0)
					for _, b in ipairs(r.bosses) do tt:AddLine(b, 1, 1, 1) end
					if #r.bosses == 0 then tt:AddLine(L.WEEKLOG_NO_BOSSES, 0.6, 0.6, 0.6, true) end
				end }
			if #(r.loot or {}) > 0 then
				local items = {}
				for _, id in ipairs(r.loot) do items[#items + 1] = { id = id } end
				lines[#lines + 1] = { indent = 2, items = items }
			end
		end
	end
	lines[#lines].gapAfter = true
	-- Newly Discovered
	lines[#lines + 1] = { header = true, text = L.WEEKLOG_PLACES, right = Grey(tostring(#t.places)),
		tooltip = function(tt) tt:AddLine(L.WEEKLOG_PLACES, 1, 0.82, 0); tt:AddLine(L.WEEKLOG_PLACES_TIP, 1, 1, 1, true) end }
	if #t.places == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WEEKLOG_NO_PLACES) } end
	local shown = 0
	for i = #t.places, 1, -1 do
		local p = t.places[i]
		if shown < Log.PLACES_SHOWN and Want(p.name, p.zone, p.char) then
			shown = shown + 1
			lines[#lines + 1] = { indent = 1, text = p.name .. (p.zone and Grey("  " .. p.zone) or ""), right = Grey(p.char) }
		end
	end
	if #t.places > shown and not q then lines[#lines + 1] = { indent = 1, text = Grey(L.AND_MORE:format(#t.places - shown)) } end
	lines[#lines].gapAfter = true
	-- Guild Life
	local mates = Mates(t)
	lines[#lines + 1] = { header = true, text = L.WEEKLOG_MATES,
		tooltip = function(tt) tt:AddLine(L.WEEKLOG_MATES, 1, 0.82, 0); tt:AddLine(L.WEEKLOG_MATES_TIP, 1, 1, 1, true) end }
	if #mates == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WEEKLOG_NO_MATES) } end
	for i = 1, math.min(Log.MATES_SHOWN, #mates) do
		local m = mates[i]
		if Want(m.name) then
			local by = {}
			for c in pairs(m.by) do by[#by + 1] = c end
			table.sort(by)
			lines[#lines + 1] = { indent = 1, text = m.name, right = Gold(Hours(m.s)) .. "  " .. Grey(table.concat(by, ", ")) }
		end
	end
	lines[#lines].gapAfter = true
	-- Share (the player's click alone)
	if not q then
		lines[#lines + 1] = { text = Gold(L.WEEKLOG_SHARE_GUILD), onClick = function() Log.Share("guild") end,
			tooltip = function(tt) tt:AddLine(L.WEEKLOG_SHARE_GUILD, 1, 0.82, 0); tt:AddLine(Log.ShareText() or L.WEEKLOG_NOTHING, 1, 1, 1, true) end }
		lines[#lines + 1] = { text = Gold(L.WEEKLOG_SHARE_SYL), onClick = function() Log.Share("sylvanistas") end,
			tooltip = function(tt) tt:AddLine(L.WEEKLOG_SHARE_SYL, 1, 0.82, 0); tt:AddLine(Log.ShareText() or L.WEEKLOG_NOTHING, 1, 1, 1, true) end }
	end
	return lines
end

ns.On("LOGIN", function()
	pcall(ns.RegisterEvent, "ENCOUNTER_END", function(...) ns.SafeCall("weeklog boss", Log.OnEncounter, ...) end)
	ns.RegisterEvent("CHAT_MSG_LOOT", function(text) ns.SafeCall("weeklog loot", Log.OnLoot, text) end)
	for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns.RegisterEvent(e, function()
			ns.SafeCall("weeklog moved", Log.Moved)
			ns.SafeCall("weeklog entered", Entered)
		end)
	end
	ns.Every(1, "weeklog bosses", function() ns.SafeCall("weeklog bosses", Log.LookForBosses) end)
	ns.Every(Log.SAMPLE, "weeklog group", function() ns.SafeCall("weeklog group", Log.SampleGroup) end)
	ns.After(5, "weeklog start", function() ns.SafeCall("weeklog moved", Log.Moved); ns.SafeCall("weeklog entered", Entered) end)
end)
