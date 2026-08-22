--!strict
-- Pure aggregation store. This module intentionally has no Roblox Instance dependency.

local Store = {}
Store.__index = Store

local DEFAULT_MAX_SAMPLES = 16
local DEFAULT_MAX_PLAYERS = 64
local DEFAULT_MAX_REMOTES = 256
local DEFAULT_RATE_WINDOW = 5

local OTHER_REMOTE = "(other remotes)"
local OTHER_PLAYER = "(other players)"

local function assertPositiveInteger(value, name)
	assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
	return value
end

local function newCounters(key)
	return {
		key = key,
		totalCalls = 0,
		totalBytes = 0,
		c2sCalls = 0,
		c2sBytes = 0,
		s2cCalls = 0,
		s2cBytes = 0,
		lastSeen = nil,
	}
end

local function newRemote(key)
	local counters = newCounters(key)
	counters.samples = {}
	return counters
end

local function incrementCounters(entry, direction, bytes, now)
	entry.totalCalls = entry.totalCalls + 1
	entry.totalBytes = entry.totalBytes + bytes
	entry.lastSeen = now

	if direction == "C2S" then
		entry.c2sCalls = entry.c2sCalls + 1
		entry.c2sBytes = entry.c2sBytes + bytes
	else
		entry.s2cCalls = entry.s2cCalls + 1
		entry.s2cBytes = entry.s2cBytes + bytes
	end
end

