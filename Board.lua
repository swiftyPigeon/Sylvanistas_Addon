local ADDON, ns = ...
local L = ns.L

-- The Board (1.1, a moderator's): who is looking for a group, and where, from what each player chose to
-- share. One click raises a flag (a dungeon, a raid, PvP or a layer) with a short note if the
-- player wants one; the card shows the poster's zone only while they share it (/syl location on)
-- and says the zone is hidden otherwise. A click on someone else's card whispers them. Nothing
-- here invites, queues or forms a group: the whisper is the player's own, and so is any invite
-- that follows (the game's own, from the person card or the chat). A page of the Realm tab, like
-- the Sylvanistas chats (Views.lua); /syl lfg opens it.
-- A camp (request #25) is the same message with flag C: the player drops it where they stand, it
-- carries the zone and nothing finer, it needs their /syl location on, and it ends by itself
-- after CAMP_LIFE. Each player holds one flag and one camp.
--   G1~<id>~<guild>~<flag>~<level>~<class>~<every>~<age>~<zone>~<note>
--       id     1-2 base-36 characters, new for each raise and kept by its refreshes
--       flag   D dungeon, R raid, P PvP, L layer; C a camp (its zone is never empty)
--       level  1-99; class the chats' two-letter code, or empty
--       every  minutes to its next refresh (10-30): the poster repeats it for late logins
--       age    minutes since it was raised: it ends LIFETIME after that, on every client
--       zone   the uiMapID of the poster's zone, empty while they keep it private
--       note   the poster's own words, NOTE_MAX bytes at most, the last field: sent with the
--              logged API (the server keeps them, so abuse can be reported); one sent without
--              it, where this client has both, shows without its words (as a decree's)
--       x, y   1.3.0, a camp only, after the note: its spot on its zone's map, 0-1000 each (where
--              the player stood, or lit the campfire); older clients read up to the note and
--              keep the zone badge, newer ones put a campfire there on the world map and minimap
--   G0~<id>   lowered by its poster; also sent for the old flag when a new one takes its place
--             (1.1 review), so every Board lets the new one in at once
--   GQ~       a client opened the Board: flag holders answer it alone, by whisper, with their
--             G1, so a player who just logged in sees the Board without waiting for refreshes
-- Clients before 1.1 have no handler for G1, G0 or GQ: they leave them unread.
-- A poster the moderators took off (net-off, Moderation.lua; 1.1, review): his flags and
-- camps (their map badges too) leave every Board and no new one is taken, and his own client
-- raises none and sends no G1.

local Board = {}
ns.Board = Board

Board.FLAGS = { "D", "R", "P", "L" } -- in the order the flag window offers them (Board.Offered)
Board.LABEL = { D = "BOARD_FLAG_D", R = "BOARD_FLAG_R", P = "BOARD_FLAG_P", L = "BOARD_FLAG_L" }
Board.MAX = 150              -- flags kept on the Board; past it, the one ending soonest goes
Board.RAISE_GAP = 30         -- seconds between two raises
Board.RAISES_PER_HOUR = 3
Board.LIFETIME = 60 * 60     -- a flag is lowered an hour after it was raised
Board.SLACK = 5 * 60         -- ...and leaves every Board this long after that at the latest
Board.NEW_ID_GAP = 20        -- a sender's new flag replaces its old one at most this often: below RAISE_GAP,
                             -- so a raise the poster's client allowed is never dropped (and a G0 of his
                             -- that took his card down lets the next one in at once)
Board.NOTE_MAX = 40          -- bytes of a note (a letter is never cut in half)
Board.LOWERED_TTL = 10 * 60  -- a lowered id stays lowered this long (a late G1 can't bring it back)
Board.EVERY_MIN, Board.EVERY_MAX = 10, 30 -- minutes between refreshes, by how full the Board is
Board.ASK_AFTER = 20         -- seconds on the channel before the Board's ask
Board.ASK_BRAKE = 4          -- asks heard in a minute past which nobody answers, and ours waits
Board.ASK_TRIES = 3
Board.ANSWER_WINDOW = 120    -- whispered flags are taken this long after our ask, never otherwise
Board.ANSWERS_PER_MIN = 6    -- whispered answers a holder sends in a minute
Board.ANSWER_REPEAT = 10 * 60 -- one answer to the same asker in that long
Board.ANSWER_TARGET = 40     -- about this many holders answer one ask, however full the Board is
Board.ANSWER_QUEUE = 30      -- no answer while our own send queue is this long
Board.CAMP_LIFE = 30 * 60    -- a camp ends by itself (a Muster's time)
Board.CAMP_EVERY = 10        -- minutes between a camp's refreshes
Board.CAMP_GAP = 10 * 60     -- one new camp every 10 minutes per character
Board.CAMP_MAX = 60          -- camps kept on the Board
Board.CAMP_BADGE = 18        -- a camp badge on the world map
Board.CAMP_ICON = "Interface\\Icons\\Spell_Fire_Fire"
Board.CAMP_PIN = 16          -- a camp's campfire at its spot on the world map (1.3.0)
Board.CAMP_PIN_MINI = 14     -- and on the minimap
Board.CAMPFIRE_SPELL = 818   -- Basic Campfire: lighting one offers to drop a camp there (1.3.0)

-- Swappable in tests.
Board.after = function(seconds, where, fn) ns.After(seconds, where, fn) end
Board.random = math.random

local posts = {}             -- [Name-Realm] (a camp: [Name-Realm|camp]) = { sender, id, guild, flag, level, class, every, zone, note, raisedAt, heardAt, firstSeen, via }
local lastNewId = {}         -- [Name-Realm|slot] = when its last new id was taken
local lowered = {}           -- ["Name-Realm#id"] = when it was lowered
local own = {}               -- our own posts by slot, own.flag our flag: { id, flag, note, zone, raisedAt, sentAt, every }
local usedIds = {}           -- [id] = when we last took it: a new post never takes one a Board may still hold lowered
local lastRaise, raises, lastCamp = -math.huge, {}, -math.huge
local asks, answered, answersSent = {}, {}, {}
local askSent, askTries, askAt, askRetryAt, askWanted = false, 0, nil, nil, false
local answersGiven = 0

local function Gold(s) return "|cffffd200" .. s .. "|r" end
local function Grey(s) return "|cff9d9d9d" .. s .. "|r" end
local function Green(s) return "|cff40ff40" .. s .. "|r" end

local function Label(flag) return L[Board.LABEL[flag] or ("BOARD_FLAG_" .. tostring(flag))] end

-- 1.3.0 (the user's call): the kinds the flag window offers. PvP only on a PvP realm (ns.PVP_REALM,
-- Core.lua; unset, a realm named "...PvP..."): a PvP flag from elsewhere (/syl lfg pvp, an older
-- client) still shows on the Board.
function Board.PvPRealm()
	if ns.PVP_REALM ~= nil then return ns.PVP_REALM == true end
	return tostring(ns.CurrentRealm and ns.CurrentRealm() or ""):lower():find("pvp", 1, true) ~= nil
end
function Board.Offered()
	local out = {}
	for _, flag in ipairs(Board.FLAGS) do
		if flag ~= "P" or Board.PvPRealm() then out[#out + 1] = flag end
	end
	return out
end
function Board.MyFlag() return own.flag end
Board.Label = Label

-- The page and the tree's link redraw at most once a second, whatever arrives.
local changePending = false
local function Changed()
	if changePending then return end
	changePending = true
	Board.after(1, "board changed", function()
		changePending = false
		ns.Fire("BOARD_CHANGED")
	end)
end

---------------------------------------------------------------------------
-- The message
---------------------------------------------------------------------------

-- A note as it may travel and show: one line, no escape code ("|") and no field separator
-- ("~"), runs of spaces as one, NOTE_MAX bytes at most.
function Board.CleanNote(s)
	s = tostring(s or ""):gsub("[%c|~]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, Board.NOTE_MAX)
end

local function CleanGuild(s) return (tostring(s or ""):gsub("[~|%c]", "")) end
-- WoW limits guild names to 24 characters (Codec's rule: an accented letter takes 2 or 3 bytes).
local function LongGuild(guild)
	return #guild > 72 or select(2, guild:gsub("[^\128-\191]", "")) > 24
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function RandomId()
	local n = Board.random(1, 36 * 36 - 1)
	local hi, lo = math.floor(n / 36), n % 36
	return (hi > 0 and B36:sub(hi + 1, hi + 1) or "") .. B36:sub(lo + 1, lo + 1)
end
-- A new post's id: not one of ours of the last LOWERED_TTL (every Board keeps a lowered id out
-- that long, so a new flag under it would be left out).
local function NewId(now)
	now = now or ns.Now()
	for id, t in pairs(usedIds) do if now - t > Board.LOWERED_TTL then usedIds[id] = nil end end
	local id = RandomId()
	for _ = 1, 8 do
		if not usedIds[id] then break end
		id = RandomId()
	end
	usedIds[id] = now
	return id
end

-- Which flags a message may carry (Board.KINDS: every kind this version reads; a kind it does
-- not know drops the message, so later ones can add theirs) and how long each one lasts.
Board.KINDS = { D = true, R = true, P = true, L = true, C = true }
local function Life(flag) return flag == "C" and Board.CAMP_LIFE or Board.LIFETIME end

function Board.Encode(e)
	local zone = tonumber(e.zone) and tostring(math.floor(e.zone)) or ""
	return ("G1~%s~%s~%s~%d~%s~%d~%d~%s~%s"):format(e.id, CleanGuild(e.guild), e.flag, math.floor(tonumber(e.level) or 1),
		tostring(e.class or ""), e.every, math.max(0, math.floor(tonumber(e.age) or 0)), zone, Board.CleanNote(e.note))
		.. ((e.flag == "C" and tonumber(e.x) and tonumber(e.y)) and ("~%d~%d"):format(e.x, e.y) or "")
end

-- The G1 as a table, or nil for anything malformed. Fields past the note are left for later versions.
function Board.Decode(s)
	if type(s) ~= "string" then return nil end
	local id, guild, flag, level, class, every, age, zone, rest = s:match("^G1~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)~?(.*)$")
	if not id or not id:find("^[0-9a-z][0-9a-z]?$") or not Board.KINDS[flag] then return nil end
	if guild == "" or LongGuild(guild) then return nil end
	level, every, age = tonumber(level:match("^%d%d?$") or ""), tonumber(every:match("^%d%d?$") or ""), tonumber(age:match("^%d%d?%d?$") or "")
	if not level or level < 1 or not every or every < Board.EVERY_MIN or every > Board.EVERY_MAX then return nil end
	if not age or age * 60 > Life(flag) then return nil end
	if class ~= "" and not class:find("^%u%u$") then return nil end
	if zone ~= "" and not zone:find("^%d%d?%d?%d?%d?%d?$") then return nil end
	if flag == "C" and zone == "" then return nil end -- (a camp is its zone)
	-- 1.3.0: a camp's spot, after the note (both or neither, each 0-1000).
	local x, y
	if flag == "C" then
		x, y = rest:match("^[^~]*~(%d%d?%d?%d?)~(%d%d?%d?%d?)")
		x, y = tonumber(x), tonumber(y)
		if not x or not y or x > 1000 or y > 1000 then x, y = nil, nil end
	end
	return { id = id, guild = guild, flag = flag, level = level, class = class, every = every, age = age,
		zone = tonumber(zone), x = x, y = y, note = Board.CleanNote(rest:match("^[^~]*")) }
end

---------------------------------------------------------------------------
-- The Board as this client holds it
---------------------------------------------------------------------------

local function Expires(e)
	local life = Life(e.flag)
	return math.min(e.raisedAt + life, e.firstSeen + life + Board.SLACK, e.heardAt + (2 * e.every + 1) * 60)
end
Board.Expires = Expires

-- Which of a sender's posts a flag takes: one flag each, and one camp.
local function SlotOf(flag) return flag == "C" and "camp" or "flag" end
local function Key(sender, slot) return slot == "flag" and sender or (sender .. "|" .. slot) end

-- A poster the moderators took off (net-off, Moderation.lua), in the name of `guild`.
local function Off(sender, guild)
	local M = ns.Moderation
	return M.Hides ~= nil and M.Hides(sender, guild) ~= nil
end

-- A post past its end leaves, and its id stays out like a lowered one: a refresh that still
-- comes (a sender claiming it was raised just now) can't bring it back. A post of one the
-- moderators took off since leaves too (1.1, review), its id not held: put back on, his
-- next refresh shows it again.
local function Prune(now)
	for key, e in pairs(posts) do
		if now >= Expires(e) then
			posts[key] = nil
			lowered[e.sender .. "#" .. e.id] = now
		elseif Off(e.sender, e.guild) then
			posts[key] = nil
		end
	end
	for key, t in pairs(lowered) do
		if now - t > Board.LOWERED_TTL then lowered[key] = nil end
	end
end

-- How many posts of a slot ("flag") are on the Board now, and the one of them ending soonest.
function Board.Count(slot, now)
	now = now or ns.Now()
	local n, soonest, which = 0, nil, nil
	for key, e in pairs(posts) do
		if now < Expires(e) and (not slot or SlotOf(e.flag) == slot) and not Off(e.sender, e.guild) then
			n = n + 1
			local x = Expires(e)
			if not soonest or x < soonest then soonest, which = x, key end
		end
	end
	return n, which
end

-- The posts of a slot, newest first: { sender, id, guild, flag, level, class, zone, note, raisedAt, ... }.
function Board.List(slot, now)
	now = now or ns.Now()
	Prune(now)
	local out = {}
	for _, e in pairs(posts) do
		if SlotOf(e.flag) == (slot or "flag") then out[#out + 1] = e end
	end
	table.sort(out, function(a, b)
		if a.raisedAt ~= b.raisedAt then return a.raisedAt > b.raisedAt end
		return a.sender < b.sender
	end)
	return out
end

local function Ignored(sender)
	local api = C_FriendList and C_FriendList.IsIgnored
	if not api then return false end
	local ok, res = pcall(api, ns.DisplayName(sender))
	return ok and res == true
end

-- A G1 from the channel, or whispered in answer to our ask.
function Board.HandlePost(dist, sender, text)
	local now = ns.Now()
	if dist == "WHISPER" then
		if not askAt or now - askAt > Board.ANSWER_WINDOW then return end
	elseif dist ~= "CHANNEL" then
		return
	end
	local e = Board.Decode(text)
	if not e or not ns.IsFederation(e.guild) then return end
	sender = ns.FullName(sender)
	if sender == ns.me or Ignored(sender) then return end
	-- 1.1 (review): a name the moderators took off (net-off, Moderation.lua): no flag or
	-- camp of his, and the ones he had leave the Board.
	if Off(sender, e.guild) then
		if posts[sender] or posts[Key(sender, "camp")] then
			posts[sender], posts[Key(sender, "camp")] = nil, nil
			Changed()
		end
		return
	end
	-- One guild per sender, as the chats: our own guild's name only from our roster.
	local own = GetGuildInfo("player")
	if own and e.guild == own then
		if not ns.Roster.RankOf(sender) then return end
	elseif not ns.Data.ClaimGuild(sender, e.guild) then
		return
	end
	-- Its words through the logged API, as a decree's.
	if e.note ~= "" and C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		ns.Log("board flag from %s shown without its note: not sent with the logged API", sender)
		e.note = ""
	end
	Prune(now)
	if lowered[sender .. "#" .. e.id] then return end
	local slot = SlotOf(e.flag)
	local key = Key(sender, slot)
	local old = posts[key]
	local raisedAt = now - e.age * 60
	if old and old.id == e.id then
		old.guild, old.flag, old.level, old.class, old.every, old.zone, old.note = e.guild, e.flag, e.level, e.class, e.every, e.zone, e.note
		old.x, old.y = e.x, e.y
		old.raisedAt, old.heardAt = math.min(old.raisedAt, raisedAt), now
		return Changed()
	end
	if lastNewId[sender .. "|" .. slot] and now - lastNewId[sender .. "|" .. slot] < Board.NEW_ID_GAP then return end
	if not old then
		local n, soonest = Board.Count(slot, now)
		local cap = slot == "camp" and Board.CAMP_MAX or Board.MAX
		if n >= cap and soonest then posts[soonest] = nil end
	end
	lastNewId[sender .. "|" .. slot] = now
	e.sender, e.raisedAt, e.heardAt, e.firstSeen, e.via = sender, raisedAt, now, now, dist
	posts[key] = e
	Changed()
end

function Board.HandleLower(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local id = text:match("^G0~([0-9a-z][0-9a-z]?)$")
	if not id then return end
	sender = ns.FullName(sender)
	lowered[sender .. "#" .. id] = ns.Now()
	for key, e in pairs(posts) do
		if e.sender == sender and e.id == id then
			posts[key] = nil
			-- His card is down: his next flag (the one taking its place) shows at once.
			lastNewId[sender .. "|" .. SlotOf(e.flag)] = nil
			Changed()
		end
	end
end

---------------------------------------------------------------------------
-- Our own flag
---------------------------------------------------------------------------

local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end

-- Our zone, only while we share it (/syl location, Layers.Sharing): never in an instance, never a
-- continent (Layers.CurrentMap).
local function SharedZone()
	if not (ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()) then return nil end
	if IsInInstance and IsInInstance() then return nil end
	return ns.Layers.CurrentMap and ns.Layers.CurrentMap() or nil
end
Board.SharedZone = SharedZone

-- Minutes between refreshes: 10 while the Board is small, up to 30 when it is full (12 seconds a
-- post), so the channel carries about the same whatever the crowd.
function Board.Interval(n)
	n = n or Board.Count()
	return math.max(Board.EVERY_MIN, math.min(Board.EVERY_MAX, math.ceil(n * 12 / 60)))
end

local function MyClass()
	local class = ns.Roster.ClassCode(UnitClass and select(2, UnitClass("player")))
	return class:match("^%u%u$") and class or ""
end
local function MyLevel()
	local level = UnitLevel and UnitLevel("player") or 1
	return math.max(1, math.min(99, tonumber(level) or 1))
end

-- The G1 for one of our posts as it stands now: a flag's zone read again each time (where we
-- are, and none the moment the player stops sharing); a camp keeps its own (where it was dropped).
local function Message(p, now)
	if p.flag ~= "C" then p.zone = SharedZone() end
	return Board.Encode({ id = p.id, guild = GetGuildInfo("player"), flag = p.flag, level = MyLevel(), class = MyClass(),
		every = p.every, age = math.floor((now - p.raisedAt) / 60), zone = p.zone, x = p.x, y = p.y, note = p.note })
end

-- Our posts are kept for a /reload (per character, SavedVariables): still up on everyone's
-- Board, they go on being repeated, and a click still lowers them. Never raised again: one
-- that has ended, or that nobody heard for two of its refreshes, is forgotten.
local function Save()
	if not ns.rdb then return end
	local all = type(ns.rdb.board) == "table" and ns.rdb.board or {}
	local copy = {}
	for slot, p in pairs(own) do
		copy[slot] = { id = p.id, flag = p.flag, note = p.note, zone = p.zone, x = p.x, y = p.y, raisedAt = p.raisedAt, sentAt = p.sentAt, every = p.every }
	end
	all[ns.me or "?"] = next(copy) and copy or nil
	ns.rdb.board = next(all) and all or nil
end

function Board.Restore(now)
	now = now or ns.Now()
	local all = ns.rdb and ns.rdb.board
	local saved = type(all) == "table" and all[ns.me or "?"]
	if type(saved) ~= "table" then return end
	for slot, p in pairs(saved) do
		local fine = type(p) == "table" and type(p.id) == "string" and p.id:find("^[0-9a-z][0-9a-z]?$") and Board.KINDS[p.flag]
			and SlotOf(p.flag) == slot and tonumber(p.raisedAt) and tonumber(p.sentAt) and tonumber(p.every)
		if fine and not own[slot] and now - p.raisedAt < Life(p.flag) and now < p.sentAt + (2 * p.every + 1) * 60 then
			local x, y = tonumber(p.x), tonumber(p.y)
			if not (x and y and x >= 0 and x <= 1000 and y >= 0 and y <= 1000) then x, y = nil, nil end
			own[slot] = { id = p.id, flag = p.flag, note = Board.CleanNote(p.note), zone = tonumber(p.zone), x = x, y = y,
				raisedAt = p.raisedAt, sentAt = p.sentAt, every = p.every }
			usedIds[p.id] = now
		end
	end
	Save()
end

-- The send queue's key of a post: one per post, so its refresh waiting to go gives way to its
-- G0, and a new post never takes the place of the old one's G0 (Comm's queue keeps one message
-- per key).
local function QueueKey(p) return (SlotOf(p.flag) == "flag" and "banner" or SlotOf(p.flag)) .. p.id end

local function Send(p, now)
	p.every = p.flag == "C" and Board.CAMP_EVERY or Board.Interval()
	p.sentAt = now
	-- Its note, the player's own words, through the logged API (Comm.Send).
	ns.Comm.Send("CHANNEL", Message(p, now), QueueKey(p), nil, p.note ~= "")
	Save()
end
Board.Send = Send

-- Whether we can put anything on the Board now: a member, on the channel, not in lockdown, not off.
function Board.Ready()
	if not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return false, "member"
	end
	if not ns.Comm.ChannelReady() then
		ns.Print(L.CHAN_NOT_READY)
		return false, "ready"
	end
	if Locked() then
		ns.Print(L.CHAN_LOCKDOWN)
		return false, "lockdown"
	end
	-- 1.1 (review): the moderators took this character off (net-off, Moderation.lua):
	-- nobody would see it.
	local M = ns.Moderation
	local off = M.SelfOff and M.SelfOff()
	if off then
		ns.Print(M.YouText(off))
		return false, "netoff"
	end
	return true
end

-- One click: our flag goes up (it replaces the one we had), with the note typed in the dialog.
function Board.Raise(flag, note)
	if not Board.LABEL[flag] then return false, "flag" end
	local ok, why = Board.Ready()
	if not ok then return false, why end
	local now = ns.Now()
	if now - lastRaise < Board.RAISE_GAP then
		ns.Print(L.BOARD_WAIT:format(math.ceil(Board.RAISE_GAP - (now - lastRaise))))
		return false, "wait"
	end
	for i = #raises, 1, -1 do if now - raises[i] >= 3600 then table.remove(raises, i) end end
	if #raises >= Board.RAISES_PER_HOUR then
		ns.Print(L.BOARD_HOURLY:format(Board.RAISES_PER_HOUR))
		return false, "hourly"
	end
	if not own.flag and Board.Count("flag", now) >= Board.MAX then
		ns.Print(L.BOARD_FULL)
		return false, "full"
	end
	lastRaise = now
	raises[#raises + 1] = now
	-- The flag it replaces comes down first, on every Board (its G0 ahead of the new one).
	local old = own.flag
	if old then ns.Comm.Send("CHANNEL", "G0~" .. old.id, QueueKey(old)) end
	local mine = { id = NewId(now), flag = flag, note = Board.CleanNote(note), raisedAt = now }
	own.flag = mine
	Send(mine, now)
	local zone = mine.zone and ns.Zones.NameForKey("m" .. mine.zone)
	ns.Print(zone and L.BOARD_RAISED:format(Label(flag), zone) or L.BOARD_RAISED_HIDDEN:format(Label(flag)))
	Changed()
	return true
end

-- Lowered by its poster: the Board's G0 (it takes the place of a refresh still waiting to go).
-- `slot`: which of ours ("flag" when none is named).
local function LowerPost(slot)
	local p = own[slot or "flag"]
	if not p then return false end
	ns.Comm.Send("CHANNEL", "G0~" .. p.id, QueueKey(p))
	own[slot or "flag"] = nil
	Save()
	Changed()
	return true
end
Board.LowerPost = LowerPost

function Board.Lower(quiet)
	if not LowerPost("flag") then return false end
	if not quiet then ns.Print(L.BOARD_LOWERED) end
	return true
end

-- A camp (request #25), dropped where we stand: its zone and (1.3.0, the user's call) its spot,
-- where we stand as it is dropped (a campfire's, lit just before), fixed from then on: never
-- where we go after. Only while we share our location (/syl location on), one every CAMP_GAP,
-- ending by itself after CAMP_LIFE. It takes the place of our last one.
function Board.CampZone()
	if not (ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()) then return nil, "private" end
	local zone = SharedZone()
	if not zone then return nil, "zone" end
	return zone
end

-- Where we stand on `zone`'s map, 0-1000 each, or nil (an instance, a map without positions).
function Board.SpotIn(zone)
	local pos = zone and C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(zone, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or not y or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

-- Seconds before another camp may go up (0: now).
function Board.CampWait(now)
	return math.max(0, Board.CAMP_GAP - ((now or ns.Now()) - lastCamp))
end

function Board.DropCamp(note)
	local ok, why = Board.Ready()
	if not ok then return false, why end
	local zone, no = Board.CampZone()
	if not zone then
		ns.Print(no == "private" and L.BOARD_CAMP_NEEDS_LOCATION or L.BOARD_CAMP_NO_ZONE)
		return false, no
	end
	local now = ns.Now()
	if now - lastCamp < Board.CAMP_GAP then
		ns.Print(L.BOARD_CAMP_WAIT:format(math.ceil((Board.CAMP_GAP - (now - lastCamp)) / 60)))
		return false, "wait"
	end
	if not own.camp and Board.Count("camp", now) >= Board.CAMP_MAX then
		ns.Print(L.BOARD_FULL)
		return false, "full"
	end
	lastCamp = now
	local x, y = Board.SpotIn(zone)
	own.camp = { id = NewId(now), flag = "C", note = Board.CleanNote(note), zone = zone, x = x, y = y, raisedAt = now }
	Send(own.camp, now)
	ns.Print(L.BOARD_CAMP_DROPPED:format(ns.Zones.NameForKey("m" .. zone)))
	Changed()
	return true
end

function Board.LowerCamp(quiet)
	if not LowerPost("camp") then return false end
	if not quiet then ns.Print(L.BOARD_CAMP_LOWERED) end
	return true
end

function Board.Mine() return own.flag end
function Board.MineIn(slot) return own[slot] end

---------------------------------------------------------------------------
-- The ask of a client that opened the Board (GQ), and the whispered answers
---------------------------------------------------------------------------

local function Recent(list, now, span)
	for i = #list, 1, -1 do if now - list[i] >= span then table.remove(list, i) end end
	return #list
end

-- Once a session, when the Board is first opened: the holders of the flags up now answer us
-- alone. Not while the channel was just joined, nor while others just asked (their answers are
-- on their way to them; ours waits, ASK_TRIES times, then the refreshes fill the Board).
function Board.Ask(now)
	now = now or ns.Now()
	if askSent then return false end
	askWanted = true
	if not ns.IsMember() or not ns.Comm.ChannelReady() then return false end
	if now - (ns.Comm.joinedAt or -math.huge) < Board.ASK_AFTER then
		askRetryAt = (ns.Comm.joinedAt or now) + Board.ASK_AFTER
		return false
	end
	if askRetryAt and now < askRetryAt then return false end
	if Recent(asks, now, 60) >= Board.ASK_BRAKE then
		askTries = askTries + 1
		if askTries >= Board.ASK_TRIES then askSent = true return false end
		askRetryAt = now + Board.random(30, 90)
		return false
	end
	askSent, askAt, askRetryAt = true, now, nil
	ns.Comm.Send("CHANNEL", "GQ~", "boardask")
	return true
end

-- Every post of ours, whispered to one asker (its note through the logged API).
local function Answer(asker)
	local now = ns.Now()
	for _, p in ipairs(Board.Own()) do
		ns.Comm.Whisper(asker, Message(p, now), nil, nil, p.note ~= "")
	end
end

function Board.HandleAsk(dist, sender, text)
	if dist ~= "CHANNEL" or text:sub(1, 3) ~= "GQ~" then return end
	local now = ns.Now()
	asks[#asks + 1] = now
	-- The first asks of a minute only: a crowd logging in at once doesn't flood the holders.
	if Recent(asks, now, 60) > Board.ASK_BRAKE then return end
	if #Board.Own() == 0 then return end
	sender = ns.FullName(sender)
	if answered[sender] and now - answered[sender] < Board.ANSWER_REPEAT then return end
	if Recent(answersSent, now, 60) >= Board.ANSWERS_PER_MIN then return end
	if ns.Comm.QueueSize() >= Board.ANSWER_QUEUE or Locked() then return end
	-- A full Board: only a share of its holders answer (about ANSWER_TARGET in all).
	if Board.random() > math.min(1, Board.ANSWER_TARGET / math.max(1, (Board.Count()))) then return end
	answered[sender] = now
	answersSent[#answersSent + 1] = now
	answersGiven = answersGiven + 1
	Board.after(Board.random(1, 20), "board answer", function() Answer(sender) end)
end

-- Our posts up now (our flag, and whatever else is ours: a camp).
function Board.Own()
	local out = {}
	for _, p in pairs(own) do out[#out + 1] = p end
	table.sort(out, function(a, b) return a.flag < b.flag end)
	return out
end

-- Every 30 seconds: our flag refreshed or lowered at the end of its hour, the Board pruned, and
-- our ask sent once the channel lets it.
function Board.Tick(now)
	now = now or ns.Now()
	local mine = own.flag
	if mine then
		if not ns.IsMember() then
			own.flag = nil
			Save()
			Changed()
		elseif now - mine.raisedAt >= Board.LIFETIME then
			Board.Lower(true)
			ns.Print(L.BOARD_LOWERED_HOUR)
		elseif now - (mine.sentAt or -math.huge) >= mine.every * 60 or (mine.zone and not SharedZone()) then
			-- (Its zone leaves every card within 30 seconds of the player's /syl location off.)
			Send(mine, now)
		end
	end
	-- Our camp: ended after CAMP_LIFE, taken down the moment we stop sharing our location.
	local camp = own.camp
	if camp then
		if not ns.IsMember() then
			own.camp = nil
			Save()
			Changed()
		elseif now - camp.raisedAt >= Board.CAMP_LIFE then
			Board.LowerCamp(true)
			ns.Print(L.BOARD_CAMP_ENDED)
		elseif not (ns.Layers and ns.Layers.Sharing and ns.Layers.Sharing()) then
			Board.LowerCamp(true)
			ns.Print(L.BOARD_CAMP_PRIVATE)
		elseif now - (camp.sentAt or -math.huge) >= camp.every * 60 then
			Send(camp, now)
		end
	end
	ns.SafeCall("board camps", Board.RefreshCamps)
	Prune(now)
	if askWanted and not askSent then Board.Ask(now) end
end

---------------------------------------------------------------------------
-- The page (a page of the Realm tab: Views.ShowBoard)
---------------------------------------------------------------------------

-- A note as this screen shows it: none on the King's (his stream): only names reach it.
function Board.NoteShown(e)
	if not e or e.note == "" or ns.KingsScreen() then return "" end
	return e.note
end

function Board.ZoneText(zone)
	if zone then return ns.Zones.NameForKey("m" .. zone) end
	return Grey(L.BOARD_ZONE_HIDDEN)
end

-- The whisper is the player's own, in Sylvanistas's whisper window (1.3.0, the user's call: never
-- the game's chat box, whose opening from addon code taints LAST_ACTIVE_CHAT_EDIT_BOX and gets the
-- player's own /cast or /target blocked afterwards).
function Board.Whisper(name)
	return ns.UI.WhisperWindow(ns.TellName(name) or name)
end

local function Colored(name, class)
	local file = class and class ~= "" and ns.CLASS_FILES[class]
	local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	name = ns.Codec.Plain(name)
	return c and c.colorStr and ("|c%s%s|r"):format(c.colorStr, name) or name
end

-- A card: its flag, who and their guild, the note; on the right the zone (or that it is hidden)
-- and how long it has been up. A click whispers its poster.
-- A camp's card leads with its zone (where the fire is), and says how long it has left.
function Board.Card(e)
	local who = ns.DisplayName(e.sender) or "?"
	local note = Board.NoteShown(e)
	local classFile = e.class ~= "" and ns.CLASS_FILES[e.class]
	local camp = e.flag == "C"
	return {
		text = Gold("[" .. Label(e.flag) .. "]") .. " " .. (camp and (Board.ZoneText(e.zone) .. ": ") or "") .. Colored(who, e.class) .. " "
			.. Green("<" .. ns.Codec.Plain(e.guild) .. ">") .. (note ~= "" and ("  " .. '"' .. note .. '"') or ""),
		right = camp and Grey(L.BOARD_CAMP_LEFT:format(math.max(1, math.ceil((e.raisedAt + Board.CAMP_LIFE - ns.Now()) / 60))))
			or (Board.ZoneText(e.zone) .. "  " .. Grey(ns.Ago(e.raisedAt))),
		onClick = function() Board.Whisper(e.sender) end,
		tooltip = function(tt)
			tt:AddLine(Label(e.flag) .. ": " .. who, 1, 0.82, 0)
			tt:AddLine(("<%s>  %s"):format(ns.Codec.Plain(e.guild), L.LEVEL_N:format(e.level))
				.. (classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] and ("  " .. LOCALIZED_CLASS_NAMES_MALE[classFile]) or ""), 1, 1, 1)
			if note ~= "" then tt:AddLine('"' .. note .. '"', 1, 1, 1, true) end
			tt:AddLine(e.zone and L.BOARD_ZONE_IS:format(Board.ZoneText(e.zone)) or L.BOARD_ZONE_HIDDEN_TIP, 0.8, 0.8, 0.8, true)
			tt:AddLine(L.BOARD_CARD_TIP:format(who), 0.6, 0.6, 0.6, true)
		end,
	}
end

-- What the dialog says before a flag goes up: who reads it, and whether the zone goes with it.
function Board.PrivacyText(zoneTaken)
	local zone = zoneTaken and ns.Zones.NameForKey("m" .. zoneTaken)
	return (zone and L.BOARD_ASK_ZONE:format(zone) or L.BOARD_ASK_NO_ZONE) .. "\n" .. ns.Comm.Audience()
end

---------------------------------------------------------------------------
-- The flag window (1.3.0, the user's call: one "Raise a flag" button in place of a row per kind):
-- the kind (a button each, Board.Offered), a short note (optional), what goes out with it. Raised
-- with Raise or Enter in the note, once a kind is picked. Sylvanistas's own window (no game popup:
-- the same with the gamepad UI and a guild window open).
---------------------------------------------------------------------------

local picker

local function Text(parent, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
	fs:SetJustifyH("LEFT")
	return fs
end

local function MakePicker()
	local ok, f = pcall(CreateFrame, "Frame", "SylvanistasFlagFrame", UIParent, "BasicFrameTemplateWithInset")
	if not ok or not f then f = CreateFrame("Frame", "SylvanistasFlagFrame", UIParent) end
	f:SetSize(360, 240)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.TitleText then
		f.TitleText:SetText(L.BOARD_PICK_TITLE)
	else
		local t = Text(f, "GameFontNormal")
		t:SetText(L.BOARD_PICK_TITLE)
		t:SetPoint("TOP", 0, -6)
	end
	local k = Text(f)
	k:SetText(L.BOARD_PICK_KIND)
	k:SetPoint("TOPLEFT", 18, -34)
	f.kinds = {}
	for i, flag in ipairs(Board.FLAGS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetHeight(24)
		b:SetText(Label(flag))
		b.flag = flag
		b:SetScript("OnClick", function() f.flag = flag; ns.SafeCall("board flag window", Board.RefreshPicker) end)
		f.kinds[i] = b
	end
	f.info = Text(f, "GameFontHighlightSmall")
	f.info:SetPoint("TOPLEFT", 18, -82)
	f.info:SetWidth(324)
	f.info:SetWordWrap(true)
	f.info:SetTextColor(0.75, 0.75, 0.75)
	f.noteLabel = Text(f)
	f.noteLabel:SetText(L.BOARD_PICK_NOTE)
	f.noteLabel:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -12)
	local okb, eb = pcall(CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
	if not okb or not eb then eb = CreateFrame("EditBox", nil, f) end
	eb:SetSize(318, 20)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(Board.NOTE_MAX)
	if eb.SetMaxBytes then eb:SetMaxBytes(Board.NOTE_MAX + 1) end -- (NOTE_MAX bytes and the end)
	eb:SetFontObject("ChatFontNormal")
	eb:SetPoint("TOPLEFT", f.noteLabel, "BOTTOMLEFT", 6, -4)
	eb.sylvanistasBox = true
	eb:SetScript("OnEnterPressed", function() ns.SafeCall("board raise", Board.RaiseFromPicker) end)
	eb:SetScript("OnEscapePressed", function() f:Hide() end)
	f.note = eb
	f.raise = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.raise:SetSize(110, 24)
	f.raise:SetPoint("BOTTOMRIGHT", -18, 14)
	f.raise:SetText(L.BOARD_RAISE_BTN)
	f.raise:SetScript("OnClick", function() ns.SafeCall("board raise", Board.RaiseFromPicker) end)
	f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.cancel:SetSize(90, 24)
	f.cancel:SetPoint("RIGHT", f.raise, "LEFT", -8, 0)
	f.cancel:SetText(CANCEL or "Cancel")
	f.cancel:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnHide", function() f.note:ClearFocus() end)
	ns.EscapeCloses("SylvanistasFlagFrame")
	return f
end

-- The kinds offered (PvP on a PvP realm alone), the one picked lit, Raise only with one picked,
-- and the window as tall as its words.
function Board.RefreshPicker()
	local f = picker
	if not f then return end
	local offered = {}
	for _, flag in ipairs(Board.Offered()) do offered[flag] = true end
	-- (A kind no longer offered, from /syl lfg pvp on a PvE realm, stays while it is the one picked.)
	if f.flag then offered[f.flag] = true end
	local shown = {}
	for _, b in ipairs(f.kinds) do
		b:SetShown(offered[b.flag] == true)
		if offered[b.flag] then shown[#shown + 1] = b end
		if b.flag == f.flag then b:LockHighlight() else b:UnlockHighlight() end
	end
	local gap = 8
	local w = math.floor((324 - gap * (#shown - 1)) / math.max(1, #shown))
	for i, b in ipairs(shown) do
		b:SetWidth(w)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 18 + (i - 1) * (w + gap), -50)
	end
	f.info:SetText((f.flag and (L.BOARD_PICK_CHOSEN:format(Label(f.flag)) .. "\n\n") or "")
		.. Board.PrivacyText(SharedZone()) .. "\n\n" .. L.BOARD_PICK_INFO)
	f.raise:SetEnabled(f.flag ~= nil)
	local infoH = f.info:GetStringHeight() or 60
	f:SetHeight(math.ceil(82 + infoH + 12 + 14 + 4 + 20 + 50))
end

-- The flag window, its kind already picked when one is named (/syl lfg dungeon), the note as given.
function Board.Prompt(flag, note)
	if flag ~= nil and not Board.LABEL[flag] then return end
	picker = picker or MakePicker()
	picker.flag = flag
	picker.note:SetText(Board.CleanNote(note) or "")
	picker:Show()
	Board.RefreshPicker()
	ns.Focus(picker.note)
	return picker
end

-- Raise or Enter: the flag goes up and the window closes; refused (a wait, the hourly limit, the
-- Board full: Board.Raise said why), it stays for another try.
function Board.RaiseFromPicker()
	local f = picker
	if not f or not f:IsShown() or not f.flag then return end
	if Board.Raise(f.flag, f.note:GetText()) then f:Hide() end
end
function Board.Picker() return picker end -- (tests)

-- Does a card hold the search `q` (Views.Query), as its row shows it?
local function Hit(q, e)
	if not q then return true end
	local zone = e.zone and ns.Zones.NameForKey("m" .. e.zone) or L.BOARD_ZONE_HIDDEN
	return ns.Holds(q, Label(e.flag), ns.DisplayName(e.sender), ns.Codec.Plain(e.guild), zone, Board.NoteShown(e))
end
Board.Hit = Hit

-- The page's lines: the way back, our flag (or the flags to raise), the Board's flags, then the
-- camps (Board.CampLines). `q`: the Realm tab's search, over the cards.
-- The Board's grey info lines, wrapped to the page's width (Views.GreyRows; 1.3.0).
local function GreyRows(lines, text, indent)
	ns.Views.GreyRows(lines, text, { indent = indent })
end

function Board.Lines(q)
	local lines = { { text = Gold(L.BOARD_BACK), onClick = function() ns.Views.ShowBoard(false) end, gapAfter = true } }
	-- 1.2.21: the week in numbers (WeeklyBrief.lua), a page of its own.
	if not q and ns.WeeklyBrief and ns.WeeklyBrief.Link then lines[#lines + 1] = ns.WeeklyBrief.Link() end
	-- The King's week first (Week.lua, 1.1): what the army has on, by day.
	if ns.Week and ns.Week.Section then ns.Week.Section(lines, q) end
	-- (1.3.0: Parties moved to the Screams tab's buttons; their switches to its cog.)
	if not q then
		lines[#lines + 1] = { header = true, text = L.BOARD_YOURS,
			tooltip = function(tt) tt:AddLine(L.BOARD_YOURS, 1, 0.82, 0); tt:AddLine(L.BOARD_YOURS_TIP, 1, 1, 1, true) end }
		local mine = own.flag
		if mine then
			local note = mine.note ~= "" and ('  "' .. mine.note .. '"') or ""
			lines[#lines + 1] = { indent = 1, text = Green(L.BOARD_MINE:format(Label(mine.flag))) .. note,
				right = Board.ZoneText(mine.zone) .. "  " .. Grey(ns.Ago(mine.raisedAt)),
				onClick = function() Board.Lower() end,
				tooltip = function(tt) tt:AddLine(L.BOARD_MINE:format(Label(mine.flag)), 1, 0.82, 0); tt:AddLine(L.BOARD_MINE_TIP, 1, 1, 1, true) end }
		else
			-- (1.3.0: the "Raise a flag" button below opens the flag window, Board.Prompt.)
			GreyRows(lines, L.BOARD_NONE_YET, 1)
		end
		GreyRows(lines, SharedZone() and L.BOARD_ZONE_SHARED or L.BOARD_ZONE_PRIVATE, 1)
		lines[#lines].gapAfter = true
	end
	local list = Board.List("flag")
	lines[#lines + 1] = { header = true, text = L.BOARD_FLAGS:format(#list) }
	local found = 0
	for _, e in ipairs(list) do
		if Hit(q, e) then
			found = found + 1
			local card = Board.Card(e)
			card.indent = 1
			lines[#lines + 1] = card
		end
	end
	if found == 0 then
		GreyRows(lines, q and L.SEARCH_NO_MATCH or (askAt and ns.Now() - askAt < 30 and L.BOARD_GATHERING or L.BOARD_EMPTY), 1)
	end
	lines[#lines].gapAfter = true
	Board.CampLines(lines, q)
	return lines
end

-- The camps (request #25): ours (or where we could drop one), then every camp up, by zone.
function Board.CampLines(lines, q)
	local list = Board.List("camp")
	table.sort(list, function(a, b)
		local za, zb = Board.ZoneText(a.zone), Board.ZoneText(b.zone)
		if za ~= zb then return za < zb end
		return a.raisedAt > b.raisedAt
	end)
	lines[#lines + 1] = { header = true, text = L.BOARD_CAMPS:format(#list),
		tooltip = function(tt) tt:AddLine(L.BOARD_CAMPS:format(#list), 1, 0.82, 0); tt:AddLine(L.BOARD_CAMPS_TIP, 1, 1, 1, true) end }
	if not q then
		local camp = own.camp
		local zone, no = Board.CampZone()
		if camp then
			local note = camp.note ~= "" and ('  "' .. camp.note .. '"') or ""
			lines[#lines + 1] = { indent = 1, text = Green(L.BOARD_CAMP_MINE:format(Board.ZoneText(camp.zone))) .. note,
				right = Grey(L.BOARD_CAMP_LEFT:format(math.max(1, math.ceil((camp.raisedAt + Board.CAMP_LIFE - ns.Now()) / 60)))),
				onClick = function() Board.LowerCamp() end,
				tooltip = function(tt) tt:AddLine(L.BOARD_CAMP_MINE:format(Board.ZoneText(camp.zone)), 1, 0.82, 0); tt:AddLine(L.BOARD_CAMP_MINE_TIP, 1, 1, 1, true) end }
		elseif zone then
			-- (1.3.0: the "Drop a camp" button below, or a campfire lit, opens the camp's dialog.)
			GreyRows(lines, L.BOARD_CAMP_NONE_YET, 1)
		else
			lines[#lines + 1] = { indent = 1, text = Grey(no == "private" and L.BOARD_CAMP_NEEDS_LOCATION or L.BOARD_CAMP_NO_ZONE) }
		end
	end
	local found = 0
	for _, e in ipairs(list) do
		if Hit(q, e) then
			found = found + 1
			local card = Board.Card(e)
			card.indent = 1
			lines[#lines + 1] = card
		end
	end
	if found == 0 then lines[#lines + 1] = { indent = 1, text = Grey(q and L.SEARCH_NO_MATCH or L.BOARD_CAMPS_EMPTY) } end
end

-- The camp's dialog: where it goes, who reads it, a note (optional). Dropped on its button or Enter.
function Board.PromptCamp(note)
	local zone, no = Board.CampZone()
	if not zone then return ns.Print(no == "private" and L.BOARD_CAMP_NEEDS_LOCATION or L.BOARD_CAMP_NO_ZONE) end
	return ns.ShowDialog("SYLVANISTAS_BOARD_CAMP", Board.ZoneText(zone), ns.Comm.Audience(), { camp = true, note = Board.CleanNote(note) })
end

function Board.ConfirmCamp(data, note)
	if type(data) ~= "table" or data.answered then return end
	data.answered = true
	return Board.DropCamp(note)
end

StaticPopupDialogs["SYLVANISTAS_BOARD_CAMP"] = {
	text = L.BOARD_CAMP_ASK,
	button1 = L.BOARD_CAMP_BTN,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 260,
	maxLetters = Board.NOTE_MAX,
	maxBytes = Board.NOTE_MAX + 1,
	OnShow = function(self, data)
		local eb = self.editBox or self.EditBox
		data = data or self.data
		if eb then eb:SetText(type(data) == "table" and data.note or "") eb:SetFocus() end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("board camp", Board.ConfirmCamp, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("board camp", Board.ConfirmCamp, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

---------------------------------------------------------------------------
-- The camps on the world map: one badge per zone beside its circle (Map.Badge), with how many
-- camps are up there; its tooltip lists them. Mouse and keyboard only (ns.WorldMapIcons: none
-- on the gamepad UI's world map), and only while ns.db.showCamps is on (/syl camps, the map's
-- Sylvanistas menu).
-- 1.3.0 (the user's call): a camp that carries its spot (Board.Decode's x, y) is a campfire there
-- instead, on the world map and on the minimap (the minimap with the gamepad UI too: it has no
-- world map icons, Fellows.lua's tabards do the same); ours too. A camp from an older client (its
-- zone alone) keeps the zone's badge.
---------------------------------------------------------------------------

local campBadges, spareBadges = {}, {} -- [mapID] = the badge's anchor; anchors to reuse

local function CampTip(self)
	local mapID = self.mapID
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L.BOARD_CAMPS_IN:format(Board.ZoneText(mapID)), 1, 0.55, 0.15)
	for _, e in ipairs(Board.List("camp")) do
		if e.zone == mapID then
			local note = Board.NoteShown(e)
			GameTooltip:AddLine(("%s <%s>%s"):format(ns.DisplayName(e.sender) or "?", ns.Codec.Plain(e.guild), note ~= "" and ('  "' .. note .. '"') or ""), 1, 1, 1, true)
		end
	end
	GameTooltip:AddLine(L.BOARD_CAMP_MAP_TIP, 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end
Board.CampTip = CampTip

local function NewBadge()
	local a = ns.Map.Badge(Board.CAMP_BADGE, true)
	ns.Map.SetBadge(a, Board.CAMP_ICON, 1, 0.55, 0.15)
	a.badge.count = a.badge:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	a.badge.count:SetPoint("BOTTOMRIGHT", a.badge, "BOTTOMRIGHT", 3, -3)
	a.badge:SetScript("OnEnter", CampTip)
	a.badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return a
end

local campPins, sparePins = {}, {} -- [post key] = { world, mini, e }; pins to reuse

local function PinTip(self)
	local e = self.camp
	if not e then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(L.BOARD_CAMP_PIN:format(Board.ZoneText(e.zone)), 1, 0.55, 0.15)
	local who = e.mine and (ns.DisplayName(ns.me) or "?") or (ns.DisplayName(e.sender) or "?")
	local note = e.mine and (e.note or "") or Board.NoteShown(e)
	GameTooltip:AddLine(("%s <%s>%s"):format(who, ns.Codec.Plain(e.guild or GetGuildInfo("player") or "?"), note ~= "" and ('  "' .. note .. '"') or ""), 1, 1, 1, true)
	local left = math.max(1, math.ceil((e.raisedAt + Board.CAMP_LIFE - ns.Now()) / 60))
	GameTooltip:AddLine(L.BOARD_CAMP_LEFT:format(left), 0.6, 0.6, 0.6)
	GameTooltip:AddLine(e.mine and L.BOARD_CAMP_PIN_MINE_TIP or L.BOARD_CAMP_MAP_TIP, 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function CampIcon(size)
	local f = CreateFrame("Frame", nil, UIParent)
	f.sylvanistas = true -- (ours: photo mode leaves it shown, UI.TogglePhoto)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexture(Board.CAMP_ICON)
	if ns.Map and ns.Map.RoundIcon then ns.Map.RoundIcon(f.tex, Board.CAMP_ICON) end
	f:EnableMouse(true)
	f:SetScript("OnEnter", PinTip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

-- The camps with a spot: a campfire on the world map and the minimap each.
local function RefreshPins(Pins, world)
	local want = {}
	if ns.db.showCamps ~= false and ns.IsMember() then
		for _, e in ipairs(Board.List("camp")) do
			if e.zone and e.x and e.y then want[Key(e.sender, "camp")] = e end
		end
		local c = own.camp
		if c and c.zone and c.x and c.y then
			want["|mine"] = { mine = true, zone = c.zone, x = c.x, y = c.y, note = c.note, raisedAt = c.raisedAt }
		end
	end
	for key, p in pairs(campPins) do
		local e = want[key]
		if not e or e.zone ~= p.zone or e.x ~= p.x or e.y ~= p.y then
			if world or p.onWorld then Pins:RemoveWorldMapIcon(Board, p.world) end
			Pins:RemoveMinimapIcon(Board, p.mini)
			p.world:Hide()
			p.mini:Hide()
			campPins[key] = nil
			sparePins[#sparePins + 1] = p
		end
	end
	for key, e in pairs(want) do
		local p = campPins[key]
		if not p then
			p = table.remove(sparePins) or { world = CampIcon(Board.CAMP_PIN), mini = CampIcon(Board.CAMP_PIN_MINI) }
			p.zone, p.x, p.y, p.onWorld = e.zone, e.x, e.y, world
			if world then Pins:AddWorldMapIconMap(Board, p.world, e.zone, e.x / 1000, e.y / 1000, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2) end
			Pins:AddMinimapIconMap(Board, p.mini, e.zone, e.x / 1000, e.y / 1000, true, false)
			campPins[key] = p
		elseif world and not p.onWorld then
			-- (Back from the gamepad UI, which took every world map icon off: ns.WorldMapIcons.)
			Pins:AddWorldMapIconMap(Board, p.world, e.zone, e.x / 1000, e.y / 1000, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
			p.onWorld = true
		elseif not world then
			p.onWorld = false
		end
		p.world.camp, p.mini.camp = e, e
	end
end
function Board.CampPins() return campPins end -- (tests)

function Board.RefreshCamps()
	local Pins = ns.Pins()
	if not Pins or not (ns.Map and ns.Map.Badge) then return end
	local world = ns.WorldMapIcons(Pins, Board)
	ns.SafeCall("board camp pins", RefreshPins, Pins, world)
	local want, newest = {}, {}
	if world and ns.db.showCamps ~= false and ns.IsMember() then
		for _, e in ipairs(Board.List("camp")) do
			if e.zone and not (e.x and e.y) then
				want[e.zone] = (want[e.zone] or 0) + 1
				newest[e.zone] = math.max(newest[e.zone] or 0, e.raisedAt)
			end
		end
	end
	for mapID, a in pairs(campBadges) do
		if not want[mapID] then
			-- (Off the map already when the gamepad UI came on: ns.WorldMapIcons took them all.)
			if world then Pins:RemoveWorldMapIcon(Board, a) end
			a:Hide()
			campBadges[mapID] = nil
			spareBadges[#spareBadges + 1] = a
		end
	end
	for mapID, n in pairs(want) do
		local a = campBadges[mapID]
		if not a then
			a = table.remove(spareBadges) or NewBadge()
			campBadges[mapID] = a
			a.badge.mapID = mapID
			Pins:AddWorldMapIconMap(Board, a, mapID, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2)
		end
		a.since = newest[mapID] -- (Map.BADGE_MAX: the newest are laid out first)
		a.badge.count:SetText(n > 1 and tostring(n) or "")
	end
end

-- The zones with a camp badge on the world map now: { [mapID] = anchor } (tests, /syl status).
function Board.CampBadges() return campBadges end

-- The camps on the map, or not: /syl camps on|off (and the map's Sylvanistas menu).
function Board.SetCampsShown(on)
	ns.db.showCamps = on and true or false
	ns.Print(ns.db.showCamps and L.BOARD_CAMPS_MAP_ON or L.BOARD_CAMPS_MAP_OFF)
	ns.SafeCall("board camps", Board.RefreshCamps)
end

-- The line in the Realm tree that opens the page.
function Board.LinkLine()
	local parts = { L.BOARD_LINK_FLAGS:format((Board.Count("flag"))), L.BOARD_LINK_CAMPS:format((Board.Count("camp"))) }
	local week = ns.Week and ns.Week.LinkPart and ns.Week.LinkPart()
	if week then table.insert(parts, 1, week) end
	return {
		text = "|TInterface\\Icons\\INV_Misc_Note_01:14:14|t " .. Gold(L.BOARD_LINK),
		right = Grey(table.concat(parts, "  ·  ")),
		onClick = function() ns.Views.ShowBoard(true) end,
		gapAfter = true,
		tooltip = function(tt)
			tt:AddLine(L.BOARD_LINK, 1, 0.82, 0)
			tt:AddLine(L.BOARD_LINK_TIP, 1, 1, 1, true)
		end,
	}
end

-- /syl lfg [dungeon|raid|pvp|layer [note] | off]: the Board, a flag's dialog, or ours lowered.
Board.WORDS = { d = "D", dungeon = "D", masmorra = "D", r = "R", raid = "R", raide = "R", p = "P", pvp = "P", jxj = "P",
	l = "L", layer = "L", camada = "L" }
function Board.Open()
	ns.Views.ShowBoard(true, true)
	ns.UI.SelectTab("realm")
end
function Board.Slash(cmd, rest)
	rest = tostring(rest or "")
	local word, note = rest:match("^(%S*)%s*(.-)$")
	word = ns.Fold(word or "")
	-- /syl camp [note | off]: a camp's dialog, or ours taken down. /syl camps on|off: the map's badges.
	if cmd == "camps" then
		if word == "on" or word == "off" then return Board.SetCampsShown(word == "on") end
		-- /syl camps ask on|off (1.3.0): the question when we light a campfire.
		if word == "ask" then
			local w = ns.Fold(note or "")
			if w == "on" or w == "off" then return Board.SetCampfireAsk(w == "on") end
			return ns.Print(ns.db.campfireAsk ~= false and L.CAMPFIRE_ASK_ON or L.CAMPFIRE_ASK_OFF)
		end
		return ns.Print(ns.db.showCamps ~= false and L.BOARD_CAMPS_MAP_ON or L.BOARD_CAMPS_MAP_OFF)
	end
	if cmd == "camp" then
		if word == "off" then
			if not Board.LowerCamp() then ns.Print(L.BOARD_CAMP_NONE_UP) end
			return
		end
		return Board.PromptCamp(rest)
	end
	if word == "" or cmd == "week" then return Board.Open() end
	if word == "off" then
		if not Board.Lower() then ns.Print(L.BOARD_NONE_UP) end
		return
	end
	local flag = Board.WORDS[word]
	if not flag then return ns.Print(L.HELP_BOARD) end
	Board.Prompt(flag, note)
end

-- 1.3.0: the player's last casts, as the game reports them (/syl bug), to learn the campfire kits' ids.
local casts = { n = 0 }
function Board.SawCast(name, id)
	casts.n = casts.n + 1
	table.insert(casts, 1, ("%s (%s)"):format(tostring(name or "?"), tostring(id)))
	casts[6] = nil
end
local function CastsText()
	if casts.n == 0 then return "none seen" end
	return ("%d seen, last: %s"):format(casts.n, table.concat(casts, ", "))
end

-- /syl status: what this client holds, what it sends.
function Board.StatusLine()
	local mine, camp = own.flag, own.camp
	local mineText = mine and ("%s %s, every %d min"):format(mine.flag, ns.Ago(mine.raisedAt), mine.every or 0) or "none"
	return ("flags %d  |  camps %d  |  mine: %s  |  my camp: %s  |  asked: %s  |  answers sent %d  |  camps on map: %s  |  your casts: %s"):format(
		(Board.Count("flag")), (Board.Count("camp")), mineText, camp and ("m" .. tostring(camp.zone) .. " " .. ns.Ago(camp.raisedAt)) or "none",
		askAt and ns.Ago(askAt) or (askSent and "gave up" or "not yet"), answersGiven, tostring(ns.db.showCamps ~= false), CastsText())
end

-- Tests start from nothing.
function Board.Reset()
	wipe(posts); wipe(lastNewId); wipe(lowered); wipe(raises); wipe(asks); wipe(answered); wipe(answersSent); wipe(own); wipe(usedIds)
	lastRaise, lastCamp = -math.huge, -math.huge
	if ns.rdb then ns.rdb.board = nil end
	askSent, askTries, askAt, askRetryAt, askWanted, answersGiven = false, 0, nil, nil, false, 0
	changePending = false
end

ns.Comm.Handle("G1", function(...) Board.HandlePost(...) end)
ns.Comm.Handle("G0", function(...) Board.HandleLower(...) end)
ns.Comm.Handle("GQ", function(...) Board.HandleAsk(...) end)

-- The page redraws while it shows (it only shows in the Realm tab: Views.CloseChat), and the
-- camps' badges follow.
ns.On("BOARD_CHANGED", function()
	if ns.Views and ns.Views.BoardShown and ns.Views.BoardShown() and ns.UI and ns.UI.IsShown and ns.UI.IsShown() then ns.UI.RefreshSoon() end
	ns.SafeCall("board camps", Board.RefreshCamps)
end)

---------------------------------------------------------------------------
-- A campfire lit (1.3.0, the user's call): Basic Campfire cast by us offers to put a camp on the
-- Board right there (the camp's dialog, the fire's zone and spot). Asked only when it could go
-- up: a member, sharing the location (else one line a session saying so), outside an instance,
-- no camp of ours up, CAMP_GAP passed. "Never ask" turns it off; /syl camps ask on brings it back.
---------------------------------------------------------------------------

local toldPrivate = false
function Board.SetCampfireAsk(on)
	ns.db.campfireAsk = on and true or false
	ns.Print(on and L.CAMPFIRE_ASK_ON or L.CAMPFIRE_ASK_OFF)
end

-- 1.3.0: a kit's cast may only start the fire's placement (a ground cursor, then a second cast): the
-- pop-up waits until the player is neither placing nor casting for CAMPFIRE_SETTLE seconds, so it
-- never takes the click or the keyboard from the placement. Another fire cast meanwhile starts the
-- wait again; after CAMPFIRE_GIVEUP seconds it is not asked.
Board.CAMPFIRE_SETTLE = 1.5
Board.CAMPFIRE_GIVEUP = 60
local fireWait
local function Busy()
	if type(SpellIsTargeting) == "function" and SpellIsTargeting() then return true end
	if type(UnitCastingInfo) == "function" and UnitCastingInfo("player") then return true end
	if type(UnitChannelInfo) == "function" and UnitChannelInfo("player") then return true end
	return false
end
function Board.CampfireSoon()
	local now = GetTime()
	if fireWait then
		fireWait.since, fireWait.quietAt = now, nil
		return
	end
	fireWait = { since = now }
	local ticker
	ticker = C_Timer.NewTicker(0.25, function()
		ns.SafeCall("board campfire", function()
			local w, t = fireWait, GetTime()
			if not w then return ticker:Cancel() end
			if t - w.since > Board.CAMPFIRE_GIVEUP then
				fireWait = nil
				return ticker:Cancel()
			end
			if Busy() then
				w.quietAt = nil
				return
			end
			w.quietAt = w.quietAt or t
			if t - w.quietAt < Board.CAMPFIRE_SETTLE then return end
			fireWait = nil
			ticker:Cancel()
			Board.CampfireLit()
		end)
	end)
end

function Board.CampfireLit()
	if ns.db.campfireAsk == false or not ns.IsMember() or own.camp then return end
	if Board.CampWait() > 0 then return end
	local zone, no = Board.CampZone()
	if not zone then
		if no == "private" and not toldPrivate then
			toldPrivate = true
			ns.Print(L.CAMPFIRE_PRIVATE)
		end
		return
	end
	return ns.ShowDialog("SYLVANISTAS_BOARD_CAMPFIRE", Board.ZoneText(zone), ns.Comm.Audience(), { camp = true, note = "" })
end

StaticPopupDialogs["SYLVANISTAS_BOARD_CAMPFIRE"] = {
	text = L.CAMPFIRE_ASK,
	button1 = L.CAMPFIRE_SHARE,
	button2 = L.CAMPFIRE_NOT_NOW,
	button3 = L.CAMPFIRE_NEVER,
	hasEditBox = true,
	editBoxWidth = 260,
	maxLetters = Board.NOTE_MAX,
	maxBytes = Board.NOTE_MAX + 1,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then eb:SetText("") end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("board campfire", Board.ConfirmCamp, data or self.data, eb and eb:GetText())
	end,
	OnAlt = function() ns.SafeCall("board campfire", Board.SetCampfireAsk, false) end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.SafeCall("board campfire", Board.ConfirmCamp, parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- A spell's name: C_Spell.GetSpellName on the newer clients (Forever's has no GetSpellInfo), else
-- GetSpellInfo; nil when neither knows it.
local function SpellName(id)
	if type(id) ~= "number" then return nil end
	local name
	if C_Spell and type(C_Spell.GetSpellName) == "function" then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok then name = n end
	end
	if name == nil and type(GetSpellInfo) == "function" then
		local ok, n = pcall(GetSpellInfo, id)
		if ok then name = n end
	end
	return type(name) == "string" and name ~= "" and name or nil
end
Board.SpellName = SpellName

ns.On("LOGIN", function()
	-- (The campfire's spell id, or its name on a client that gives none.)
	local fireName = SpellName(Board.CAMPFIRE_SPELL)
	ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
		if unit ~= "player" then return end
		if type(issecretvalue) == "function" and issecretvalue(spellID) == true then return end
		-- 1.3.0: Forever's campfire kits aren't Classic's spell 818: any cast of ours named like a fire or a
		-- camp goes in the log (/syl bug) with its id, to learn the kits' ids (NEXT-STEPS, camps plan).
		local castName = SpellName(spellID)
		Board.SawCast(castName, spellID)
		local low = castName and castName:lower() or ""
		if low:find("fire", 1, true) or low:find("camp", 1, true) then
			ns.Log("campfire? you cast %s (spell %s)%s", castName, tostring(spellID),
				(ns.Crafters and ns.Crafters.WindowShown and ns.Crafters.WindowShown()) and ", profession window open" or "")
		end
		if spellID ~= Board.CAMPFIRE_SPELL and not (fireName and castName == fireName) then return end
		Board.CampfireSoon()
	end)
	Board.Restore()
	ns.Every(30, "board", function() Board.Tick() end)
end)
