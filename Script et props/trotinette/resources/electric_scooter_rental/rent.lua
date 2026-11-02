-- Brabissimo-Community © 2026: integration da interface de rental e da infobox.
-- Proteção de inicialização: evita que a interface quebre se config.lua estiver ausente
-- ou a versão antiga do meta.xml ainda estiver instalada. A configuration oficial tem prioridade.
local configWasMissing = type(ScooterConfig) ~= "table"
if configWasMissing then ScooterConfig = {} end
local function ensureScooterTable(key)
    if type(ScooterConfig[key]) ~= "table" then ScooterConfig[key] = {} end
    return ScooterConfig[key]
end
local defaults = {
    models = { vehicle = 448, carried = 1867, station = 1874 },
    economy = { price = 100, freeHoursLimit = 10, chargeIntervalMs = 60000 },
    interaction = { stationRadius = 2.0, stationServerDistance = 4.0, foldDistance = 3.5, actionCooldownMs = 650 },
    restrictions = { blockWeaponsWhileCarrying = true, notifyWeaponAttempt = true },
    visual = {
            accent = { 65, 174, 255, 255 }, accentDark = { 25, 105, 170, 255 },
            panel = { 13, 18, 27, 242 }, panelSoft = { 24, 32, 44, 235 },
            text = { 245, 248, 252, 255 }, subText = { 177, 190, 205, 255 },
            line = { 255, 255, 255, 28 }, success = { 92, 218, 157, 255 },
            warning = { 255, 194, 86, 255 }, error = { 255, 102, 112, 255 },
        },
    stations = {
            { x = 1896.146484375, y = -1761.3681640625, z = 13.546837806702, rot = 0, name = "Downtown Station" },
            { x = 1170.142578125, y = -1415.3046875, z = 13.503165245056, rot = 0, name = "Hospital Station" },
            { x = 1324.8115234375, y = -1367.90625, z = 13.590615272522, rot = 0, name = "Pershing Station" },
            { x = 618.837890625, y = -1369.451171875, z = 13.640909194946, rot = 0, name = "Rodeo Station" },
            { x = 1523.740234375, y = -1684.064453125, z = 13.546875, rot = 0, name = "City Hall Station" },
        },
}
for key, value in pairs(defaults) do
    if key == "stations" then
        if type(ScooterConfig.stations) ~= "table" or #ScooterConfig.stations == 0 then
            ScooterConfig.stations = value
        end
    else
        local target = ensureScooterTable(key)
        for subKey, subValue in pairs(value) do
            if target[subKey] == nil then target[subKey] = subValue end
        end
    end
end
if configWasMissing then
    outputDebugString("[Scooter] WARNING: ScooterConfig não estava available. Fallback configuration applied; check meta.xml and reinstall the complete resource folder.", 2)
end

-- Electric Scooter RP — interface, sinalização e controles do cliente

local screenW, screenH = guiGetScreenSize()
local uiScale = math.max(0.72, math.min(1.0, math.min(screenW / 1366, screenH / 768)))

local ui = {
    visible = false,
    activeCol = false,
    actionLockUntil = 0,
}
local suppressReopenUntilLeave = false

local serverClock = {
    start = 0,
    startClient = getTickCount(),
}
setmetatable(serverClock, {
    __index = function(self, key)
        if key == "current" then
            return (self.start or 0) + (getTickCount() - (self.startClient or getTickCount()))
        end
    end,
})

local rtW, rtH = 320, 92
local scooterRT = dxCreateRenderTarget(rtW, rtH, true)
local stationRTW, stationRTH = 320, 92
local stationRT = dxCreateRenderTarget(stationRTW, stationRTH, true)

local lastScooter = false
local lastScooterRTUpdate = 0
local lastStationRTUpdate = 0

local function rgba(name, overrideAlpha)
    local value = ScooterConfig.visual[name]
    if not value then
        return tocolor(255, 255, 255, overrideAlpha or 255)
    end
    return tocolor(value[1], value[2], value[3], overrideAlpha or value[4] or 255)
