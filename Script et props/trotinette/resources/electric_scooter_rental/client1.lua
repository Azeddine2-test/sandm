-- Brabissimo-Community © 2026: manutenção e melhorias deste resource. Assets original preservados.
-- Evita que uma configuration ausente impeça o carregamento dos modelos custom.
local configWasMissing = type(ScooterConfig) ~= "table"
if configWasMissing then ScooterConfig = {} end
if type(ScooterConfig.models) ~= "table" then ScooterConfig.models = {} end
ScooterConfig.models.vehicle = tonumber(ScooterConfig.models.vehicle) or 448
ScooterConfig.models.carried = tonumber(ScooterConfig.models.carried) or 1867
ScooterConfig.models.station = tonumber(ScooterConfig.models.station) or 1874
if configWasMissing then
    outputDebugString("[Scooter] WARNING: client configuration is missing; default model IDs will be used. Check meta.xml.", 2)
end

-- Electric Scooter RP — modelos custom e animações

local getNativeElementModel = getElementModel
local playersWithAnimations = {}
local loadedAnimationGroups = {}
local originalFrontWheelSize = false
local originalRearWheelSize = false

local animations = {
    "_Back",
    "_drivebyFT",
    "_drivebyLHS",
    "_drivebyRHS",
    "_Fwd",
    "_getoffBACK",
    "_getoffLHS",
    "_getoffRHS",
    "_hit",
    "_jumponL",
    "_jumponR",
    "_kick",
    "_Left",
    "_passenger",
    "_pushes",
    "_Ride",
    "_Right",
    "_Still",
}

-- O bloco personalizado é exclusivo deste resource, evitando colisões com
-- outro resource que também possa carregar uma IFP chamada "scooter".
-- Mantém o nome do bloco abaixo de 24 caracteres (limite seguro para o
-- identificador de bloco do GTA), sem perder o namespace recomendado pelo MTA.
local animationResourceName = (getResourceName(getThisResource()) or "scooter")
    :gsub("[^%w_]", "_"):sub(1, 14)
local customAnimationBlock = animationResourceName .. ".scooter"

-- [modelo] = { arquivo IFP, bloco original, bloco personalizado }
local customAnimations = {
    [448] = { "files/bike.ifp", "BIKEV", customAnimationBlock },
}

local function debugScooter(message, level)
    outputDebugString("[Scooter] " .. tostring(message), level or 3)
end

local function getVehicleModel(element)
    if not isElement(element) then
        return false
    end

    -- Compatibilidade preserved com resources de veículos custom do server.
    local customModel = tonumber(getElementData(element, "vehicleID"))
    if customModel then
        return customModel
    end
    -- API current do MTA; getVehicleModel/getNativeElementModel são legacys.
    return getElementModel(element)
end

local function restoreAnimations(player)
    if not isElement(player) then
        playersWithAnimations[player] = nil
        return
    end

    for _, animationName in ipairs(animations) do
        engineRestoreAnimation(player, "BIKEV", "BIKEV" .. animationName)
    end
    playersWithAnimations[player] = nil
end

local function loadAnimations(player, model)
    local animationInfo = customAnimations[model]
    if not isElement(player) or not animationInfo or not loadedAnimationGroups[animationInfo[3]] then
        return false
    end
    if playersWithAnimations[player] == model then
        return true
    end

    -- Se o jogador veio de outro modelo compatível, limpa primeiro a substituição anterior.
    if playersWithAnimations[player] then
        restoreAnimations(player)
    end

    local allReplaced = true
    for _, animationName in ipairs(animations) do
        -- No arquivo bike.ifp, os nomes exportados usam "BIKEv_" (v minúsculo),
        -- enquanto o bloco interno original do GTA é "BIKEV".
        local customAnimationName = "BIKEv" .. animationName
        local replaced = engineReplaceAnimation(
            player,
            animationInfo[2],
            animationInfo[2] .. animationName,
            animationInfo[3],
            customAnimationName
        )
        if not replaced then
            allReplaced = false
        end
    end

    -- Registramos o jogador mesmo com failure parcial para que a restauração tente limpar tudo.
    playersWithAnimations[player] = model
    if not allReplaced then
        debugScooter("One or more custom animations could not be applied.", 2)
    end
    return allReplaced
end

local function loadModelAssets(modelId, txdPath, dffPath, colPath)
    local allLoaded = true

    -- A colisão é optional para veículos, mas required nos modelos de objeto customizados.
    if colPath then
        local col = engineLoadCOL(colPath)
        if col then
            if not engineReplaceCOL(col, modelId) then
                allLoaded = false
                debugScooter("Failed to apply collision to model " .. tostring(modelId) .. ": " .. colPath, 1)
            end
        else
            allLoaded = false
            debugScooter("Failed to load collision: " .. colPath, 1)
        end
    end

    local txd = engineLoadTXD(txdPath)
    if txd then
        if not engineImportTXD(txd, modelId) then
            allLoaded = false
            debugScooter("Failure ao aplicar as texturas ao modelo " .. tostring(modelId) .. ": " .. txdPath, 1)
        end
    else
        allLoaded = false
        debugScooter("Failure ao carregar textura: " .. txdPath, 1)
    end

    local dff = engineLoadDFF(dffPath, modelId)
    if dff then
        if not engineReplaceModel(dff, modelId, modelId == ScooterConfig.models.vehicle) then
            allLoaded = false
            debugScooter("Failure ao aplicar o modelo personalizado " .. tostring(modelId) .. ": " .. dffPath, 1)
        end
    else
        allLoaded = false
        debugScooter("Failure ao carregar modelo: " .. dffPath, 1)
    end

    return allLoaded
