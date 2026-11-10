-- ============================================================
-- By : Phanthomme
-- client/visualizer.lua - Visualisation 3D + Test NPC
-- Version clean compatible enter / exit
-- ============================================================

local showingPath = nil
local showingPathId = nil
local testNPCs = {}

local PATH_POINT_THRESHOLD = 1.15

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

local function renderPathVisualization()
    if not showingPath or #showingPath < 2 then return end

    local px, py, pz = getElementPosition(localPlayer)
    local maxDist = (AMConfig and AMConfig.visualizer and AMConfig.visualizer.maxDistance) or 50
    local lineColor = (AMConfig and AMConfig.visualizer and AMConfig.visualizer.lineColor) or {255, 215, 0}
    local lineWidth = (AMConfig and AMConfig.visualizer and AMConfig.visualizer.lineWidth) or 2.0

    for i = 1, #showingPath - 1 do
        local p1 = showingPath[i]
        local p2 = showingPath[i + 1]
        local dist = getDistanceBetweenPoints3D(px, py, pz, p1.x, p1.y, p1.z)

        if dist < maxDist then
            local r, g, b = lineColor[1], lineColor[2], lineColor[3]
            if p1.moveState == "stand" then
                r, g, b = 100, 100, 255
            elseif p1.moveState == "walk" then
                r, g, b = 87, 242, 135
            elseif p1.moveState == "run" then
                r, g, b = 255, 165, 0
            elseif p1.moveState == "sprint" then
                r, g, b = 255, 50, 50
            end
            dxDrawLine3D(p1.x, p1.y, p1.z + 0.1, p2.x, p2.y, p2.z + 0.1, tocolor(r, g, b, 200), lineWidth)
        end
    end

    local startPoint = showingPath[1]
    local endPoint = showingPath[#showingPath]

    if getDistanceBetweenPoints3D(px, py, pz, startPoint.x, startPoint.y, startPoint.z) < maxDist then
        dxDrawLine3D(startPoint.x, startPoint.y, startPoint.z, startPoint.x, startPoint.y, startPoint.z + 2, tocolor(87, 242, 135, 255), 3.0)
        local sx, sy = getScreenFromWorldPosition(startPoint.x, startPoint.y, startPoint.z + 2.2)
        if sx and sy then
            dxDrawText("DEPART", sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 255), 1.2, "default-bold", "center", "center")
            dxDrawText("DEPART", sx, sy, sx, sy, tocolor(87, 242, 135, 255), 1.2, "default-bold", "center", "center")
        end
    end

    if getDistanceBetweenPoints3D(px, py, pz, endPoint.x, endPoint.y, endPoint.z) < maxDist then
        dxDrawLine3D(endPoint.x, endPoint.y, endPoint.z, endPoint.x, endPoint.y, endPoint.z + 2, tocolor(237, 66, 69, 255), 3.0)
        local sx, sy = getScreenFromWorldPosition(endPoint.x, endPoint.y, endPoint.z + 2.2)
        if sx and sy then
            dxDrawText("ARRIVEE", sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 255), 1.2, "default-bold", "center", "center")
            dxDrawText("ARRIVEE", sx, sy, sx, sy, tocolor(237, 66, 69, 255), 1.2, "default-bold", "center", "center")
        end
    end

    local sw, sh = guiGetScreenSize()
    -- vague 53 (demande 18) : même habillage que le menu d'animations
    THEME.rect(sw / 2 - 200, 10, 400, 60, THEME.R.carte, THEME.c("fond"))
    THEME.rect(sw / 2 - 200 + 10, 10, 380, 3, 1.5, THEME.c("accent"))
    dxDrawText("VISUALISATION CHEMIN #" .. tostring(showingPathId or "?"), sw / 2 - 200, 15, sw / 2 + 200, 35, tocolor(255, 255, 255, 255), 1, THEME.police("semibold", 13), "center", "center")
    dxDrawText(#showingPath .. " points | /pathhide pour masquer", sw / 2 - 200, 35, sw / 2 + 200, 55, THEME.c("texte2"), 1, THEME.police("regular", 13), "center", "center")

    if AMConfig and AMConfig.visualizer and AMConfig.visualizer.showLegend then
        dxDrawText("Bleu: Stand | Vert: Walk | Orange: Run | Rouge: Sprint", sw / 2 - 200, 50, sw / 2 + 200, 68, THEME.c("texteDim"), 1, THEME.police("regular", 11), "center", "center")
    end
end

addEvent("AdminMagasin:showPath", true)
addEventHandler("AdminMagasin:showPath", localPlayer, function(pathData, pathId)
    if not pathData or type(pathData) ~= "table" or #pathData < 2 then
        outputChatBox("[AdminMagasin] Erreur : Donnees de chemin invalides.", 237, 66, 69)
        return
    end

    showingPath = pathData
    showingPathId = pathId

    if not isHandlerAttached("onClientRender", root, renderPathVisualization) then
        addEventHandler("onClientRender", root, renderPathVisualization)
    end
end)

addEvent("AdminMagasin:hidePath", true)
addEventHandler("AdminMagasin:hidePath", localPlayer, function()
    showingPath = nil
    showingPathId = nil

    if isHandlerAttached("onClientRender", root, renderPathVisualization) then
        removeEventHandler("onClientRender", root, renderPathVisualization)
    end
end)

local function setBotControl(bot, control, state)
    if not bot.controls then bot.controls = {} end
    if bot.controls[control] ~= state then
        bot.controls[control] = state
        if isElement(bot.ped) then
            setPedControlState(bot.ped, control, state)
        end
    end
end

local function stopBotMovement(bot)
    setBotControl(bot, "forwards", false)
    setBotControl(bot, "walk", false)
    setBotControl(bot, "sprint", false)
end

local function applyMoveState(bot, moveState)
    if moveState == "stand" then
        stopBotMovement(bot)
    elseif moveState == "walk" then
        setBotControl(bot, "forwards", true)
        setBotControl(bot, "walk", true)
        setBotControl(bot, "sprint", false)
    elseif moveState == "run" then
        setBotControl(bot, "forwards", true)
        setBotControl(bot, "walk", false)
        setBotControl(bot, "sprint", false)
    elseif moveState == "sprint" then
        setBotControl(bot, "forwards", true)
        setBotControl(bot, "walk", false)
        setBotControl(bot, "sprint", true)
    else
        setBotControl(bot, "forwards", true)
        setBotControl(bot, "walk", true)
        setBotControl(bot, "sprint", false)
    end
end

local function renderTestNPCs()
    for i = #testNPCs, 1, -1 do
        local bot = testNPCs[i]

        if not isElement(bot.ped) then
            table.remove(testNPCs, i)
        else
            local targetNode = bot.path[bot.pathIndex]

            if not targetNode then
                stopBotMovement(bot)
                local bx, by, bz = getElementPosition(bot.ped)
                local sx, sy = getScreenFromWorldPosition(bx, by, bz + 1.5)
                if sx and sy then
                    dxDrawText("TERMINE", sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 255), 1.3, "default-bold", "center", "center")
                    dxDrawText("TERMINE", sx, sy, sx, sy, tocolor(87, 242, 135, 255), 1.3, "default-bold", "center", "center")
                end
            else
                local bx, by, bz = getElementPosition(bot.ped)
                local dist = getDistanceBetweenPoints3D(bx, by, bz, targetNode.x, targetNode.y, targetNode.z)

                while targetNode and dist <= PATH_POINT_THRESHOLD do
                    bot.pathIndex = bot.pathIndex + 1
                    targetNode = bot.path[bot.pathIndex]
                    if targetNode then
                        dist = getDistanceBetweenPoints3D(bx, by, bz, targetNode.x, targetNode.y, targetNode.z)
                    end
                end

                if targetNode then
                    local dx = targetNode.x - bx
                    local dy = targetNode.y - by
                    local pedRot = math.deg(math.atan2(dy, dx)) - 90
                    if pedRot < 0 then pedRot = pedRot + 360 end

                    local _, _, currentRot = getElementRotation(bot.ped)
                    local diff = pedRot - currentRot
                    if diff > 180 then diff = diff - 360 elseif diff < -180 then diff = diff + 360 end
                    setElementRotation(bot.ped, 0, 0, currentRot + diff * 0.15, "default", true)

                    local moveState = targetNode.moveState or "walk"
                    if moveState == "stand" and dist > PATH_POINT_THRESHOLD then moveState = "walk" end
                    applyMoveState(bot, moveState)

                    local progress = math.floor((bot.pathIndex / #bot.path) * 100)
                    local sx, sy = getScreenFromWorldPosition(bx, by, bz + 1.5)
                    if sx and sy then
                        dxDrawText("TEST NPC | " .. progress .. "%", sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 255), 1.0, "default-bold", "center", "center")
                        dxDrawText("TEST NPC | " .. progress .. "%", sx, sy, sx, sy, tocolor(255, 215, 0, 255), 1.0, "default-bold", "center", "center")
                        dxDrawText("Point " .. bot.pathIndex .. "/" .. #bot.path, sx, sy + 18, sx, sy + 18, tocolor(200, 200, 200, 255), 0.8, "default", "center", "center")
                    end
                end
            end
        end
    end

    if #testNPCs == 0 and isHandlerAttached("onClientRender", root, renderTestNPCs) then
        removeEventHandler("onClientRender", root, renderTestNPCs)
    end
end

addEvent("AdminMagasin:testPath", true)
addEventHandler("AdminMagasin:testPath", localPlayer, function(ped, pathData)
    if not isElement(ped) or not pathData or type(pathData) ~= "table" or #pathData < 2 then
        outputChatBox("[AdminMagasin] Erreur : Impossible de tester ce chemin.", 237, 66, 69)
        return
    end

    table.insert(testNPCs, {
        ped = ped,
        path = pathData,
        pathIndex = 1,
        controls = {},
    })

    if not isHandlerAttached("onClientRender", root, renderTestNPCs) then
        addEventHandler("onClientRender", root, renderTestNPCs)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, bot in ipairs(testNPCs) do
        if isElement(bot.ped) then stopBotMovement(bot) end
    end
    testNPCs = {}
    showingPath = nil
    showingPathId = nil

    if isHandlerAttached("onClientRender", root, renderPathVisualization) then
        removeEventHandler("onClientRender", root, renderPathVisualization)
    end
    if isHandlerAttached("onClientRender", root, renderTestNPCs) then
        removeEventHandler("onClientRender", root, renderTestNPCs)
    end
end)
