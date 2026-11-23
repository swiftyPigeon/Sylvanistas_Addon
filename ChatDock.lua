local ADDON, ns = ...
local L = ns.L

-- The chat by the game's chat (the user, 2026-11-13): a button docked with the game's chat buttons,
-- like PUG Social's (Sylvanistas's logo with a small chat bubble), that opens the Sylvanistas chats
-- alone in a narrow window, over the game's chat by default. That window has no top row, no
-- see-through levels and no tab's line: the lines, the box to write in, and one round button (as on
-- the profession windows) that switches to the whole add-on. The minimap button is unchanged.
-- The chat pane is ChatWindow.lua's own (ChatWindow.Attach with host.compact): one window holds the
-- chat at a time, so opening one closes the chat in the other.

local Dock = {}
ns.ChatDock = Dock

-- Its size: PUG Social's window's by default (300 x 470, the user's call), resizable within these.
Dock.WIDTH, Dock.HEIGHT = 300, 470
Dock.WIDTH_MIN, Dock.WIDTH_MAX = 260, 520
Dock.HEIGHT_MIN, Dock.HEIGHT_MAX = 220, 640
Dock.BUTTON = 32 -- the docked button, as PUG Social's
Dock.CRAFT_ICON = "Interface\\Icons\\Trade_BlackSmithing" -- the Crafters' own (Crafters.Link)

local win, button          -- the small chat and its button
local cwin                 -- the small Crafters window (2026-11-13; opened from the small chat's title bar)
local nwin                 -- 1.3.6: the small Nearby window (Finder.lua), from the same title bar

local function Saved(key)
	ns.db[key] = type(ns.db[key]) == "table" and ns.db[key] or {}
	return ns.db[key]
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Where a window goes: where the player left it, else on the game's chat (its first window's bottom
-- left, `dx` to the right of it; taller than the chat, it reaches up as PUG Social's does).
local function PlaceWindow(f, key, dx)
	local p = Saved(key)
	f:ClearAllPoints()
	if tonumber(p.x) and tonumber(p.y) then
		f:SetSize(Clamp(tonumber(p.w) or Dock.WIDTH, Dock.WIDTH_MIN, Dock.WIDTH_MAX), Clamp(tonumber(p.h) or Dock.HEIGHT, Dock.HEIGHT_MIN, Dock.HEIGHT_MAX))
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
		return
	end
	local chat = DEFAULT_CHAT_FRAME or ChatFrame1
	f:SetSize(Dock.WIDTH, Dock.HEIGHT)
	if chat and chat.GetLeft and chat:GetLeft() then
		f:SetPoint("BOTTOMLEFT", chat, "BOTTOMLEFT", -8 + dx, -36)
	else
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30 + dx, 120)
	end
end

local function Remember(f, key)
	local p = Saved(key)
	p.x, p.y = math.floor((f:GetLeft() or 0) + 0.5), math.floor((f:GetBottom() or 0) + 0.5)
	p.w, p.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
end

-- The chat pane's places in its window (UI.ChatPlaces' shape): no top row, the lines from under the
-- title bar, the box to write in at the bottom.
local PLACES = {
	search = { left = 10, right = -8, top = -26 },
	box = { left = 6, top = -26, right = -6, bottom = 34 },
	input = { left = 8, right = -8, y = 7, h = 20 },
}

