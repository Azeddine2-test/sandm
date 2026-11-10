-- =========================================================
-- client.lua - Système de Métiers (SystemTrabajos)
-- Version optimisée : 1 NPC actif + cooldown aléatoire côté serveur
-- Exit normal, sans téléportation forcée
-- Debug visuel désactivé par défaut
-- =========================================================

local inCashierMode = false
local preCashierPos = nil
local activeStoreID = nil

local jobTarget = nil
local jobTargetBlip = nil
local cashierMarkers = {}
local storesCache = {}
local lastMarkersHash = ""

local knownNPCs = {}
local npcBaskets = {}
local permanentBaskets = {}

local draggedItem = nil
local draggedItemNPC = nil
local draggedItemOriginalPos = nil
local draggedItemZ = 0

local CLICK_MAX_DISTANCE = 3.0
local DROP_RADIUS = 0.8

local lookAroundEnabled = false
local baseCameraPos = nil
local baseCameraYaw = 0
local baseCameraPitch = 0
local lookYawOffset = 0
local lookPitchOffset = 0

local LOOK_YAW_LIMIT = math.rad(120)
local LOOK_PITCH_LIMIT = math.rad(45)
local LOOK_SENSITIVITY = 0.002

local freecamEnabled = false
local camX, camY, camZ = 0, 0, 0
local camPitch, camYaw = 0, 0
local lastTick = 0

local editingObject = nil
local editorWindow = nil
local moveSpeed = 0.1
local customBasketID = nil

local isRecording = false
local recordedPath = {}
local recordTimer = nil
local recordingStartTime = 0

local DEBUG_MARKERS = false
local DEBUG_NPCS = false

-- ═══════════════════════════════════════════════════════════════
-- HELPERS CURSEUR / ARTICLES
-- ═══════════════════════════════════════════════════════════════

local function getCursorWorldPositionOnPlane(targetZ)
    if not isCursorShowing() then return false end

    local cx, cy = getCursorPosition()
    if not cx then return false end

    local sw, sh = guiGetScreenSize()
    local camX, camY, camZ = getCameraMatrix()
    local wX, wY, wZ = getWorldFromScreenPosition(cx * sw, cy * sh, 100)
    if not wX then return false end

    local dirX, dirY, dirZ = wX - camX, wY - camY, wZ - camZ
    if dirZ == 0 then return false end

    local t = (targetZ - camZ) / dirZ
    if t < 0 then return false end

    return camX + dirX * t, camY + dirY * t, targetZ
end

local function findClickedArticle(clickX, clickY)
    if not activeStoreID then return nil, nil end

    local firstWaitingBot = nil
    local firstWaitingPed = nil

    for ped, bot in pairs(knownNPCs) do
        if isElement(ped) and bot.state == "waiting" and bot.storeID == activeStoreID then
            firstWaitingBot = bot
            firstWaitingPed = ped
            break
        end
    end

    if not firstWaitingBot or not firstWaitingBot.counterItems then
        return nil, nil
    end

    local closestItem = nil
    local minDist2D = 80
    local counterZ = nil

    for _, item in ipairs(firstWaitingBot.counterItems) do
        if isElement(item) then
            local _, _, iz = getElementPosition(item)
            counterZ = iz
            break
        end
    end

    if counterZ then
        local c3x, c3y, c3z = getCursorWorldPositionOnPlane(counterZ)
        if c3x then
            local min3D = 0.5
            for _, item in ipairs(firstWaitingBot.counterItems) do
                if isElement(item) then
                    local ox, oy, oz = getElementPosition(item)
                    local dist3D = getDistanceBetweenPoints3D(c3x, c3y, c3z, ox, oy, oz)
                    if dist3D < min3D then
                        min3D = dist3D
                        closestItem = item
                    end
                end
            end
        end
    end

    if not closestItem then
        for _, item in ipairs(firstWaitingBot.counterItems) do
            if isElement(item) then
                local ox, oy, oz = getElementPosition(item)
                local sx, sy = getScreenFromWorldPosition(ox, oy, oz)
                if sx and sy then
                    local dist = math.sqrt((sx - clickX)^2 + (sy - clickY)^2)
                    if dist < minDist2D then
                        minDist2D = dist
                        closestItem = item
                    end
                end
            end
        end
    end

    return closestItem, firstWaitingPed
end

-- ═══════════════════════════════════════════════════════════════
-- ANTI-DAMAGE NPC
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "isJobNPC") then
        cancelEvent()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- MAGASINS / MARKERS
-- ═══════════════════════════════════════════════════════════════

local function fetchStoresFromAdminMagasin()
    return storesCache or {}
end

local function requestStoresFromServer()
    triggerServerEvent("SystemTrabajos:requestStores", localPlayer)
end

local function destroyAllCashierMarkers()
    for marker, _ in pairs(cashierMarkers) do
        if isElement(marker) then destroyElement(marker) end
    end
    cashierMarkers = {}
end

local function createCashierMarkerForStore(storeID, storeData)
    if not storeData or not storeData.pos then return end

    local r, g, b, a
    if DEBUG_MARKERS then
        r, g, b, a = 0, 255, 200, 100
    else
        r, g, b, a = 0, 0, 0, 0
    end

    local m = createMarker(
        storeData.pos.x,
        storeData.pos.y,
        storeData.pos.z - 0.9,
        "cylinder",
        1.5,
        r, g, b, a
    )

    if isElement(m) then
        cashierMarkers[m] = storeID
        setElementData(m, "systemTrabajos:cashierMarker", true)
        setElementData(m, "systemTrabajos:storeID", storeID)
        outputDebugString("[SystemTrabajos] Marker caissier cree pour magasin #" .. tostring(storeID))
    end
end

local function rebuildAllMarkers()
    local hash = ""

    for storeID, storeData in pairs(storesCache or {}) do
        if storeData and storeData.pos then
            hash = hash .. tostring(storeID) .. ":" .. math.floor(storeData.pos.x) .. "," .. math.floor(storeData.pos.y) .. "," .. math.floor(storeData.pos.z) .. ";"
        end
    end

    if hash == lastMarkersHash then return end
    lastMarkersHash = hash

    destroyAllCashierMarkers()

    local count = 0
    for storeID, storeData in pairs(storesCache or {}) do
        createCashierMarkerForStore(storeID, storeData)
        count = count + 1
    end

    outputDebugString("[SystemTrabajos] " .. count .. " markers caissier crees.")
end

