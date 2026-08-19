local Store = dofile("src/shared/Store.lua")
local FormatSnapshot = dofile("src/shared/FormatSnapshot.lua")

local function assertContains(haystack, needle, label)
	if not string.find(haystack, needle, 1, true) then
		error(string.format("%s: missing %q in:\n%s", label, needle, haystack))
	end
end

local store = Store.new({
	maxSamples = 4,
	maxPlayers = 4,
	maxRemotes = 4,
	rateWindow = 2,
})

store:record("CombatRemote", "C2S", 40, "101", 10.2)
store:record("CombatRemote", "S2C", 80, "101", 10.4)
store:record("ProjectileCorrectionRemote", "C2S", 16, "202", 11.0)

local text = FormatSnapshot.format(store:snapshot(11.5, 2))

assertContains(text, "window=2s", "window header")
assertContains(text, "CombatRemote", "remote row")
assertContains(text, "ProjectileCorrectionRemote", "second remote row")
assertContains(text, "101", "player row")
assertContains(text, "C <-> S", "bidirectional combat remote")
assertContains(text, "C -> S", "unidirectional projectile remote")

print("RemoteLens FormatSnapshot test passed")