end

local colors = {
    panel = rgba("panel"),
    panelSoft = rgba("panelSoft"),
    accent = rgba("accent"),
    accentDark = rgba("accentDark"),
    text = rgba("text"),
    subText = rgba("subText"),
    line = rgba("line"),
    success = rgba("success"),
    warning = rgba("warning"),
    error = rgba("error"),
    white = tocolor(255, 255, 255, 255),
    shadow = tocolor(0, 0, 0, 180),
}

local renderRentalPanel
local clickRentalPanel

local function debugScooter(message, level)
    outputDebugString("[Scooter] " .. tostring(message), level or 3)
end

local function showScooterNotification(notificationType, message, duration)
    local content = "Scooter • " .. tostring(message)
    local aliases = { "bc_infobox", "bpc_infobox" }
    for _, resourceName in ipairs(aliases) do
        local ok, result = pcall(function()
            if resourceName == "bc_infobox" then
                return exports.bc_infobox:addNotification(content, notificationType or "info", duration or 5000)
            end
            return exports.bpc_infobox:addNotification(content, notificationType or "info", duration or 5000)
        end)
        if ok and result ~= false then
            return true
        end
    end

    local legacyOK, legacyResult = pcall(function()
        return exports.FR_DxMessages:addBox(content, notificationType or "info", duration or 5000)
    end)
    if legacyOK and legacyResult ~= false then
        return true
    end

    local color = "#41AEFF"
    if notificationType == "error" then
        color = "#FF6670"
    elseif notificationType == "warning" then
        color = "#FFC256"
    elseif notificationType == "success" then
        color = "#5CDA9D"
    end
    outputChatBox(color .. "[Scooter]#FFFFFF " .. tostring(message), 255, 255, 255, true)
    return false
end

local function isMouseInPosition(x, y, width, height)
    if not isCursorShowing() then
        return false
    end
    local mouseX, mouseY = getCursorPosition()
    if not mouseX or not mouseY then
        return false
    end
    mouseX, mouseY = mouseX * screenW, mouseY * screenH
    return mouseX >= x and mouseX <= x + width and mouseY >= y and mouseY <= y + height
end

local function drawBorderedRectangle(x, y, width, height, fillColor, borderColor, borderSize)
    borderSize = borderSize or 1
    dxDrawRectangle(x, y, width, height, fillColor)
    dxDrawRectangle(x, y, width, borderSize, borderColor)
    dxDrawRectangle(x, y + height - borderSize, width, borderSize, borderColor)
    dxDrawRectangle(x, y, borderSize, height, borderColor)
    dxDrawRectangle(x + width - borderSize, y, borderSize, height, borderColor)
end

local function formatRentalTime(milliseconds)
    local totalSeconds = math.max(0, math.floor((tonumber(milliseconds) or 0) / 1000))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60

    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%02d:%02d", minutes, seconds)
end

local function getPositionFromElementOffset(element, offX, offY, offZ)
    if not isElement(element) then
        return false
    end
    local matrix = getElementMatrix(element)
    if not matrix then
        return false
    end

    local x = offX * matrix[1][1] + offY * matrix[2][1] + offZ * matrix[3][1] + matrix[4][1]
    local y = offX * matrix[1][2] + offY * matrix[2][2] + offZ * matrix[3][2] + matrix[4][2]
    local z = offX * matrix[1][3] + offY * matrix[2][3] + offZ * matrix[3][3] + matrix[4][3]
    return x, y, z
end

local function getPlayerHours()
    return tonumber(getElementData(localPlayer, "hoursplayed"))
        or tonumber(getElementData(localPlayer, "player:hours"))
        or 0
end

local function getActiveRental()
    local rented = getElementData(localPlayer, "scooter:rented")
    if isElement(rented) then
        return rented, getElementType(rented)
    end
    return false, false
end

local function playerHasActiveJob()
    local job = getElementData(localPlayer, "player:job")
    return job ~= nil and job ~= false and job ~= 0 and job ~= "" and job ~= "none"
