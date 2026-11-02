-- Las RPM se estiman: GTA/MTA no expone las revoluciones reales del motor.
local CFG = {
    command = 'nfsmw', -- Comando para activar/desactivar el velocimetro.
    size = 340, -- Ancho a 1920x1080; se adapta a la resolucion.
    marginRight = 24,
    marginBottom = 24,
    maxRPM = 10000
}

local textures = {}
local enabled = true -- Cada jugador empieza con el velocimetro activado.
local ready = false
local renderAttached = false
local updateRenderState
local currentVehicle, rpm, nitro = nil, 0, 0
local boost = 0
local lastTick = getTickCount()
local white = tocolor(245, 244, 232)
local amber = tocolor(244, 187, 99)
local green = tocolor(186, 234, 75)
local dark = tocolor(20, 23, 19, 215)
local inactive = tocolor(57, 46, 23, 65)
local active = tocolor(37, 32, 19)

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function smooth(value, target, dt)
    return value + (target - value) * (1 - math.exp(-12 * dt))
end

local digits = {
    ['0'] = 'abcdef',
    ['1'] = 'bc',
    ['2'] = 'abdeg',
    ['3'] = 'abcdg',
    ['4'] = 'bcfg',
    ['5'] = 'acdfg',
    ['6'] = 'acdefg',
    ['7'] = 'abc',
    ['8'] = 'abcdefg',
    ['9'] = 'abcdfg'
}
local segments = {
    a = {4, 0, 22, 4},
    b = {26, 4, 4, 22},
    c = {26, 30, 4, 22},
    d = {4, 52, 22, 4},
    e = {0, 30, 4, 22},
    f = {0, 4, 4, 22},
    g = {4, 26, 22, 4}
}

