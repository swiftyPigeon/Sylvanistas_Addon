local ADDON, ns = ...
local L = ns.L

-- Royal decrees sent to every Sylvanistas guild over SylvanistasNet:
--   REV    "Revenant Call" (1.3.0, was ARMS "Call for the Revenant"): a rare or tougher enemy in the
--          caller's target. A skull on every member's map; the alert (a toast, ns.Toast, and a soft
--          sound) only for members in the caller's zone or one next to it (Decree.Near). Its words:
--          "<target's GUID>^<target's name>^<note>". It ends when the target dies (the caller's
--          addon sends RV~<GUID>; a client that sees it die ends it too) or after 5 minutes.
--          ARMS from clients before 1.3.0 still shows, as before, under the new name.
--   MUSTER "Gathering" (meeting point): a toast + soft sound, marker for 30 min
-- Only Captains (rank <= ns.CAPTAIN_RANK) can send, and the King's Steward (1.0.0). Receivers
-- rate-limit per sender and, for senders only the census vouches for, the whole army (the
-- flood guard). A decree's words are its sender's own text: sent with the logged API (1.0.0),
-- like a chat line.

local Decree = {}
ns.Decree = Decree

local Pins = ns.Pins()
local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local DURATION = { ARMS = 5 * 60, REV = 5 * 60, MUSTER = 30 * 60, ROYAL = 60 * 60, HERALDRY = 60 * 60 }
local CROWN_ONLY = { ROYAL = true, HERALDRY = true }
Decree.CROWN_ONLY = CROWN_ONLY
local SEND_COOLDOWN = 60
local PER_SENDER_COOLDOWN = 60
local MAX_PER_MINUTE = 6

local active = {}          -- list of decrees
local lastSent = 0
local lastBySender = {}
local recent = {}          -- timestamps of accepted decrees (flood guard)

local function Where()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	return mapID, x, y
end

local LABEL = { ARMS = "ARMS", REV = "ARMS", MUSTER = "MUSTER", ROYAL = "ROYAL", HERALDRY = "HERALDRY_CALL" }
-- Each decree's sound switch (1.1, ns.SOUND_KINDS): the Tabard inspection goes with the Royal decree.
local SOUND = { ARMS = "arms", REV = "arms", MUSTER = "muster", ROYAL = "royal", HERALDRY = "royal" }
Decree.SOUND = SOUND
local ICONS = {
	ARMS = "Interface\\Icons\\Spell_Shadow_RaiseDead",
	REV = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
	MUSTER = "Interface\\Icons\\INV_Misc_Horn_01",
	ROYAL = "Interface\\AddOns\\Sylvanistas\\media\\logo64",
	HERALDRY = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
}
local function Label(d)
	-- 1.2.2: the tabard call is Assemble the Loyal in casual (ns.TABARD_MODE).
	if d.kind == "HERALDRY" and ns.Casual() then return L.ASSEMBLE_CALL end
	return L[LABEL[d.kind] or "MUSTER"]
end
Decree.Label = Label