end

local function getPanelBounds()
    -- Layout responsivo: painel maior em telas grandes, com limites em resoluções baixas.
    local scale = math.max(0.68, math.min(1.0, math.min(screenW / 1440, screenH / 850)))
    local width = math.min(screenW - 28, 540 * scale)
    local height = math.min(screenH - 28, 356 * scale)
    return (screenW - width) / 2, (screenH - height) / 2, width, height
end

local function setRentalUI(state, col, dismissedByPlayer)
    local wasVisible = ui.visible
    ui.visible = state
    ui.activeCol = state and col or false
    if state then
        suppressReopenUntilLeave = false
    elseif dismissedByPlayer then
        suppressReopenUntilLeave = true
    end
    showCursor(state)

    if state and not wasVisible then
        addEventHandler("onClientRender", root, renderRentalPanel)
        addEventHandler("onClientClick", root, clickRentalPanel)
    elseif not state and wasVisible then
        removeEventHandler("onClientRender", root, renderRentalPanel)
        removeEventHandler("onClientClick", root, clickRentalPanel)
    end
end

renderRentalPanel = function()
    if not ui.visible or not isElement(ui.activeCol) then
        setRentalUI(false)
        return
    end

    local x, y, width, height = getPanelBounds()
    local s = math.max(0.68, math.min(1.0, width / 540))
    local rented, rentedType = getActiveRental()
    local free = getPlayerHours() < ScooterConfig.economy.freeHoursLimit
    local actionX, actionY = x + 28 * s, y + height - 76 * s
    local actionW, actionH = width - 56 * s, 46 * s
    local hovered = isMouseInPosition(actionX, actionY, actionW, actionH)
    local closeHovered = isMouseInPosition(x + width - 39 * s, y + 14 * s, 24 * s, 24 * s)

    -- Sombra, moldura e cabeçalho com identidade visual RIO.
    dxDrawRectangle(x + 5 * s, y + 7 * s, width, height, colors.shadow)
    drawBorderedRectangle(x, y, width, height, colors.panel, colors.line, math.max(1, s))
    dxDrawRectangle(x, y, width, 5 * s, colors.accent)
    dxDrawRectangle(x + 24 * s, y + 22 * s, 42 * s, 42 * s, colors.panelSoft)
    dxDrawRectangle(x + 24 * s, y + 22 * s, 3 * s, 42 * s, colors.accent)
    dxDrawText("R", x + 27 * s, y + 22 * s, x + 63 * s, y + 64 * s,
        colors.accent, 1.35 * s, "default-bold", "center", "center")

    dxDrawText("RIO MOBILITY", x + 78 * s, y + 20 * s, x + width - 55 * s, y + 42 * s,
        colors.text, 1.12 * s, "default-bold", "left", "center")
    dxDrawText("ELECTRIC SCOOTER  /  RENTAL STATION", x + 78 * s, y + 43 * s,
        x + width - 55 * s, y + 64 * s, colors.subText, 0.78 * s, "default", "left", "center")
    dxDrawText("×", x + width - 40 * s, y + 12 * s, x + width - 12 * s, y + 39 * s,
        closeHovered and colors.error or colors.subText, 1.5 * s, "default-bold", "center", "center")
    dxDrawRectangle(x + 24 * s, y + 78 * s, width - 48 * s, 1 * s, colors.line)

    local priceText = free
        and ("ACTIVE BENEFIT  •  FREE FOR UP TO " .. ScooterConfig.economy.freeHoursLimit .. "H DE JOGO")
        or ("TARIFA  •  $" .. tostring(ScooterConfig.economy.price) .. " POR MINUTO")
    local priceColor = free and colors.success or colors.accent
    dxDrawRectangle(x + 24 * s, y + 94 * s, width - 48 * s, 39 * s, colors.panelSoft)
    dxDrawRectangle(x + 24 * s, y + 94 * s, 4 * s, 39 * s, priceColor)
    dxDrawText(priceText, x + 38 * s, y + 94 * s, x + width - 36 * s, y + 133 * s,
        priceColor, 0.82 * s, "default-bold", "left", "center", true)

    local statusTitle, detailText, buttonText, statusColor
    if rentedType == "object" then
        statusTitle = "SCOOTER STORED"
        detailText = "Your scooter is folded. Unfold it to keep riding, or return it at this station to end the rental."
        buttonText = "RETURN SCOOTER"
        statusColor = colors.warning
    elseif rentedType == "vehicle" then
        statusTitle = "SCOOTER IN USE"
        detailText = "Park and get off the scooter. Press H nearby to fold it, then return to this station to end the rental."
        buttonText = "VER INSTRUÇÕES DE DEVOLUÇÃO"
        statusColor = colors.accent
    else
        statusTitle = "READY FOR YOUR RIDE?"
        detailText = "Rent a scooter at this station. Press H to fold it, then return it to any rental station."
        buttonText = "RENT SCOOTER"
        statusColor = colors.success
    end

    dxDrawRectangle(x + 24 * s, y + 148 * s, 7 * s, 7 * s, statusColor)
    dxDrawText(statusTitle, x + 39 * s, y + 140 * s, x + width - 25 * s, y + 163 * s,
        statusColor, 0.88 * s, "default-bold", "left", "center")
    dxDrawText(detailText, x + 25 * s, y + 169 * s, x + width - 25 * s, y + 221 * s,
        colors.subText, 0.88 * s, "default", "left", "top", true, true)

    -- Mini guia de comandos para deixar a ação principal autoexplicativa.
    local guideY = y + 230 * s
    dxDrawRectangle(x + 24 * s, guideY, width - 48 * s, 28 * s, tocolor(255, 255, 255, 7))
    dxDrawText("H", x + 34 * s, guideY, x + 56 * s, guideY + 28 * s,
        colors.accent, 0.85 * s, "default-bold", "center", "center")
    dxDrawText("GUARDAR / ABRIR", x + 59 * s, guideY, x + 175 * s, guideY + 28 * s,
        colors.subText, 0.76 * s, "default", "left", "center")
    dxDrawText("ESC", x + width - 113 * s, guideY, x + width - 82 * s, guideY + 28 * s,
        colors.accent, 0.78 * s, "default-bold", "center", "center")
    dxDrawText("FECHAR", x + width - 78 * s, guideY, x + width - 30 * s, guideY + 28 * s,
        colors.subText, 0.76 * s, "default", "left", "center")

    local actionPending = getTickCount() < (ui.actionLockUntil or 0)
    if actionPending then buttonText = "AGUARDE..." end
    local actionFill = hovered and not actionPending and colors.accentDark or colors.panelSoft
    drawBorderedRectangle(actionX, actionY, actionW, actionH, actionFill,
        hovered and not actionPending and colors.accent or colors.line, math.max(1, s))
    dxDrawText(buttonText, actionX + 8 * s, actionY, actionX + actionW - 8 * s, actionY + actionH,
        colors.text, 0.88 * s, "default-bold", "center", "center", true)
