local ADDON, ns = ...

-- The game's week (1.3.0: kept from the dues, which are gone): from one weekly reset to the next.
-- Where the week starts: the client's own weekly reset (the server's clock plus the time left to
-- it, rounded to the hour it falls on: every client of a region works out the same one), or the US
-- realms' while the client can't say (asked again next time: early in a login it may not).
-- Your week (WeekLog.lua) and the week's brief (WeeklyBrief.lua) count by it.
local Weeks = {}
ns.Weeks = Weeks

Weeks.WEEK = 7 * 86400
Weeks.RESET_US = 486000 -- Tuesday 15:00 UTC (the US realms' reset) where the client can't say

local anchor
local function Clock() return GetServerTime and GetServerTime() or ns.Now() end

function Weeks.Anchor()
	if anchor then return anchor end
	local f = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
	local ok, left = false, nil
	if f then ok, left = pcall(f) end
	left = ok and tonumber(left) or nil
	if not (left and left > 0 and left <= Weeks.WEEK) then return Weeks.RESET_US end
	anchor = (math.floor((Clock() + left) / 3600 + 0.5) * 3600) % Weeks.WEEK
	return anchor
end
function Weeks.WeekOf(t) return math.floor(((tonumber(t) or 0) - Weeks.Anchor()) / Weeks.WEEK) end
function Weeks.Week() return Weeks.WeekOf(Clock()) end
function Weeks.WeekStart(week) return Weeks.Anchor() + week * Weeks.WEEK end
-- The day a week starts on (UTC): "2026-09-29".
function Weeks.DateLabel(week)
	local ok, s = pcall(date, "!%Y-%m-%d", Weeks.WeekStart(week))
	return ok and s or tostring(week)
end
