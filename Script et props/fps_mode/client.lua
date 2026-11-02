--[[
-----------------------------------------
####   ###  ##### ####  ###  ###  #   # -
#   # #   #   #   #   #  #  #     #  #  -
####  #####   #   ####   #  #     ###   -
#     #   #   #   #  #   #  #     #  #  -
#     #   #   #   #   # ###  ###  #   # -
-----------------------------------------

#  Developed by: Patrick                                        
#  Support     : Support on my Discord (@_roger79)

]]

-- Caché de funciones 

local math_sin, math_cos, math_rad, math_deg, math_atan2 = math.sin, math.cos, math.rad, math.deg, math.atan2
local math_min, math_max, math_sqrt = math.min, math.max, math.sqrt
local getElementRotation, getElementVelocity, getElementMatrix = getElementRotation, getElementVelocity, getElementMatrix
local getPedBonePosition, getPedControlState, getPedMoveState, getPedWeapon = getPedBonePosition, getPedControlState, getPedMoveState, getPedWeapon
local getPedOccupiedVehicle, isPedInVehicle = getPedOccupiedVehicle, isPedInVehicle
local setCameraMatrix, setCameraTarget, getCameraMatrix = setCameraMatrix, setCameraTarget, getCameraMatrix
local setPedLookAt, getPedTask = setPedLookAt, getPedTask
local getTickCount = getTickCount

local Config = {
    fov = 75, sensitivity = 0.10, headOffset = 0.55, headOffsetInVeh = 0.20,
    camZWalk = 0.08, camZVeh = 0.08,
    maxPitch = 85, maxVehYaw = 130,
    transitionSpeed = 0.002, returnTime = 2500
}

local state = {
    isFP = false, isAiming = false,
    yaw = 0, pitch = 0, vehYaw = 0, vehPitch = 0,
    wasInVeh = false, currentRoll = 0, swayTime = 0,
    lastMouseTime = 0, lastMouseDX = 0,
    transProgress = 1.0,
    sX = 0, sY = 0, sZ = 0, sLX = 0, sLY = 0, sLZ = 0, sRoll = 0, sFov = 75
}

function disableFP()
    state.isFP = false
    removeEventHandler("onClientPreRender", root, updateFP)
    removeEventHandler("onClientCursorMove", root, updateMouse)
    removeEventHandler("onClientPlayerWasted", localPlayer, disableFPOnDeath)
    
    setCameraTarget(localPlayer)
    setPedLookAt(localPlayer, 0, 0, 0, 0)
    setNearClipDistance(0.3)
    triggerServerEvent("onPlayerToggleFP", localPlayer, false)
end

function disableFPOnDeath()
    if state.isFP then disableFP() end
end

function toggleFP()
    if isPedDead(localPlayer) then return end 

    if not state.isFP then
        state.isFP = true
        local _, _, rz = getElementRotation(localPlayer)
        state.yaw = (rz + 90) % 360
        state.pitch, state.vehYaw, state.vehPitch, state.currentRoll = 0, 0, 0, 0
        state.wasInVeh = isPedInVehicle(localPlayer)
        state.isAiming = false
        state.transProgress = 1.0
        
        addEventHandler("onClientPreRender", root, updateFP)
        addEventHandler("onClientCursorMove", root, updateMouse)
        addEventHandler("onClientPlayerWasted", localPlayer, disableFPOnDeath) 
        triggerServerEvent("onPlayerToggleFP", localPlayer, true)
        setNearClipDistance(0.1)
    else
        disableFP()
    end
end
addCommandHandler("fp", toggleFP)

