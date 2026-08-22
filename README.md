# RemoteLens

Opt-in, server-side instrumentation for Roblox remotes (`RemoteEvent`, `UnreliableRemoteEvent`, `RemoteFunction`). Tracks call counts, direction (client-to-server / server-to-client), estimated payload sizes, and recent rates — with bounded memory usage.

## How it works

- **C2S events:** passively observed via `observeEvent`; existing handlers stay untouched.
- **C2S functions:** installed through `bindFunction`, since `OnServerInvoke` allows only one handler.
- **S2C:** measured when sends go through `wrapEvent` / `wrapFunction`.
- **Payload sizes:** heuristic estimates only; values are inspected transiently and never stored.
- **Aggregation:** bounded by default to 16 one-second samples, 64 player buckets, 256 remote buckets. Overflow aggregates into `(other)` buckets rather than growing unbounded.

## Installation

Requires [Rojo](https://rojo.space). From the project directory:

```bash
rojo serve
```

Mappings: `src/shared` → `ReplicatedStorage.RemoteLens.Shared`, `src/server` → `ServerScriptService.RemoteLens.Server`. Map those same folders in any consuming place file.

## Usage

```lua
local RemoteLens = require(game.ServerScriptService.RemoteLens.Server.RemoteLens)
local lens = RemoteLens.new()

-- C2S: passive observation
lens:observeEvent(ReplicatedStorage.Remotes.CombatAction)

-- S2C: send through the wrapper to be measured
local combatOut = lens:wrapEvent(ReplicatedStorage.Remotes.CombatAction)
combatOut:FireAllClients("round-start")

-- RemoteFunctions: install the invoke handler through RemoteLens
lens:bindFunction(ReplicatedStorage.Remotes.GetLoadout, function(player, slot)
	return loadoutService:Get(player, slot)
end)

print(lens:dump())
```

## Limits

Defaults are hard bounds, overridable for tests via `RemoteLens.new({ storeOptions = { ... } })`: `maxSamples = 16`, `maxPlayers = 64`, `maxRemotes = 256`.

Payload estimates are comparative signals ("this remote is heavier than that one"), not wire-exact byte counts. No payloads or per-call histories are retained. `FireAllClients` counts one delivery per current player.

## Testing

```bash
./tools/check.sh
```

Runs deterministic store/payload/format tests with no Roblox dependencies (any Lua runtime with `dofile`).

## Non-goals

No global monkey-patching of existing calls, no packet-exact accounting, no payload logging, no unbounded history, no Studio plugin dependency in the metrics path.