addEvent("SystemTrabajos:receiveStores", true)
addEventHandler("SystemTrabajos:receiveStores", localPlayer, function(stores)
    storesCache = stores or {}
    rebuildAllMarkers()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(function()
        requestStoresFromServer()
    end, 3000, 1)
end)

addEvent("AdminMagasin:notifyStoresChanged", true)
addEventHandler("AdminMagasin:notifyStoresChanged", root, function()
    requestStoresFromServer()
end)

-- ═══════════════════════════════════════════════════════════════
-- GPS
-- ═══════════════════════════════════════════════════════════════

addEvent("v1:showJobRoute", true)
addEventHandler("v1:showJobRoute", root, function(destX, destY, destZ)
    if not destX then
        jobTarget = nil
        if isElement(jobTargetBlip) then destroyElement(jobTargetBlip) end
        return
    end

    jobTarget = {x = destX, y = destY, z = destZ}
    if isElement(jobTargetBlip) then destroyElement(jobTargetBlip) end
    jobTargetBlip = createBlip(destX, destY, destZ, 41)

    exports["[FU]Notify"]:notify("Dirigez-vous vers le point marque sur votre radar.", "infos")
end)

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "ecran:noir") then return end -- demande 38 : rien du monde pendant l'écran noir (coffre, bandeau)
    if not jobTarget then return end

    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(px, py, pz, jobTarget.x, jobTarget.y, jobTarget.z)

    if dist < 2.5 then
        jobTarget = nil
        if isElement(jobTargetBlip) then destroyElement(jobTargetBlip) end
        exports["[FU]Notify"]:notify("Vous etes arrive a la zone de travail. Bonne chance !", "success")
    else
        local pulseAlpha = 150 + math.sin(getTickCount() / 250) * 55
        dxDrawLine3D(px, py, pz - 0.6, jobTarget.x, jobTarget.y, jobTarget.z, tocolor(255, 215, 0, pulseAlpha), 3.5)

        local sx, sy = getScreenFromWorldPosition(jobTarget.x, jobTarget.y, jobTarget.z + 0.5)
        if sx and sy then
            local distanceText = math.floor(dist) .. " m"
            dxDrawText(distanceText, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1.2, "default-bold", "center", "bottom")
            dxDrawText(distanceText, sx, sy, sx, sy, tocolor(255, 215, 0, 255), 1.2, "default-bold", "center", "bottom")
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- MARKER CAISSIER / MODE CAISSIER
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientMarkerHit", root, function(hitElement, matchingDimension)
    if hitElement ~= localPlayer or not matchingDimension then return end
    if not getElementData(source, "systemTrabajos:cashierMarker") then return end

    local storeID = cashierMarkers[source] or getElementData(source, "systemTrabajos:storeID")
    if not storeID then
        outputDebugString("[SystemTrabajos] Marker touche mais storeID introuvable !")
        return
    end

    if inCashierMode then
        outputDebugString("[SystemTrabajos] Deja en mode caissier, ignore.")
        return
    end

    outputDebugString("[SystemTrabajos] Marker caissier touche pour magasin #" .. tostring(storeID))
    triggerServerEvent("v1:tryEnterCashier", localPlayer, storeID)
end)

addEvent("v1:enterCashierMode", true)
addEventHandler("v1:enterCashierMode", root, function(storeID)
    if not storesCache[storeID] then requestStoresFromServer() end

    local store = storesCache[storeID]
    if not store then
        outputDebugString("[SystemTrabajos] Magasin #" .. tostring(storeID) .. " introuvable dans le cache.")
        return
    end

    preCashierPos = {getElementPosition(localPlayer)}
    inCashierMode = true
    activeStoreID = storeID

    setElementFrozen(localPlayer, true)
    setElementAlpha(localPlayer, 0)
    showCursor(true)

    setTimer(function()
        if not inCashierMode then return end

        local cx, cy, cz, tx, ty, tz = getCameraMatrix()
        baseCameraPos = {x = cx, y = cy, z = cz}

        local dx = tx - cx
        local dy = ty - cy
        local dz = tz - cz
        local horizontalDist = math.sqrt(dx * dx + dy * dy)

        baseCameraYaw = math.atan2(dy, dx)
        baseCameraPitch = math.atan2(dz, horizontalDist)

        lookYawOffset = 0
        lookPitchOffset = 0
        lookAroundEnabled = false

        outputDebugString("[SystemTrabajos] Camera initiale sauvegardee. Yaw: " .. math.floor(math.deg(baseCameraYaw)) .. "°, Pitch: " .. math.floor(math.deg(baseCameraPitch)) .. "°")
    end, 300, 1)

    exports["[FU]Notify"]:notify("Vous etes positionne au magasin #" .. tostring(storeID) .. " : " .. (store.name or "?") .. ". Appuyez sur BACKSPACE pour quitter la caisse.", "infos")
    exports["[FU]Notify"]:notify("Astuce : Appuyez sur ² pour desactiver le curseur et regarder autour de vous.", "aviso")

    setTimer(function()
        if inCashierMode and activeStoreID == storeID then
            triggerServerEvent("SystemTrabajos:startNPCSystem", localPlayer, storeID)
        end
    end, 500, 1)
end, true, "low")

local function exitCashierMode()
    if not inCashierMode then return end

    triggerServerEvent("SystemTrabajos:stopNPCSystem", localPlayer)

    for storeID, basket in pairs(permanentBaskets) do
        if isElement(basket) then destroyElement(basket) end
    end
    permanentBaskets = {}

    for ped, basket in pairs(npcBaskets) do
        if isElement(basket) then destroyElement(basket) end
    end
    npcBaskets = {}

    inCashierMode = false
    setCameraTarget(localPlayer)

    lookAroundEnabled = false
    baseCameraPos = nil
    baseCameraYaw = 0
    baseCameraPitch = 0
    lookYawOffset = 0
    lookPitchOffset = 0

    if preCashierPos then
        setElementPosition(localPlayer, preCashierPos[1], preCashierPos[2], preCashierPos[3])
        preCashierPos = nil
    end

    setElementFrozen(localPlayer, false)
    setElementAlpha(localPlayer, 255)
    showCursor(false)

    exports["[FU]Notify"]:notify("Vous avez quitte le comptoir. Les clients vous attendront.", "infos")
end