end

clickRentalPanel = function(button, state)
    if not ui.visible or button ~= "left" or state ~= "down" then
        return
    end

    local x, y, width, height = getPanelBounds()
    if not isMouseInPosition(x, y, width, height) then
        setRentalUI(false, nil, true)
        return
    end

    local scale = math.max(0.68, math.min(1.0, width / 540))
    if isMouseInPosition(x + width - 39 * scale, y + 14 * scale, 24 * scale, 24 * scale) then
        setRentalUI(false, nil, true)
        return
    end

    local actionX, actionY = x + 28 * scale, y + height - 76 * scale
    local actionW, actionH = width - 56 * scale, 46 * scale
    if not isMouseInPosition(actionX, actionY, actionW, actionH) then
        return
    end

    local rented, rentedType = getActiveRental()
    if rentedType == "vehicle" then
        showScooterNotification("warning", "Get off, move closer to the scooter, and press H to fold it before returning it.")
        return
    end

    if not rented and playerHasActiveJob() then
        showScooterNotification("warning", "Finish your current job before renting a scooter.")
        return
    end

    if getTickCount() < (ui.actionLockUntil or 0) then
        return
    end

    -- Mantém o painel aberto até o server concluir a ação. Em caso de erro,
    -- o jogador pode ler a mensagem e tentar novamente sem sair da station.
    -- A trava também impede duplo clique de rent e return em sequência.
    ui.actionLockUntil = getTickCount() + 1200
    triggerServerEvent("scooter:rent", resourceRoot)