-- A small window as both have it: the title, moved and sized by the player (kept in ns.db[key]),
-- its X, Escape, the resize grip, and the round logo at the title bar's left that switches to the
-- whole add-on (`switch`, `switchTip`). `onResized` after a resize.
local function Window(name, key, title, dx, switch, switchTip)
	local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplate")
	if not ok or not f then f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset") end
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		pcall(f.SetResizeBounds, f, Dock.WIDTH_MIN, Dock.HEIGHT_MIN, Dock.WIDTH_MAX, Dock.HEIGHT_MAX)
	elseif f.SetMinResize then
		pcall(f.SetMinResize, f, Dock.WIDTH_MIN, Dock.HEIGHT_MIN)
		pcall(f.SetMaxResize, f, Dock.WIDTH_MAX, Dock.HEIGHT_MAX)
	end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Remember(self, key)
	end)
	if f.SetTitle then f:SetTitle(title)
	elseif f.TitleText then f.TitleText:SetText(title)
	elseif f.TitleContainer and f.TitleContainer.TitleText then f.TitleContainer.TitleText:SetText(title) end
	-- Its X hides it itself (as the main window's: HideUIPanel does nothing in combat).
	f.onCloseCallback = function() f:Hide() return false end
	local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
	if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() f:Hide() end) end

	-- The resize grip, bottom right (the game's chat windows' own).
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip = grip
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		Remember(f, key)
	end)
	f:SetScript("OnSizeChanged", function(self)
		if self:IsShown() and self.onResized then ns.SafeCall(key .. " size", self.onResized, self) end
	end)

	-- The switch to the whole add-on: the round logo, as on the profession windows.
	local sw = ns.MakeRoundButton(nil, f, 26)
	sw:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 6)
	sw:SetFrameLevel(f:GetFrameLevel() + 10)
	sw:SetScript("OnClick", function() ns.SafeCall(key .. " switch", switch) end)
	sw:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.CHATDOCK_SWITCH, 1, 0.82, 0)
		GameTooltip:AddLine(switchTip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.switchButton = sw

	f:Hide()
	ns.EscapeCloses(f:GetName())
	f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	f:HookScript("OnHide", function() Dock.Paint() end)
	PlaceWindow(f, key, dx)
	return f
end

-- The game's own Professions button art (its micro menu's "K", the user's pick, 2026-11-13): read
-- from that button where it is, else its atlas by name, else the Crafters' icon.
Dock.PROFESSIONS_ATLAS = "UI-HUD-MicroMenu-Professions-Up"
function Dock.ProfessionsArt(tex)
	local mb = _G.ProfessionMicroButton
	local nt = type(mb) == "table" and mb.GetNormalTexture and mb:GetNormalTexture() or nil
	local atlas = nt and nt.GetAtlas and nt:GetAtlas() or nil
	if tex.SetAtlas then
		for _, a in ipairs({ atlas or false, Dock.PROFESSIONS_ATLAS }) do
			if a then
				local ok, res = pcall(tex.SetAtlas, tex, a)
				if ok and res ~= false and (not tex.GetAtlas or tex:GetAtlas()) then return true end
			end
		end
	end
	local file = nt and nt.GetTexture and nt:GetTexture() or nil
	if file then
		tex:SetTexture(file)
		return true
	end
	tex:SetTexture(Dock.CRAFT_ICON)
	return false
end

---------------------------------------------------------------------------
-- The small chat
---------------------------------------------------------------------------

local function Build()
	if win then return win end
	local f = Window("SylvanistasChatDock", "chatDock", L.CHATDOCK_TITLE, 0, function() Dock.SwitchToMain() end, L.CHATDOCK_SWITCH_TIP)
	f.compact = true
	f.onResized = function(self)
		if ns.ChatWindow.Host() == self then ns.ChatWindow.Render() end
	end
	-- The Crafters' icon in its title bar, left of the X (the user, 2026-11-13: part of the small
	-- chat, not a second docked button): the small Crafters window opens and closes; right-click,
	-- the whole add-on on its Crafters page. Lit while that window shows (Dock.Paint).
	local cb = CreateFrame("Button", nil, f)
	cb:SetSize(22, 28) -- (the micro menu's art: taller than wide, with room around the hammer; 16 x 20 was too small)
	local close = f.CloseButton or _G[f:GetName() .. "CloseButton"]
	if type(close) == "table" and close.GetObjectType then cb:SetPoint("RIGHT", close, "LEFT", 1, -1)
	else cb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -3) end
	cb:SetFrameLevel(f:GetFrameLevel() + 10)
	cb.icon = cb:CreateTexture(nil, "ARTWORK")
	cb.icon:SetAllPoints()
	Dock.ProfessionsArt(cb.icon)
	cb.glow = cb:CreateTexture(nil, "HIGHLIGHT")
	cb.glow:SetAllPoints()
	Dock.ProfessionsArt(cb.glow)
	cb.glow:SetBlendMode("ADD")
	cb.glow:SetAlpha(0.4)
	cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cb:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.SafeCall("crafters switch", Dock.CraftersToMain) else ns.SafeCall("crafters window", Dock.ToggleCrafters) end
	end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.CRAFTDOCK_TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.CRAFTDOCK_BUTTON_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.craftersButton = cb
	-- 1.3.6 (the user): Nearby's spyglass left of the Crafters' icon: the small Nearby window opens and
	-- closes beside the chat; right-click, the whole add-on on its Nearby tab. Lit while it shows.
	local nb = CreateFrame("Button", nil, f)
	-- (16 x 16, its icon's own border cropped, 6 px from the hammer: 20 x 20 overran the title bar's
	-- rim and sat too close, the user, 2026-11-20.)
	nb:SetSize(16, 16)
	nb:SetPoint("RIGHT", cb, "LEFT", -6, 1)
	nb:SetFrameLevel(f:GetFrameLevel() + 10)
	local spy = ns.UI and ns.UI.FirstTexture and ns.UI.SPYGLASSES and ns.UI.FirstTexture(ns.UI.SPYGLASSES) or "Interface\\Icons\\INV_Misc_Spyglass_03"
	nb.icon = nb:CreateTexture(nil, "ARTWORK")
	nb.icon:SetAllPoints()
	nb.icon:SetTexture(spy)
	nb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	nb.glow = nb:CreateTexture(nil, "HIGHLIGHT")
	nb.glow:SetAllPoints()
	nb.glow:SetTexture(spy)
	nb.glow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	nb.glow:SetBlendMode("ADD")
	nb.glow:SetAlpha(0.4)
	nb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	nb:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.SafeCall("nearby switch", Dock.NearbyToMain) else ns.SafeCall("nearby window", Dock.ToggleNearby) end
	end)
	nb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.NEARBYDOCK_TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.NEARBYDOCK_BUTTON_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	nb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.nearbyButton = nb
	-- 1.3.5 (the user): "Close after sending", a tick box in the title bar right of the round logo,
	-- off by default, kept in ns.db.chatDockAutoClose. On: a line sent, an empty Enter or Escape in
	-- the box closes the small chat, as the game's chat box does (CHAT_BOX_DONE below).
	local ac = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	ac:SetSize(22, 22)
	ac:SetPoint("LEFT", f.switchButton, "RIGHT", 0, -3)
	ac:SetFrameLevel(f:GetFrameLevel() + 10)
	ac:SetChecked(Dock.AutoClose())
	-- Its word beside it (the user): "Auto-close", red while off, light purple while on; a click on
	-- the word ticks the box too.
	ac.word = ac.Text or ac.text or ac:CreateFontString(nil, "OVERLAY")
	ac.word:SetFontObject("GameFontNormalSmall")
	ac.word:ClearAllPoints()
	ac.word:SetPoint("LEFT", ac, "RIGHT", -1, 1)
	ac.word:SetText(L.CHATDOCK_AUTOCLOSE_WORD)
	ac:SetHitRectInsets(0, -math.ceil(ac.word:GetStringWidth() or 50), 0, 0)
	Dock.PaintAutoClose(ac)
	ac:SetScript("OnClick", function(self) Dock.SetAutoClose(self:GetChecked() and true or false) end)
	ac:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.CHATDOCK_AUTOCLOSE, 1, 0.82, 0)
		GameTooltip:AddLine(L.CHATDOCK_AUTOCLOSE_TIP, 1, 1, 1, true)
		GameTooltip:AddLine(Dock.AutoClose() and L.CHATDOCK_AUTOCLOSE_ON or L.CHATDOCK_AUTOCLOSE_OFF, 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	ac:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.autoCloseBox = ac
	-- The main window took the chat (its Chat tab): this one closes.
	f.onChatTaken = function(self) self:Hide() end
	f:HookScript("OnHide", function(self)
		ns.ChatWindow.Detach(self)
		if cwin then cwin:Hide() end -- (its X closes both: the Crafters hang on it)
		if nwin then nwin:Hide() end -- (and Nearby, 1.3.6)
	end)
	win = f
	return f
end

-- Opened: the main window, if it holds the chat, closes first (one window holds it at a time).
function Dock.Open()
	local C = ns.Channels
	if C.missing or not ns.IsMember() or C.MyLevel() == 0 then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	local f = Build()
	local CW = ns.ChatWindow
	local h = CW.Host()
	if CW.IsShown() and h ~= f and h then h:Hide() end
	f:Show()
	CW.Attach(f, PLACES)
	CW.Render()
	Dock.Paint()
end

function Dock.Toggle()
	if win and win:IsShown() then win:Hide() else Dock.Open() end
end

function Dock.IsShown() return win ~= nil and win:IsShown() end

-- The whole add-on, on the tab it was last on (never Chat: that would only move the chat back).
function Dock.SwitchToMain()
	if win then win:Hide() end
	local UI = ns.UI
	local last = UI.LastTab and UI.LastTab() or nil
	UI.SelectTab((last and last ~= "chat") and last or "census")
end

---------------------------------------------------------------------------
-- The small Crafters window (the user, 2026-11-13): the Crafters board on its own, independent of
-- the Realm tab's page (what shows opened is its own: Crafters.Lines(nil, "dock")). Beside the small
-- chat by default. With the small chat open, a shift-click on a crafter's recipe puts
-- "@Crafter [item] " in its box (Crafters.TagInChat).
---------------------------------------------------------------------------

-- Anchored to the small chat's right side (the user, 2026-11-13): as tall as it, moved with it (a drag
-- on either moves both, the chat's place kept), its own width (the grip: wider or narrower, kept in
-- ns.db.craftDock.w). Its X closes it alone; the chat's closes both. No round logo of its own (the
-- chat's is beside it; the Crafters icon's right-click opens the whole add-on on its Crafters page).
Dock.CRAFT_GAP = 2

