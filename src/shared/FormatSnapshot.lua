--!strict

local FormatSnapshot = {}

local function direction(row)
	if row.c2sCalls > 0 and row.s2cCalls > 0 then
		return "C <-> S"
	elseif row.c2sCalls > 0 then
		return "C -> S"
	elseif row.s2cCalls > 0 then
		return "S -> C"
	end
	return "-"
end

function FormatSnapshot.format(snapshot)
	local lines = {
		string.format("%-40s %9s %12s %9s", "Remote", "Calls/s", "Avg payload", "Direction"),
		string.rep("-", 75),
	}

	for _, row in ipairs(snapshot.remotes) do
		lines[#lines + 1] = string.format(
			"%-40s %9.2f %9.1f B %9s",
			row.key,
			row.callsPerSecond,
			row.averagePayloadBytes,
			direction(row)
		)
	end

	return table.concat(lines, "\n")
end

return FormatSnapshot
