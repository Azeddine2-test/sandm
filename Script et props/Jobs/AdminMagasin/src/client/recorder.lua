-- ============================================================
-- client/recorder.lua - Enregistreur de chemins NPC
-- Version clean : paths utiles enter / exit uniquement
-- ============================================================

local isRecording = false
local recordedPath = {}
local recordTimer = nil
local recordingStartTime = 0
local recordingStoreId = nil
local recordingPathType = nil

local showHelpHUD = false
local helpHUDStartTime = 0
local HELP_HUD_DURATION = 10000

local function notify(message, nType)
    nType = nType or "info"
    local fuNotify = getResourceFromName("[FU]Notify")
    if fuNotify and getResourceState(fuNotify) == "running" then
        exports["[FU]Notify"]:notify(message, nType)
    else
        local colors = {
            success = {87, 242, 135},
            error = {237, 66, 69},
            info = {88, 165, 255},
            warning = {254, 231, 92},
        }
        local c = colors[nType] or colors.info
        outputChatBox("[AdminMagasin] " .. tostring(message), c[1], c[2], c[3])
    end
end

local function isHandlerAttached(eventName, attachedTo, handlerFunction)
    if type(eventName) ~= "string" or not isElement(attachedTo) or type(handlerFunction) ~= "function" then return false end
    local handlers = getEventHandlers(eventName, attachedTo)
    if type(handlers) == "table" then
        for _, v in ipairs(handlers) do
            if v == handlerFunction then return true end
        end
    end
    return false
end

local pathTypesHelp = {
    {type = "enter", desc = "Chemin d'entree : le client va du spawn/panier client au comptoir"},
    {type = "exit",  desc = "Chemin de sortie : le client quitte le magasin apres paiement"},
}

local function renderPathHelpHUD()
    if not showHelpHUD then return end

    if getTickCount() - helpHUDStartTime > HELP_HUD_DURATION then
        showHelpHUD = false
        return
    end

    local sw, sh = guiGetScreenSize()
    -- demande 19 : texte à la taille du panel admin (13) → cadre élargi et
    -- lignes plus hautes (390 × 155 avant)
    local panelW = 500
    local panelH = 180
    local panelX = sw - panelW - 20
    local panelY = (sh - panelH) / 2

    -- vague 53 (demande 18) : même habillage que le menu d'animations
    THEME.rect(panelX, panelY, panelW, panelH, THEME.R.panneau, THEME.c("fond"))
    THEME.rect(panelX, panelY + 12, 3, panelH - 24, 1.5, THEME.c("accent"))

    dxDrawText("TYPES DE CHEMIN", panelX + 12, panelY + 10, panelX + panelW - 12, panelY + 32, tocolor(255, 255, 255, 255), 1, THEME.police("semibold", 15), "left", "top")
    dxDrawText("Utilisation : /pathrecord [id] [enter|exit]", panelX + 12, panelY + 34, panelX + panelW - 12, panelY + 54, THEME.c("texteDim"), 1, THEME.police("regular", 13), "left", "top")
    dxDrawRectangle(panelX + 12, panelY + 60, panelW - 24, 1, THEME.c("separateur"))

    local y = panelY + 70
    local colors = {
        {87, 242, 135},
        {237, 66, 69},
    }

    for i, pt in ipairs(pathTypesHelp) do
        local c = colors[i] or {200, 200, 200}
        dxDrawText(pt.type, panelX + 15, y, panelX + panelW - 12, y + 20, tocolor(c[1], c[2], c[3], 255), 1, THEME.police("semibold", 13), "left", "top")
        dxDrawText(pt.desc, panelX + 15, y + 21, panelX + panelW - 15, y + 41, THEME.c("texte2"), 1, THEME.police("regular", 12), "left", "top")
        y = y + 48
    end
end

addEventHandler("onClientRender", root, renderPathHelpHUD)

addCommandHandler("pathaide", function()
    showHelpHUD = true
    helpHUDStartTime = getTickCount()
    notify("Aide affichee a droite de l'ecran.", "info")
end)