local function AnchorCrafters(f)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", win, "TOPRIGHT", Dock.CRAFT_GAP, 0)
	f:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", Dock.CRAFT_GAP, 0)
	f:SetWidth(Clamp(tonumber(Saved("craftDock").w) or Dock.WIDTH, Dock.WIDTH_MIN, Dock.WIDTH_MAX))
end

local function BuildCrafters()
	if cwin then return cwin end
	Build() -- (the chat it hangs on)
	local f = Window("SylvanistasCraftDock", "craftDock", L.CRAFTDOCK_TITLE, 0,
		function() Dock.CraftersToMain() end, L.CRAFTDOCK_SWITCH_TIP)
	f.switchButton:Hide()
	f:SetClampedToScreen(false) -- (the chat is; this follows it)
	-- A drag on it moves the pair (by the chat).
	f:SetScript("OnDragStart", function() win:StartMoving() end)
	f:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		Remember(win, "chatDock")
	end)
	-- Its grip: the width only; then hung on the chat again.
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("RIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		Saved("craftDock").w = math.floor(f:GetWidth() + 0.5)
		AnchorCrafters(f)
	end)
	local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", "SylvanistasCraftDockScroll", f, "UIPanelScrollFrameTemplate")
	if not okScroll or not scroll then scroll = CreateFrame("ScrollFrame", "SylvanistasCraftDockScroll", f) end
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 22)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(Dock.WIDTH - 40, 10)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	f.onResized = function() Dock.RedrawCrafters() end
	f:HookScript("OnShow", function() Dock.RedrawCrafters() end)
	AnchorCrafters(f)
	cwin = f
	return f
