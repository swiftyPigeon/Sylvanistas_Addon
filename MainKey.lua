local ADDON, ns = ...

-- 1.2.21 (from Olympus 1.2.1): a session-only shortcut that opens and closes the window. The
-- player's saved bindings and other addons' overrides stay theirs: the key is borrowed only while
-- both its base binding and its override slot are empty. The key is Shift + the game's guild key
-- (Forever's "Guild & Communities" is J), read at run time from the player's own binding of
-- TOGGLEGUILDTAB, so a guild key moved elsewhere moves this one too. A guild key that already has a
-- modifier, or none bound, gives Shift-J. The player's own key is the game's: Key Bindings,
-- AddOns, "Toggle Sylvanistas" (Bindings.xml, MainKey.Toggle below). Mouse and keyboard only: with
-- the gamepad UI nothing is borrowed. /syl hotkey on|off.
local Key = {}
ns.MainKey = Key
local BUTTON = "SylvanistasMainKey"
local ACTION = "CLICK " .. BUTTON .. ":LeftButton"
Key.GUILD_ACTION = "TOGGLEGUILDTAB"
Key.FALLBACK = "SHIFT-J"
local button, held, pending, syncing

local function Combat()
	if type(InCombatLockdown) ~= "function" then return true end
	local ok, locked = pcall(InCombatLockdown)
	return not ok or locked ~= false
end

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
local function Allowed() return not ns.GamepadUI() end

function Key.Enabled() return type(ns.db) == "table" and ns.db.mainKeyOff ~= true end

-- The key this session borrows: "SHIFT-" and the first key bound to the game's guild window, when
-- that key has no modifier of its own; else Key.FALLBACK.
function Key.Wanted()
	if type(GetBindingKey) ~= "function" then return Key.FALLBACK end
	local ok, first = pcall(GetBindingKey, Key.GUILD_ACTION)
	if not ok or Secret(first) or type(first) ~= "string" or first == "" then return Key.FALLBACK end
	for _, mod in ipairs({ "ALT", "CTRL", "SHIFT", "META", "LALT", "RALT", "LCTRL", "RCTRL", "LSHIFT", "RSHIFT" }) do
		if first:sub(1, #mod + 1) == mod .. "-" and #first > #mod + 1 then return Key.FALLBACK end
	end
	return "SHIFT-" .. first
end

-- Nothing bound to that key, neither saved nor an override (ours aside).
local function Available(key)
	if not Allowed() or type(GetBindingAction) ~= "function" then return false end
	key = key or Key.Wanted()
	for _, overrides in ipairs({ false, true }) do
		local ok, action = pcall(GetBindingAction, key, overrides)
		if not ok or Secret(action) or type(action) ~= "string"
			or (action ~= "" and not (overrides and held == key and action == ACTION)) then return false end
	end
	return true
end

local function Release()
	if not held then pending = nil; return true end
	if Combat() then pending = true; return false end
	if type(ClearOverrideBindings) ~= "function" then return false end
	local ok = pcall(ClearOverrideBindings, button)
	if ok then held, pending = nil, nil end
	return ok
end

function Key.Press(_, _, down)
	if not Allowed() then return end
	if down == false or not Key.Enabled() or not ns.IsMember() or not held or not Available(held) then return end
	if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

function Key.Refresh()
	if syncing then return end
	if not Allowed() then Release() return end
	if Combat() then pending = true; return end
	syncing = true
	local key = Key.Wanted()
	-- (The guild key moved: the old borrowed key goes back first.)
	if held and held ~= key then Release() end
	if not Key.Enabled() or not ns.IsMember() or not Available(key) then
		Release()
	elseif not held and type(SetOverrideBindingClick) == "function" then
		if not button then
			button = CreateFrame("Button", BUTTON, UIParent)
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", Key.Press)
		end
		held = pcall(SetOverrideBindingClick, button, false, key, BUTTON, "LeftButton") and key or nil
	end
	syncing, pending = nil, nil
end

function Key.SetEnabled(on)
	if type(ns.db) ~= "table" or type(on) ~= "boolean" then return false end
	ns.db.mainKeyOff = not on or nil
	Key.Refresh()
	return true
end

-- The key as the game writes it for the player ("Shift-J"), else as bound ("SHIFT-J").
function Key.Text(key)
	key = key or held or Key.Wanted()
	if type(GetBindingText) == "function" then
		local ok, text = pcall(GetBindingText, key)
		if ok and not Secret(text) and type(text) == "string" and text ~= "" then return text end
	end
	return key
end

function Key.Slash(text)
	text = tostring(text or ""):lower()
	if text == "on" or text == "off" then Key.SetEnabled(text == "on") end
	ns.Print(ns.L.MAINKEY_STATUS:format(Key.Text(), Key.Enabled() and ns.L.MAINKEY_ON or ns.L.MAINKEY_OFF))
end

-- The game's Key Bindings menu (Bindings.xml: AddOns, "Toggle Sylvanistas"): a key the player chose
-- there, saved by the game as any binding. It opens and closes the window as the minimap button
-- does, whatever /syl hotkey says (that switch is the borrowed key's alone).
function Key.Toggle(down)
	if down == "up" or down == false then return end
	if ns.UI and ns.UI.Toggle then ns.SafeCall("toggle binding", ns.UI.Toggle) end
end
BINDING_HEADER_SYLVANISTAS = "Sylvanistas"
BINDING_NAME_SYLVANISTAS_TOGGLE = ns.L and ns.L.MAINKEY_BINDING or "Toggle Sylvanistas"
function SylvanistasToggleBinding(keystate) Key.Toggle(keystate) end

function Key.Held() return held ~= nil end
function Key.HeldKey() return held end
ns.On("LOGIN", function() Key.Refresh() end)
ns.RegisterEvent("UPDATE_BINDINGS", function() Key.Refresh() end)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function() Key.Refresh() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then Key.Refresh() end end)