local function PinEnter(self)
	local d = self.decree
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Label(d), 1, 0.25, 0.25)
	if d.text ~= "" then GameTooltip:AddLine(Decree.Words(d), 1, 1, 1, true) end
	GameTooltip:AddLine(L.DECREE_BY:format(d.sender, d.guild ~= "" and d.guild or "?", ns.Ago(d.t)), 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- On the world map a decree is a round icon in a disc of its colour, beside the zone circles
-- rather than over their numbers (1.0.0, Map.Badge; a square of 34 before). An expired decree's
-- icon waits for the next one.
Decree.BADGE = 20
local COLORS = { ARMS = { 1, 0.25, 0.2 }, REV = { 0.85, 0.1, 0.1 }, MUSTER = { 1, 0.8, 0.2 }, ROYAL = { 0.9, 0.76, 0.36 }, HERALDRY = { 0.35, 0.6, 1 } }
local spare = {}

local function MakePin(d)
	local f = table.remove(spare) or ns.Map.Badge(Decree.BADGE, true)
	local c = COLORS[d.kind] or COLORS.MUSTER
	ns.Map.SetBadge(f, ICONS[d.kind] or ICONS.MUSTER, c[1], c[2], c[3])
	f.badge.decree, f.since = d, d.t -- (the newest are laid out first: Map.BADGE_MAX)
	f.badge:SetScript("OnEnter", PinEnter)
	f.badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return f
end

-- A decree's words as they show: the player's block terms hide them until a click on the Decrees
-- tab shows them (1.1, #31); the decree itself, its alarm and its marker stay. A Revenant Call's:
-- its target's name, then the note.
function Decree.Words(d)
	if d.hidden and not d.revealed then return ns.L.FILTER_WORDS_HIDDEN_SHORT end
	if d.kind == "REV" then
		local note = d.note and d.note ~= "" and (" - " .. d.note) or ""
		return (d.target or "?") .. note
	end
	return d.text or ""
end

-- 1.3.0: a Revenant Call's words, taken apart: its target's GUID, name and the caller's note.
local function ReadRevenant(d)
	local guid, name, note = tostring(d.text or ""):match("^([^%^]*)%^([^%^]*)%^?(.*)$")
	if not guid or guid == "" then return false end
	d.guid, d.target, d.note = guid, name ~= "" and name or "?", note or ""
	return true
end

-- 1.3.0: a map in our zone, or in one next to it: the same zone, one inside the other (a city), or
-- whose rectangles on the continent touch (within NEAR_YARDS), from HereBeDragons' world
-- coordinates. No adjacency table to keep: it works for any zone the library knows.
Decree.NEAR_YARDS = 300
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local function Rect(mapID)
	if not (HBD and HBD.GetWorldCoordinatesFromZone) then return nil end
	local x1, y1, inst = HBD:GetWorldCoordinatesFromZone(0, 0, mapID)
	local x2, y2 = HBD:GetWorldCoordinatesFromZone(1, 1, mapID)
	if not x1 or not x2 then return nil end
	return math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2), inst
end
function Decree.Near(mapID)
	local mine = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not mine or not mapID then return false end
	if mine == mapID then return true end
	local ax1, ax2, ay1, ay2, ai = Rect(mine)
	local bx1, bx2, by1, by2, bi = Rect(mapID)
	if not ax1 or not bx1 or ai ~= bi then return false end
	local m = Decree.NEAR_YARDS
	return ax1 - m <= bx2 and bx1 - m <= ax2 and ay1 - m <= by2 and by1 - m <= ay2
end

-- 1.3.0: the target a Revenant Call needs: a living enemy, rare or tougher (rare, rare elite,
-- world boss). nil and why when there is none.
local RARE = { elite = true, rare = true, rareelite = true, worldboss = true } -- (elites too: the user's call)
function Decree.RevenantTarget()
	if not UnitExists or not UnitExists("target") then return nil end
	if UnitIsDead("target") or not UnitCanAttack("player", "target") then return nil end
	local c = UnitClassification and UnitClassification("target")
	if not RARE[c] then return nil end
	local ok, guid, name = pcall(function() return UnitGUID("target"), UnitName("target") end)
	if not ok or type(guid) ~= "string" or type(name) ~= "string" then return nil end
	return guid, name
end

-- own: sent or previewed here (the player's click): shown in an instance too. Anyone else's
-- waits there, and on Busy (1.1, ns.Alert): its chat line and its line on the Decrees tab now,
-- its raid warning once the player is out, if it has not expired by then.
local function Show(d, own)
	d.expires = d.t + DURATION[d.kind]
	table.insert(active, 1, d)
	local zone = ns.Zones.NameForKey("m" .. d.mapID)
	local words = Decree.Words(d)
	local text = ("%s %s%s"):format(Label(d), zone, words ~= "" and (" - " .. words) or "")
	-- 1.3.0: a Revenant Call alerts only the caller's zone and the ones next to it; farther away,
	-- its skull on the map and its line on the Screams tab alone.
	local alert = own or d.kind ~= "REV" or Decree.Near(d.mapID)
	if alert then
		ns.Print(("|cffff4040%s|r  (%s <%s>)"):format(text, d.sender, d.guild))
		-- (1.3.0: the Banshee Scream and Assemble the Loyal on a parchment scroll; the calls in the
		-- small window, ns.Alert.)
		local scroll = (d.kind == "ROYAL" or d.kind == "HERALDRY") and { title = Label(d), body = (words ~= "" and words or zone),
			by = ("%s <%s>  ·  %s"):format(d.sender or "?", d.guild ~= "" and d.guild or "?", zone) } or nil
		ns.Alert(SOUND[d.kind] or "muster", (d.kind == "MUSTER" or d.kind == "ARMS" or d.kind == "REV") and "soft" or "loud", {
			text = text, color = { r = 1, g = 0.3, b = 0.1 }, own = own, scroll = scroll, icon = ICONS[d.kind],
			what = ("%s (%s)"):format(L["HELP_" .. (LABEL[d.kind] == "ARMS" and "ARMS" or d.kind) .. "_NAME"], zone),
			open = function() return ns.Now() <= d.expires end,
		})
	end
	if Pins then d.pin = MakePin(d) end
	Decree.RefreshPins()
	ns.Log("decree %s from %s <%s> map %d", d.kind, d.sender, d.guild, d.mapID)
	ns.Fire("DECREES_CHANGED")
end

-- (Not on the world map with the gamepad UI: ns.WorldMapIcons.)
local function RefreshPinsNow()
	if not Pins then return end
	local world = ns.WorldMapIcons(Pins, Decree)
	for _, d in ipairs(active) do
		if d.pin then
			if ns.db.showDecrees then
				if world then Pins:AddWorldMapIconMap(Decree, d.pin, d.mapID, d.x, d.y, SHOW_FLAG) end
			else
				if world then Pins:RemoveWorldMapIcon(Decree, d.pin) end
				d.pin:Hide()
			end
		end
	end
end

function Decree.RefreshPins()
	ns.SafeCall("decree pins", RefreshPinsNow)
end

-- The King's Steward (1.0.0, King.IsSteward: the signed titles list marks him) sends the Crown's
-- decrees for the King's guild, whatever his own rank or guild; every client takes them by his
-- name, as the King's (below).
local function Steward() return ns.King ~= nil and ns.King.IsSteward ~= nil and ns.King.IsSteward() end

function Decree.CanSend(kind)
	if Steward() then return true end
	if CROWN_ONLY[kind] then return ns.IsCrown() end
	-- 1.3.0: the Revenant Call is every member's (its rare target is the gate); the others a Dark
	-- Ranger's (an officer) or a Dreadguard's (a moderator), equal in authority.
	if kind == "ARMS" or kind == "REV" then return ns.IsMember() == true end
	return ns.Roster.IsOfficer() or ns.IsHighCouncillor(ns.me) == true
end

function Decree.Send(kind, text)
	local steward = Steward()
	if not steward and not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	if not steward and CROWN_ONLY[kind] and not ns.IsCrown() then
		ns.Print(L.CROWN_ONLY)
		return
	end
	if not steward and not Decree.CanSend(kind) then
		ns.Print(L.DECREE_OFFICERS_ONLY)
		return
	end
	-- 1.1: the moderators took this character off (net-off, Moderation.lua): nobody would see it.
	local off = ns.Moderation.SelfOff and ns.Moderation.SelfOff()
	if off then
		ns.Print(ns.Moderation.YouText(off))
		return
	end
	local now = ns.Now()
	if now - lastSent < SEND_COOLDOWN then
		ns.Print(L.DECREE_COOLDOWN:format(SEND_COOLDOWN - (now - lastSent)))
		return
	end
	local mapID, x, y = Where()
	if not mapID then
		ns.Print(L.DECREE_NO_POSITION)
		return
	end
	-- 1.3.0: the Revenant Call, on a rare or tougher enemy in our target (its GUID and name ride in
	-- its words, before the note).
	local guid, target
	if kind == "ARMS" or kind == "REV" then
		guid, target = Decree.RevenantTarget()
		if not guid then return ns.Print(L.REVENANT_NEED_RARE) end
		kind = "REV"
		text = ("%s^%s^%s"):format(guid, target, tostring(text or ""):gsub("%^", ""))
	end
	lastSent = now
	local guild = steward and ns.KingGuildName() or GetGuildInfo("player") or ""
	local rank = steward and 0 or ns.Roster.MyRank()
	-- Logged (1.0.0): the server keeps its words, so abuse can be reported (Comm.Send).
	ns.Comm.Send("CHANNEL", ns.Codec.EncodeDecree(kind, mapID, x, y, guild, rank, text), nil, nil, true)
	-- 1.1 (#12): our own decree never comes back to us: in our log as we send it.
	ns.Chronicle.Add("decree", ns.me, Label({ kind = kind }) .. " " .. ns.Zones.NameForKey("m" .. mapID), { words = target or text })
	local d = { kind = kind, mapID = mapID, x = x, y = y, guild = guild, rank = rank, text = text or "", sender = ns.DisplayName(ns.me), t = now, mine = true }
	if kind == "REV" then ReadRevenant(d) end
	Show(d, true)
	-- 1.2.2: Assemble the Loyal (casual): our patrol counts who comes in regalia (Inspect.Assembly).
	if kind == "HERALDRY" and ns.Casual() and ns.Inspect.StartAssembly then ns.Inspect.StartAssembly() end
end

-- Local-only preview so anyone can see what a decree looks like (nothing is sent).
function Decree.Preview(kind)
	local mapID, x, y = Where()
	if not mapID then return end
	local d = { kind = kind, mapID = mapID, x = x, y = y, guild = GetGuildInfo("player") or "Sylvanistas", rank = 0,
		text = L.DECREE_PREVIEW_TEXT, sender = ns.DisplayName(ns.me), t = ns.Now() }
	if kind == "ARMS" then
		local _, name = Decree.RevenantTarget()
		d.kind, d.guid, d.target, d.note = "REV", "preview", name or L.REVENANT_PREVIEW_TARGET, L.DECREE_PREVIEW_TEXT
	end
	Show(d, true)
end

-- 1.3.0: a Revenant Call over: its target died. Its skull and line go at once.
function Decree.EndRevenant(guid, sender)
	if type(guid) ~= "string" or guid == "" then return end
	local changed
	for _, d in ipairs(active) do
		if d.kind == "REV" and d.guid == guid and (sender == nil or d.mine or ns.ShortName(d.sender) == ns.ShortName(ns.DisplayName(sender))) then
			d.expires, changed = 0, true
		end
	end
	if changed then
		Decree.Active()
		ns.Fire("DECREES_CHANGED")
	end
end
-- Our own call's target died (we saw it): the others are told, and it ends here.
local function OnDeath(guid)
	for _, d in ipairs(active) do
		if d.kind == "REV" and d.guid == guid and ns.Now() <= d.expires then
			if d.mine then ns.Comm.Send("CHANNEL", "RV~" .. guid) end
			Decree.EndRevenant(guid)
			return
		end
	end
end
-- Seen dead: Forever forbids an addon the combat log (registering COMBAT_LOG_EVENT_UNFILTERED is
-- refused, ADDON_ACTION_FORBIDDEN), so while a Revenant Call is on, once a second we look at the
-- units this client can see (target, focus, mouseover, the nameplates) for its target, dead. Each
-- unit's GUID read under pcall: Forever may hand some as secret values.
local WATCH = { "target", "focus", "mouseover" }
local function DeadGUID(unit)
	local ok, guid, dead = pcall(function()
		if not UnitExists(unit) then return nil, false end
		return UnitGUID(unit), UnitIsDead(unit)
	end)
	if ok and dead and type(guid) == "string" then return guid end
	return nil
end
function Decree.CheckDeaths()
	local any
	for _, d in ipairs(active) do if d.kind == "REV" and d.guid and ns.Now() <= d.expires then any = true break end end
	if not any then return end
	local units = {}
	for _, u in ipairs(WATCH) do units[#units + 1] = u end
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	for _, u in ipairs(units) do
		local guid = DeadGUID(u)
		if guid then
			for _, d in ipairs(active) do
				local ok, same = pcall(function() return d.kind == "REV" and d.guid == guid end)
				if ok and same then return OnDeath(d.guid) end
			end
		end
	end
end

-- The 15 s expiry timer also follows a switch of the interface style without a /reload: to the
-- gamepad UI, the decrees leave the world map at once (not 5 to 60 minutes later, when they
-- expire); back to mouse and keyboard, they return.
local lastWorld
function Decree.Active()
	local now, out = ns.Now(), {}
	local world = Pins and ns.WorldMapIcons(Pins, Decree)
	if Pins and lastWorld == false and world then RefreshPinsNow() end
	lastWorld = world
	for i = #active, 1, -1 do
		local d = active[i]
		if now > d.expires then
			if Pins and d.pin then
				if world then Pins:RemoveWorldMapIcon(Decree, d.pin) end
				d.pin:Hide()
				spare[#spare + 1], d.pin = d.pin, nil
			end
			table.remove(active, i)
		end
	end
	for _, d in ipairs(active) do out[#out + 1] = d end
	return out
end

ns.Comm.Handle("D1", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local d = ns.Codec.DecodeDecree(text)
	if not d or not ns.IsFederation(d.guild) then return end
	-- 1.1: a name the moderators took off (net-off, Moderation.lua).
	if ns.Moderation.Hides and ns.Moderation.Hides(sender, d.guild) then
		return ns.Log("decree from %s ignored: net-off", sender)
	end
	-- The King by his pinned name (the server stamps it), never by a vote: his decree needs no
	-- census. So do his Hands' for his guild (his list or a Steward's, King.IsHandName), on every
	-- client outside it: there they are of his Crown on his word (1.0.0); on its own members'
	-- clients its roster says who speaks for it. His Steward's (1.0.0: the signed titles list
	-- names him, King.IsStewardName) on every client, as the King's. Everyone else: the rank we
	-- can verify, never the rank written in the message.
	local mine = GetGuildInfo("player")
	local kings = ns.IsKingGuild(d.guild)
	local king = kings and ns.IsKingCharacter(sender)
	local steward = kings and not king and ns.King ~= nil and ns.King.IsStewardName(sender)
	local hand = kings and not king and not steward and not ns.IsKingGuild(mine) and ns.King ~= nil and ns.King.IsHandName(sender)
	local rank = (king or steward or hand) and 0 or ns.Data.KnownRank(sender, d.guild)
	-- 1.3.0: a Dreadguard (moderator) speaks as an officer; a Revenant Call is any member's (our
	-- roster's, or one speaking for that guild alone, Data.ClaimGuild).
	if not rank and ns.IsHighCouncillor(sender) then rank = ns.CAPTAIN_RANK end
	if not rank and d.kind == "REV" and (ns.Roster.RankOf(sender) ~= nil or ns.Data.ClaimGuild(sender, d.guild)) then rank = 9 end
	if not rank then
		ns.Log("decree from %s ignored: rank in %s not verified", sender, d.guild)
		return
	end
	d.rank = rank
	if CROWN_ONLY[d.kind] then
		if not ns.IsCrownRank(d.guild, rank) then return end
	elseif rank > ns.CAPTAIN_RANK and d.kind ~= "REV" then
		return
	end
	-- The King, his Steward, his Hands and our own guild's officers (our roster: the server's
	-- word) never wait behind the flood guard, which census ranks (anyone's votes) can fill.
	-- Anyone else speaks for one guild only, as in the chats (Data.ClaimGuild).
	local sure = king or steward or hand or (mine ~= nil and d.guild == mine and ns.Roster.RankOf(sender) ~= nil)
	if not sure and not ns.Data.ClaimGuild(sender, d.guild) then
		ns.Log("decree from %s ignored: speaks for another guild than %s", sender, d.guild)
		return
	end
	local now = ns.Now()
	if lastBySender[sender] and now - lastBySender[sender] < PER_SENDER_COOLDOWN then return end
	for i = #recent, 1, -1 do if now - recent[i] > 60 then table.remove(recent, i) end end
	if #recent >= MAX_PER_MINUTE and not sure then return end
	lastBySender[sender] = now
	if not sure then recent[#recent + 1] = now end
	-- Its words come through the logged API (the server keeps them, so abuse can be reported),
	-- as a chat line's do. One sent with the plain API, where this client has both (a sender
	-- before 1.0.0, or edited code), still shows, without its words (1.0.0).
	if d.text ~= "" and C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged
		and not ns.Comm.DeliveredLogged() then
		ns.Log("decree from %s shown without its text: not sent with the logged API", sender)
		d.text = ""
	end
	d.sender, d.t = ns.DisplayName(sender), now
	if d.kind == "REV" and not ReadRevenant(d) then return end
	-- 1.1 (#31): its words hidden when the player's block terms hit them (Filter.lua).
	local F = ns.Filter
	if d.text ~= "" and F and not F.missing and F.Hides(d.text) then d.hidden = true end
	-- 1.1 (#12): in this client's log of acts, with the name the server stamped.
	ns.Chronicle.Add("decree", sender, Label(d) .. " " .. ns.Zones.NameForKey("m" .. d.mapID), { words = d.kind == "REV" and d.target or d.text })
	Show(d)
end)

-- 1.3.0: RV~<GUID>, a Revenant Call's caller saw its target die: that caller's call ends.
-- (Not DE: Link.lua's.)
ns.Comm.Handle("RV", function(dist, sender, text)
	if dist ~= "CHANNEL" then return end
	local guid = tostring(text or ""):match("^RV~([%w%-]+)$")
	if guid then Decree.EndRevenant(guid, sender) end
end)

ns.On("LOGIN", function()
	-- (1.3.0: not the combat log, which Forever forbids an addon: Decree.CheckDeaths.)
	ns.Every(1, "revenant deaths", function() ns.SafeCall("revenant death", Decree.CheckDeaths) end)
	ns.Every(15, "decree expiry", function()
		local before = #active
		Decree.Active()
		if #active ~= before then ns.Fire("DECREES_CHANGED") end
	end)
end)