end

function Dock.CraftersShown() return cwin ~= nil and cwin:IsShown() end

function Dock.RedrawCrafters()
	if not Dock.CraftersShown() then return end
	local C = ns.Crafters
	if not C or type(C.Lines) ~= "function" then return end
	cwin.content:SetWidth(math.max(100, (cwin.scroll:GetWidth() or (Dock.WIDTH - 40))))
	ns.Views.Render(cwin.content, C.Lines(nil, "dock"))
end

function Dock.OpenCrafters()
	if not ns.IsMember() then
		ns.Print(L.MEMBERS_ONLY)
		return
	end
	if not Dock.IsShown() then Dock.Open() end -- (they hang on the chat)
	if not Dock.IsShown() then return end
	if nwin then nwin:Hide() end -- (1.3.6: one window beside the chat at a time)
	BuildCrafters():Show()
	Dock.RedrawCrafters()
	Dock.Paint()
end

function Dock.ToggleCrafters()
	if Dock.CraftersShown() then cwin:Hide() else Dock.OpenCrafters() end
end

-- The whole add-on on its Crafters page (the Realm tab's).
function Dock.CraftersToMain()
	if cwin then cwin:Hide() end
	ns.UI.SelectTab("realm")
	ns.Views.ShowPage("crafters")
end

ns.On("REALM_PAGE_CHANGED", function(key)
	if key == "crafters" then ns.SafeCall("crafters window", Dock.RedrawCrafters) end
end)

---------------------------------------------------------------------------
-- 1.3.6 (the user): the small Nearby window, Finder.lua's list beside the small chat, hung on it as
-- the Crafters' is (same place: one of the two shows at a time). Its own width (wider by default:
-- the rows carry Whisper, Invite and Recruit), kept in ns.db.nearbyDock.w. Its three buttons at the
-- bottom are the Nearby tab's: what to search, Search (one /who, from the click), Clear.
---------------------------------------------------------------------------
Dock.NEARBY_WIDTH = 400
Dock.NEARBY_BUTTONS_H = 26

