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

local win, button

local function Saved()
	ns.db.chatDock = type(ns.db.chatDock) == "table" and ns.db.chatDock or {}
	return ns.db.chatDock
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Where the window goes: where the player left it, else on the game's chat (its first window's
-- bottom left; taller than the chat, it reaches up over the screen's left side as PUG Social's does).
local function PlaceWindow(f)
	local p = Saved()
	f:ClearAllPoints()
	if tonumber(p.x) and tonumber(p.y) then
		f:SetSize(Clamp(tonumber(p.w) or Dock.WIDTH, Dock.WIDTH_MIN, Dock.WIDTH_MAX), Clamp(tonumber(p.h) or Dock.HEIGHT, Dock.HEIGHT_MIN, Dock.HEIGHT_MAX))
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
		return
	end
	local chat = DEFAULT_CHAT_FRAME or ChatFrame1
	f:SetSize(Dock.WIDTH, Dock.HEIGHT)
	if chat and chat.GetLeft and chat:GetLeft() then
		f:SetPoint("BOTTOMLEFT", chat, "BOTTOMLEFT", -8, -36)
	else
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 120)
	end
end

local function Remember(f)
	local p = Saved()
	p.x, p.y = math.floor((f:GetLeft() or 0) + 0.5), math.floor((f:GetBottom() or 0) + 0.5)
	p.w, p.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
end

-- The pane's places in this window (UI.ChatPlaces' shape): no top row, the lines from under the
-- title bar, the box to write in at the bottom.
local PLACES = {
	search = { left = 10, right = -8, top = -26 },
	box = { left = 6, top = -26, right = -6, bottom = 34 },
	input = { left = 8, right = -8, y = 7, h = 20 },
}

local function Build()
	if win then return win end
	local ok, f = pcall(CreateFrame, "Frame", "SylvanistasChatDock", UIParent, "BasicFrameTemplate")
	if not ok or not f then f = CreateFrame("Frame", "SylvanistasChatDock", UIParent, "BasicFrameTemplateWithInset") end
	f.compact = true
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
		Remember(self)
	end)
	local title = L.CHATDOCK_TITLE
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
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		Remember(f)
	end)
	f:SetScript("OnSizeChanged", function()
		if f:IsShown() and ns.ChatWindow.Host() == f then ns.SafeCall("chat dock size", ns.ChatWindow.Render) end
	end)

	-- The switch to the whole add-on: the round logo, as on the profession windows, at the title
	-- bar's left.
	local sw = ns.MakeRoundButton(nil, f, 26)
	sw:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 6)
	sw:SetFrameLevel(f:GetFrameLevel() + 10)
	sw:SetScript("OnClick", function() ns.SafeCall("chat dock switch", Dock.SwitchToMain) end)
	sw:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L.CHATDOCK_SWITCH, 1, 0.82, 0)
		GameTooltip:AddLine(L.CHATDOCK_SWITCH_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.switchButton = sw

	-- The main window took the chat (its Chat tab): this one closes.
	f.onChatTaken = function(self) self:Hide() end
	f:SetScript("OnHide", function(self)
		ns.ChatWindow.Detach(self)
		Dock.Paint()
	end)
	f:Hide()
	ns.EscapeCloses(f:GetName())
	f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end)
	PlaceWindow(f)
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
-- The docked button: over PUG Social's when it is there, else over the game's social button
---------------------------------------------------------------------------

local function Anchor(b)
	b:ClearAllPoints()
	local below = _G.Pugger_ChatButton
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

local function MakeButton()
	local b = CreateFrame("Button", "SylvanistasChatDockButton", UIParent)
	b:SetSize(Dock.BUTTON, Dock.BUTTON)
	b:SetFrameStrata("MEDIUM")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(ns.LOGO)
	if b.icon.SetMask then pcall(b.icon.SetMask, b.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	-- The small chat bubble on its corner (the Chat tab's own icon).
	b.bubble = b:CreateTexture(nil, "OVERLAY")
	b.bubble:SetSize(15, 15)
	b.bubble:SetPoint("BOTTOMRIGHT", 3, -3)
	b.bubble:SetTexture(ns.UI.FirstTexture(ns.UI.CHAT_ICONS))
	b.shine = b:CreateTexture(nil, "HIGHLIGHT")
	b.shine:SetAllPoints()
	b.shine:SetTexture(ns.LOGO)
	if b.shine.SetMask then pcall(b.shine.SetMask, b.shine, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	b.shine:SetBlendMode("ADD")
	b.shine:SetAlpha(0.35)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 1, -1) self.icon:SetPoint("BOTTOMRIGHT", 1, -1) end)
	b:SetScript("OnMouseUp", function(self) self.icon:SetAllPoints() end)
	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.SafeCall("chat dock switch", Dock.SwitchToMain)
		else ns.SafeCall("chat dock", Dock.Toggle) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.CHATDOCK_TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L.CHATDOCK_BUTTON_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Anchor(b)
	return b
end

-- Shown for members; lit while the narrow window is open.
function Dock.Paint()
	if not button then return end
	local member = ns.IsMember() and not ns.Channels.missing and ns.Channels.MyLevel() > 0
	button:SetShown(member)
	if Dock.IsShown() then button:LockHighlight() else button:UnlockHighlight() end
end

ns.On("LOGIN", function()
	-- (A moment after login: PUG Social makes its button at its own login.)
	ns.After(2, "chat dock", function()
		button = button or MakeButton()
		Anchor(button)
		Dock.Paint()
	end)
	ns.Every(30, "chat dock", function() Dock.Paint() end)
end)