addEventHandler("onClientKey", root, function(button, press)
    if not inCashierMode or not press then return end
    if isChatBoxInputActive() or isConsoleActive() then return end

    -- BACKSPACE / Échap : sortie du comptoir via RETOUR (demande 21), en bas du fichier
    if button == "#" then -- touche ² (AZERTY)
        lookAroundEnabled = not lookAroundEnabled

        if lookAroundEnabled then
            showCursor(false)
            local sx, sy = guiGetScreenSize()
            setCursorPosition(sx / 2, sy / 2)
            -- Notification look around désactivée pour éviter le spam visuel.
        else
            showCursor(true)
            -- Notification look around désactivée pour éviter le spam visuel.
        end

        cancelEvent()
    end
end)

addEventHandler("onClientCursorMove", root, function(_, _, absX, absY)
    if not inCashierMode or not lookAroundEnabled then return end
    if not baseCameraPos then return end

    local sx, sy = guiGetScreenSize()
    local cx, cy = sx / 2, sy / 2

    local dx = absX - cx
    local dy = absY - cy
    if dx == 0 and dy == 0 then return end

    lookYawOffset = lookYawOffset - dx * LOOK_SENSITIVITY
    lookPitchOffset = lookPitchOffset - dy * LOOK_SENSITIVITY

    if lookYawOffset > LOOK_YAW_LIMIT then lookYawOffset = LOOK_YAW_LIMIT end
    if lookYawOffset < -LOOK_YAW_LIMIT then lookYawOffset = -LOOK_YAW_LIMIT end
    if lookPitchOffset > LOOK_PITCH_LIMIT then lookPitchOffset = LOOK_PITCH_LIMIT end
    if lookPitchOffset < -LOOK_PITCH_LIMIT then lookPitchOffset = -LOOK_PITCH_LIMIT end

    local finalYaw = baseCameraYaw + lookYawOffset
    local finalPitch = baseCameraPitch + lookPitchOffset

    setCursorPosition(cx, cy)

    local dist = 5.0
    local tx = baseCameraPos.x + math.cos(finalPitch) * math.cos(finalYaw) * dist
    local ty = baseCameraPos.y + math.cos(finalPitch) * math.sin(finalYaw) * dist
    local tz = baseCameraPos.z + math.sin(finalPitch) * dist

    setCameraMatrix(baseCameraPos.x, baseCameraPos.y, baseCameraPos.z, tx, ty, tz)
end)

local function performQuitJob(isAutoKick)
    if jobTarget or inCashierMode or activeStoreID then
        if inCashierMode then exitCashierMode() end

        jobTarget = nil
        if isElement(jobTargetBlip) then destroyElement(jobTargetBlip) end
        activeStoreID = nil

        if isAutoKick == true then
            exports["[FU]Notify"]:notify("Vous vous etes trop eloigne de votre succursale. Service termine.", "error")
        else
            exports["[FU]Notify"]:notify("Vous avez quitte le travail.", "aviso")
        end

        triggerServerEvent("v1:quitJobCajero", localPlayer)
    end
end
addCommandHandler("quitterjob", performQuitJob)

setTimer(function()
    if not activeStoreID then return end
    local store = storesCache[activeStoreID]
    if not store or not store.pos then return end

    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(px, py, pz, store.pos.x, store.pos.y, store.pos.z)

    if dist > 15.0 then performQuitJob(true) end
end, 2000, 0)

-- ═══════════════════════════════════════════════════════════════
-- NPC CLIENTS
-- ═══════════════════════════════════════════════════════════════

