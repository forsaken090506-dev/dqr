# First-boss refuge orbit: candidate fix (not yet integrated)

Source: `HarvardLabs_V6_Clean_RoomEntry.lua`, function `context.archRefugeCircle`.

## Root cause
The controller calls `humanoid:Move(best or Vector3.zero, false)`. Strict candidate risk rejection may leave `best=nil`, causing a stop inside the green refuge while new tracking floor attacks spawn under the character.

## Proposed change
1. Add `local emergency, emergencySign, emergencyScore, emergencyPoint = nil, orbit.sign, math.huge, nil` next to the fallback locals.
2. Inside `consider`, after the path sampling loop and before `if startRisk >= 0.12 then`, retain a minimum-exposure emergency candidate. Keep pre-existing wall, projectile, safe boundary and re-entry checks intact.
3. After underfoot fallback selection, if `best` is still nil, choose that emergency candidate, and rescore next frame rather than holding it.
4. Keep `Vector3.zero` only when every physical route was blocked.

The complete edited Lua file and unified patch are available in the ChatGPT response; this note is intentionally separate because GitHub connector did not return the contents of this unusually large Lua file, so replacing it blindly would be unsafe.

Testing: **not verified in Roblox**. Check that the character keeps moving during green-circle attacks, stays within the zone, and does not cross live hazard patches.
