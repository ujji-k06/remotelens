--!strict
-- Heuristic only. Values are inspected transiently and never retained by this module.

local PayloadEstimate = {}

local DEFAULT_MAX_DEPTH = 4
local DEFAULT_MAX_NODES = 256
local DEFAULT_MAX_STRING_BYTES = 8192

local FIXED_ROBLOX_SIZES = {
	Vector2 = 16,
	Vector3 = 24,
	CFrame = 48,
	Color3 = 24,
	BrickColor = 4,
	UDim = 16,
	UDim2 = 32,
	Rect = 32,
	Ray = 48,
	NumberRange = 16,
	EnumItem = 4,
	Instance = 8,
}

local function valueType(value)
	if typeof then
		return typeof(value)
	end
	return type(value)
end

local function estimate(value, state, depth)
	if state.nodes >= state.maxNodes then
		state.truncated = true
		return 0
	end
	state.nodes = state.nodes + 1

	local kind = valueType(value)
	if kind == "nil" then
		return 0
	elseif kind == "boolean" then
		return 1
	elseif kind == "number" then
		return 8
	elseif kind == "string" then
		local length = #value
		if length > state.maxStringBytes then
			state.truncated = true
			return state.maxStringBytes
		end
		return length
	elseif kind == "table" then
		if depth >= state.maxDepth then
			state.truncated = true
			return 8
		end
		if state.seen[value] then
			return 0
		end
		state.seen[value] = true

		local bytes = 8
		for key, child in pairs(value) do
			bytes = bytes + estimate(key, state, depth + 1)
			bytes = bytes + estimate(child, state, depth + 1)
			if state.nodes >= state.maxNodes then
				break
			end
		end
		return bytes
	end

	local fixed = FIXED_ROBLOX_SIZES[kind]
	if fixed then
		return fixed
	end

	if kind == "buffer" and buffer and buffer.len then
		return buffer.len(value)
	end

	-- Unknown userdata-like values are charged a small fixed amount instead of serialized.
	return 8
end

local function newState(options)
	options = options or {}
	return {
		maxDepth = options.maxDepth or DEFAULT_MAX_DEPTH,
		maxNodes = options.maxNodes or DEFAULT_MAX_NODES,
		maxStringBytes = options.maxStringBytes or DEFAULT_MAX_STRING_BYTES,
		nodes = 0,
		truncated = false,
		seen = {},
	}
end

function PayloadEstimate.value(value, options)
	local state = newState(options)
	local bytes = estimate(value, state, 0)
	return bytes, state.truncated
end

function PayloadEstimate.args(...)
	local state = newState(nil)
	local bytes = 0
	for index = 1, select("#", ...) do
		bytes = bytes + estimate(select(index, ...), state, 0)
	end
	return bytes, state.truncated
end

function PayloadEstimate.packed(values, count)
	local state = newState(nil)
	local bytes = 0
	for index = 1, count do
		bytes = bytes + estimate(values[index], state, 0)
	end
	return bytes, state.truncated
end

return PayloadEstimate