local function AnchorNearby(f)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", win, "TOPRIGHT", Dock.CRAFT_GAP, 0)
	f:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", Dock.CRAFT_GAP, 0)
	f:SetWidth(Clamp(tonumber(Saved("nearbyDock").w) or Dock.NEARBY_WIDTH, Dock.WIDTH_MIN, Dock.WIDTH_MAX))
end

local function NearbyButton(f, label)
	local ok, b = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", nil, f)
		b:SetNormalFontObject("GameFontNormalSmall")
	end
	b:SetHeight(22)
	b:SetText(label)
	if b.GetFontString and b:GetFontString() then b:GetFontString():SetFontObject("GameFontNormalSmall") end
	return b
end

local function BuildNearby()
	if nwin then return nwin end
	Build() -- (the chat it hangs on)
	local f = Window("SylvanistasNearbyDock", "nearbyDock", L.NEARBYDOCK_TITLE, 0,
		function() Dock.NearbyToMain() end, L.NEARBYDOCK_SWITCH_TIP)
	f.switchButton:Hide()
	f:SetClampedToScreen(false) -- (the chat is; this follows it)
	f:SetScript("OnDragStart", function() win:StartMoving() end)
	f:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		Remember(win, "chatDock")
	end)
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("RIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		Saved("nearbyDock").w = math.floor(f:GetWidth() + 0.5)
		AnchorNearby(f)
	end)
	local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", "SylvanistasNearbyDockScroll", f, "UIPanelScrollFrameTemplate")
	if not okScroll or not scroll then scroll = CreateFrame("ScrollFrame", "SylvanistasNearbyDockScroll", f) end
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 22 + Dock.NEARBY_BUTTONS_H)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(Dock.NEARBY_WIDTH - 40, 10)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	-- The Nearby tab's buttons (UI.lua's BUTTONS.finder), the first two showing their state.
	local F = ns.Finder
	f.modeButton = NearbyButton(f, F.ModeLabel())
	f.modeButton:SetScript("OnClick", function() ns.SafeCall("nearby mode", F.NextMode) end)
	f.searchButton = NearbyButton(f, F.SearchLabel())
	f.searchButton:SetScript("OnClick", function() ns.SafeCall("nearby search", F.Search) Dock.RedrawNearby() end)
	f.searchButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(F.SearchLabel(), 1, 0.82, 0)
		GameTooltip:AddLine(L.FINDER_SEARCH_BTN_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.searchButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.modeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(F.ModeLabel(), 1, 0.82, 0)
		GameTooltip:AddLine(L.FINDER_MODE_BTN_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.modeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.clearButton = NearbyButton(f, L.FINDER_CLEAR_BTN)
	f.clearButton:SetScript("OnClick", function() ns.SafeCall("nearby clear", F.Clear) end)
	f.LayoutButtons = function(self)
		local inner = (self:GetWidth() or Dock.NEARBY_WIDTH) - 16 - 4
		local w = math.floor(inner / 3)
		self.modeButton:ClearAllPoints()
		self.modeButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 8, 20)
		self.modeButton:SetWidth(w)
		self.searchButton:ClearAllPoints()
		self.searchButton:SetPoint("LEFT", self.modeButton, "RIGHT", 2, 0)
		self.searchButton:SetWidth(w)
		self.clearButton:ClearAllPoints()
		self.clearButton:SetPoint("LEFT", self.searchButton, "RIGHT", 2, 0)
		self.clearButton:SetWidth(w)
	end
	f.onResized = function(self) self:LayoutButtons() Dock.RedrawNearby() end
	f:HookScript("OnShow", function(self) self:LayoutButtons() Dock.RedrawNearby() end)
	AnchorNearby(f)
	nwin = f
	return f
end

function Dock.NearbyShown() return nwin ~= nil and nwin:IsShown() end

function Dock.RedrawNearby()
	if not Dock.NearbyShown() then return end
	local F = ns.Finder
	if not F or type(F.Build) ~= "function" then return end
	nwin.modeButton:SetText(F.ModeLabel())
	nwin.searchButton:SetText(F.SearchLabel())
	nwin.content:SetWidth(math.max(100, (nwin.scroll:GetWidth() or (Dock.NEARBY_WIDTH - 40))))
	ns.Views.Render(nwin.content, (F.Build()))
end

-- (The small chat is for members: Nearby hangs on it, so it is too; non-members have the Nearby tab.)
function Dock.OpenNearby()
	if not Dock.IsShown() then Dock.Open() end
	if not Dock.IsShown() then return end
	if cwin then cwin:Hide() end -- (one window beside the chat at a time)
	BuildNearby():Show()
	Dock.RedrawNearby()
	Dock.Paint()
end

function Dock.ToggleNearby()
	if Dock.NearbyShown() then nwin:Hide() else Dock.OpenNearby() end
end

-- The whole add-on on its Nearby tab.
function Dock.NearbyToMain()
	if nwin then nwin:Hide() end
	ns.UI.SelectTab("finder")
end

ns.On("FINDER_CHANGED", function() ns.SafeCall("nearby window", Dock.RedrawNearby) end)

---------------------------------------------------------------------------
-- The docked button: over PUG Social's when it is there, else over the game's social button.
---------------------------------------------------------------------------

local function Anchor(b, over)
	b:ClearAllPoints()
	local below = over or _G.Pugger_ChatButton
	if type(below) ~= "table" or not below.GetObjectType then
		below = nil
		for _, name in ipairs({ "QuickJoinToastButton", "FriendsMicroButton", "ChatFrameChannelButton", "ChatFrameMenuButton" }) do
			local f = _G[name]
			if type(f) == "table" and f.GetObjectType then below = f break end
		end
	end
	if below then b:SetPoint("BOTTOM", below, "TOP", 0, 4)
	else b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 240) end