end

local function closeRentalUI()
    if ui.visible then
        setRentalUI(false, nil, true)
    end
end

bindKey("backspace", "down", closeRentalUI)
bindKey("escape", "down", function()
    if ui.visible then
        cancelEvent()
        setRentalUI(false, nil, true)
    end
end)

-- A interface é modal: teclas de movimento não fecham a janela nem fazem
-- o personagem sair acidentalmente da station enquanto o jogador interage.
local movementKeysWhilePanelOpen = {
    w = true, a = true, s = true, d = true, space = true,
    arrow_l = true, arrow_r = true, arrow_u = true, arrow_d = true,
}
addEventHandler("onClientKey", root, function(button, press)
    if ui.visible and press and movementKeysWhilePanelOpen[string.lower(button)] then
        cancelEvent()
    end
end)

addEventHandler("onClientColShapeHit", resourceRoot, function(element, matchingDimension)
    if element ~= localPlayer or not matchingDimension then
        return
    end
    if not getElementData(source, "scooter:rental") then
        return
    end
    if getPedOccupiedVehicle(localPlayer) then
        return
    end
    setRentalUI(true, source)
end)

addEventHandler("onClientColShapeLeave", resourceRoot, function(element)
    if element ~= localPlayer or not getElementData(source, "scooter:rental") then
        return
    end
    if ui.activeCol == source then
        setRentalUI(false)
    end
end)

-- Também verifica proximidade periodicamente. Isso abre o painel se o jogador sair
-- de um veículo já dentro da área, situação em que um evento de entrada pode não ocorrer.
setTimer(function()
    if ui.visible or getPedOccupiedVehicle(localPlayer) then
        return
    end

    local px, py, pz = getElementPosition(localPlayer)
    local interior = getElementInterior(localPlayer)
    local dimension = getElementDimension(localPlayer)
    local radius = ScooterConfig.interaction.stationRadius + 0.25
    local insideAnyStation = false

    for _, col in ipairs(getElementsByType("colshape", resourceRoot)) do
        if getElementData(col, "scooter:rental")
            and getElementInterior(col) == interior
            and getElementDimension(col) == dimension then
            local x, y, z = getElementPosition(col)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= radius then
                insideAnyStation = true
                if not suppressReopenUntilLeave then
                    setRentalUI(true, col)
                end
                break
            end
        end
    end

    if not insideAnyStation then
        suppressReopenUntilLeave = false
    end
end, 450, 0)

-- H alterna entre scooter na mão e scooter no chão.
-- No veículo: dobra para a mão. Na mão: abre/coloca no chão.
bindKey("h", "down", function()
    local rented, rentedType = getActiveRental()
    if not rented or not isPedOnGround(localPlayer) then return end
    if getPedOccupiedVehicle(localPlayer) then return end

    if rentedType == "object" then
        triggerServerEvent("scooter:deploy", resourceRoot)
        return
    end

    if rentedType == "vehicle" then
        local px, py, pz = getElementPosition(localPlayer)
        local vx, vy, vz = getElementPosition(rented)
        if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= ScooterConfig.interaction.foldDistance then
            triggerServerEvent("scooter:fold", resourceRoot)
        end
    end
end)

-- I guarda no inventário apenas quando o scooter está na mão.
bindKey("i", "down", function()
    local rented, rentedType = getActiveRental()
    if not rented or rentedType ~= "object" or not isPedOnGround(localPlayer) then return end
    if getPedOccupiedVehicle(localPlayer) then return end
    triggerServerEvent("scooter:store", resourceRoot)
end)

