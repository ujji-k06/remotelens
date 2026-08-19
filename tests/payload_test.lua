local PayloadEstimate = dofile("src/shared/PayloadEstimate.lua")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value, label)
	if not value then
		error(label)
	end
end

assertEqual(PayloadEstimate.value(nil), 0, "nil")
assertEqual(PayloadEstimate.value(true), 1, "boolean")
assertEqual(PayloadEstimate.value(3.14), 8, "number")
assertEqual(PayloadEstimate.value("abcd"), 4, "string")

local tableBytes = PayloadEstimate.value({ hp = 100, name = "Gojo" })
-- table overhead 8 + key "hp" 2 + number 8 + key "name" 4 + string 4
assertEqual(tableBytes, 26, "small table")

local cycle = {}
cycle.self = cycle
assertEqual(PayloadEstimate.value(cycle), 8 + 4, "cycle charges table + key, not infinite")

local argsBytes, truncated = PayloadEstimate.args(1, "xy", false)
assertEqual(argsBytes, 8 + 2 + 1, "vararg args")
assertEqual(truncated, false, "small args are not truncated")

local packed = { "ok", 2 }
assertEqual(PayloadEstimate.packed(packed, 2), 2 + 8, "packed results")

local long = string.rep("x", 9000)
local capped, didTruncate = PayloadEstimate.value(long)
assertEqual(capped, 8192, "string contribution is capped")
assertTrue(didTruncate, "oversize string sets truncated")

print("RemoteLens PayloadEstimate test passed")