end

-- One docked button: `icon` (round when `round`), a small `badge` on its corner, a click and a
-- right-click, a tooltip.
local function MakeButton(name, icon, round, badge, onClick, onRight, title, tip)
	local b = CreateFrame("Button", name, UIParent)
	b:SetSize(Dock.BUTTON, Dock.BUTTON)
	b:SetFrameStrata("MEDIUM")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(icon)
	b.shine = b:CreateTexture(nil, "HIGHLIGHT")
	b.shine:SetAllPoints()
	b.shine:SetTexture(icon)
	b.shine:SetBlendMode("ADD")
	b.shine:SetAlpha(0.35)
	if round then
		for _, t in ipairs({ b.icon, b.shine }) do
			if t.SetMask then pcall(t.SetMask, t, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
		end
	end
	if badge then
		b.badge = b:CreateTexture(nil, "OVERLAY")
		b.badge:SetSize(15, 15)
		b.badge:SetPoint("BOTTOMRIGHT", 3, -3)
		b.badge:SetTexture(badge)
	end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 1, -1) self.icon:SetPoint("BOTTOMRIGHT", 1, -1) end)
	b:SetScript("OnMouseUp", function(self) self.icon:SetAllPoints() end)
	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.SafeCall(name .. " right", onRight) else ns.SafeCall(name, onClick) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 0.82, 0)
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- The docked button shown for members, lit while the small chat is open; the Crafters' icon in its
-- title bar lit while the small Crafters window is open.
function Dock.Paint()
	local member = ns.IsMember() and not ns.Channels.missing and ns.Channels.MyLevel() > 0
	if button then
		button:SetShown(member)
		if Dock.IsShown() then button:LockHighlight() else button:UnlockHighlight() end
	end
	local cb = win and win.craftersButton
	if cb then
		if Dock.CraftersShown() then cb:LockHighlight() else cb:UnlockHighlight() end
	end
	local nb = win and win.nearbyButton
	if nb then
		if Dock.NearbyShown() then nb:LockHighlight() else nb:UnlockHighlight() end
	end
