--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("RemoteLens"):WaitForChild("Shared")
local Store = require(Shared:WaitForChild("Store"))
local PayloadEstimate = require(Shared:WaitForChild("PayloadEstimate"))
local FormatSnapshot = require(Shared:WaitForChild("FormatSnapshot"))

local RemoteLens = {}
RemoteLens.__index = RemoteLens

local function assertRemoteEvent(remote)
	assert(remote and remote:IsA("RemoteEvent"), "expected RemoteEvent")
end

local function assertRemoteFunction(remote)
	assert(remote and remote:IsA("RemoteFunction"), "expected RemoteFunction")
end

local function defaultRemoteKey(remote)
	return remote:GetFullName()
end

local function defaultPlayerKey(player)
	return tostring(player.UserId)
end

function RemoteLens.new(options)
	options = options or {}

	local self = setmetatable({}, RemoteLens)
	self.store = options.store or Store.new(options.storeOptions)
	self.clock = options.clock or os.clock
	self.players = options.players or Players
	self.remoteKey = options.remoteKey or defaultRemoteKey
	self.playerKey = options.playerKey or defaultPlayerKey

	return self
end

function RemoteLens:_record(remote, direction, estimatedBytes, player)
	local playerKey = player and self.playerKey(player) or nil
	self.store:record(self.remoteKey(remote), direction, estimatedBytes, playerKey, self.clock())
end

function RemoteLens:observeEvent(remoteEvent)
	assertRemoteEvent(remoteEvent)

	return remoteEvent.OnServerEvent:Connect(function(player, ...)
		local estimatedBytes = PayloadEstimate.args(...)
		self:_record(remoteEvent, "C2S", estimatedBytes, player)
	end)
end

function RemoteLens:bindFunction(remoteFunction, handler)
	assertRemoteFunction(remoteFunction)
	assert(type(handler) == "function", "handler must be a function")

	remoteFunction.OnServerInvoke = function(player, ...)
		local requestBytes = PayloadEstimate.args(...)
		self:_record(remoteFunction, "C2S", requestBytes, player)

		local results = table.pack(handler(player, ...))
		local responseBytes = PayloadEstimate.packed(results, results.n)
		self:_record(remoteFunction, "S2C", responseBytes, player)
		return table.unpack(results, 1, results.n)
	end
end

function RemoteLens:wrapEvent(remoteEvent)
	assertRemoteEvent(remoteEvent)
	local lens = self
	local wrapper = {}

	function wrapper:FireClient(player, ...)
		local estimatedBytes = PayloadEstimate.args(...)
		lens:_record(remoteEvent, "S2C", estimatedBytes, player)
		return remoteEvent:FireClient(player, ...)
	end

	function wrapper:FireAllClients(...)
		local estimatedBytes = PayloadEstimate.args(...)
		for _, player in ipairs(lens.players:GetPlayers()) do
			lens:_record(remoteEvent, "S2C", estimatedBytes, player)
		end
		return remoteEvent:FireAllClients(...)
	end

	return wrapper
end

function RemoteLens:wrapFunction(remoteFunction)
	assertRemoteFunction(remoteFunction)
	local lens = self
	local wrapper = {}

	function wrapper:InvokeClient(player, ...)
		local requestBytes = PayloadEstimate.args(...)
		lens:_record(remoteFunction, "S2C", requestBytes, player)

		local results = table.pack(remoteFunction:InvokeClient(player, ...))
		local responseBytes = PayloadEstimate.packed(results, results.n)
		lens:_record(remoteFunction, "C2S", responseBytes, player)
		return table.unpack(results, 1, results.n)
	end

	return wrapper
end

function RemoteLens:snapshot(windowSeconds)
	return self.store:snapshot(self.clock(), windowSeconds)
end

RemoteLens.Store = Store
RemoteLens.PayloadEstimate = PayloadEstimate
RemoteLens.FormatSnapshot = FormatSnapshot

return RemoteLens
