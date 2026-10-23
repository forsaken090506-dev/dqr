-- Dungeon Quest speed-30 bootstrap. Loads the maintained boss/dodge script.
-- This file is complete and intentionally does not reuse the truncated upload.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "LocalPlayer unavailable")
local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.DQ30Stop) == "function" then pcall(env.DQ30Stop) end
local alive = true
local connections = {}
local function disconnect()
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
end
env.DQ30Stop = disconnect
local humanoid
local function bindCharacter(character)
    humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid and character then
        humanoid = character:WaitForChild("Humanoid", 10)
    end
    if humanoid and alive then
        pcall(function() humanoid.WalkSpeed = 30 end)
    end
end
table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
bindCharacter(player.Character)
table.insert(connections, RunService.Heartbeat:Connect(function()
    if not alive then return end
    if humanoid and humanoid.Parent and humanoid.Health > 0 then
        if humanoid.WalkSpeed ~= 30 then
            humanoid.WalkSpeed = 30
        end
    end
end))
local original = "https://raw.githubusercontent.com/forsaken090506-dev/dqr/fix/first-boss-refuge-orbit/HarvardLabs_V6_Clean_RoomEntry.lua"
local ok, sourceOrError = pcall(function() return game:HttpGet(original) end)
if not ok or type(sourceOrError) ~= "string" or #sourceOrError < 100 then
    warn("[DQ30] Could not download the original autofarm: " .. tostring(sourceOrError))
    return
end
local fn, compileError = loadstring(sourceOrError)
if not fn then
    warn("[DQ30] Original autofarm failed to compile: " .. tostring(compileError))
    return
end
local ran, runtimeError = pcall(fn)
if not ran then warn("[DQ30] Original autofarm error: " .. tostring(runtimeError)) end