end

-- 1.3.5 (user): the bubble on the button's corner pulses white to red when a line from someone else comes in
-- while the chat shows nowhere (neither the small window nor the main one's Chat tab), and white
-- again once the chat is seen (CHAT_SEEN, ChatWindow.Attach).
-- (1.3.5.1, the user: not a static red, a slow fade white -> red -> white until the chat is seen;
-- the OnUpdate runs only while it pulses.)
local unseen = false
Dock.PULSE_SECONDS = 1.6 -- one white -> red -> white
local pulseAt = 0
local function Pulse(self, elapsed)
	pulseAt = (pulseAt + (elapsed or 0)) % Dock.PULSE_SECONDS
	local red = (1 - math.cos(pulseAt / Dock.PULSE_SECONDS * 2 * math.pi)) / 2 -- 0 white .. 1 red
	local gb = 1 - red * 0.85
	self.badge:SetVertexColor(1, gb, gb)
end
function Dock.PaintBubble()
	if not (button and button.badge) then return end
	if unseen and ns.ChatWindow.IsShown() then unseen = false end
	if unseen then
		if not button.pulsing then
			button.pulsing, pulseAt = true, 0
			button:SetScript("OnUpdate", Pulse)
		end
	else
		if button.pulsing then
			button.pulsing = nil
			button:SetScript("OnUpdate", nil)
		end
		button.badge:SetVertexColor(1, 1, 1)
	end
end
function Dock.Unseen() return unseen end
ns.On("CHAT_LINE", function(t)
	if ns.Channels.CanUse(t) and not ns.ChatWindow.IsShown() then unseen = true end
	Dock.PaintBubble()
end)
ns.On("CHAT_SEEN", function()
	unseen = false
	Dock.PaintBubble()
end)

---------------------------------------------------------------------------
-- 1.3.5 (the user): the Talk binding (Bindings.xml, Key Bindings > AddOns: "Talk in the Sylvanistas
-- chat", Ctrl+Enter by default): the small chat opened if no chat shows, then the keyboard to the
-- box of the chat that shows. Only Sylvanistas's own frames: the game's chat box is never touched.
-- The game may leave an add-on's default key unbound on characters made before it: Ctrl+Enter is
-- then borrowed as an override, only while the player has no key of their own for Talk and nothing
-- else holds Ctrl+Enter; never in combat, never with the gamepad UI (whose code rebinds on every
-- UPDATE_BINDINGS, ChatWindow.lua's notes); changed only when what is wanted changes.
---------------------------------------------------------------------------
Dock.TALK_KEY = "CTRL-ENTER"
Dock.TALK_ACTION = "SYLVANISTAS_TALK"
local talkOwner, talkHeld, talkSyncing = nil, false, false

function Dock.Talk(down)
	if down == "up" or down == false then return end
	local CW = ns.ChatWindow
	if not CW.IsShown() then Dock.Open() end
	CW.FocusBox()
end

-- "Close after sending" (the title bar's tick box): off unless the player turned it on.
function Dock.AutoClose() return type(ns.db) == "table" and ns.db.chatDockAutoClose == true end
Dock.AUTOCLOSE_OFF_COLOUR = { 1, 0.25, 0.25 } -- red
Dock.AUTOCLOSE_ON_COLOUR = { 0.8, 0.6, 1 }     -- light purple
function Dock.PaintAutoClose(ac)
	if not (ac and ac.word) then return end
	local c = Dock.AutoClose() and Dock.AUTOCLOSE_ON_COLOUR or Dock.AUTOCLOSE_OFF_COLOUR
	ac.word:SetTextColor(c[1], c[2], c[3])
end
function Dock.SetAutoClose(on)
	if type(ns.db) ~= "table" then return end
	ns.db.chatDockAutoClose = on and true or nil
	local ac = win and win.autoCloseBox
	if ac then
		ac:SetChecked(on and true or false)
		Dock.PaintAutoClose(ac)
	end
end
ns.On("CHAT_BOX_DONE", function()
	if not Dock.AutoClose() then return end
	if win and win:IsShown() and ns.ChatWindow.Host() == win then win:Hide() end
end)
BINDING_NAME_SYLVANISTAS_TALK = L.TALK_BINDING or "Talk in the Sylvanistas chat"
function SylvanistasTalkBinding(keystate) ns.SafeCall("talk binding", Dock.Talk, keystate) end

local function Str(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v or nil end

-- Whether Ctrl+Enter should be ours now: the player's own Talk key none, the key free in their
-- bindings (ours aside).
function Dock.TalkKeyWanted()
	if ns.GamepadUI() or type(GetBindingKey) ~= "function" or type(GetBindingAction) ~= "function" then return false end
	local ok, own = pcall(GetBindingKey, Dock.TALK_ACTION)
	if not ok or (own ~= nil and Str(own) == nil) then return false end
	if Str(own) then return false end
	local ok2, action = pcall(GetBindingAction, Dock.TALK_KEY, false)
	return ok2 and Str(action) == ""
end

function Dock.SyncTalkKey()
	if talkSyncing then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if type(SetOverrideBinding) ~= "function" or type(ClearOverrideBindings) ~= "function" then return end
	local want = Dock.TalkKeyWanted()
	if want == talkHeld then return end
	talkSyncing = true
	local ok, err = pcall(function()
		talkOwner = talkOwner or CreateFrame("Frame")
		ClearOverrideBindings(talkOwner)
		if want then SetOverrideBinding(talkOwner, false, Dock.TALK_KEY, Dock.TALK_ACTION) end
		talkHeld = want
	end)
	talkSyncing = false
	if not ok then error(err, 0) end
end
function Dock.TalkKeyHeld() return talkHeld end
ns.RegisterEvent("UPDATE_BINDINGS", function() ns.SafeCall("talk key", Dock.SyncTalkKey) end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() ns.SafeCall("talk key", Dock.SyncTalkKey) end)
pcall(ns.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function() ns.SafeCall("talk key", Dock.SyncTalkKey) end)

ns.On("LOGIN", function()
	ns.SafeCall("talk key", Dock.SyncTalkKey)
	-- (A moment after login: PUG Social makes its button at its own login.)
	ns.After(2, "chat dock", function()
		button = button or MakeButton("SylvanistasChatDockButton", ns.LOGO, true, ns.UI.FirstTexture(ns.UI.CHAT_ICONS),
			function() Dock.Toggle() end, function() Dock.SwitchToMain() end, L.CHATDOCK_TITLE, L.CHATDOCK_BUTTON_TIP)
		Anchor(button)
		Dock.Paint()
		Dock.PaintBubble()
	end)
	ns.Every(30, "chat dock", function() Dock.Paint() end)
end)