end

local function initializeCustomModels()
    -- As funções de escala das rodas só existem em builds mais recentes; keeps
    -- compatibility com versões antigas e restaura os valores ao parar o resource.
    local supportsWheelSize = type(getVehicleModelWheelSize) == "function"
        and type(setVehicleModelWheelSize) == "function"
    if supportsWheelSize then
        originalFrontWheelSize = getVehicleModelWheelSize(ScooterConfig.models.vehicle, "front_axle")
        originalRearWheelSize = getVehicleModelWheelSize(ScooterConfig.models.vehicle, "rear_axle")
    end

    if not loadModelAssets(ScooterConfig.models.vehicle, "files/448.txd", "files/448.dff") then
        debugScooter("O modelo do scooter (448) ficou parcialmente carregado; confira os erros de DFF/TXD acima.", 1)
    end
    if supportsWheelSize then
        setVehicleModelWheelSize(ScooterConfig.models.vehicle, "all_wheels", 0.29)
    else
        debugScooter("Esta versão do MTA não oferece leitura e restauração da escala das rodas; a escala global não será alterada.", 2)
    end

    if not loadModelAssets(ScooterConfig.models.station,
        "files/escooterrental.txd", "files/escooterrental.dff", "files/escooterrental.col") then
        debugScooter("O modelo da station (" .. tostring(ScooterConfig.models.station) .. ") não foi carregado por completo; a station pode aparecer com o modelo padrão do GTA.", 1)
    end
    if not loadModelAssets(ScooterConfig.models.carried,
        "files/foldedscooter.txd", "files/foldedscooter.dff", "files/foldedscooter.col") then
        debugScooter("O modelo do scooter guardado (" .. tostring(ScooterConfig.models.carried) .. ") não foi carregado por completo; a retirada pode ficar sem o visual correto.", 1)
    end

    for _, animationInfo in pairs(customAnimations) do
        if not fileExists(animationInfo[1]) then
            debugScooter("O arquivo de animação não foi encontrado no cliente: " .. animationInfo[1] .. ". As animações padrão will be preserveds.", 2)
        else
            local ifp = engineLoadIFP(animationInfo[1], animationInfo[3])
            if ifp then
                loadedAnimationGroups[animationInfo[3]] = ifp
            else
                -- Animações são cosméticas; a failure delas não deve bloquear o rental.
                debugScooter("O MTA não carregou " .. animationInfo[1] .. " no bloco " .. animationInfo[3] .. ". O scooter continuará funcional com animações padrão.", 2)
            end
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, initializeCustomModels)

addEventHandler("onClientVehicleStartEnter", root, function(player)
    if not isElement(player) then
        return
    end

    local model = getVehicleModel(source)
    if customAnimations[model] then
        loadAnimations(player, model)
    elseif playersWithAnimations[player] then
        restoreAnimations(player)
    end

    if getElementData(source, "scooter:owner")
        and getElementData(source, "scooter:owner") ~= localPlayer
        and player == localPlayer then
        cancelEvent()
    end
end)

addEventHandler("onClientVehicleEnter", root, function(player)
    local model = getVehicleModel(source)
    if player and customAnimations[model] and not playersWithAnimations[player] then
        loadAnimations(player, model)
    end
end)

addEventHandler("onClientVehicleExit", root, function(player)
    local model = getVehicleModel(source)
    if player and customAnimations[model] then
        restoreAnimations(player)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "player" then
        return
    end

    local vehicle = getPedOccupiedVehicle(source)
    if not vehicle then
        return
    end

    local model = getVehicleModel(vehicle)
    if customAnimations[model] then
        loadAnimations(source, model)
    elseif playersWithAnimations[source] then
        restoreAnimations(source)
    end
end)

addEventHandler("onClientPlayerQuit", root, function()
    playersWithAnimations[source] = nil
end)

-- Verificação leve de segurança para estados de entrada/stream que não geraram evento esperado.
setTimer(function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        local vehicle = getPedOccupiedVehicle(player)
        if vehicle then
            local model = getVehicleModel(vehicle)
            if customAnimations[model] and not playersWithAnimations[player] then
                loadAnimations(player, model)
            elseif not customAnimations[model] and playersWithAnimations[player] then
                restoreAnimations(player)
            end
        elseif playersWithAnimations[player] then
            restoreAnimations(player)
        end
    end
end, 1500, 0)

addEventHandler("onClientWorldSound", root, function()
    if getElementType(source) == "vehicle" and getElementModel(source) == ScooterConfig.models.vehicle then
        cancelEvent()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for player in pairs(playersWithAnimations) do
        restoreAnimations(player)
    end

    engineRestoreModel(ScooterConfig.models.vehicle)
    engineRestoreModel(ScooterConfig.models.station)
    engineRestoreModel(ScooterConfig.models.carried)
    engineRestoreCOL(ScooterConfig.models.station)
    engineRestoreCOL(ScooterConfig.models.carried)
    if type(setVehicleModelWheelSize) == "function" then
        if tonumber(originalFrontWheelSize) then
            setVehicleModelWheelSize(ScooterConfig.models.vehicle, "front_axle", originalFrontWheelSize)
        end
        if tonumber(originalRearWheelSize) then
            setVehicleModelWheelSize(ScooterConfig.models.vehicle, "rear_axle", originalRearWheelSize)
        end
    end
end)