addEventHandler("onClientVehicleStartEnter", root, function(player)
    if player ~= localPlayer then
        return
    end
    local rented, rentedType = getActiveRental()
    if rented and rentedType == "object" then
        cancelEvent()
    end
end)

local function updateScooterRenderTarget(scooter)
    if not scooterRT or not isElement(scooter) then
        return false
    end

    lastScooterRTUpdate = getTickCount() + 1000
    lastScooter = scooter

    local owner = getElementData(scooter, "scooter:owner")
    local ownerName = isElement(owner) and getPlayerName(owner):gsub("_", " "):gsub("#%x%x%x%x%x%x", "") or "Desconhecido"
    local rentTime = tonumber(getElementData(scooter, "scooter:rented:time")) or serverClock.current
    local elapsed = math.max(0, serverClock.current - rentTime)

    if not dxSetRenderTarget(scooterRT, true) then
        return false
    end
    dxDrawRectangle(0, 0, rtW, rtH, tocolor(10, 16, 24, 238))
    dxDrawRectangle(0, 0, rtW, 4, colors.accent)
    dxDrawRectangle(0, rtH - 1, rtW, 1, colors.line)
    dxDrawText("ELECTRIC SCOOTER", 0, 10, rtW, 30, colors.text, 1, "default-bold", "center", "center")
    dxDrawText("RENTAL TIME  " .. formatRentalTime(elapsed), 0, 34, rtW, 52,
        colors.accent, 0.9, "default-bold", "center", "center")
    dxDrawText("ALUGADO POR  " .. ownerName, 5, 58, rtW - 5, 78,
        colors.subText, 0.84, "default", "center", "center", true)
    dxSetRenderTarget()
    return true
end

local function updateStationRenderTarget()
    if not stationRT then
        return false
    end

    lastStationRTUpdate = getTickCount() + 1500
    local playerHours = getPlayerHours()
    local priceText = playerHours < ScooterConfig.economy.freeHoursLimit
        and ("FREE • UNDER " .. ScooterConfig.economy.freeHoursLimit .. "H")
        or ("$" .. ScooterConfig.economy.price .. " INICIAL + $" .. ScooterConfig.economy.price .. "/MIN")

    if not dxSetRenderTarget(stationRT, true) then
        return false
    end
    dxDrawRectangle(0, 0, stationRTW, stationRTH, tocolor(10, 16, 24, 238))
    dxDrawRectangle(0, 0, stationRTW, 4, colors.accent)
    dxDrawRectangle(0, stationRTH - 1, stationRTW, 1, colors.line)
    dxDrawText("SCOOTER STATION", 0, 10, stationRTW, 30,
        colors.text, 0.92, "default-bold", "center", "center")
    dxDrawText(priceText, 0, 34, stationRTW, 52,
        playerHours < ScooterConfig.economy.freeHoursLimit and colors.success or colors.accent,
        0.88, "default-bold", "center", "center")
    dxDrawText("Enter the area to rent or return", 0, 58, stationRTW, 78,
        colors.subText, 0.79, "default", "center", "center")
    dxSetRenderTarget()
    return true
end

addEventHandler("onClientRender", root, function()
    local rented = getElementData(localPlayer, "scooter:rented")
    if isElement(rented) then
        local cameraX, cameraY, cameraZ = getCameraMatrix()
        local x, y, z = getElementPosition(rented)
        local distance = getDistanceBetweenPoints3D(cameraX, cameraY, cameraZ, x, y, z)
        if distance > 20 then
            local screenX, screenY = getScreenFromWorldPosition(x, y, z + 0.6)
            if screenX and screenY then
                dxDrawText("MY SCOOTER", screenX - 75, screenY - 12, screenX + 75, screenY + 12,
                    colors.accent, 0.9, "default-bold", "center", "center", false, false, false, true)
            end
        end
    end
end)