local function appendSample(remote, direction, bytes, second, maxSamples)
	local samples = remote.samples
	local latest = samples[#samples]

	if latest and latest.second == second then
		latest.calls = latest.calls + 1
		latest.bytes = latest.bytes + bytes
		if direction == "C2S" then
			latest.c2sCalls = latest.c2sCalls + 1
			latest.c2sBytes = latest.c2sBytes + bytes
		else
			latest.s2cCalls = latest.s2cCalls + 1
			latest.s2cBytes = latest.s2cBytes + bytes
		end
		return
	end

	assert(not latest or second >= latest.second, "Store timestamps must be monotonic")

	samples[#samples + 1] = {
		second = second,
		calls = 1,
		bytes = bytes,
		c2sCalls = direction == "C2S" and 1 or 0,
		c2sBytes = direction == "C2S" and bytes or 0,
		s2cCalls = direction == "S2C" and 1 or 0,
		s2cBytes = direction == "S2C" and bytes or 0,
	}

	if #samples > maxSamples then
		table.remove(samples, 1)
	end
end

local function average(total, count)
	if count == 0 then
		return 0
	end
	return total / count
end

local function sortedRows(map, overflowKey, project)
	local rows = {}
	for _, entry in pairs(map) do
		if entry.totalCalls > 0 then
			rows[#rows + 1] = project(entry)
		end
	end

	table.sort(rows, function(a, b)
		if a.totalCalls ~= b.totalCalls then
			return a.totalCalls > b.totalCalls
		end
		if a.key == overflowKey then
			return false
		end
		if b.key == overflowKey then
			return true
		end
		return a.key < b.key
	end)

	return rows
end

function Store.new(options)
	options = options or {}

	local maxSamples = assertPositiveInteger(options.maxSamples or DEFAULT_MAX_SAMPLES, "maxSamples")
	local maxPlayers = assertPositiveInteger(options.maxPlayers or DEFAULT_MAX_PLAYERS, "maxPlayers")
	local maxRemotes = assertPositiveInteger(options.maxRemotes or DEFAULT_MAX_REMOTES, "maxRemotes")
	local rateWindow = assertPositiveInteger(options.rateWindow or DEFAULT_RATE_WINDOW, "rateWindow")

	assert(rateWindow <= maxSamples, "rateWindow cannot exceed maxSamples")

	local self = setmetatable({}, Store)
	self.maxSamples = maxSamples
	self.maxPlayers = maxPlayers
	self.maxRemotes = maxRemotes
	self.rateWindow = rateWindow

	self.remotes = {
		[OTHER_REMOTE] = newRemote(OTHER_REMOTE),
	}
	self.players = {
		[OTHER_PLAYER] = newCounters(OTHER_PLAYER),
	}
	self.remoteCount = 1
	self.playerCount = 1

	return self
end

function Store:_remoteFor(remoteKey)
	local existing = self.remotes[remoteKey]
	if existing then
		return existing
	end

	if self.remoteCount < self.maxRemotes then
		local entry = newRemote(remoteKey)
		self.remotes[remoteKey] = entry
		self.remoteCount = self.remoteCount + 1
		return entry
	end

	return self.remotes[OTHER_REMOTE]
end

function Store:_playerFor(playerKey)
	if playerKey == nil then
		return nil
	end

	local existing = self.players[playerKey]
	if existing then
		return existing
	end

	if self.playerCount < self.maxPlayers then
		local entry = newCounters(playerKey)
		self.players[playerKey] = entry
		self.playerCount = self.playerCount + 1
		return entry
	end

	return self.players[OTHER_PLAYER]
end

function Store:record(remoteKey, direction, estimatedBytes, playerKey, now)
	assert(type(remoteKey) == "string" and remoteKey ~= "", "remoteKey must be a non-empty string")
	assert(direction == "C2S" or direction == "S2C", "direction must be C2S or S2C")
	assert(type(estimatedBytes) == "number" and estimatedBytes >= 0, "estimatedBytes must be non-negative")
	assert(playerKey == nil or type(playerKey) == "string", "playerKey must be nil or a string")
	assert(type(now) == "number", "now must be a number")

	local remote = self:_remoteFor(remoteKey)
	incrementCounters(remote, direction, estimatedBytes, now)
	appendSample(remote, direction, estimatedBytes, math.floor(now), self.maxSamples)

	local player = self:_playerFor(playerKey)
	if player then
		incrementCounters(player, direction, estimatedBytes, now)
	end
end

local function remoteProjection(entry, nowSecond, windowSeconds)
	local firstSecond = nowSecond - windowSeconds + 1
	local recentCalls = 0
	local recentBytes = 0
	local recentC2SCalls = 0
	local recentS2CCalls = 0

	for _, sample in ipairs(entry.samples) do
		if sample.second >= firstSecond and sample.second <= nowSecond then
			recentCalls = recentCalls + sample.calls
			recentBytes = recentBytes + sample.bytes
			recentC2SCalls = recentC2SCalls + sample.c2sCalls
			recentS2CCalls = recentS2CCalls + sample.s2cCalls
		end
	end

	return {
		key = entry.key,
		totalCalls = entry.totalCalls,
		totalEstimatedBytes = entry.totalBytes,
		averagePayloadBytes = average(entry.totalBytes, entry.totalCalls),
		callsPerSecond = recentCalls / windowSeconds,
		estimatedBytesPerSecond = recentBytes / windowSeconds,
		c2sCalls = entry.c2sCalls,
		s2cCalls = entry.s2cCalls,
		c2sCallsPerSecond = recentC2SCalls / windowSeconds,
		s2cCallsPerSecond = recentS2CCalls / windowSeconds,
		lastSeen = entry.lastSeen,
	}
end

local function playerProjection(entry)
	return {
		key = entry.key,
		totalCalls = entry.totalCalls,
		totalEstimatedBytes = entry.totalBytes,
		averagePayloadBytes = average(entry.totalBytes, entry.totalCalls),
		c2sCalls = entry.c2sCalls,
		s2cCalls = entry.s2cCalls,
		lastSeen = entry.lastSeen,
	}
end

function Store:snapshot(now, windowSeconds)
	assert(type(now) == "number", "now must be a number")
	windowSeconds = windowSeconds or self.rateWindow
	assertPositiveInteger(windowSeconds, "windowSeconds")
	assert(windowSeconds <= self.maxSamples, "windowSeconds cannot exceed maxSamples")

	local nowSecond = math.floor(now)
	local remotes = sortedRows(self.remotes, OTHER_REMOTE, function(entry)
		return remoteProjection(entry, nowSecond, windowSeconds)
	end)
	local players = sortedRows(self.players, OTHER_PLAYER, playerProjection)

	return {
		remotes = remotes,
		players = players,
		windowSeconds = windowSeconds,
		limits = {
			maxSamples = self.maxSamples,
			maxPlayers = self.maxPlayers,
			maxRemotes = self.maxRemotes,
		},
	}
end

Store.OTHER_REMOTE = OTHER_REMOTE
Store.OTHER_PLAYER = OTHER_PLAYER

return Store
