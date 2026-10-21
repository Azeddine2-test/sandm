--[[
    Open Door Animation
    Plays a door push animation when walking into swing doors.

    Original: OpenDoorAnim by JuniorDjjr
    https://github.com/JuniorDjjr/OpenDoorAnim

    MTA:SA port by Dryxio
]]

local COOLDOWN = 1700
local TRIGGER_DIST = 0.7

local doorCache = {}
local lastAnim = {}

local function isDoor(model)
    if doorCache[model] ~= nil then
        return doorCache[model]
    end

    local group = engineGetModelPhysicalPropertiesGroup(model)
    if not group or group == -1 then
        doorCache[model] = false
        return false
    end

    local response = engineGetObjectGroupPhysicalProperty(group, "special_col_response")
    doorCache[model] = (response == "swingdoor")
    return doorCache[model]
end

local function canAnimate(ped)
    if getElementHealth(ped) <= 0 then return false end
    if not isPedOnGround(ped) then return false end
    if isPedDucked(ped) then return false end
    if isPedOnFire(ped) then return false end
    if isElementInWater(ped) then return false end
    if isPedInVehicle(ped) then return false end
    if isPedDoingGangDriveby(ped) then return false end

    if isPedDoingTask(ped, "TASK_SIMPLE_USE_GUN") then return false end
    if isPedDoingTask(ped, "TASK_SIMPLE_FIGHT") then return false end

    local state = getPedMoveState(ped)
    if state == "stand" or state == "crouch" then return false end

    return true
end

local function checkDoor()
    local ped = localPlayer
    local x, y, z = getElementPosition(ped)
    local _, _, rz = getElementRotation(ped)

    z = z + 0.5
    local angle = math.rad(-rz)
    local dx, dy = math.sin(angle), math.cos(angle)

    local hit, hx, hy, hz, elem, _, _, _, _, _, _, model = processLineOfSight(
        x, y, z, x + dx, y + dy, z,
        true, true, true, true, true,
        false, false, false, nil, true, false
    )

    if not hit then return end

    local dist = getDistanceBetweenPoints3D(x, y, z, hx, hy, hz)
    if dist > TRIGGER_DIST then return end

    model = model or (elem and getElementModel(elem))
    if not model or not isDoor(model) then return end
    if not canAnimate(ped) then return end

    local now = getTickCount()
    if lastAnim[ped] and (now - lastAnim[ped]) < COOLDOWN then return end

    setPedAnimation(ped, "ped", "walk_doorpartial", -1, false, false, true, false, 100)
    lastAnim[ped] = now
end

addEventHandler("onClientPreRender", root, checkDoor)