local function renderRecordingIndicator()
    if not isRecording then return end

    local sw, sh = guiGetScreenSize()

    THEME.rect(sw / 2 - 200, 10, 400, 50, THEME.R.carte, THEME.c("fond"))
    THEME.rect(sw / 2 - 200 + 10, 10, 380, 3, 1.5, THEME.c("dangerSurvol"))   -- rouge = enregistrement

    local blink = (getTickCount() % 1000 < 500)
    if blink then THEME.rect(sw / 2 - 185, 25, 15, 15, 7.5, THEME.c("dangerSurvol")) end

    local typeName = (AMData and AMData.getPathTypeName) and AMData.getPathTypeName(recordingPathType) or (recordingPathType or "?")
    dxDrawText("ENREGISTREMENT EN COURS", sw / 2 - 160, 18, sw / 2 + 200, 38, tocolor(255, 255, 255, 255), 1, THEME.police("semibold", 13), "left", "center")
    dxDrawText("Magasin #" .. tostring(recordingStoreId or "?") .. " | " .. tostring(typeName) .. " | " .. #recordedPath .. " points", sw / 2 - 160, 38, sw / 2 + 200, 55, THEME.c("texte2"), 1, THEME.police("regular", 13), "left", "center")

    if #recordedPath > 1 then
        local startIdx = math.max(1, #recordedPath - 20)
        for i = startIdx, #recordedPath - 1 do
            local p1 = recordedPath[i]
            local p2 = recordedPath[i + 1]
            dxDrawLine3D(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, tocolor(237, 66, 69, 200), 2.0)
        end
    end
end

addEvent("AdminMagasin:startRecording", true)
addEventHandler("AdminMagasin:startRecording", localPlayer, function(storeId, pathType)
    if isRecording then return notify("Un enregistrement est deja en cours. Tapez /pathstop.", "error") end

    if pathType ~= "enter" and pathType ~= "exit" then
        return notify("Type de path invalide. Utilise enter ou exit.", "error")
    end

    isRecording = true
    recordedPath = {}
    recordingStartTime = getTickCount()
    recordingStoreId = storeId
    recordingPathType = pathType

    showHelpHUD = true
    helpHUDStartTime = getTickCount()

    local typeName = (AMData and AMData.getPathTypeName) and AMData.getPathTypeName(pathType) or pathType
    notify("Enregistrement demarre pour le magasin #" .. tostring(storeId) .. " (" .. tostring(typeName) .. ").", "success")
    notify("Marchez le chemin. Tapez /pathstop quand vous avez termine.", "info")

    local fps = (AMConfig and AMConfig.recorder and AMConfig.recorder.fps) or 10
    local interval = math.floor(1000 / fps)

    recordTimer = setTimer(function()
        if not isRecording or not isElement(localPlayer) then return end

        local x, y, z = getElementPosition(localPlayer)
        local _, _, rot = getElementRotation(localPlayer)

        local moveState = "stand"
        local isMoving = getPedControlState(localPlayer, "forwards")
            or getPedControlState(localPlayer, "backwards")
            or getPedControlState(localPlayer, "left")
            or getPedControlState(localPlayer, "right")

        if isMoving then
            if getPedControlState(localPlayer, "walk") then
                moveState = "walk"
            elseif getPedControlState(localPlayer, "sprint") then
                moveState = "sprint"
            else
                moveState = "run"
            end
        end

        table.insert(recordedPath, {
            x = x,
            y = y,
            z = z,
            rot = rot,
            time = getTickCount() - recordingStartTime,
            moveState = moveState
        })
    end, interval, 0)

    if not isHandlerAttached("onClientRender", root, renderRecordingIndicator) then
        addEventHandler("onClientRender", root, renderRecordingIndicator)
    end
end)

addEvent("AdminMagasin:stopRecording", true)
addEventHandler("AdminMagasin:stopRecording", localPlayer, function()
    if not isRecording then return notify("Aucun enregistrement en cours.", "error") end

    isRecording = false
    if isTimer(recordTimer) then killTimer(recordTimer) recordTimer = nil end

    if isHandlerAttached("onClientRender", root, renderRecordingIndicator) then
        removeEventHandler("onClientRender", root, renderRecordingIndicator)
    end

    local minPoints = (AMConfig and AMConfig.recorder and AMConfig.recorder.minPoints) or 5
    if #recordedPath < minPoints then
        notify("Chemin trop court (" .. #recordedPath .. " points, minimum " .. minPoints .. "). Annule.", "error")
        recordedPath = {}
        recordingStoreId = nil
        recordingPathType = nil
        return
    end

    triggerServerEvent("AdminMagasin:savePath", localPlayer, recordingStoreId, recordingPathType, recordedPath)
    notify("Enregistrement termine : " .. #recordedPath .. " points captures.", "success")

    recordedPath = {}
    recordingStoreId = nil
    recordingPathType = nil
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    isRecording = false
    if isTimer(recordTimer) then killTimer(recordTimer) recordTimer = nil end
    if isHandlerAttached("onClientRender", root, renderRecordingIndicator) then
        removeEventHandler("onClientRender", root, renderRecordingIndicator)
    end
    recordedPath = {}
    recordingStoreId = nil
    recordingPathType = nil
    showHelpHUD = false
end)