local function render()
    local now = getTickCount()
    local dt = clamp((now - lastTick) / 1000, 0, 0.1)
    lastTick = now
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle or isPedDead(localPlayer) then
        updateRenderState()
        return
    end
    if isPlayerMapVisible() then
        currentVehicle, rpm, nitro = nil, 0, 0
        boost = 0
        return
    end

    local vx, vy, vz = getElementVelocity(vehicle)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    local gear = getVehicleCurrentGear(vehicle) or 0
    local level = getVehicleNitroLevel(vehicle)
    local hasNitro = type(level) == 'number'
    level = hasNitro and clamp(level, 0, 1) or 0

    local health = clamp((getElementHealth(vehicle) - 250) / 750, 0, 1)
    local targetRPM = 0

    if getVehicleEngineState(vehicle) and getElementHealth(vehicle) > 0 then
        targetRPM = clamp(speed / math.max(gear, 1) * 155, 850, CFG.maxRPM - 300)
    end

    if currentVehicle ~= vehicle then
        currentVehicle, rpm, nitro = vehicle, targetRPM, level
        boost = 0
    end

    rpm = smooth(rpm, targetRPM, dt)
    nitro = hasNitro and smooth(nitro, level, dt) or 0

    local reverse = false
    if speed > 1 then
        local matrix = getElementMatrix(vehicle)
        reverse = matrix and vx * matrix[2][1] + vy * matrix[2][2] + vz * matrix[2][3] < -0.005
    end

    local driver = getVehicleController(vehicle)
    local accelerating = driver and getPedControlState(driver, 'accelerate')
    local targetBoost = 0
    if getVehicleEngineState(vehicle) and getElementHealth(vehicle) > 0 then
        if reverse then
            targetBoost = -clamp(speed / 30, 0.25, 1)
        elseif accelerating then
            targetBoost = 1
        end
    end

    local boostRate = targetBoost == 0 and 3 or 1.2
    boost = boost + (targetBoost - boost) * (1 - math.exp(-boostRate * dt))
    local gearText = reverse and 'R' or (speed < 1 and 'N' or tostring(gear))
    local healthColor = health <= 0.3 and tocolor(240, 68, 53) or (health <= 0.6 and tocolor(249, 153, 57) or amber)

    local sw, sh = guiGetScreenSize()
    local screenScale = math.min(sw / 1920, sh / 1080)
    local scale = math.min(CFG.size / 620 * screenScale, (sw - 16) / 620, (sh - 16) / 620)
    local x = sw - CFG.marginRight * screenScale - 620 * scale
    local y = sh - CFG.marginBottom * screenScale - 620 * scale
    local cx, cy = 310, 310
    local outerRadius, outerWidth = 286, 18

    local function rect(px, py, w, h, color)
        dxDrawRectangle(x + px * scale, y + py * scale, w * scale, h * scale, color)
    end

    local function text(value, px, py, w, h, color, size, font)
        dxDrawText(value, x + px * scale, y + py * scale, x + (px + w) * scale, y + (py + h) * scale, color, size * scale, font or 'default-bold', 'center', 'center')
    end

    local function image(name, px, py, w, h, rotation, color)
        dxDrawImage(x + px * scale, y + py * scale, w * scale, h * scale, textures[name], rotation or 0, 0, 0, color or white)
    end

    local function arc(radius, startAngle, sweep, width, color, centerX, centerY)
        local count = math.max(1, math.ceil(math.abs(sweep) / 3))
        local prevX, prevY
        for i = 0, count do
            local angle = math.rad(startAngle + sweep * i / count)
            local px = x + ((centerX or cx) + math.sin(angle) * radius) * scale
            local py = y + ((centerY or cy) - math.cos(angle) * radius) * scale
            if prevX then
                dxDrawLine(prevX, prevY, px, py, color, width * scale)
            end
            prevX, prevY = px, py
        end
    end

    local function digital(value, px, py, count, factor)
        local str = tostring(value)
        str = string.rep(' ', math.max(0, count - #str)) .. str
        for i = 1, count do
            local lit = digits[str:sub(i, i)] or ''
            for name, bounds in pairs(segments) do
                rect(px + ((i - 1) * 36 + bounds[1]) * factor, py + bounds[2] * factor, bounds[3] * factor, bounds[4] * factor, lit:find(name, 1, true) and active or inactive)
            end
        end
    end

    dxDrawCircle(x + cx * scale, y + cy * scale, 238 * scale, 0, 360, dark, dark, 64)
    arc(239, 70, 44, 16, tocolor(186, 37, 53, 220))
    image('dial', cx - 256, cy - 264, 512, 512)

    local healthStart, healthSweep = -129, 180
    arc(outerRadius, healthStart, healthSweep, outerWidth, tocolor(77, 66, 43, 200))
    if health > 0 then
        arc(outerRadius, healthStart, healthSweep * health, outerWidth, healthColor)
    end

    arc(outerRadius, 61, 160, outerWidth, tocolor(57, 73, 30, 200))
    if nitro > 0.001 then
        arc(outerRadius, 221 - 160 * nitro, 160 * nitro, outerWidth, green)
    end
    image('turbo', cx - 256, cy + 145, 512, 128)
    image('turboNeedle', cx - 64, cy - 256, 128, 512, -43 * boost, amber)

    rect(cx - 44, cy - 115, 88, 48, amber)
    if tonumber(gearText) then
        digital(tonumber(gearText), cx - 9, cy - 109, 1, 0.64)
        text('^', cx - 41, cy - 112, 28, 44, active, 1.8)
    else
        text(gearText, cx - 44, cy - 115, 88, 48, active, 2)
    end

    rect(cx - 96, cy + 48, 192, 86, amber)
    digital(clamp(math.floor(speed + 0.5), 0, 999), cx - 64, cy + 56, 3, 1.25)
    text('KM/H', cx - 90, cy + 135, 180, 43, white, 2)
    image('needle', cx - 64, cy - 256, 128, 512, 66 + 228 * rpm / CFG.maxRPM, amber)
    local hub = tocolor(158, 160, 151)
    dxDrawCircle(x + cx * scale, y + cy * scale, 23 * scale, 0, 360, hub, hub, 24)
end

local function detachRender()
    if renderAttached then
        removeEventHandler('onClientRender', root, render)
        renderAttached = false
    end
    currentVehicle, rpm, nitro, boost = nil, 0, 0, 0
end

updateRenderState = function()
    local active = ready and enabled and not isPedDead(localPlayer) and isElement(getPedOccupiedVehicle(localPlayer))
    if not active then
        detachRender()
    elseif not renderAttached then
        lastTick = getTickCount()
        addEventHandler('onClientRender', root, render)
        renderAttached = true
    end
end

addCommandHandler(CFG.command, function()
    enabled = not enabled
    updateRenderState()
    outputChatBox('[NFSMW_Speedo] Velocimetro ' .. (enabled and 'activado.' or 'desactivado.'), 244, 187, 99)
end)
addEventHandler('onClientPlayerVehicleEnter', localPlayer, updateRenderState, false)
addEventHandler('onClientPlayerVehicleExit', localPlayer, detachRender, false)
addEventHandler('onClientPlayerWasted', localPlayer, detachRender, false)
addEventHandler('onClientPlayerSpawn', localPlayer, updateRenderState, false)

addEventHandler('onClientResourceStart', resourceRoot, function()
    ready = true
    local paths = {
        dial = '10000_LINES_00',
        needle = 'TACH_NEEDLE_00',
        turbo = 'TURBO_LINES_00',
        turboNeedle = 'TURBO_NEEDLE_00'
    }
    for name, path in pairs(paths) do
        textures[name] = dxCreateTexture('img/' .. path .. '.png', 'argb', true, 'clamp')
        if not isElement(textures[name]) then
            ready = false
            outputDebugString('[NFSMW_Speedo] No se pudo cargar img/' .. path .. '.png', 1)
        end
    end
    updateRenderState()
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    detachRender()
    for _, texture in pairs(textures) do
        if isElement(texture) then
            destroyElement(texture)
        end
    end
end)