function updateMouse(_, _, aX, aY)
    if not state.isFP or isCursorShowing() or isMTAWindowActive() or state.isAiming then return end
    
    local sx, sy = guiGetScreenSize()
    local cx, cy = sx * 0.5, sy * 0.5 
    local dX, dY = aX - cx, aY - cy
    
    if dX == 0 and dY == 0 then return end
    state.lastMouseDX = dX 
    
    if isPedInVehicle(localPlayer) then
        state.vehYaw = math_max(-Config.maxVehYaw, math_min(Config.maxVehYaw, state.vehYaw - dX * Config.sensitivity))
        state.vehPitch = math_max(-Config.maxPitch, math_min(Config.maxPitch, state.vehPitch - dY * Config.sensitivity))
    else
        state.yaw = (state.yaw - dX * Config.sensitivity) % 360
        state.pitch = math_max(-Config.maxPitch, math_min(Config.maxPitch, state.pitch - dY * Config.sensitivity))
    end
    
    state.lastMouseTime = getTickCount()
end

function updateFP(dt)
    local inVeh = isPedInVehicle(localPlayer)
    
    if inVeh and not state.wasInVeh then
        state.vehYaw, state.vehPitch = 0, 0
    elseif not inVeh and state.wasInVeh then
        local _, _, rz = getElementRotation(localPlayer)
        state.yaw = (rz + 90) % 360
        state.pitch = 0
    end
    state.wasInVeh = inVeh

    local currentlyAiming = false
    if getPedControlState(localPlayer, "aim_weapon") then
        local weapon = getPedWeapon(localPlayer)
        currentlyAiming = (weapon >= 22 and weapon <= 38)
    end
    
    if currentlyAiming then
        if not state.isAiming then
            state.isAiming = true
            setCameraTarget(localPlayer)
        end
        return 
    else
        if state.isAiming then
            state.isAiming = false
            state.transProgress = 0.0
            
            local cx, cy, cz, lx, ly, lz, roll, fov = getCameraMatrix()
            state.sX, state.sY, state.sZ = cx, cy, cz
            state.sLX, state.sLY, state.sLZ = lx, ly, lz
            state.sRoll, state.sFov = roll, fov
            
            local dx, dy, dz = lx - cx, ly - cy, lz - cz
            state.yaw = math_deg(math_atan2(dy, dx)) % 360
            state.pitch = math_deg(math_atan2(dz, math_sqrt(dx*dx + dy*dy)))
            
            if inVeh then
                state.vehYaw, state.vehPitch = 0, state.pitch
            end
        end
    end

    local camX, camY, camZ, lookDirX, lookDirY, lookDirZ
    local targetRoll, targetFov = 0, Config.fov
    local hx, hy, hz = getPedBonePosition(localPlayer, 8)
    
    state.swayTime = state.swayTime + dt
    state.lastMouseDX = state.lastMouseDX * 0.9 
    
    if inVeh then
        local veh = getPedOccupiedVehicle(localPlayer)
        if veh then
            local mat = getElementMatrix(veh)
            local radY, radP = math_rad(state.vehYaw), math_rad(state.vehPitch)
            
            local cosY, sinY = math_cos(radY), math_sin(radY)
            local cosP, sinP = math_cos(radP), math_sin(radP)
            
            local dirX = -sinY * cosP
            local dirY = cosY * cosP
            local dirZ = sinP
            
            lookDirX = dirX * mat[1][1] + dirY * mat[2][1] + dirZ * mat[3][1]
            lookDirY = dirX * mat[1][2] + dirY * mat[2][2] + dirZ * mat[3][2]
            lookDirZ = dirX * mat[1][3] + dirY * mat[2][3] + dirZ * mat[3][3]
            
            camX = hx + lookDirX * Config.headOffsetInVeh
            camY = hy + lookDirY * Config.headOffsetInVeh
            camZ = hz + Config.camZVeh 
            
            local rx, ry = getElementRotation(veh)
            if rx > 180 then rx = rx - 360 end
            if ry > 180 then ry = ry - 360 end
            targetRoll = -(ry * cosY - rx * sinY)
            
            local vx, vy, vz = getElementVelocity(veh)
            targetFov = targetFov + math_min(20, (math_sqrt(vx*vx + vy*vy + vz*vz) * 180) * 0.1)
        end
    else
        local velX, velY = getElementVelocity(localPlayer)
        local speed = math_sqrt(velX*velX + velY*velY)
        local swayZ, swayPitch = 0, 0
        
        if speed < 0.01 then
            swayZ = math_sin(state.swayTime * 0.0015) * 0.005
            swayPitch = math_sin(state.swayTime * 0.001) * 0.2
        else
            local moveState = getPedMoveState(localPlayer)
            local bobSpeed = (moveState == "sprint") and 0.015 or ((moveState == "run") and 0.012 or 0.008)
            swayZ = math_sin(state.swayTime * bobSpeed) * 0.03
            swayPitch = math_sin(state.swayTime * bobSpeed * 0.5) * 1.0
            targetFov = targetFov + (speed * 15)
        end
        
        local radY = math_rad(state.yaw)
        local radP = math_rad(state.pitch + swayPitch)
        
        local cosY, sinY = math_cos(radY), math_sin(radY)
        local cosP, sinP = math_cos(radP), math_sin(radP)
        
        lookDirX = cosY * cosP
        lookDirY = sinY * cosP
        lookDirZ = sinP
        
        camX = hx + lookDirX * Config.headOffset
        camY = hy + lookDirY * Config.headOffset
        camZ = hz + Config.camZWalk + swayZ
        
        if getPedControlState(localPlayer, "left") then targetRoll = -2.5
        elseif getPedControlState(localPlayer, "right") then targetRoll = 2.5 end
        targetRoll = targetRoll + math_max(-3, math_min(3, -state.lastMouseDX * 0.15))
        
        local _, _, rz = getElementRotation(localPlayer)
        local baseRot = (rz + 90) % 360
        local diff = (state.yaw - baseRot + 180) % 360 - 180
        
        if diff > 85 then state.yaw = (baseRot + 85) % 360
        elseif diff < -85 then state.yaw = (baseRot - 85) % 360 end
        
        if getTickCount() - state.lastMouseTime > Config.returnTime then
            state.yaw = (state.yaw - diff * dt * 0.003) % 360
            state.pitch = state.pitch - state.pitch * dt * 0.003
        end
    end
    
    local rollDiff = (targetRoll - state.currentRoll) % 360
    if rollDiff > 180 then rollDiff = rollDiff - 360 end
    state.currentRoll = state.currentRoll + rollDiff * dt * 0.01
    
    local lookX = camX + lookDirX * 100
    local lookY = camY + lookDirY * 100
    local lookZ = camZ + lookDirZ * 100

    if state.transProgress < 1.0 then
        state.transProgress = math_min(1.0, state.transProgress + dt * Config.transitionSpeed)
        local ease = 1 - (1 - state.transProgress) * (1 - state.transProgress) * (1 - state.transProgress)
        
        camX = state.sX + (camX - state.sX) * ease
        camY = state.sY + (camY - state.sY) * ease
        camZ = state.sZ + (camZ - state.sZ) * ease
        
        lookX = state.sLX + (lookX - state.sLX) * ease
        lookY = state.sLY + (lookY - state.sLY) * ease
        lookZ = state.sLZ + (lookZ - state.sLZ) * ease
        
        state.currentRoll = state.sRoll + (state.currentRoll - state.sRoll) * ease
        targetFov = state.sFov + (targetFov - state.sFov) * ease
    end
    
    setCameraMatrix(camX, camY, camZ, lookX, lookY, lookZ, state.currentRoll, targetFov)
    
    local task = getPedTask(localPlayer, "primary", 3)
    if task ~= "TASK_COMPLEX_ENTER_CAR_AS_DRIVER" and task ~= "TASK_COMPLEX_ENTER_CAR_AS_PASSENGER" then
        setPedLookAt(localPlayer, lookX, lookY, lookZ, 3000, 0)
    end
end