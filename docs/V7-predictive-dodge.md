# V7 predictive dodge controller

The existing `HarvardLabs_V6_Clean_RoomEntry.lua` loader now embeds a new planner and Roblox adapter. Its filename and loadstring URL stay compatible. Normal movement remains 27. There are no additional runtime downloads.

## Behavior

- Plans a destination and a timed route, including a short safe interval after arrival.
- First-boss red-circle warnings reject destinations still inside their future footprints. Adds rim and overlapping-circle intersection candidates, checks activation timing, and replaces a committed destination if a new circle covers it.
- Follows waypoints rather than rescoring opposite headings every frame.
- During combat, joins waypoint and retry transitions using checked short moving steps when available, rather than inserting a hold because no complete route passes its destination dwell check. Safe row-opening holds remain deliberate. Proactive movement alone does not suspend offensive casts.
- Cancels for walls, missing floor, imminent attacks/projectiles, an enemy interception, a mechanic transition, or 0.45 seconds without physical progress.
- Requires a distant forecast to persist for 0.1 seconds before cancelling; imminent threats interrupt immediately.
- Tries a two-segment route around local corners if direct routes fail.
- Reads visible green precasts from named boss refuge models if the central reader has no current spots.
- Keeps refuge paths inside the inset circle. Preserves routes across reader refreshes using geometric mechanic keys.
- Holds a checked row opening while it remains safe and searches again when it closes.
- Yields clean travel to existing navigation. Recovers from missing native movement intent using the existing navigation goal.
- Temporarily holds offensive casts during active escape routes. Does not override a game-imposed zero speed or anchored root.
- Never chooses a known projectile collision or wall crossing as a least-risk fallback. If a complete route is unavailable and the current position is unsafe, tries a short checked escape prefix without entering a worse hazard. Safe waits are rechecked after at most 0.05 seconds. If even the short prefix has no physically valid route, it can still hold.

## Debugging

The runtime report is `_G.HL_V7_DODGE.report`. It includes the current mode, route ID, decision, rejection counts, errors and controller work time. The planner keeps up to 160 decision events, including commits, arrivals, stalls and cancellation reasons. Up to 12 health-loss events retain the position and scalar hazard geometry.

Print a JSON diagnostic after a failure:

```lua
print(_G.HL_V7_DODGE.dump())
```

`_G.HL_V7_DODGE.simulate(frames)` runs a separate planner on supplied frame environments and returns commands and events without touching the live character. See the tests for deterministic scene examples.

## Development and validation

```sh
python -m pip install lupa
python dodge/build_embedded.py
python -m unittest discover -s tests -v
```

Edit `dodge/PredictivePlanner.lua` and `dodge/RobloxAdapter.lua`, then regenerate the embedded controller. The planner is pure Lua and can be tested independently of Roblox. The adapter is exercised with mocked services, vector operations, native-controller handoffs, movement holds and disable behavior. Projectile regression tests extract the actual predictor from the full loader, including future start times for second route segments.

The suite currently contains 35 test methods. The projectile test covers nine swept-geometry cases. These are isolated and mocked tests, not a successful live hardcore run. Detection still depends on the existing hazard reader, and unrecognized attacks, network delay, server corrections or genuinely blocked routes can still cause failure. No zero-death guarantee is implied.
