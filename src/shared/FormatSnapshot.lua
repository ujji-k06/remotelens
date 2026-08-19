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

local function appendSection(lines, title, rows, rateLabel, rateField, rateFormat)
	lines[#lines + 1] = string.format("%-40s %9s %12s %9s", title, rateLabel, "Avg payload", "Direction")
	lines[#lines + 1] = string.rep("-", 75)

	for _, row in ipairs(rows) do
		lines[#lines + 1] = string.format(
			"%-40s " .. rateFormat .. " %9.1f B %9s",
			row.key,
			row[rateField],
			row.averagePayloadBytes,
			direction(row)
		)
	end
end

function FormatSnapshot.format(snapshot)
	local lines = {
		string.format("RemoteLens snapshot  window=%ds", snapshot.windowSeconds or 0),
	}

	appendSection(lines, "Remote", snapshot.remotes, "Calls/s", "callsPerSecond", "%9.2f")

	if snapshot.players and #snapshot.players > 0 then
		lines[#lines + 1] = ""
		appendSection(lines, "Player", snapshot.players, "Calls", "totalCalls", "%9d")
	end

	return table.concat(lines, "\n")
end

return FormatSnapshot