addEvent("SystemTrabajos:npcSpawned", true)
addEventHandler("SystemTrabajos:npcSpawned", root, function(ped, storeID, slotIndex, enterPath, pausePoints)
    if not isElement(ped) then return end

    knownNPCs[ped] = {
        storeID = storeID,
        slotIndex = slotIndex,
        spawnTime = getTickCount(),
        path = enterPath,
        pathIndex = 1,
        pausePoints = pausePoints or {},
        pausePointsDone = {},
        state = enterPath and "entering" or "idle",
        isPausing = false,
        pauseEndTime = 0,
    }

    if customBasketID then
        local nx, ny, nz = getElementPosition(ped)
        local basket = createObject(customBasketID, nx, ny, nz)

        if isElement(basket) then
            setElementCollisionsEnabled(basket, false)
            setElementDimension(basket, getElementDimension(ped))
            setElementInterior(basket, getElementInterior(ped))

            local attached = false
            if getResourceState(getResourceFromName("bone_attach")) == "running" then
                attached = exports.bone_attach:attachElementToBone(basket, ped, 12, 0.0, 0.06, 0.05, 180, 0, 0)
            end

            if not attached then
                attachElements(basket, ped, 0.25, 0.1, -0.1, 180, 0, 0)
            end

            setElementParent(basket, ped)
            npcBaskets[ped] = basket
        end
    end

    outputDebugString("[SystemTrabajos] NPC recu - Magasin #" .. tostring(storeID) .. " slot " .. tostring(slotIndex) .. (enterPath and " (syncer, path: " .. #enterPath .. " points)" or " (spectateur)"))
end)

addEvent("SystemTrabajos:npcDespawned", true)
addEventHandler("SystemTrabajos:npcDespawned", root, function(ped)
    if not ped then return end
    if knownNPCs[ped] then
        outputDebugString("[SystemTrabajos] NPC despawn - Magasin #" .. tostring(knownNPCs[ped].storeID))
        knownNPCs[ped] = nil
    end
end)

addEvent("SystemTrabajos:npcArrivedAtCounter", true)
addEventHandler("SystemTrabajos:npcArrivedAtCounter", root, function(ped, storeID, items, basketPermPos)
    if not isElement(ped) then return end

    if npcBaskets[ped] then
        if isElement(npcBaskets[ped]) then destroyElement(npcBaskets[ped]) end
        npcBaskets[ped] = nil
    end

    if knownNPCs[ped] then
        knownNPCs[ped].state = "waiting"
        knownNPCs[ped].counterItems = items or {}
    end

    if basketPermPos and basketPermPos.isSet and customBasketID then
        if not permanentBaskets[storeID] or not isElement(permanentBaskets[storeID]) then
            local basket = createObject(customBasketID, basketPermPos.x, basketPermPos.y, basketPermPos.z, 0, 0, basketPermPos.rot or 0)
            if isElement(basket) then
                setElementCollisionsEnabled(basket, false)
                setElementData(basket, "systemTrabajos:permanentBasket", true)
                setElementData(basket, "systemTrabajos:storeID", storeID)
                permanentBaskets[storeID] = basket
                outputDebugString("[SystemTrabajos] Panier permanent cree au comptoir magasin #" .. tostring(storeID))
            end
        else
            setElementAlpha(permanentBaskets[storeID], 255)
        end
    end

    outputDebugString("[SystemTrabajos] NPC arrive au comptoir - " .. #(items or {}) .. " articles")
end)

addEventHandler("onClientRender", root, function()
    if not DEBUG_NPCS then return end
    if not isElement(localPlayer) then return end

    local px, py, pz = getElementPosition(localPlayer)
    if not px then return end

    local toRemove = {}

    for ped, info in pairs(knownNPCs) do
        if not isElement(ped) or type(info) ~= "table" then
            table.insert(toRemove, ped)
        else
            local nx, ny, nz = getElementPosition(ped)
            if nx then
                local dist = getDistanceBetweenPoints3D(px, py, pz, nx, ny, nz)
                if dist <= 30 then
                    local sx, sy = getScreenFromWorldPosition(nx, ny, nz + 1.2)
                    if sx and sy then
                        local label = "[NPC Client]\nMagasin #" .. tostring(info.storeID or "?") .. " (slot " .. tostring(info.slotIndex or "?") .. ")"
                        dxDrawText(label, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), 0.8, "default-bold", "center", "center")
                        dxDrawText(label, sx, sy, sx, sy, tocolor(87, 242, 135, 255), 0.8, "default-bold", "center", "center")
                    end
                end
            end
        end
    end

    for _, ped in ipairs(toRemove) do knownNPCs[ped] = nil end
end)

-- ═══════════════════════════════════════════════════════════════
-- FREECAM / EDITEUR CAMERA
-- ═══════════════════════════════════════════════════════════════

local function freecamRender()
    if not freecamEnabled then return end

    local currentTick = getTickCount()
    local dt = (currentTick - lastTick) / 1000.0
    if dt > 0.1 then dt = 0.016 end
    lastTick = currentTick

    if not isChatBoxInputActive() and not isCursorShowing() and not isConsoleActive() then
        local speed = 15.0 * dt
        if getKeyState("lshift") then speed = speed * 3 end
        if getKeyState("lalt") then speed = speed * 0.2 end

        local fX = math.cos(camPitch) * math.cos(camYaw)
        local fY = math.cos(camPitch) * math.sin(camYaw)
        local fZ = math.sin(camPitch)
        local rX = math.cos(camYaw - math.pi / 2)
        local rY = math.sin(camYaw - math.pi / 2)

        if getKeyState("w") then camX = camX + fX * speed; camY = camY + fY * speed; camZ = camZ + fZ * speed end
        if getKeyState("s") then camX = camX - fX * speed; camY = camY - fY * speed; camZ = camZ - fZ * speed end
        if getKeyState("a") then camX = camX - rX * speed; camY = camY - rY * speed end
        if getKeyState("d") then camX = camX + rX * speed; camY = camY + rY * speed end
        if getKeyState("space") then camZ = camZ + speed end
        if getKeyState("lctrl") then camZ = camZ - speed end
    end

    local targetX = camX + math.cos(camPitch) * math.cos(camYaw)
    local targetY = camY + math.cos(camPitch) * math.sin(camYaw)
    local targetZ = camZ + math.sin(camPitch)
    setCameraMatrix(camX, camY, camZ, targetX, targetY, targetZ)

    local sx, sy = guiGetScreenSize()
    dxDrawText("Mode Editeur de Camera\nW, A, S, D pour bouger | SHIFT rapide | ALT lent\nESPACE monter | CTRL descendre\nTapez /editeurcamera pour sauvegarder et quitter.", 0, sy - 150, sx, sy, tocolor(255, 255, 255, 255), 1.2, "default-bold", "center", "center", false, false, false, true)
end

local function freecamMouseMove(_, _, ax, ay)
    if not freecamEnabled or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end

    local sx, sy = guiGetScreenSize()
    local cx, cy = sx / 2, sy / 2
    local dx = ax - cx
    local dy = ay - cy
    if dx == 0 and dy == 0 then return end

    camYaw = camYaw - dx * 0.002
    camPitch = camPitch - dy * 0.002

    if camPitch > math.pi / 2 - 0.05 then camPitch = math.pi / 2 - 0.05 end
    if camPitch < -math.pi / 2 + 0.05 then camPitch = -math.pi / 2 + 0.05 end

    setCursorPosition(cx, cy)
end

addCommandHandler("editeurcamera", function()
    if not freecamEnabled then
        freecamEnabled = true
        lastTick = getTickCount()

        local cx, cy, cz, tx, ty, tz = getCameraMatrix()
        camX, camY, camZ = cx, cy, cz

        local dx = tx - cx
        local dy = ty - cy
        local dz = tz - cz
        local dist = math.sqrt(dx * dx + dy * dy)
        camYaw = math.atan2(dy, dx)
        camPitch = math.atan2(dz, dist)

        addEventHandler("onClientRender", root, freecamRender)
        addEventHandler("onClientCursorMove", root, freecamMouseMove)

        local sx, sy = guiGetScreenSize()
        setCursorPosition(sx / 2, sy / 2)

        setElementAlpha(localPlayer, 0)
        exports["[FU]Notify"]:notify("Mode camera libre active. Utilisez /editeurcamera pour sauvegarder.", "infos")
    else
        freecamEnabled = false
        removeEventHandler("onClientRender", root, freecamRender)
        removeEventHandler("onClientCursorMove", root, freecamMouseMove)

        local cx, cy, cz, tx, ty, tz = getCameraMatrix()
        local matrixString = string.format("%.3f, %.3f, %.3f, %.3f, %.3f, %.3f", cx, cy, cz, tx, ty, tz)

        setCameraTarget(localPlayer)
        setElementAlpha(localPlayer, 255)
        setClipboard(matrixString)
        exports["[FU]Notify"]:notify("Position capturée et copiée dans le presse-papiers.", "success")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- PANIER CUSTOM
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientResourceStart", resourceRoot, function()
    customBasketID = engineRequestModel("object")

    if customBasketID then
        local txd = engineLoadTXD("assets/models/shopbasket1.txd")
        if txd then engineImportTXD(txd, customBasketID) end

        local col = engineLoadCOL("assets/models/shopbasket1.col")
        if col then engineReplaceCOL(col, customBasketID) end

        local dff = engineLoadDFF("assets/models/shopbasket1.dff")
        if dff then engineReplaceModel(dff, customBasketID) end

        outputDebugString("[SystemTrabajos] Modele panier custom charge : ID " .. tostring(customBasketID))
    else
        outputDebugString("[SystemTrabajos] Erreur d'assignation de modele : limite d'IDs atteinte.")
    end
end)

function getCustomBasketID()
    return customBasketID
end

-- ═══════════════════════════════════════════════════════════════
-- EDITEUR OBJET /placerobjet
-- ═══════════════════════════════════════════════════════════════

local function updateObjectPosition(axis, dir)
    if not isElement(editingObject) then return end
    local x, y, z = getElementPosition(editingObject)
    local rx, ry, rz = getElementRotation(editingObject)

    if axis == "x" then x = x + (moveSpeed * dir)
    elseif axis == "y" then y = y + (moveSpeed * dir)
    elseif axis == "z" then z = z + (moveSpeed * dir)
    elseif axis == "rx" then rx = rx + (moveSpeed * 10 * dir)
    elseif axis == "ry" then ry = ry + (moveSpeed * 10 * dir)
    elseif axis == "rz" then rz = rz + (moveSpeed * 10 * dir)
    end

    setElementPosition(editingObject, x, y, z)
    setElementRotation(editingObject, rx, ry, rz)
end

local function closeEditor()
    if isElement(editorWindow) then destroyElement(editorWindow) end
    if isElement(editingObject) then destroyElement(editingObject) end
    editingObject = nil
    showCursor(false)
end

local function saveEditor()
    if isElement(editingObject) then
        local x, y, z = getElementPosition(editingObject)
        local rx, ry, rz = getElementRotation(editingObject)
        local posString = string.format("%.3f, %.3f, %.3f, %.3f, %.3f, %.3f", x, y, z, rx, ry, rz)
        setClipboard(posString)
        exports["[FU]Notify"]:notify("Position copiée dans le presse-papiers.", "success")
    end
    closeEditor()
end

local function createEditorPanel()
    if isElement(editorWindow) then destroyElement(editorWindow) end

    local sw, sh = guiGetScreenSize()
    editorWindow = guiCreateWindow(sw - 320, sh / 2 - 150, 300, 300, "Panneau d'édition 3D", false)
    guiWindowSetSizable(editorWindow, false)

    guiCreateLabel(15, 30, 270, 20, "Vitesse de déplacement :", false, editorWindow)
    local rSlow = guiCreateRadioButton(15, 50, 80, 20, "Lent", false, editorWindow)
    local rNormal = guiCreateRadioButton(105, 50, 80, 20, "Normal", false, editorWindow)
    local rFast = guiCreateRadioButton(195, 50, 80, 20, "Rapide", false, editorWindow)
    guiRadioButtonSetSelected(rNormal, true)

    addEventHandler("onClientGUIClick", rSlow, function() moveSpeed = 0.01 end, false)
    addEventHandler("onClientGUIClick", rNormal, function() moveSpeed = 0.1 end, false)
    addEventHandler("onClientGUIClick", rFast, function() moveSpeed = 1.0 end, false)

    guiCreateLabel(15, 80, 270, 20, "Position (X, Y, Z) :", false, editorWindow)
    local btnXMinus = guiCreateButton(15, 100, 40, 30, "X-", false, editorWindow)
    local btnXPlus = guiCreateButton(60, 100, 40, 30, "X+", false, editorWindow)
    local btnYMinus = guiCreateButton(115, 100, 40, 30, "Y-", false, editorWindow)
    local btnYPlus = guiCreateButton(160, 100, 40, 30, "Y+", false, editorWindow)
    local btnZMinus = guiCreateButton(215, 100, 40, 30, "Z-", false, editorWindow)
    local btnZPlus = guiCreateButton(260, 100, 40, 30, "Z+", false, editorWindow)

    guiCreateLabel(15, 140, 270, 20, "Rotation (RX, RY, RZ) :", false, editorWindow)
    local btnRXMinus = guiCreateButton(15, 160, 40, 30, "RX-", false, editorWindow)
    local btnRXPlus = guiCreateButton(60, 160, 40, 30, "RX+", false, editorWindow)
    local btnRYMinus = guiCreateButton(115, 160, 40, 30, "RY-", false, editorWindow)
    local btnRYPlus = guiCreateButton(160, 160, 40, 30, "RY+", false, editorWindow)
    local btnRZMinus = guiCreateButton(215, 160, 40, 30, "RZ-", false, editorWindow)
    local btnRZPlus = guiCreateButton(260, 160, 40, 30, "RZ+", false, editorWindow)

    addEventHandler("onClientGUIClick", btnXMinus, function() updateObjectPosition("x", -1) end, false)
    addEventHandler("onClientGUIClick", btnXPlus, function() updateObjectPosition("x", 1) end, false)
    addEventHandler("onClientGUIClick", btnYMinus, function() updateObjectPosition("y", -1) end, false)
    addEventHandler("onClientGUIClick", btnYPlus, function() updateObjectPosition("y", 1) end, false)
    addEventHandler("onClientGUIClick", btnZMinus, function() updateObjectPosition("z", -1) end, false)
    addEventHandler("onClientGUIClick", btnZPlus, function() updateObjectPosition("z", 1) end, false)
    addEventHandler("onClientGUIClick", btnRXMinus, function() updateObjectPosition("rx", -1) end, false)
    addEventHandler("onClientGUIClick", btnRXPlus, function() updateObjectPosition("rx", 1) end, false)
    addEventHandler("onClientGUIClick", btnRYMinus, function() updateObjectPosition("ry", -1) end, false)
    addEventHandler("onClientGUIClick", btnRYPlus, function() updateObjectPosition("ry", 1) end, false)
    addEventHandler("onClientGUIClick", btnRZMinus, function() updateObjectPosition("rz", -1) end, false)
    addEventHandler("onClientGUIClick", btnRZPlus, function() updateObjectPosition("rz", 1) end, false)

    local btnSave = guiCreateButton(15, 210, 270, 35, "Sauvegarder la position et copier", false, editorWindow)
    local btnClose = guiCreateButton(15, 255, 270, 35, "Annuler et fermer", false, editorWindow)
    addEventHandler("onClientGUIClick", btnSave, saveEditor, false)
    addEventHandler("onClientGUIClick", btnClose, closeEditor, false)
    if type(HABILLAGE) == "table" then HABILLAGE.appliquer(editorWindow) end   -- demande 22 : thème du menu d'animations
end

addCommandHandler("placerobjet", function(cmd, modelArg)
    if isElement(editingObject) then
        closeEditor()
    else
        local objModel = customBasketID
        local objScale = 1.0

        if modelArg and tonumber(modelArg) then
            objModel = tonumber(modelArg)
            local editorScales = {[1580] = 0.40, [1545] = 1.0, [1544] = 1.0, [1487] = 1.0, [1520] = 1.0, [1517] = 1.0}
            if editorScales[objModel] then objScale = editorScales[objModel] end
        elseif not customBasketID then
            exports["[FU]Notify"]:notify("Le modèle du panier n'est pas encore chargé.", "error")
            return
        end

        local px, py, pz = getElementPosition(localPlayer)
        editingObject = createObject(objModel, px, py + 1, pz)
        setObjectScale(editingObject, objScale)
        setElementCollisionsEnabled(editingObject, false)
        setElementAlpha(editingObject, 200)

        createEditorPanel()
        showCursor(true)
        exports["[FU]Notify"]:notify("Mode de placement active. Utilisez le panel pour ajuster.", "infos")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- ANCIEN PATH RECORDER /enregistrerbot
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("enregistrerbot", function()
    if isRecording then
        isRecording = false
        if isTimer(recordTimer) then killTimer(recordTimer) end

        local output = "local npcPath = {\n"
        for i, point in ipairs(recordedPath) do
            output = output .. string.format("    {x=%.3f, y=%.3f, z=%.3f, rot=%.3f, time=%d, moveState=\"%s\"},\n", point.x, point.y, point.z, point.rot, point.time, point.moveState)
        end
        output = output .. "}\n"
        setClipboard(output)

        exports["[FU]Notify"]:notify("Enregistrement termine et copie (" .. #recordedPath .. " frames).", "success")
    else
        isRecording = true
        recordedPath = {}
        recordingStartTime = getTickCount()

        recordTimer = setTimer(function()
            local x, y, z = getElementPosition(localPlayer)
            local _, _, rot = getElementRotation(localPlayer)

            local moveState = "stand"
            if getPedControlState(localPlayer, "forwards") or getPedControlState(localPlayer, "backwards") or getPedControlState(localPlayer, "left") or getPedControlState(localPlayer, "right") then
                if getPedControlState(localPlayer, "walk") then moveState = "walk"
                elseif getPedControlState(localPlayer, "sprint") then moveState = "sprint"
                else moveState = "run" end
            end

            table.insert(recordedPath, {x = x, y = y, z = z, rot = rot, time = getTickCount() - recordingStartTime, moveState = moveState})
        end, 100, 0)

        exports["[FU]Notify"]:notify("Enregistrement demarre. Utilisez /enregistrerbot pour arreter.", "infos")
        exports["[FU]Notify"]:notify("[Astuce] Pour sauvegarder en DB, utilisez /pathrecord d'AdminMagasin.", "aviso")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- MOTEUR DE MOUVEMENT NPC - VERSION PROPRE
-- ═══════════════════════════════════════════════════════════════

local PATH_POINT_THRESHOLD = 1.15
local PAUSE_TRIGGER_DISTANCE = 0.9

local function setNPCControlState(ped, control, state)
    if not isElement(ped) then return end
    if not knownNPCs[ped] then return end

    if not knownNPCs[ped].controls then knownNPCs[ped].controls = {} end

    if knownNPCs[ped].controls[control] ~= state then
        knownNPCs[ped].controls[control] = state
        setPedControlState(ped, control, state)
    end
end

local function stopNPCControls(ped)
    setNPCControlState(ped, "forwards", false)
    setNPCControlState(ped, "walk", false)
    setNPCControlState(ped, "sprint", false)
end

local function smoothRotateNPC(ped, targetRot, factor)
    factor = factor or 0.15
    local _, _, currentRot = getElementRotation(ped)
    local diff = targetRot - currentRot

    while diff > 180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end

    local newRot = currentRot + diff * factor
    setElementRotation(ped, 0, 0, newRot, "default", true)
end

local function checkPausePoint(ped, bot)
    if not isElement(ped) then return nil end
    if not bot.pausePoints or #bot.pausePoints == 0 then return nil end

    local bx, by, bz = getElementPosition(ped)
    if not bx then return nil end

    for idx, pt in ipairs(bot.pausePoints) do
        if not bot.pausePointsDone[idx] then
            local dist = getDistanceBetweenPoints3D(bx, by, bz, pt.x, pt.y, pt.z)
            if dist < PAUSE_TRIGGER_DISTANCE then
                return idx, pt
            end
        end
    end
    return nil
end

local function shouldSkipPathNode(bot, node, dist)
    if not node then return false end
    local moveState = node.moveState or "walk"

    if dist <= PATH_POINT_THRESHOLD then
        return true
    end

    -- Fix important : les paths exit peuvent commencer avec plusieurs points stand proches.
    if bot.state == "exiting" and moveState == "stand" and dist <= 2.0 then
        return true
    end

    return false
end

local function applyNPCMoveState(ped, moveState)
    if moveState == "stand" then
        stopNPCControls(ped)
    elseif moveState == "walk" then
        setNPCControlState(ped, "forwards", true)
        setNPCControlState(ped, "walk", true)
        setNPCControlState(ped, "sprint", false)
    elseif moveState == "run" then
        setNPCControlState(ped, "forwards", true)
        setNPCControlState(ped, "walk", false)
        setNPCControlState(ped, "sprint", false)
    elseif moveState == "sprint" then
        setNPCControlState(ped, "forwards", true)
        setNPCControlState(ped, "walk", false)
        setNPCControlState(ped, "sprint", true)
    else
        setNPCControlState(ped, "forwards", true)
        setNPCControlState(ped, "walk", true)
        setNPCControlState(ped, "sprint", false)
    end
end

local function finishBotPath(ped, bot)
    stopNPCControls(ped)

    local lastPoint = bot.path and bot.path[#bot.path]
    if lastPoint and lastPoint.rot then
        setElementRotation(ped, 0, 0, lastPoint.rot, "default", true)
    end

    if bot.state == "entering" then
        bot.state = "waiting"
        triggerServerEvent("SystemTrabajos:npcReachedCounter", localPlayer, ped, bot.storeID)
        outputDebugString("[SystemTrabajos] NPC atteint le comptoir du magasin #" .. tostring(bot.storeID))
    elseif bot.state == "exiting" then
        bot.state = "exited"
        triggerServerEvent("SystemTrabajos:npcFinishedExit", localPlayer, ped)
        outputDebugString("[SystemTrabajos] NPC a atteint la fin du path exit")
    end
end

local function updateBotMovement(ped, bot)
    if not isElement(ped) then return end
    if not bot.path then return end
    if bot.state ~= "entering" and bot.state ~= "exiting" then return end

    if bot.isPausing then
        stopNPCControls(ped)
        if getTickCount() >= bot.pauseEndTime then
            bot.isPausing = false
            outputDebugString("[SystemTrabajos] Fin de pause pour NPC magasin #" .. tostring(bot.storeID))
        end
        return
    end

    if bot.pathIndex > #bot.path then
        finishBotPath(ped, bot)
        return
    end

    local pauseIdx, pausePt = checkPausePoint(ped, bot)
    if pauseIdx and not bot.pausePointsDone[pauseIdx] then
        bot.pausePointsDone[pauseIdx] = true
        bot.isPausing = true
        bot.pauseEndTime = getTickCount() + (pausePt.duration or 2000)

        if pausePt.rot then
            setElementRotation(ped, 0, 0, pausePt.rot, "default", true)
        end

        stopNPCControls(ped)
        outputDebugString("[SystemTrabajos] NPC en pause au point #" .. tostring(pauseIdx) .. " (durée: " .. tostring(pausePt.duration or 2000) .. "ms)")
        return
    end

    local targetNode = bot.path[bot.pathIndex]
    if not targetNode then return end

    local bx, by, bz = getElementPosition(ped)
    if not bx then return end

    local distToTarget = getDistanceBetweenPoints3D(bx, by, bz, targetNode.x, targetNode.y, targetNode.z)

    while targetNode and shouldSkipPathNode(bot, targetNode, distToTarget) do
        bot.pathIndex = bot.pathIndex + 1

        if bot.pathIndex > #bot.path then
            finishBotPath(ped, bot)
            return
        end

        targetNode = bot.path[bot.pathIndex]
        if not targetNode then return end

        distToTarget = getDistanceBetweenPoints3D(bx, by, bz, targetNode.x, targetNode.y, targetNode.z)
    end

    if not targetNode then return end

    local lookAheadIdx = math.min(bot.pathIndex + 5, #bot.path)
    local lookAheadNode = bot.path[lookAheadIdx] or targetNode

    local dx = lookAheadNode.x - bx
    local dy = lookAheadNode.y - by

    if (dx * dx + dy * dy) > 0.01 then
        local targetRot = math.deg(math.atan2(dy, dx)) - 90
        if targetRot < 0 then targetRot = targetRot + 360 end
        smoothRotateNPC(ped, targetRot, 0.20)
    end

    local moveState = targetNode.moveState or "walk"

    -- Fix : si un point stand est encore trop loin, on marche vers lui au lieu de rester bloqué.
    if moveState == "stand" and distToTarget > PATH_POINT_THRESHOLD then
        moveState = "walk"
    end

    applyNPCMoveState(ped, moveState)
end

addEventHandler("onClientRender", root, function()
    local toRemove = {}

    for ped, bot in pairs(knownNPCs) do
        if not isElement(ped) or type(bot) ~= "table" then
            table.insert(toRemove, ped)
        else
            if bot.path then updateBotMovement(ped, bot) end
        end
    end

    for _, ped in ipairs(toRemove) do knownNPCs[ped] = nil end
end)

-- ═══════════════════════════════════════════════════════════════
-- DRAG & DROP ARTICLES
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if button ~= "left" or state ~= "down" then return end
    if not inCashierMode then return end
    if lookAroundEnabled then return end
    if not isCursorShowing() then return end

    local clickedItem, ownerNPC = findClickedArticle(absX, absY)
    if not clickedItem then return end

    draggedItem = clickedItem
    draggedItemNPC = ownerNPC

    local ox, oy, oz = getElementPosition(draggedItem)
    draggedItemOriginalPos = {x = ox, y = oy, z = oz}
    draggedItemZ = oz

    playSoundFrontEnd(37)
    outputDebugString("[SystemTrabajos] Article agrippe pour drag")
end)

addEventHandler("onClientRender", root, function()
    if not draggedItem then return end
    if not getKeyState("mouse1") then return end

    if not isElement(draggedItem) then
        draggedItem = nil
        draggedItemNPC = nil
        draggedItemOriginalPos = nil
        return
    end

    local nx, ny, nz = getCursorWorldPositionOnPlane(draggedItemZ + 0.15)
    if nx then setElementPosition(draggedItem, nx, ny, nz) end
end)

local function isInBasketZone(itemX, itemY, itemZ, storeID)
    local basket = permanentBaskets[storeID]
    if not isElement(basket) then return false end

    local bx, by, bz = getElementPosition(basket)
    local dist = getDistanceBetweenPoints3D(itemX, itemY, itemZ, bx, by, bz)
    return dist <= DROP_RADIUS
end

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if button ~= "left" or state ~= "up" then return end
    if not draggedItem then return end

    if not isElement(draggedItem) then
        draggedItem = nil
        draggedItemNPC = nil
        draggedItemOriginalPos = nil
        return
    end

    local itemX, itemY, itemZ = getElementPosition(draggedItem)

    if isInBasketZone(itemX, itemY, itemZ, activeStoreID) then
        triggerServerEvent("SystemTrabajos:depositArticle", localPlayer, draggedItem, draggedItemNPC)
        outputDebugString("[SystemTrabajos] Depot envoye au serveur")
    else
        if draggedItemOriginalPos then
            setElementPosition(draggedItem, draggedItemOriginalPos.x, draggedItemOriginalPos.y, draggedItemOriginalPos.z)
        end
        playSoundFrontEnd(32)
        outputDebugString("[SystemTrabajos] Depot hors zone, article restaure")
    end

    draggedItem = nil
    draggedItemNPC = nil
    draggedItemOriginalPos = nil
end)

addEvent("SystemTrabajos:articleDeposited", true)
addEventHandler("SystemTrabajos:articleDeposited", localPlayer, function(ped, articleIndex)
    playSoundFrontEnd(37)
    outputDebugString("[SystemTrabajos] Article #" .. tostring(articleIndex) .. " depose avec succes")
end)

addEvent("SystemTrabajos:paymentReceived", true)
addEventHandler("SystemTrabajos:paymentReceived", localPlayer, function(totalAmount, baseAmount, tips, nbArticles)
    playSoundFrontEnd(35)

    local moneySoundPath = "assets/sounds/MoneySound.mp4"
    if fileExists(moneySoundPath) then
        local moneySound = playSound(moneySoundPath)
        if isElement(moneySound) then setSoundVolume(moneySound, 0.6) end
    end

    local unitPrice = 0
    if nbArticles and nbArticles > 0 then unitPrice = math.floor(baseAmount / nbArticles) end

    local msg = string.format("Vous avez vendu %d article(s) pour +%d$.", nbArticles or 0, totalAmount or 0)
    exports["[FU]Notify"]:notify(msg, "success")

    local invRes = getResourceFromName("crp_inventory")
    if invRes and getResourceState(invRes) == "running" then
        triggerEvent("notifyItem", localPlayer, "1dollar", totalAmount, "Ajoute")
    end

    outputDebugString("[SystemTrabajos] Paiement recu : " .. tostring(totalAmount) .. "$")
end)

-- ═══════════════════════════════════════════════════════════════
-- SORTIE NPC PATH EXIT
-- ═══════════════════════════════════════════════════════════════

local EXIT_DIALOGS = {
    "Merci beaucoup pour le service, a bientot !",
    "Passez une excellente journee.",
    "Merci, a la prochaine.",
    "Tout est parfait, merci beaucoup.",
    "Tres aimable de votre part, a bientot.",
    "Merci pour votre temps, au revoir.",
}

addEvent("SystemTrabajos:npcStartExit", true)
addEventHandler("SystemTrabajos:npcStartExit", root, function(ped, exitPath)
    if not isElement(ped) then return end
    if not knownNPCs[ped] then return end

    local storeID = knownNPCs[ped].storeID

    if permanentBaskets[storeID] then
        local hasOtherWaiting = false
        for otherPed, otherBot in pairs(knownNPCs) do
            if otherPed ~= ped and isElement(otherPed) and otherBot.state == "waiting" and otherBot.storeID == storeID then
                hasOtherWaiting = true
                break
            end
        end

        if not hasOtherWaiting then
            if isElement(permanentBaskets[storeID]) then destroyElement(permanentBaskets[storeID]) end
            permanentBaskets[storeID] = nil
            outputDebugString("[SystemTrabajos] Panier permanent detruit (magasin #" .. tostring(storeID) .. ")")
        end
    end

    knownNPCs[ped].chatText = EXIT_DIALOGS[math.random(#EXIT_DIALOGS)]
    knownNPCs[ped].chatTextEndTime = getTickCount() + 4000

    if exitPath and type(exitPath) == "table" and #exitPath > 0 then
        knownNPCs[ped].path = exitPath
        knownNPCs[ped].pathIndex = 1
        knownNPCs[ped].state = "exiting"
        knownNPCs[ped].pausePointsDone = {}
        knownNPCs[ped].isPausing = false
        knownNPCs[ped].pauseEndTime = 0
        knownNPCs[ped].controls = {}

        setElementFrozen(ped, false)
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "walk", false)
        setPedControlState(ped, "sprint", false)

        outputDebugString("[SystemTrabajos] NPC demarre path exit NORMAL (" .. #exitPath .. " points)")
    else
        knownNPCs[ped].state = "exiting"
        outputDebugString("[SystemTrabajos] NPC en sortie (spectateur)")
    end
end)

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "ecran:noir") then return end -- demande 38 : rien du monde pendant l'écran noir (coffre, bandeau)
    for ped, info in pairs(knownNPCs) do
        if isElement(ped) and info.chatText and info.chatTextEndTime then
            if getTickCount() > info.chatTextEndTime then
                info.chatText = nil
                info.chatTextEndTime = nil
            else
                local px, py, pz = getElementPosition(localPlayer)
                local nx, ny, nz = getElementPosition(ped)
                if px and nx then
                    local dist = getDistanceBetweenPoints3D(px, py, pz, nx, ny, nz)
                    if dist <= 25 then
                        local sx, sy = getScreenFromWorldPosition(nx, ny, nz + 0.85)
                        if sx and sy then
                            local text = info.chatText
                            local font = "default-bold"
                            local scale = 1.0
                            local tW = dxGetTextWidth(text, scale, font)
                            local tH = dxGetFontHeight(scale, font)
                            local padX, padY = 8, 4

                            dxDrawRectangle(sx - (tW / 2) - padX - 1, sy - (tH / 2) - padY - 1, tW + (padX * 2) + 2, tH + (padY * 2) + 2, tocolor(0, 0, 0, 200))
                            dxDrawRectangle(sx - (tW / 2) - padX, sy - (tH / 2) - padY, tW + (padX * 2), tH + (padY * 2), tocolor(25, 25, 25, 180))
                            dxDrawText(text, sx - (tW / 2), sy - (tH / 2), sx + (tW / 2), sy + (tH / 2), tocolor(240, 240, 240, 255), scale, font, "center", "center")
                        end
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- NETTOYAGE
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientResourceStop", resourceRoot, function()
    destroyAllCashierMarkers()

    if inCashierMode then
        setCameraTarget(localPlayer)
        setElementFrozen(localPlayer, false)
        setElementAlpha(localPlayer, 255)
        showCursor(false)
    end

    if isElement(jobTargetBlip) then destroyElement(jobTargetBlip) end
    if isElement(editorWindow) then destroyElement(editorWindow) end
    if isElement(editingObject) then destroyElement(editingObject) end

    if freecamEnabled then
        removeEventHandler("onClientRender", root, freecamRender)
        removeEventHandler("onClientCursorMove", root, freecamMouseMove)
        setCameraTarget(localPlayer)
        setElementAlpha(localPlayer, 255)
    end

    if isTimer(recordTimer) then killTimer(recordTimer) end

    for ped, basket in pairs(npcBaskets) do
        if isElement(basket) then destroyElement(basket) end
    end
    npcBaskets = {}

    for storeID, basket in pairs(permanentBaskets) do
        if isElement(basket) then destroyElement(basket) end
    end
    permanentBaskets = {}

    if draggedItem and isElement(draggedItem) and draggedItemOriginalPos then
        setElementPosition(draggedItem, draggedItemOriginalPos.x, draggedItemOriginalPos.y, draggedItemOriginalPos.z)
    end

    draggedItem = nil
    draggedItemNPC = nil
    draggedItemOriginalPos = nil
    knownNPCs = {}

    outputDebugString("[SystemTrabajos] Nettoyage effectue.")
end)

-- Demande 21 : BACKSPACE et Échap = « retour » (un niveau chacun) : quitter le
-- comptoir de la caisse, fermer le panneau d'édition 3D (placement annulé).
if RETOUR then
    RETOUR.brancher({ nom = "comptoir (caisse)", ouvert = function() return inCashierMode end, retour = function() exitCashierMode() end })
    RETOUR.brancher({ nom = "edition 3D", ouvert = function() return isElement(editorWindow) end, retour = function() closeEditor() end })
end
