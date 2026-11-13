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
	-- The main window took the chat (its Chat tab): this one closes.
	f.onChatTaken = function(self) self:Hide() end
	f:HookScript("OnHide", function(self)
		ns.ChatWindow.Detach(self)
		if cwin then cwin:Hide() end -- (its X closes both: the Crafters hang on it)
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
end

ns.On("LOGIN", function()
	-- (A moment after login: PUG Social makes its button at its own login.)
	ns.After(2, "chat dock", function()
		button = button or MakeButton("SylvanistasChatDockButton", ns.LOGO, true, ns.UI.FirstTexture(ns.UI.CHAT_ICONS),
			function() Dock.Toggle() end, function() Dock.SwitchToMain() end, L.CHATDOCK_TITLE, L.CHATDOCK_BUTTON_TIP)
		Anchor(button)
		Dock.Paint()
	end)
	ns.Every(30, "chat dock", function() Dock.Paint() end)
end)
