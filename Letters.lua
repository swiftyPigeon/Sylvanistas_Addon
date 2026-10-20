local ADDON, ns = ...
local L = ns.L

-- The "what's new" letters (1.2.20, after Olympus 1.1.5's version letters): after the addon updates
-- to a new version, once a version, a short letter about what changed in it, on a window of our own
-- with a parchment page. `/syl letters` lists every letter, newest first, and a click opens one;
-- `/syl letters <version>` opens that one. The help page (the window's "i") names the command.
-- When it shows by itself: a few seconds after login (LOGIN_WAIT, then every RETRY until it could),
-- for a member of a Sylvanistas guild, never in combat or an instance, and never while the privacy
-- page shows or still has a question to ask this session (that page comes first).
-- Once a version, saved per account (ns.db.lettersRead[version]). A first install stays quiet: its
-- version is a baseline (ns.db.lettersAutoVersion), not an update. An account from before 1.2.20
-- (sessions, no baseline) is an update: its letter shows.
-- A letter is a headline in the quest font (L.LETTER_<version>_HEADLINE, the version's dots as
-- underscores) over one or more sections (Letters.PARTS: by default the version's own), each a
-- subsection title (L.LETTER_<part>_TITLE) and its points (L.LETTER_<part>: one per line, each
-- starting "- ", drawn as bullets with a hanging indent). English and pt-BR; a version listed here
-- without its strings is left out. Going forward: every release adds its version to LIST, its
-- headline, and one section (its title and points), or several through PARTS.

local Letters = {}
ns.Letters = Letters
local SizedFont -- (below)

-- Every version with a letter, newest first.
Letters.LIST = { "1.3.0", "1.2.21" }
-- A letter's sections, in order, when it has more than its own. 1.2.21 is the first release with
-- letters: it also tells 1.2.2's changes and 1.2.20's (never released on its own).
Letters.PARTS = { ["1.2.21"] = { "1.2.2", "1.2.20", "1.2.21" }, ["1.3.0"] = { "1.3.0", "1.3.0b", "1.3.0c", "1.3.0d" } }
Letters.SPACING = 3       -- extra pixels between a paragraph's lines
Letters.BULLET_GAP = 6    -- between two points
Letters.SECTION_GAP = 14  -- before a subsection title
Letters.INDENT = 14       -- a point's text, after its bullet
Letters.LOGIN_WAIT = 8
Letters.RETRY = 10
Letters.WIDTH, Letters.HEIGHT = 440, 470

local frame, ticker, waited

local function Key(version) return "LETTER_" .. tostring(version):gsub("%.", "_") end

local function Str(key)
	local v = rawget(L, key)
	return type(v) == "string" and v ~= "" and v or nil
end
-- A section's title and points.
local function Section(part)
	local key = Key(part)
	local title, body = Str(key .. "_TITLE"), Str(key)
	if not (title and body) then return nil end
	local points = {}
	for line in (body .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then points[#points + 1] = { text = line:gsub("^%-%s*", ""), bullet = line:find("^%-") ~= nil } end
	end
	return { version = part, title = title, points = points }
end
local function Headline(version) return Str(Key(version) .. "_HEADLINE") end
function Letters.Has(version) return Headline(version) ~= nil and Section(version) ~= nil end

local function Read()
	local db = ns.db
	if type(db) ~= "table" then return {} end
	if type(db.lettersRead) ~= "table" then db.lettersRead = {} end
	return db.lettersRead
end
function Letters.IsRead(version) return Read()[version] == true end
function Letters.MarkRead(version)
	if not version then return end
	Read()[version] = true
	if version == ns.VERSION and type(ns.db) == "table" then ns.db.lettersAutoVersion = version end
end

-- A version's letter: its headline and its sections, in order; parts: the versions they tell.
function Letters.Text(version)
	local headline = Headline(version)
	if not headline then return nil end
	local sections, parts = {}, {}
	for _, part in ipairs(Letters.PARTS[version] or { version }) do
		local sec = Section(part)
		if sec then sections[#sections + 1], parts[#parts + 1] = sec, part end
	end
	if #sections == 0 then return nil end
	return headline, sections, parts
end

-- The versions with a letter, newest first.
function Letters.Versions()
	local out = {}
	for _, v in ipairs(Letters.LIST) do if Letters.Has(v) then out[#out + 1] = v end end
	return out
end

-- An update since the last letter shown (see the top of the file).
local function AutoEligible()
	local db = ns.db
	if type(db) ~= "table" then return false end
	if type(db.sessions) ~= "number" or not (db.sessions > 1) then
		db.lettersAutoVersion = ns.VERSION
		return false
	end
	local baseline = db.lettersAutoVersion
	if type(baseline) == "string" and #baseline <= 12 and baseline:match("^%d+%.%d+%.%d+$") then
		local W = ns.Workshop
		return W ~= nil and type(W.Newer) == "function" and W.Newer(ns.VERSION, baseline) == true
	end
	return true
end
Letters.AutoEligible = AutoEligible -- (tests)

local function Busy()
	return (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) and true or false
end

-- The privacy page shows, or still has a question to ask this session: it comes first.
local function PageFirst()
	local C = ns.Consent
	if type(C) ~= "table" then return false end
	local f = type(C.Frame) == "function" and C.Frame() or nil
	if f and f:IsShown() then return true end
	return type(C.Waiting) == "function" and C.Waiting() == true
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Height(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return h end
	end
	-- (No measure: about 6 pixels a letter, 14 a line.)
	local lines = 0
	for line in ((fs:GetText() or "") .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(#line / math.max(1, math.floor(width / 6))))
	end
	return lines * 14
end

local function Button(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 22)
	b:SetText(label)
	return b
end

Letters.HEADLINE_SIZE, Letters.SECTION_SIZE = 20, 15

-- A font string in its font object's face at `size` (the quest font's, for the headline and the
-- subsection titles); left as it is where the client gives no face.
SizedFont = function(fs, size)
	local face, _, flags = fs:GetFont()
	if face then fs:SetFont(face, size, flags) end
end

local function Make()
	local f = CreateFrame("Frame", "SylvanistasLetterFrame", UIParent)
	f:SetSize(Letters.WIDTH, Letters.HEIGHT)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	local okBorder, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderTemplate")
	if not okBorder or not border then
		border = f:CreateTexture(nil, "BACKGROUND")
		border:SetColorTexture(0, 0, 0, 0.9)
	end
	border:SetAllPoints()
	f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.heading:SetPoint("TOPLEFT", 20, -18)
	f.heading:SetPoint("RIGHT", -40, 0)
	f.heading:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() f:Hide() end)
	-- The page: the game's inset box, the parchment inside it, scrolled when a letter is long.
	local okBox, box = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if not okBox or not box then box = CreateFrame("Frame", nil, f) end
	box:SetPoint("TOPLEFT", 16, -44)
	box:SetPoint("BOTTOMRIGHT", -16, 44)
	local paper = box:CreateTexture(nil, "BACKGROUND", nil, 1)
	paper:SetPoint("TOPLEFT", 3, -3)
	paper:SetPoint("BOTTOMRIGHT", -3, 3)
	local file = ns.UI and ns.UI.FirstTexture and ns.UI.FirstTexture(ns.UI.PARCHMENTS) or "Interface\\QuestFrame\\QuestBG"
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		paper:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		paper:SetTexture(file)
		if file:find("QuestBG", 1, true) then paper:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	local scroll = CreateFrame("ScrollFrame", "SylvanistasLetterScroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -10)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)
	f.scroll = scroll
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(Letters.WIDTH - 80, 10)
	scroll:SetScrollChild(page)
	f.page = page
	-- The headline, in the quest font (the parchment's own), larger.
	f.title = page:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	f.title:SetJustifyH("LEFT")
	SizedFont(f.title, Letters.HEADLINE_SIZE)
	f.sign = page:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	f.sign:SetJustifyH("RIGHT")
	f.parts = {} -- the subsection titles, bullets and points, made as needed (Part)
	f.rows = {}
	f.done = Button(f, L.LETTERS_CLOSE, 100)
	f.done:SetPoint("BOTTOMRIGHT", -16, 14)
	f.done:SetScript("OnClick", function() f:Hide() end)
	f.all = Button(f, L.LETTERS_ALL, 130)
	f.all:SetPoint("BOTTOMLEFT", 16, 14)
	f.all:SetScript("OnClick", function() ns.SafeCall("letters", Letters.ShowHistory) end)
	return f
end

local function Frame()
	frame = frame or Make()
	if ns.EscapeCloses then ns.EscapeCloses(frame:GetName()) end
	return frame
end

local function HideRows(f)
	for _, r in ipairs(f.rows) do r:Hide() end
end

-- The page's pieces, kept for the next letter: kind "title" (a subsection title), "bullet" (its
-- mark) or "text" (a point).
local function Part(f, kind, n)
	f.parts[kind] = f.parts[kind] or {}
	local list = f.parts[kind]
	local fs = list[n]
	if fs then return fs end
	if kind == "title" then
		fs = f.page:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormal")
		SizedFont(fs, Letters.SECTION_SIZE)
	else
		fs = f.page:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
		if kind == "text" then
			if fs.SetWordWrap then fs:SetWordWrap(true) end
			if fs.SetSpacing then fs:SetSpacing(Letters.SPACING) end
		end
	end
	fs:SetJustifyH("LEFT")
	if fs.SetJustifyV then fs:SetJustifyV("TOP") end
	list[n] = fs
	return fs
end
local function HideParts(f)
	for _, list in pairs(f.parts) do for _, fs in ipairs(list) do fs:Hide() end end
end

-- A version's letter in the window; true when it has one.
function Letters.Show(version)
	local headline, sections, parts = Letters.Text(version)
	if not headline then return false end
	local f = Frame()
	HideRows(f)
	HideParts(f)
	local width = Letters.WIDTH - 80
	f.heading:SetText(L.LETTER_TITLE:format(version))
	f.title:ClearAllPoints()
	f.title:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, 0)
	f.title:SetWidth(width)
	f.title:SetText(headline)
	f.title:Show()
	local y = -Height(f.title, width) - 6
	local n = { title = 0, bullet = 0, text = 0 }
	for _, sec in ipairs(sections) do
		y = y - Letters.SECTION_GAP
		n.title = n.title + 1
		local t = Part(f, "title", n.title)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, y)
		t:SetWidth(width)
		t:SetText(sec.title)
		t:Show()
		y = y - Height(t, width) - 6
		for _, point in ipairs(sec.points) do
			local indent = point.bullet and Letters.INDENT or 0
			if point.bullet then
				n.bullet = n.bullet + 1
				local b = Part(f, "bullet", n.bullet)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f.page, "TOPLEFT", 2, y)
				b:SetText("\226\128\162") -- (a bullet, U+2022)
				b:Show()
			end
			n.text = n.text + 1
			local fs = Part(f, "text", n.text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", f.page, "TOPLEFT", indent, y)
			fs:SetWidth(width - indent)
			fs:SetText(point.text)
			fs:Show()
			y = y - Height(fs, width - indent) - Letters.BULLET_GAP
		end
	end
	y = y - 8
	f.sign:ClearAllPoints()
	f.sign:SetPoint("TOPRIGHT", f.page, "TOPRIGHT", 0, y)
	f.sign:SetWidth(width)
	f.sign:SetText(L.LETTER_SIGNED)
	f.sign:Show()
	y = y - 24
	f.page:SetHeight(-y)
	if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
	f.all:Show()
	Letters.MarkRead(version)
	for _, v in ipairs(parts) do Letters.MarkRead(v) end
	f:Show()
	return true
end

local function Row(f, i)
	local r = f.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, f.page)
	r:SetHeight(22)
	r.text = r:CreateFontString(nil, "ARTWORK", _G.QuestFont and "QuestFont" or "GameFontHighlight")
	r.text:SetPoint("LEFT", 4, 0)
	r.text:SetPoint("RIGHT", -4, 0)
	r.text:SetJustifyH("LEFT")
	if r.text.SetWordWrap then r.text:SetWordWrap(false) end
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r:SetScript("OnClick", function(self) ns.SafeCall("letters", Letters.Show, self.version) end)
	f.rows[i] = r
	return r
end

-- Every letter, newest first; a click opens that version's letter.
function Letters.ShowHistory()
	local f = Frame()
	f.heading:SetText(L.LETTERS_TITLE)
	HideParts(f)
	f.sign:Hide()
	local width = Letters.WIDTH - 80
	f.title:Hide()
	local intro = Part(f, "text", 1)
	intro:ClearAllPoints()
	intro:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, 0)
	intro:SetWidth(width)
	intro:SetText(L.LETTERS_INTRO)
	intro:Show()
	local y = -Height(intro, width) - 10
	local list = Letters.Versions()
	for i, v in ipairs(list) do
		local r = Row(f, i)
		r.version = v
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f.page, "TOPLEFT", 0, y)
		r:SetWidth(width)
		local now = v == ns.VERSION and ("  |cff990000(" .. L.LETTERS_CURRENT .. ")|r") or "" -- (crimson: grey is unreadable on the parchment)
		r.text:SetText(L.LETTERS_ROW:format(v, Headline(v)) .. now)
		r:Show()
		y = y - 24
	end
	for i = #list + 1, #f.rows do f.rows[i]:Hide() end
	f.page:SetHeight(math.max(10, -y))
	if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
	f.all:Hide()
	f:Show()
	return f
end

function Letters.Frame() return frame end
function Letters.Hide() if frame then frame:Hide() end end

---------------------------------------------------------------------------
-- By itself, once a version
---------------------------------------------------------------------------

-- This version's unread letter, when nothing keeps it back (see the top). True when it showed.
function Letters.Ask(reason)
	local v = ns.VERSION
	if not Letters.Has(v) or Letters.IsRead(v) or not AutoEligible() then return false end
	if ns.IsMember() ~= true or Busy() or PageFirst() then return false end
	if frame and frame:IsShown() then return false end
	ns.Log("version letter %s shown (%s)", tostring(v), tostring(reason or "?"))
	return Letters.Show(v)
end

function Letters.OnLogin()
	if not Letters.Has(ns.VERSION) or Letters.IsRead(ns.VERSION) or not AutoEligible() then return end
	ns.After(Letters.LOGIN_WAIT, "version letter", function()
		waited = true
		Letters.Ask("login")
	end)
	ticker = ns.Every(Letters.RETRY, "version letter", function()
		if Letters.IsRead(ns.VERSION) then
			if ticker and ticker.Cancel then ticker:Cancel() end
			ticker = nil
			return
		end
		if waited then Letters.Ask("login") end
	end)
end
ns.On("LOGIN", function() Letters.OnLogin() end)

-- `/syl letters` (the list), `/syl letters <version>` (that letter; one without a letter: the list).
function Letters.Slash(rest)
	local v = type(rest) == "string" and rest:match("^%s*(%d+%.%d+%.%d+)%s*$") or nil
	if v and Letters.Show(v) then return end
	Letters.ShowHistory()
end

function Letters.StatusLine()
	local read = {}
	for _, v in ipairs(Letters.Versions()) do if Letters.IsRead(v) then read[#read + 1] = v end end
	return ("%s  |  read: %s"):format(Letters.Has(ns.VERSION) and (Letters.IsRead(ns.VERSION) and "this version's shown" or "this version's waiting")
		or "none for this version", #read > 0 and table.concat(read, ", ") or "none")
end

-- Tests start from a clean state.
function Letters.Reset()
	if ticker and ticker.Cancel then ticker:Cancel() end
	ticker, waited = nil, nil
	if frame then frame:Hide() end
	frame = nil
end
