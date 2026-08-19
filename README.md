# RemoteLens v0.1

RemoteLens is an opt-in Roblox networking instrumentation layer for measuring remote activity without pretending Studio can globally intercept arbitrary `FireServer`, `FireClient`, `InvokeServer`, or `InvokeClient` calls.

v0.1 focuses on honest server-side boundaries:

- **C2S `RemoteEvent` traffic:** passively observed at `OnServerEvent` with `observeEvent`.
- **C2S `RemoteFunction` traffic:** observed by installing the one supported `OnServerInvoke` handler with `bindFunction`.
- **S2C traffic:** measured only when game code sends through `wrapEvent` / `wrapFunction`.
- **Payload size:** heuristic only. Payload values are inspected transiently, converted to an estimated byte count, and never retained.
- **Aggregation:** bounded to 16 one-second samples, 64 player buckets, and 256 remote buckets by default.

## Layout

```text
RemoteLens/
├── default.project.json
├── README.md
├── src/
│   ├── server/
│   │   └── RemoteLens.lua
│   └── shared/
│       ├── FormatSnapshot.lua
│       ├── PayloadEstimate.lua
│       └── Store.lua
└── tests/
    └── store_test.lua
```

`Store.lua` is deliberately pure: it does not access `game`, `Instance`, services, signals, or Roblox datatypes. The runtime adapter lives in `src/server/RemoteLens.lua`.

## Rojo

From the project directory:

```bash
rojo serve
```

GitHub Actions runs [rojo-doctor](https://github.com/ujji-k06/rojo-doctor) on every push:

```bash
rojo-doctor check
```

The project maps:

- `src/shared` → `ReplicatedStorage.RemoteLens.Shared`
- `src/server` → `ServerScriptService.RemoteLens.Server`

## Basic usage

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteLens = require(ServerScriptService.RemoteLens.Server.RemoteLens)
local lens = RemoteLens.new()

local combatAction = ReplicatedStorage.Remotes.CombatAction

-- C2S: passive observation. Existing OnServerEvent handlers can remain unchanged.
lens:observeEvent(combatAction)

-- S2C: sends must opt into the wrapper to be measured.
local combatOut = lens:wrapEvent(combatAction)
combatOut:FireClient(player, "hit", 42)
combatOut:FireAllClients("round-start")

local snapshot = lens:snapshot()
print(RemoteLens.FormatSnapshot.format(snapshot))
```

### RemoteFunctions

Roblox exposes a single `OnServerInvoke` callback, so RemoteLens cannot attach a passive second listener. Install the handler through RemoteLens instead:

```lua
local getLoadout = ReplicatedStorage.Remotes.GetLoadout

lens:bindFunction(getLoadout, function(player, slot)
	return loadoutService:Get(player, slot)
end)
```

For server-to-client invokes:

```lua
local clientFunction = lens:wrapFunction(ReplicatedStorage.Remotes.ClientPrompt)
local accepted = clientFunction:InvokeClient(player, "confirm")
```

The wrapper records the S2C request and the C2S return value because both are visible at the instrumented server boundary.

## Metric semantics

Each remote aggregate contains:

- lifetime call/delivery count;
- lifetime heuristic byte total;
- average heuristic payload size;
- C2S and S2C counts;
- recent calls/second and estimated bytes/second over a configurable window;
- last-seen timestamp.

The recent rate uses one-second buckets. Only the most recent 16 buckets are retained by default; individual calls are not retained.

`FireAllClients` is counted as one S2C delivery per current player. This makes per-player activity and estimated aggregate fan-out visible. It is intentionally a delivery count, not a count of Lua API invocations.

Player aggregates contain lifetime counts/estimated bytes by direction and last-seen time. They do not retain payloads or per-call histories.

## Cardinality bounds

The defaults are hard bounds:

- `maxSamples = 16`
- `maxPlayers = 64`
- `maxRemotes = 256`

One slot in the player and remote limits is reserved for `(other players)` / `(other remotes)`. When cardinality exceeds the bound, new identities aggregate into those overflow buckets instead of causing unbounded growth or silently dropping all activity.

You can override limits when constructing the store, primarily for tests:

```lua
local lens = RemoteLens.new({
	storeOptions = {
		maxSamples = 16,
		maxPlayers = 64,
		maxRemotes = 256,
		rateWindow = 5,
	},
})
```

## Payload estimation caveats

RemoteLens does **not** claim to reproduce Roblox's wire encoding. The estimator uses simple fixed-size approximations for common scalar/Roblox value types and bounded recursive traversal for tables. It caps traversal depth, node count, and large string contribution so instrumentation work itself remains bounded.

Treat payload numbers as comparative signals such as "this remote appears much heavier than that one", not packet-capture truth. Compression, engine serialization, protocol framing, replication behavior, and transport overhead are outside v0.1.

No payload object or argument value is stored in the metrics store.

## Deterministic store test

The store test uses fixed timestamps and no Roblox APIs:

```bash
lua tests/store_test.lua
```

It verifies rate bucketing, direction totals, estimated byte aggregation, and overflow behavior for bounded remote/player cardinality. Any Lua runtime with `dofile` can run it because `Store.lua` intentionally stays within a small Lua-compatible subset.

## v0.1 non-goals

- No global monkey-patching or fake interception of arbitrary existing remote calls.
- No packet-exact byte accounting.
- No payload logging.
- No unbounded event history.
- No Studio plugin dependency in the core metrics path.
- No claim that RemoteLens replaces Roblox's own network/performance tooling.