addEventHandler("onClientPreRender", root, function()
    local cameraX, cameraY, cameraZ = getCameraMatrix()
    local nearestScooter = false
    local nearestDistance = 20
    local interior = getElementInterior(localPlayer)
    local dimension = getElementDimension(localPlayer)
    local nearbyVehicles = getElementsWithinRange(cameraX, cameraY, cameraZ, 20, "vehicle", interior, dimension) or {}

    for _, vehicle in ipairs(nearbyVehicles) do
        if getElementData(vehicle, "scooter:owner") then
            local x, y, z = getElementPosition(vehicle)
            local distance = getDistanceBetweenPoints3D(cameraX, cameraY, cameraZ, x, y, z)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestScooter = vehicle
            end
        end
    end

    if nearestScooter and isElement(nearestScooter) and scooterRT then
        if lastScooter ~= nearestScooter or lastScooterRTUpdate < getTickCount() then
            updateScooterRenderTarget(nearestScooter)
        end
        local alpha = math.max(0, math.min(255, (1 - nearestDistance / 20) * 255))
        local x, y, z = getPositionFromElementOffset(nearestScooter, 0, -0.5, -0.3)
        if x and y and z then
            dxDrawMaterialLine3D(
                x, y, z + 1.2 / (rtW / rtH),
                x, y, z,
                scooterRT,
                1.2,
                tocolor(255, 255, 255, alpha),
                cameraX, cameraY, cameraZ
            )
        end
    end

    if stationRT and lastStationRTUpdate < getTickCount() then
        updateStationRenderTarget()
    end

    local stations = getElementsByType("colshape", resourceRoot)
    for _, col in ipairs(stations) do
        if getElementData(col, "scooter:rental")
            and getElementInterior(col) == interior
            and getElementDimension(col) == dimension then
            local x, y, z = getElementPosition(col)
            local distance = getDistanceBetweenPoints3D(cameraX, cameraY, cameraZ, x, y, z)
            if distance <= 35 then
                local alpha = math.max(0, math.min(255, 255 - distance * 6))
                if stationRT then
                    dxDrawMaterialLine3D(
                        x, y, z + 1.42,
                        x, y, z + 0.92,
                        stationRT,
                        1.05,
                        tocolor(255, 255, 255, alpha),
                        cameraX, cameraY, cameraZ
                    )
                else
                    local screenX, screenY = getScreenFromWorldPosition(x, y, z + 1.5)
                    if screenX and screenY then
                        dxDrawText("SCOOTER RENTAL\nEnter the area to interact", screenX - 110, screenY - 24,
                            screenX + 110, screenY + 24, tocolor(65, 174, 255, alpha), 0.85, "default-bold",
                            "center", "center", false, true)
                    end
                end
            end
        end
    end
end)

addEventHandler("onClientVehicleExit", root, function(player)
    if player ~= localPlayer then
        return
    end
    if getElementData(source, "scooter:owner") ~= localPlayer then
        return
    end
    showScooterNotification("info", "To stop rental charges, fold the scooter and return it to a station.")
end)

addEvent("scooter:fetchTickCount", true)
addEventHandler("scooter:fetchTickCount", resourceRoot, function(tick)
    serverClock.start = tonumber(tick) or 0
    serverClock.startClient = getTickCount()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    if not scooterRT then
        debugScooter("Not enough graphics memory for the scooter sign; controls will keep working.", 2)
    end
    if not stationRT then
        debugScooter("Not enough graphics memory for the station sign; using an alternate indicator.", 2)
    end
    updateStationRenderTarget()
    triggerServerEvent("scooter:fetchTickCount", resourceRoot)
end)

addEventHandler("onClientRestore", root, function()
    updateStationRenderTarget()
    if isElement(lastScooter) then
        updateScooterRenderTarget(lastScooter)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if ui.visible then
        showCursor(false)
    end
    if isElement(scooterRT) then
        destroyElement(scooterRT)
    end
    if isElement(stationRT) then
        destroyElement(stationRT)
    end
end)
