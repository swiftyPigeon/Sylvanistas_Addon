local ADDON, ns = ...
local L = ns.L

-- Mentions (1.3.0, the user's ask): a line in a Sylvanistas chat that names one of our characters
-- ("@Kathrise", "Kathrise", "Kathrise Sunseam") is kept in a list of its own and told to us in a
-- small feed beside the minimap: one card at a time, oldest first, each rolling up and fading as
-- the next comes in; at most FEED_MAX cards on screen, the rest behind "+N more". In a dungeon or
-- while Busy (ns.Quiet) the cards wait, and play once we are out. The minimap button carries the
-- unread count; the Chat tab marks the lines and has a Mentions view (ChatWindow.lua). A soft
-- sound with each card, until "Dismiss all" ends the bunch.
-- Nothing is sent for it: each client looks for its own names in the lines it already keeps
-- (Channels.lua's CHAT_LINE: lines it may read, from players not blocked, after the net-off).
-- "Our names": this character, its account's linked main and alts (Alts.MyGroup), and every
-- character of this account seen at login on this realm group (ns.db.alts.chars). Each name
-- counts whole ("First Surname" on Forever) or by its first word, at least MIN_WORD letters.

local Mentions = {}
ns.Mentions = Mentions

Mentions.KEEP = 50            -- mentions kept (ns.rdb.mentions, per realm group: every character sees them)
Mentions.MIN_WORD = 3         -- a first name shorter than this only counts as "@Name"
Mentions.FEED_MAX = 3         -- cards on screen at once
Mentions.CARD_SECONDS = 4     -- a card stays this long (longer while the mouse is on the feed)
Mentions.CARD_GAP = 1.2       -- between two cards coming in
Mentions.ROLL = 0.45          -- a card's roll up and fade, and the others' move

local CARD_W, CARD_H, CARD_GAP_Y, FOOT_H = 250, 46, 4, 16

---------------------------------------------------------------------------
-- Our names, and whether a line holds one
---------------------------------------------------------------------------

local namesCache, namesAt

local function Esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- { { whole = "kathrise sunseam", first = "kathrise" }, ... } in lower case.
function Mentions.Names()
	local now = GetTime and GetTime() or 0
	if namesCache and namesAt and now - namesAt < 30 then return namesCache end
	local seen, out = {}, {}
	local function Add(name)
		if type(name) ~= "string" or name == "" then return end
		local short = ns.ShortName(name)
		local whole = short:lower()
		if seen[whole] then return end
		seen[whole] = true
		local first = whole:match("^(%S+)") or whole
		out[#out + 1] = { whole = whole, first = first ~= whole and first or nil }
	end
	Add(ns.me)
	local A = ns.Alts
	if A and not A.missing and A.MyGroup then
		for _, n in ipairs(A.MyGroup() or {}) do Add(n) end
	end
	local chars = ns.db and type(ns.db.alts) == "table" and ns.db.alts.chars
	if type(chars) == "table" then
		local group = ns.GroupOf and ns.GroupOf(ns.realm)
		for _, c in pairs(chars) do
			if type(c) == "table" and (c.group == nil or c.group == group) and (c.faction == nil or c.faction == ns.faction) then Add(c.name) end
		end
	end
	namesCache, namesAt = out, now
	return out
end
function Mentions.ForgetNames() namesCache = nil end -- (tests, an alt linked)

local function Holds(low, word, needAt)
	local p = Esc(word)
	if needAt then return low:find("@" .. p .. "%f[^%w]") ~= nil end
	return low:find("%f[%w@]@?" .. p .. "%f[^%w]") ~= nil
end

-- Whether `text` names one of our characters.
function Mentions.Matches(text)
	if type(text) ~= "string" or text == "" then return false end
	local low = (ns.Codec and ns.Codec.SanitizeChat and ns.Codec.SanitizeChat(text) or text):lower()
	for _, n in ipairs(Mentions.Names()) do
		if Holds(low, n.whole, false) then return true end
		if n.first and Holds(low, n.first, #n.first < Mentions.MIN_WORD) then return true end
	end
	return false
end

function Mentions.On() return ns.db == nil or ns.db.mentionsOff ~= true end
function Mentions.SetOn(on)
	if not ns.db then return end
	ns.db.mentionsOff = (not on) and true or nil
	ns.Print(on and L.MENTIONS_ON or L.MENTIONS_OFF)
	if not on then Mentions.Dismiss() end
	ns.Fire("MENTIONS_CHANGED")
end

---------------------------------------------------------------------------
-- The list (oldest first), and what is unread
---------------------------------------------------------------------------

local function Store()
	local rdb = ns.rdb
	if not rdb then return {} end
	if type(rdb.mentions) ~= "table" then rdb.mentions = {} end
	return rdb.mentions
end

-- The mentions we may still read: a channel we read, a writer not taken off the network.
function Mentions.List()
	local out, M, C = {}, ns.Moderation, ns.Channels
	for _, m in ipairs(Store()) do
		if type(m) == "table" and C and C.TIERS[m.tier] and C.CanUse(m.tier)
			and not (M and M.Hides and M.Any and M.Any() and M.Hides(m.sender, m.guild)) then
			out[#out + 1] = m
		end
	end
	return out
end

function Mentions.Unread()
	local n = 0
	for _, m in ipairs(Mentions.List()) do if not m.read then n = n + 1 end end
	return n
end

function Mentions.MarkRead(m)
	local changed = false
	for _, e in ipairs(Store()) do
		if (m == nil or e == m) and not e.read then e.read, changed = true, true end
	end
	if changed then ns.Fire("MENTIONS_CHANGED") end
end

function Mentions.Clear()
	if ns.rdb then ns.rdb.mentions = {} end
	Mentions.Dismiss()
	ns.Fire("MENTIONS_CHANGED")
end

-- The same line in a channel's history (ChatWindow.lua finds the bubble to mark and scroll to).
function Mentions.Same(a, b)
	return type(a) == "table" and type(b) == "table" and tonumber(a.t) == tonumber(b.t)
		and ns.FullName(a.sender or "") == ns.FullName(b.sender or "") and a.text == b.text
end

---------------------------------------------------------------------------
-- The feed: cards beside the minimap
---------------------------------------------------------------------------

local feed            -- the frame
local queue = {}      -- mentions waiting for a card, oldest first
local cards = {}      -- the cards on screen, top (oldest) first
local pool = {}
local lastIn = -math.huge

local function Clock() return GetTime and GetTime() or 0 end

local function Anchor(f)
	f:ClearAllPoints()
	local p = ns.db and ns.db.mentionFeedPos
	if type(p) == "table" and p[1] then
		f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	elseif rawget(_G, "Minimap") then
		f:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 0)
	else
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -20)
	end
end

local function TierLabel(t)
	local C = ns.Channels
	local d = C and C.TIERS[t]
	if not d then return "" end
	local c = d.color
	return ("|cff%02x%02x%02x[%s]|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, L[d.label] or t)
end

local function WhoText(m)
	local name = ns.Codec.Plain(ns.DisplayName(m.sender) or "?")
	local file = m.class and ns.CLASS_FILES and ns.CLASS_FILES[m.class]
	local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
	if c and c.colorStr then name = "|c" .. c.colorStr .. name .. "|r" end
	return name
end

local function Open(m)
	Mentions.MarkRead(m)
	local CW = ns.ChatWindow
	if CW and not CW.missing and CW.ShowMention then ns.SafeCall("mention open", CW.ShowMention, m) end
end

local function NewCard()
	local c = CreateFrame("Button", nil, feed, BackdropTemplateMixin and "BackdropTemplate" or nil)
	c:SetSize(CARD_W, CARD_H)
	if c.SetBackdrop then
		c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		c:SetBackdropColor(0.05, 0.03, 0.08, 0.9)
		c:SetBackdropBorderColor(1, 0.82, 0, 0.9)
	end
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(16, 16)
	c.icon:SetPoint("TOPLEFT", 8, -7)
	c.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
	c.who = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	c.who:SetPoint("LEFT", c.icon, "RIGHT", 4, 0)
	c.who:SetPoint("RIGHT", -8, 0)
	c.who:SetJustifyH("LEFT")
	c.who:SetWordWrap(false)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("TOPLEFT", 10, -24)
	c.text:SetPoint("RIGHT", -8, 0)
	c.text:SetJustifyH("LEFT")
	c.text:SetWordWrap(false)
	c:RegisterForClicks("LeftButtonUp")
	c:SetScript("OnClick", function(self)
		local m = self.m
		Mentions.Dismiss()
		if m then Open(m) end
	end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(self.who:GetText() or "", 1, 1, 1)
		GameTooltip:AddLine(self.full or "", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(L.MENTIONS_CARD_TIP, 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return c
end

local function Slot(i) return -((i - 1) * (CARD_H + CARD_GAP_Y)) end

local function PlaceFoot()
	local n = #queue
	feed.more:SetText(n > 0 and L.MENTIONS_MORE:format(n) or "")
	feed.foot:ClearAllPoints()
	feed.foot:SetPoint("TOPRIGHT", feed, "TOPRIGHT", 0, Slot(math.max(1, #cards) + 1) + 2)
	feed.foot:SetShown(#cards > 0)
end

local function Push(m)
	local c = table.remove(pool) or NewCard()
	c.m, c.born, c.leaving = m, Clock(), nil
	c.who:SetText(WhoText(m) .. "  " .. TierLabel(m.tier))
	local words = ns.Codec.SanitizeChat(m.text or "")
	c.text:SetText('"' .. words .. '"')
	c.full = words
	c.y = Slot(#cards + 1) - 12
	c.alpha = 0
	c:SetAlpha(0)
	c:ClearAllPoints()
	c:SetPoint("TOPRIGHT", feed, "TOPRIGHT", 0, c.y)
	c:Show()
	cards[#cards + 1] = c
	lastIn = Clock()
	PlaceFoot()
end

local function Hovered()
	if feed:IsMouseOver() then return true end
	for _, c in ipairs(cards) do if c:IsMouseOver() then return true end end
	return false
end

local function Step(_, elapsed)
	local now = Clock()
	local quiet = ns.Quiet and ns.Quiet()
	local hold = Hovered()
	-- The oldest card goes when its time is up (not while the mouse is on the feed).
	local top = cards[1]
	if top and not top.leaving and not hold and now - top.born >= Mentions.CARD_SECONDS then
		top.leaving = now
	end
	-- A new card, once there is room, a moment after the last one (never while quiet).
	if #queue > 0 and not quiet and #cards < Mentions.FEED_MAX and now - lastIn >= Mentions.CARD_GAP then
		-- (The user's call: a soft sound for each card, until the bunch is dismissed as a whole.)
		if ns.SoundOn and ns.SoundOn("mention") and PlaySound and SOUNDKIT then
			pcall(PlaySound, SOUNDKIT.TELL_MESSAGE or SOUNDKIT.READY_CHECK)
		end
		Push(table.remove(queue, 1))
	end
	-- Each card moves toward its place; the leaving one rolls up and fades.
	local k = math.min(1, (elapsed or 0) / Mentions.ROLL * 3)
	local i = 0
	for idx = #cards, 1, -1 do
		local c = cards[idx]
		if c.leaving and now - c.leaving >= Mentions.ROLL then
			c:Hide()
			pool[#pool + 1] = c
			table.remove(cards, idx)
			PlaceFoot()
		end
	end
	for _, c in ipairs(cards) do
		local target, alpha
		if c.leaving then
			target, alpha = Slot(1) + 24, 0
		else
			i = i + 1
			target, alpha = Slot(i), 1
		end
		c.y = c.y + (target - c.y) * k
		c.alpha = c.alpha + (alpha - c.alpha) * k
		c:ClearAllPoints()
		c:SetPoint("TOPRIGHT", feed, "TOPRIGHT", 0, c.y)
		c:SetAlpha(c.alpha)
	end
	PlaceFoot()
	if #cards == 0 and #queue == 0 then
		feed:Hide()
	end
end

local function Feed()
	if feed then return feed end
	local f = CreateFrame("Frame", "SylvanistasMentionFeed", UIParent)
	f:SetSize(CARD_W, CARD_H)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f.foot = CreateFrame("Frame", nil, f)
	f.foot:SetSize(CARD_W, FOOT_H)
	f.more = f.foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.more:SetPoint("LEFT", 6, 0)
	f.dismiss = CreateFrame("Button", nil, f.foot)
	f.dismiss:SetSize(80, FOOT_H)
	f.dismiss:SetPoint("RIGHT", -4, 0)
	f.dismiss.label = f.dismiss:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.dismiss.label:SetPoint("RIGHT")
	f.dismiss.label:SetText(L.MENTIONS_DISMISS)
	f.dismiss:SetScript("OnClick", function() Mentions.Dismiss() end)
	f.dismiss:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
	f.dismiss:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 0.82, 0) end)
	f:SetScript("OnUpdate", function(self, elapsed) ns.SafeCall("mention feed", Step, self, elapsed) end)
	f:Hide()
	feed = f
	Anchor(f)
	return f
end

-- Every card off the screen and the queue emptied (what was not seen stays unread).
function Mentions.Dismiss()
	queue = {}
	if not feed then return end
	for _, c in ipairs(cards) do c:Hide(); pool[#pool + 1] = c end
	cards = {}
	feed:Hide()
end

function Mentions.Queue() return queue end -- (tests)

---------------------------------------------------------------------------
-- A line came in
---------------------------------------------------------------------------

function Mentions.OnLine(tier, sender, text, guild, class)
	if not Mentions.On() or not ns.IsMember() then return end
	if not Mentions.Matches(text) then return end
	local list = Store()
	local m = { t = ns.Now(), tier = tier, sender = sender, guild = guild, class = class, text = text }
	list[#list + 1] = m
	while #list > Mentions.KEEP do table.remove(list, 1) end
	queue[#queue + 1] = m
	Feed():Show()
	ns.Fire("MENTIONS_CHANGED")
end

ns.On("CHAT_LINE", function(tier, sender, text, guild, class)
	ns.SafeCall("mention", Mentions.OnLine, tier, sender, text, guild, class)
end)

-- `/syl mentions [on|off|clear]`: alone, opens the Chat tab's Mentions view.
function Mentions.Slash(rest)
	local word = tostring(rest or ""):lower():match("^%s*(%S*)")
	if word == "on" or word == "off" then return Mentions.SetOn(word == "on") end
	if word == "clear" then
		Mentions.Clear()
		return ns.Print(L.MENTIONS_CLEARED)
	end
	local CW = ns.ChatWindow
	if CW and CW.ShowMentions then CW.ShowMentions() end
end
