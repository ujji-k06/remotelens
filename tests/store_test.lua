local Store = dofile("src/shared/Store.lua")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
	end
end

local store = Store.new({
	maxSamples = 3,
	maxPlayers = 3,
	maxRemotes = 3,
	rateWindow = 3,
})

store:record("CombatAction", "C2S", 10, "101", 100.10)
store:record("CombatAction", "C2S", 20, "101", 100.90)
store:record("CombatAction", "S2C", 30, "202", 101.20)
store:record("UpdateAim", "C2S", 40, "303", 102.00)
store:record("ThirdRemote", "C2S", 50, "404", 102.50)
store:record("CombatAction", "C2S", 60, "101", 103.00)

local snapshot = store:snapshot(103.25, 3)

assertEqual(#snapshot.remotes, 3, "remote aggregate count remains bounded")
assertEqual(#snapshot.players, 3, "player aggregate count remains bounded")

local byRemote = {}
for _, row in ipairs(snapshot.remotes) do
	byRemote[row.key] = row
end

assertEqual(byRemote.CombatAction.totalCalls, 4, "CombatAction total calls")
assertEqual(byRemote.CombatAction.totalEstimatedBytes, 120, "CombatAction estimated bytes")
assertEqual(byRemote.CombatAction.c2sCalls, 3, "CombatAction C2S calls")
assertEqual(byRemote.CombatAction.s2cCalls, 1, "CombatAction S2C calls")
assertEqual(byRemote.CombatAction.callsPerSecond, 2 / 3, "CombatAction three-second call rate")

assertEqual(byRemote[Store.OTHER_REMOTE].totalCalls, 1, "overflow remote captures excess cardinality")
assertEqual(byRemote[Store.OTHER_REMOTE].totalEstimatedBytes, 50, "overflow remote bytes")

local byPlayer = {}
for _, row in ipairs(snapshot.players) do
	byPlayer[row.key] = row
end

assertEqual(byPlayer["101"].totalCalls, 3, "tracked player total calls")
assertEqual(byPlayer[Store.OTHER_PLAYER].totalCalls, 2, "overflow player captures excess cardinality")

print("RemoteLens Store test passed")
