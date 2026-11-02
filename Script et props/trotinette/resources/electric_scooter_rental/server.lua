-- Electric Scooter Rental: authoritative server-side rental logic. Original assets preserved.
-- Proteção contra config.lua ausente/incompleto. O arquivo oficial continua sendo a fonte principal.
local configWasMissing = type(ScooterConfig) ~= "table"
if configWasMissing then ScooterConfig = {} end
local function ensureScooterTable(key)
    if type(ScooterConfig[key]) ~= "table" then ScooterConfig[key] = {} end
    return ScooterConfig[key]
end
local defaults = {
    resourceName = "Electric Scooter",
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
            { x = 1896.146484375, y = -1761.3681640625, z = 13.546837806702, rot = 0, name = "Station Centro" },
            { x = 1170.142578125, y = -1415.3046875, z = 13.503165245056, rot = 0, name = "Station Hospital" },
            { x = 1324.8115234375, y = -1367.90625, z = 13.590615272522, rot = 0, name = "Station Pershing" },
            { x = 618.837890625, y = -1369.451171875, z = 13.640909194946, rot = 0, name = "Station Rodeo" },
            { x = 1523.740234375, y = -1684.064453125, z = 13.546875, rot = 0, name = "Station Prefeitura" },
        },
    handling = {
            mass = 350, turnMass = 50, dragCoeff = 7, centerOfMass = { 0, 0, 0 },
            percentSubmerged = 103, tractionMultiplier = 1.8, tractionLoss = 1,
            tractionBias = 0.5, numberOfGears = 1, maxVelocity = 70,
            engineAcceleration = 60, engineInertia = 5, driveType = "awd", engineType = "electric",
            brakeDeceleration = 20, brakeBias = 0, steeringLock = 50,
            suspensionForceLevel = 1, suspensionDamping = 0.15, suspensionHighSpeedDamping = 0,
            suspensionUpperLimit = 0.12, suspensionLowerLimit = -0.17,
            suspensionFrontRearBias = 0.15, suspensionAntiDiveMultiplier = 0,
            collisionDamageMultiplier = 0, modelFlags = 0x1001100, handlingFlags = 0x1000001,
        },
}
for key, value in pairs(defaults) do
    if key == "resourceName" then
        ScooterConfig.resourceName = ScooterConfig.resourceName or value
    elseif key == "stations" then
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

-- Electric Scooter Rental - authoritative server logic
-- Dinheiro, propriedade, distância, charge e transições são validados aqui.

local rentTimers = {}
-- Estado autoritativo mantido apenas no server. Element data é usado para UI/compatibility,
-- nunca como única prova de posse de um rental.
local activeRentals = {}
-- Aluguéis cujo scooter está dobrado e stored como item no inventory.
local storedRentals = {} -- [player] = rentStartTick
local rentalOwners = {}
local actionCooldowns = { rent = {}, fold = {} }
local warnedAboutFunds = {}
local rentalItemIssued = {}

local function debugScooter(message, level)
    outputDebugString("[Scooter] " .. tostring(message), level or 3)
end

-- Auditoria operacional: registra transições importantes sem serializar dados sensíveis.
-- O log do server pode ser encaminhado para um sistema externo, se necessário.
local function auditScooter(action, player, details)
    local playerName = isElement(player) and getPlayerName(player) or "system"
    local characterId = isElement(player) and tonumber(getElementData(player, "dbid")) or nil
    local payload = {
        action = tostring(action or "unknown"),
        player = tostring(playerName or "unknown"),
        character_id = characterId,
        details = type(details) == "table" and details or {},
    }
    local encoded = type(toJSON) == "function" and toJSON(payload, true) or false
    outputDebugString("[Scooter][AUDIT] " .. (encoded or (tostring(action) .. " player=" .. tostring(playerName))), 3)
end

local function isValidPlayer(player)
    return isElement(player) and getElementType(player) == "player"
end

-- Controles envolvidos em trocar, mirar ou atacar com armas. Guardamos o estado
-- anterior para não reativar um controle que outro sistema já havia desativado.
local WEAPON_RESTRICTED_CONTROLS = {
    "fire", "action", "aim_weapon", "next_weapon", "previous_weapon",
    "vehicle_fire", "vehicle_secondary_fire",
}
local weaponControlSnapshots = {}
local weaponLockActive = {}
local weaponLockNotice = {}

local function setCarryWeaponLock(player, enabled)
    if not isValidPlayer(player) then
        weaponControlSnapshots[player] = nil
        weaponLockActive[player] = nil
        weaponLockNotice[player] = nil
        return false
    end

    if enabled then
        if weaponLockActive[player] then
            -- Reforça a restrição sem sobrescrever o snapshot original.
            for _, controlName in ipairs(WEAPON_RESTRICTED_CONTROLS) do
                toggleControl(player, controlName, false)
            end
        else
            local snapshot = {}
            for _, controlName in ipairs(WEAPON_RESTRICTED_CONTROLS) do
                snapshot[controlName] = isControlEnabled(player, controlName)
                toggleControl(player, controlName, false)
            end
            weaponControlSnapshots[player] = snapshot
            weaponLockActive[player] = true
        end

        if getPedWeaponSlot(player) ~= 0 then
            setPedWeaponSlot(player, 0)
        end
        setElementData(player, "scooter:weaponLock", true, true)
        return true
    end

    if weaponLockActive[player] then
        local snapshot = weaponControlSnapshots[player] or {}
        for _, controlName in ipairs(WEAPON_RESTRICTED_CONTROLS) do
            local previousState = snapshot[controlName]
            if previousState ~= nil then
                toggleControl(player, controlName, previousState)
            end
        end
    end

    weaponControlSnapshots[player] = nil
    weaponLockActive[player] = nil
    weaponLockNotice[player] = nil
    setElementData(player, "scooter:weaponLock", false, true)
    return true
end

local function isCarryingRentedScooter(player)
    local rented = activeRentals[player]
    return isElement(rented)
        and getElementType(rented) == "object"
        and rentalOwners[rented] == player
end

local function syncCarryWeaponLock(player)
    local restrictions = ScooterConfig.restrictions or {}
    local shouldLock = restrictions.blockWeaponsWhileCarrying ~= false
        and isCarryingRentedScooter(player)
    return setCarryWeaponLock(player, shouldLock)
end

local getRunningResourceName

local function notify(player, messageType, message)
    if not isValidPlayer(player) then
        return false
    end

    local content = "Scooter • " .. tostring(message)
    -- Nome oficial current: bc_infobox. Os demais nomes são compatibility temporária
    -- para instalações antigas; nenhuma dependência rígida impede o resource de iniciar.
    for _, resourceAlias in ipairs({ "bc_infobox", "bpc_infobox" }) do
        local infoboxResource = getRunningResourceName and getRunningResourceName(resourceAlias)
        if infoboxResource then
            local ok, result = pcall(function()
                return exports[infoboxResource]:addNotification(player, content, messageType or "info", 5500)
            end)
            if ok and result ~= false then
                return true
            end
        end
    end

    -- Compatibilidade com a antiga infobox FR_DxMessages, caso ainda esteja instalada.
    local legacyResource = getRunningResourceName and getRunningResourceName("FR_DxMessages")
    if legacyResource then
        local ok, result = pcall(function()
            return exports[legacyResource]:addBox(player, content, messageType or "info", 5500)
        end)
        if ok and result ~= false then
            return true
        end
    end

    local palette = ScooterConfig.visual or {}
    local color = palette.text or { 255, 255, 255 }
    if messageType == "success" then
        color = palette.success or color
    elseif messageType == "error" then
        color = palette.error or color
    elseif messageType == "warning" then
        color = palette.warning or color
    end

    outputChatBox("#41AEFF[Scooter]#FFFFFF " .. tostring(message), player,
        color[1] or 255, color[2] or 255, color[3] or 255, true)
    return true
end

local function getCharacterHours(player)
    return tonumber(getElementData(player, "hoursplayed"))
        or tonumber(getElementData(player, "player:hours"))
        or 0
end

local function isFreeForPlayer(player)
    return getCharacterHours(player) < ScooterConfig.economy.freeHoursLimit
end

local function hasActiveJob(player)
    local job = getElementData(player, "player:job")
    return job ~= nil and job ~= false and job ~= 0 and job ~= "" and job ~= "none"
end

local function findResourceCaseInsensitive(resourceName)
    local resource = getResourceFromName(resourceName)
    if resource then
        return resource
    end

    local wanted = string.lower(tostring(resourceName or ""))
    if type(getResources) == "function" then
        for _, candidate in ipairs(getResources()) do
            if string.lower(getResourceName(candidate) or "") == wanted then
                return candidate
            end
        end
    end
    return false
end

getRunningResourceName = function(resourceName)
    local resource = findResourceCaseInsensitive(resourceName)
    if resource and getResourceState(resource) == "running" then
        return getResourceName(resource)
    end
    return false
end

local function isResourceRunning(resourceName)
    return getRunningResourceName(resourceName) ~= false
end

local function getPlayerCash(player)
    local moneyResource = getRunningResourceName("global")
    if not moneyResource then
        return 0
    end

    local ok, amount = pcall(function()
        return exports[moneyResource]:getMoney(player)
    end)

    if not ok then
        debugScooter("Could not consultar o dinheiro de " .. getPlayerName(player) .. ". Confira o export global:getMoney.", 1)
        return 0
    end

    return tonumber(amount) or 0
end

local function hasEnoughMoney(player, amount)
    return getPlayerCash(player) >= amount
end

-- O framework pode retornar true ou nil em caso de sucesso; false/erro é failure.
local function takePlayerMoneySafe(player, amount)
    if amount <= 0 then
        return true
    end
    local moneyResource = getRunningResourceName("global")
    if not moneyResource then
        debugScooter("The 'global' resource is not running; charge blocked.", 2)
        return false
    end
    if not hasEnoughMoney(player, amount) then
        return false
    end

    local ok, result = pcall(function()
        return exports[moneyResource]:takeMoney(player, amount)
    end)

    if not ok then
        debugScooter("Failed global:takeMoney export: " .. tostring(result), 1)
        return false
    end
    return result ~= false
end

local function clearRentTimer(player)
    if rentTimers[player] and isTimer(rentTimers[player]) then
        killTimer(rentTimers[player])
    end
    rentTimers[player] = nil
end

local function clearRentalState(player, destroyRentedElement)
    local rented = activeRentals[player]
    storedRentals[player] = nil
    setCarryWeaponLock(player, false)

    -- Retire a propriedade privada antes de destruir: onElementDestroy não deve
    -- interpretar uma transição controlada como perda inesperada do scooter.
    activeRentals[player] = nil
    if rented then
        rentalOwners[rented] = nil
    end
    if destroyRentedElement and isElement(rented) then
        destroyElement(rented)
    end

    if isValidPlayer(player) then
        setElementData(player, "scooter:rented", false)
        setElementData(player, "player:animation", false)
    end
    clearRentTimer(player)
    warnedAboutFunds[player] = nil
    rentalItemIssued[player] = nil
end

local function allowAction(player, actionName)
    local now = getTickCount()
    local previous = actionCooldowns[actionName][player]
    if previous and now >= previous and now - previous < ScooterConfig.interaction.actionCooldownMs then
        return false
    end
    actionCooldowns[actionName][player] = now
    return true
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

local function isNearRentalPoint(player)
    if not isValidPlayer(player) then
        return false
    end

    local px, py, pz = getElementPosition(player)
    local playerInterior = getElementInterior(player)
    local playerDimension = getElementDimension(player)
    local maxDistance = ScooterConfig.interaction.stationServerDistance

    for _, station in ipairs(ScooterConfig.stations) do
        local stationInterior = station.interior or 0
        local stationDimension = station.dimension or 0
        if playerInterior == stationInterior and playerDimension == stationDimension then
            if getDistanceBetweenPoints3D(px, py, pz, station.x, station.y, station.z) <= maxDistance then
                return true
            end
        end
    end
    return false
end

local function setElementInPlayerWorld(element, player)
    setElementInterior(element, getElementInterior(player))
    setElementDimension(element, getElementDimension(player))
end

local attachmentFallbackLogged = false

local function tryExternalAttachment(resourceName, object, player)
    local actualName = getRunningResourceName(resourceName)
    if not actualName then
        return false
    end

    local ok, result = pcall(function()
        -- Posição validada: osso 23, offset X/Y/Z e rotação X/Y/Z.
        -- O nome real é resolvido para reconhecer pAttach/pattach sem diferença de caixa.
        return exports[actualName]:attach(object, player, 23, 0.4000, 0.0000, 0.0000, 0.00, -80.00, 30.00)
    end)

    if ok and result ~= false then
        return true
    end

    debugScooter("A integration " .. actualName .. ":attach falhou; tentando a próxima alternativa.", 2)
    return false
end

local function attachCarriedScooter(object, player)
    if not isElement(object) or not isValidPlayer(player) then
        return false
    end

    -- Prioriza a integration de osso/mão original para preservar a aparência.
    for _, resourceName in ipairs({ "pattach", "patch" }) do
        if tryExternalAttachment(resourceName, object, player) then
            return true
        end
    end

    -- Fallback nativo: o rental não deve failurer apenas porque o resource de
    -- anexação não existe ou está stopped. O objeto acompanha o personagem;
    -- a posição pode ser menos precisa que a anexação à mão pelo pattach.
    local attached = attachElements(object, player, 0.28, 0.32, -0.12, 0, 0, 35)
    if attached then
        if not attachmentFallbackLogged then
            debugScooter("pattach/patch is unavailable; using native MTA attachment. Start your attachment integration for hand positioning.", 3)
            attachmentFallbackLogged = true
        end
        return true
    end

    debugScooter("Could not anexar o scooter com a integration externa nem com attachElements.", 1)
    return false
end

local function createCarriedScooter(player, rentTime)
    local x, y, z = getElementPosition(player)
    local object = createObject(ScooterConfig.models.carried, x, y, z)
    if not object then
        return false
    end

    setElementInPlayerWorld(object, player)
    setElementData(object, "scooter:owner", player, true)
    setElementData(object, "scooter:rented:time", tonumber(rentTime) or getTickCount(), true)

    if not attachCarriedScooter(object, player) then
        destroyElement(object)
        return false
    end
    return object
end

local function giveRentalVehicleItemOnce(player, dbid)
    if rentalItemIssued[player] then
        return
    end
    if not tonumber(dbid) or tonumber(dbid) <= 0 then
        debugScooter("Chave não concedida: o personagem não possui um dbid válido.", 2)
        rentalItemIssued[player] = true
        return
    end
    local itemResource = getRunningResourceName("item-system")
    if not itemResource then
        -- O sistema de inventory é integration optional; a condução não depende dele.
        return
    end

    local ok, result = pcall(function()
        return exports[itemResource]:giveItem(player, 3, -dbid)
    end)
    if ok and result ~= false then
        rentalItemIssued[player] = true
    else
        debugScooter("Could not integrate the key with item-system:giveItem.", 2)
    end
end

local function configureScooterVehicle(player, vehicle, rentTime)
    local dbid = tonumber(getElementData(player, "dbid")) or 0
    local x, y, z = getElementPosition(vehicle)

    setElementInPlayerWorld(vehicle, player)
    setVehicleColor(vehicle, 0, 0, 0, 0, 0, 0)
    setVehicleOverrideLights(vehicle, 1)
    setVehicleEngineState(vehicle, false)

    -- Mantidos os metadados usados pelo sistema de veículos do server.
    setElementData(vehicle, "dbid", -dbid, true)
    setElementData(vehicle, "fuel", 100, true)
    setElementData(vehicle, "plate", "RENTAL", true)
    setElementData(vehicle, "Impounded", 0, true)
    setElementData(vehicle, "engine", 0, false)
    setElementData(vehicle, "oldx", x, false)
    setElementData(vehicle, "oldy", y, false)
    setElementData(vehicle, "oldz", z, false)
    setElementData(vehicle, "faction", -1, true)
    setElementData(vehicle, "owner", dbid, false)
    setElementData(vehicle, "job", 0, false)
    setElementData(vehicle, "handbrake", 0, true)
    setElementData(vehicle, "brand", "Scooter", true)
    setElementData(vehicle, "scooter:owner", player, true)
    setElementData(vehicle, "scooter:rented:time", tonumber(rentTime) or getTickCount(), true)

    return dbid
end

local function deployScooter(player, carriedObject)
    if not isElement(carriedObject) or getElementType(carriedObject) ~= "object" then
        return false
    end
    if activeRentals[player] ~= carriedObject or rentalOwners[carriedObject] ~= player then
        notify(player, "error", "This scooter is not linked to your rental.")
        return false
    end
    if not isFreeForPlayer(player) and not isResourceRunning("global") then
        notify(player, "error", "The economy system (global) is unavailable. The scooter remains stored; contact staff.")
        return false
    end
    if not isFreeForPlayer(player) and not hasEnoughMoney(player, ScooterConfig.economy.price) then
        notify(player, "error", "You need $" .. ScooterConfig.economy.price .. " available to unfold the scooter.")
        return false
    end

    local rentTime = tonumber(getElementData(carriedObject, "scooter:rented:time")) or getTickCount()
    local x, y, z = getPositionFromElementOffset(player, 0, 1.0, 0)
    if not x then
        x, y, z = getElementPosition(player)
    end
    local rx, ry, rz = getElementRotation(player)
    local vehicle = createVehicle(ScooterConfig.models.vehicle, x, y, z, rx, ry, rz)

    if not vehicle then
        notify(player, "error", "Could not unfold the scooter. Try again in an open area.")
        return false
    end

    local dbid = configureScooterVehicle(player, vehicle, rentTime)
    if not warpPedIntoVehicle(player, vehicle) then
        destroyElement(vehicle)
        notify(player, "error", "Could not mount the scooter. It remains folded.")
        return false
    end

    -- Troca o vínculo autoritativo antes de destruir o objeto antigo.
    rentalOwners[carriedObject] = nil
    activeRentals[player] = vehicle
    rentalOwners[vehicle] = player
    setElementData(player, "scooter:rented", vehicle)
    setElementData(player, "player:animation", false)
    syncCarryWeaponLock(player) -- liberado ao deixar de carregar o objeto
    destroyElement(carriedObject)
    giveRentalVehicleItemOnce(player, dbid)
    auditScooter("scooter_deployed", player, { vehicle_model = ScooterConfig.models.vehicle })
    notify(player, "success", "Scooter unfolded. To fold it, get off, move closer, and press H.")
    return true
end

local function foldScooterToCarryObject(player, vehicle)
    if not isValidPlayer(player) or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then
        return false
    end
    if activeRentals[player] ~= vehicle or rentalOwners[vehicle] ~= player then
        return false
    end

    local rentTime = tonumber(getElementData(vehicle, "scooter:rented:time")) or getTickCount()
    if getPedOccupiedVehicle(player) == vehicle then
        removePedFromVehicle(player)
    end

    local object = createCarriedScooter(player, rentTime)
    if not object then
        notify(player, "error", "Could not fold the scooter right now. It remains on the ground.")
        return false
    end

    -- Só destruímos o veículo depois de confirmar que o objeto foi criado e anexado.
    -- Atualizamos os vínculos primeiro para que a destruição não apague o novo estado.
    rentalOwners[vehicle] = nil
    activeRentals[player] = object
    rentalOwners[object] = player
    setElementData(player, "scooter:rented", object)
    setElementData(player, "player:animation", "scooter-carry")
    syncCarryWeaponLock(player) -- bloqueia armas assim que o scooter volta à mão
    destroyElement(vehicle)
    auditScooter("scooter_folded", player, {})
    return true
end

local function remindAboutScooter(player)
    local rented = activeRentals[player]
    if isElement(rented) and getElementType(rented) == "vehicle" and getPedOccupiedVehicle(player) ~= rented then
        notify(player, "warning", "You still have an active rental. Return the scooter at a station to stop charges.")
    end
end

local function chargeRecurringRent(player)
    if not isValidPlayer(player) then
        clearRentTimer(player)
        warnedAboutFunds[player] = nil
        rentalItemIssued[player] = nil
        return
    end

    local rented = activeRentals[player]
    local stored = storedRentals[player] ~= nil
    if stored and not isElement(rented) then
        -- O scooter continua alugado mesmo dobrado dentro do inventory.
        rented = false
    elseif not isElement(rented) or (getElementType(rented) ~= "object" and getElementType(rented) ~= "vehicle") then
        clearRentalState(player, false)
        return
    end
    if not stored and rentalOwners[rented] ~= player then
        clearRentalState(player, true)
        notify(player, "error", "The rental ended because the scooter was not linked to your character.")
        return
    end
    if isFreeForPlayer(player) then
        warnedAboutFunds[player] = nil
        return
    end

    local price = ScooterConfig.economy.price
    if not isResourceRunning("global") then
        auditScooter("rental_charge_blocked_economy_unavailable", player, {})
        if not warnedAboutFunds[player] then
            notify(player, "error", "The economy system (global) stopped. The scooter will remain stored until staff restores it.")
            warnedAboutFunds[player] = true
        end
        if not stored and getElementType(rented) == "vehicle" and not foldScooterToCarryObject(player, rented) then
            clearRentalState(player, true)
            notify(player, "error", "The rental ended because the scooter could not be stored while the economy was unavailable.")
        end
        return
    end

    if not hasEnoughMoney(player, price) then
        auditScooter("rental_charge_blocked_insufficient_funds", player, { amount = price })
        if not warnedAboutFunds[player] then
            notify(player, "error", "Insufficient funds for the next charge. The scooter was stored; return it at a station when possible.")
            warnedAboutFunds[player] = true
        end
        if not stored and getElementType(rented) == "vehicle" and not foldScooterToCarryObject(player, rented) then
            clearRentalState(player, true)
            notify(player, "error", "The rental ended because the scooter could not be stored due to insufficient funds.")
        end
        return
    end

    if not takePlayerMoneySafe(player, price) then
        auditScooter("rental_charge_failed", player, { amount = price })
        if not warnedAboutFunds[player] then
            notify(player, "error", "Could not complete the charge. Check your balance and try again.")
            warnedAboutFunds[player] = true
        end
        if not stored and getElementType(rented) == "vehicle" and not foldScooterToCarryObject(player, rented) then
            clearRentalState(player, true)
            notify(player, "error", "The rental ended because the scooter could not be stored after the payment failed.")
        end
        return
    end

    warnedAboutFunds[player] = nil
    auditScooter("rental_charge_succeeded", player, { amount = price })
    remindAboutScooter(player)
end

-- Os elementos criados pelo script pertencem à árvore do resource por padrão;
-- os clientes percorrem os descendentes de resourceRoot para localizar as estações.
local spawnedStationObjects = 0
local spawnedRentalAreas = 0
for _, station in ipairs(ScooterConfig.stations) do
    local object = createObject(ScooterConfig.models.station, station.x, station.y, station.z - 1, 0, 0, station.rot or 0)
    if object then
        setElementInterior(object, station.interior or 0)
        setElementDimension(object, station.dimension or 0)
        setElementData(object, "scooter:station", true, false)
        spawnedStationObjects = spawnedStationObjects + 1
    else
        debugScooter("Could not create station object: " .. tostring(station.name), 2)
    end

    local col = createColSphere(station.x, station.y, station.z, ScooterConfig.interaction.stationRadius)
    if col then
        setElementInterior(col, station.interior or 0)
        setElementDimension(col, station.dimension or 0)
        setElementData(col, "scooter:rental", true, true)
        setElementData(col, "scooter:station:name", station.name or "Rental station", false)
        spawnedRentalAreas = spawnedRentalAreas + 1
    else
        debugScooter("Could not criar a área da station: " .. tostring(station.name), 2)
    end
end

-- Guarda os valores anteriores para não deixar changes globais de handling
-- persistirem caso este resource seja stopped ou reiniciado.
local originalHandlingSnapshot = getModelHandling(ScooterConfig.models.vehicle) or {}
local originalVehicleHandling = {}
for property, value in pairs(ScooterConfig.handling) do
    originalVehicleHandling[property] = originalHandlingSnapshot[property]
    local applied = setModelHandling(ScooterConfig.models.vehicle, property, value)
    if not applied then
        debugScooter("MTA rejected handling parameter '" .. tostring(property) .. "'.", 2)
    end
end

local function inventoryResourceName()
    return getRunningResourceName(ScooterConfig.inventory.resource or "scooter_inventory_bridge")
end

local function inventoryHasRentalItem(player)
    local resourceName = inventoryResourceName()
    if not resourceName then return false end
    local ok, has = pcall(function() return exports[resourceName]:hasItem(player, ScooterConfig.inventory.itemId) end)
    return ok and has == true
end

local function giveStoredRentalItem(player, rentTime)
    local resourceName = inventoryResourceName()
    if not resourceName then
        notify(player, "error", "Inventory bridge is not running; the scooter could not be stored.")
        return false
    end
    if inventoryHasRentalItem(player) then
        notify(player, "error", "You already have a scooter item in your inventory. Action cancelled to prevent duplication.")
        return false
    end
    local ok, result, reason = pcall(function()
        return exports[resourceName]:giveItem(player, ScooterConfig.inventory.itemId, 1, false, { scooterRental = true, rentTime = tonumber(rentTime) or getTickCount() })
    end)
    if not ok or result ~= true then
        debugScooter("Failed to store scooter in inventory: " .. tostring(ok and reason or result), 1)
        notify(player, "error", "Could not store the scooter in your inventory. You are still carrying it.")
        return false
    end
    return true
end

local function takeStoredRentalItem(player)
    local resourceName = inventoryResourceName()
    if not resourceName then return false end
    local ok, result = pcall(function() return exports[resourceName]:takeItem(player, ScooterConfig.inventory.itemId, 1) end)
    return ok and result == true
end

addEvent("scooter:inventoryUse", false)
addEventHandler("scooter:inventoryUse", root, function(itemRecordID)
    local player = source
    if not isValidPlayer(player) or not storedRentals[player] or activeRentals[player] then return end
    if not allowAction(player, "fold") or isPedDead(player) or getPedOccupiedVehicle(player) then return end
    if not inventoryHasRentalItem(player) then
        notify(player, "error", "The scooter item was not found in your inventory.")
        return
    end
    local rentTime = storedRentals[player]
    local object = createCarriedScooter(player, rentTime)
    if not object then
        notify(player, "error", "Could not retrieve the scooter right now. The item remains in your inventory.")
        return
    end
    if not takeStoredRentalItem(player) then
        destroyElement(object)
        notify(player, "error", "Could not safely consume the inventory item. Nothing was retrieved.")
        return
    end
    storedRentals[player] = nil
    activeRentals[player] = object
    rentalOwners[object] = player
    setElementData(player, "scooter:rented", object)
    setElementData(player, "player:animation", "scooter-carry")
    syncCarryWeaponLock(player)
    auditScooter("rental_item_used", player, {})
    notify(player, "success", "Scooter retrieved from inventory. Press H to unfold it, or store it again.")
end)

addEvent("scooter:rent", true)
addEventHandler("scooter:rent", resourceRoot, function()
    local player = client
    if not isValidPlayer(player) or source ~= resourceRoot then
        return
    end
    if not allowAction(player, "rent") then
        return
    end
    if isPedDead(player) then
        notify(player, "error", "You cannot interact with the rental in your current state.")
        return
    end
    if getPedOccupiedVehicle(player) then
        notify(player, "warning", "Exit your vehicle before renting or returning a scooter.")
        return
    end
    if not isNearRentalPoint(player) then
        notify(player, "error", "You must be at a rental station to rent or return a scooter.")
        return
    end

    if storedRentals[player] then
        if not takeStoredRentalItem(player) then
            notify(player, "error", "Could not remove the inventory item; the rental remains active.")
            return
        end
        storedRentals[player] = nil
        clearRentTimer(player)
        warnedAboutFunds[player] = nil
        rentalItemIssued[player] = nil
        setElementData(player, "scooter:rented", false)
        setElementData(player, "player:animation", false)
        auditScooter("rental_returned_from_inventory", player, {})
        notify(player, "success", "Scooter returned. Rental charges have stopped.")
        return
    end

    local rented = activeRentals[player]
    if rented and not isElement(rented) then
        -- Reconcilia uma referência que tenha sido destruída por outro resource.
        clearRentalState(player, false)
        rented = nil
    end
    if isElement(rented) then
        if getElementType(rented) ~= "object" then
            notify(player, "warning", "Before returning it, get off the scooter and press H nearby to fold it.")
            return
        end
        if rentalOwners[rented] ~= player then
            notify(player, "error", "This scooter is not linked to your rental. Return blocked.")
            return
        end

        activeRentals[player] = nil
        rentalOwners[rented] = nil
        setCarryWeaponLock(player, false)
        setElementData(player, "scooter:rented", false)
        setElementData(player, "player:animation", false)
        destroyElement(rented)
        clearRentTimer(player)
        warnedAboutFunds[player] = nil
        rentalItemIssued[player] = nil
        auditScooter("rental_returned", player, {})
        notify(player, "success", "Scooter returned. Rental charges have stopped.")
        return
    end

    -- Se o estado em memory foi perdido (por exemplo, após reinício do resource),
    -- permite return o item órfão nesta station em vez de iniciar outro rental.
    if inventoryHasRentalItem(player) then
        if not takeStoredRentalItem(player) then
            notify(player, "error", "A scooter item already exists in your inventory, but the return could not be reconciled. No new rental was started.")
            return
        end
        clearRentTimer(player)
        warnedAboutFunds[player] = nil
        rentalItemIssued[player] = nil
        storedRentals[player] = nil
        setElementData(player, "scooter:rented", false)
        setElementData(player, "player:animation", false)
        auditScooter("rental_returned_orphan_inventory_item", player, {})
        notify(player, "success", "Scooter returned and inventory item removed. Local rental charges have stopped.")
        return
    end

    if hasActiveJob(player) then
        notify(player, "error", "Finish your current job before renting a scooter.")
        return
    end

    local isFree = isFreeForPlayer(player)
    local price = ScooterConfig.economy.price
    if not isFree and not isResourceRunning("global") then
        notify(player, "error", "Paid rentals are unavailable because the 'global' economy resource is not running. Contact staff.")
        debugScooter("Retirada paga bloqueada para " .. getPlayerName(player) .. ": resource global ausente/stopped.", 2)
        return
    end
    if not isFree and not hasEnoughMoney(player, price) then
        notify(player, "error", "You need $" .. price .. " to start the rental.")
        return
    end

    local rentTime = getTickCount()
    local object = createCarriedScooter(player, rentTime)
    if not object then
        notify(player, "error", "Could not rent the scooter. Contact staff if the problem persists.")
        return
    end

    -- Prepara o temporizador antes da charge. Se ele failurer, não iniciaremos um
    -- rental pago que não consiga executar as charges periódicas.
    clearRentTimer(player)
    local timer = setTimer(chargeRecurringRent, ScooterConfig.economy.chargeIntervalMs, 0, player)
    if not timer then
        destroyElement(object)
        debugScooter("Could not start the charge timer for " .. getPlayerName(player), 1)
        notify(player, "error", "Could not start the rental right now. Please try again shortly.")
        return
    end

    if not isFree and not takePlayerMoneySafe(player, price) then
        killTimer(timer)
        destroyElement(object)
        notify(player, "error", "The initial charge failed; the scooter was not issued.")
        return
    end

    activeRentals[player] = object
    rentalOwners[object] = player
    rentTimers[player] = timer
    setElementData(player, "scooter:rented", object)
    setElementData(player, "player:animation", "scooter-carry")
    syncCarryWeaponLock(player)
    warnedAboutFunds[player] = nil
    auditScooter("rental_started", player, { initial_fee = isFree and 0 or price, free_eligibility_hours = getCharacterHours(player) })

    if isFree then
        notify(player, "success", "Free scooter rental for characters with fewer than " .. ScooterConfig.economy.freeHoursLimit .. " hours. Press H to unfold it.")
    else
        notify(player, "success", "Scooter rented for $" .. price .. ". The fee of $" .. price .. "  is charged every minute. Press H to unfold the scooter.")
    end
end)

-- H: abrir/colocar no chão o scooter que está na mão.
addEvent("scooter:deploy", true)
addEventHandler("scooter:deploy", resourceRoot, function()
    local player = client
    if not isValidPlayer(player) or source ~= resourceRoot then return end
    if not allowAction(player, "fold") or isPedDead(player) or getPedOccupiedVehicle(player) then return end
    local carried = activeRentals[player]
    if not isElement(carried) or getElementType(carried) ~= "object" or rentalOwners[carried] ~= player then
        notify(player, "error", "You must be carrying your scooter to unfold it.")
        return
    end
    deployScooter(player, carried)
end)

-- I: guarda o scooter na mão no inventory; H permanece dedicado ao chão.
addEvent("scooter:store", true)
addEventHandler("scooter:store", resourceRoot, function()
    local player = client
    if not isValidPlayer(player) or source ~= resourceRoot then return end
    if not allowAction(player, "fold") or isPedDead(player) or getPedOccupiedVehicle(player) then return end
    local carried = activeRentals[player]
    if not isElement(carried) or getElementType(carried) ~= "object" or rentalOwners[carried] ~= player then
        notify(player, "error", "You must be carrying your scooter to store it.")
        return
    end
    local rentTime = tonumber(getElementData(carried, "scooter:rented:time")) or getTickCount()
    if not giveStoredRentalItem(player, rentTime) then return end
    rentalOwners[carried] = nil
    activeRentals[player] = nil
    storedRentals[player] = rentTime
    setCarryWeaponLock(player, false)
    setElementData(player, "scooter:rented", false)
    setElementData(player, "player:animation", false)
    destroyElement(carried)
    auditScooter("rental_stored_in_inventory", player, {})
    notify(player, "success", "Scooter stored in inventory. Use the item to retrieve it; return it at a station to stop rental charges.")
end)

addEvent("scooter:fold", true)
addEventHandler("scooter:fold", resourceRoot, function()
    local player = client
    if not isValidPlayer(player) or source ~= resourceRoot then
        return
    end
    if not allowAction(player, "fold") then
        return
    end
    if isPedDead(player) then
        notify(player, "error", "You cannot move the scooter in your current state.")
        return
    end

    local rented = activeRentals[player]
    if not isElement(rented) then
        if rented then
            clearRentalState(player, false)
        end
        return
    end
    if rentalOwners[rented] ~= player then
        notify(player, "error", "This scooter is not linked to your rental.")
        return
    end

    local rentedType = getElementType(rented)
    if rentedType ~= "vehicle" then
        notify(player, "warning", "Press H to unfold the scooter or I to store it in your inventory.")
        return
    end

    if getPedOccupiedVehicle(player) then
        notify(player, "warning", "Get off the scooter before storing it.")
        return
    end
    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(rented)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > ScooterConfig.interaction.foldDistance then
        notify(player, "warning", "Move closer to your scooter to store it.")
        return
    end

    if foldScooterToCarryObject(player, rented) then
        notify(player, "success", "Scooter folded. Take it to a station to return it, or press H to unfold it again.")
    end
end)

addEvent("scooter:fetchTickCount", true)
addEventHandler("scooter:fetchTickCount", resourceRoot, function()
    if isValidPlayer(client) and source == resourceRoot then
        triggerClientEvent(client, "scooter:fetchTickCount", resourceRoot, getTickCount())
    end
end)

-- Regra de RP autoritativa: enquanto o scooter estiver sendo carregado, o jogador
-- permanece desarmado. A checagem de dano evita que um cliente modificado ignore os controles.
addEventHandler("onPlayerWeaponSwitch", root, function(_, currentWeaponID)
    local player = source
    if not weaponLockActive[player] or not isCarryingRentedScooter(player) then
        return
    end

    if tonumber(currentWeaponID) ~= 0 then
        cancelEvent()
        -- A tentativa não altera o inventory; selecionamos apenas o slot desarmado.
        if getPedWeaponSlot(player) ~= 0 then
            setPedWeaponSlot(player, 0)
        end
        local restrictions = ScooterConfig.restrictions or {}
        if restrictions.notifyWeaponAttempt ~= false and not weaponLockNotice[player] then
            weaponLockNotice[player] = true
            notify(player, "warning", "Guarde ou abra o scooter antes de equipar ou usar armas.")
        end
    end
end)

addEventHandler("onPlayerDamage", root, function(attacker)
    if isValidPlayer(attacker) and weaponLockActive[attacker] and isCarryingRentedScooter(attacker) then
        cancelEvent()
    end
end)

-- Barreira no server: outros jogadores não podem tomar o scooter alugado.
addEventHandler("onVehicleStartEnter", root, function(player)
    local owner = rentalOwners[source]
    if owner and isElement(owner) and player ~= owner then
        cancelEvent()
    end
end)

-- Se outro resource destruir inesperadamente um scooter alugado, limpa a referência
-- privada, o temporizador e os metadados para não deixar uma charge órfã.
addEventHandler("onElementDestroy", root, function()
    local owner = rentalOwners[source]
    if not owner then
        return
    end

    rentalOwners[source] = nil
    if activeRentals[owner] ~= source then
        return
    end

    activeRentals[owner] = nil
    setCarryWeaponLock(owner, false)
    if isValidPlayer(owner) then
        setElementData(owner, "scooter:rented", false)
        setElementData(owner, "player:animation", false)
        auditScooter("rental_ended_unexpected_element_destroy", owner, {})
        notify(owner, "warning", "O rental foi encerrado porque o scooter foi removido do mundo.")
    end
    clearRentTimer(owner)
    warnedAboutFunds[owner] = nil
    rentalItemIssued[owner] = nil
end)

addEventHandler("onPlayerQuit", root, function()
    clearRentalState(source, true)
    storedRentals[source] = nil
    actionCooldowns.rent[source] = nil
    actionCooldowns.fold[source] = nil
end)

addEventHandler("onPlayerWasted", root, function()
    clearRentalState(source, true)
    storedRentals[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    debugScooter("Inicialização: " .. tostring(spawnedStationObjects) .. "/" .. tostring(#ScooterConfig.stations)
        .. " objetos visuais e " .. tostring(spawnedRentalAreas) .. "/" .. tostring(#ScooterConfig.stations)
        .. " áreas de rental criadas.", 3)
    if not isResourceRunning("global") then
        debugScooter("The 'global' resource is not running. Paid rentals will remain unavailable until it starts.", 2)
    end
    if not isResourceRunning("pattach") and not isResourceRunning("patch") then
        debugScooter("pattach/patch is not running; the resource will use native MTA attachment as a fallback.", 3)
    end
    if not isResourceRunning("item-system") then
        debugScooter("The 'item-system' resource is not running; optional key integration will be skipped.", 3)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, timer in pairs(rentTimers) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    rentTimers = {}

    -- Só remove entidades que este resource reconhece como aluguéis reais.
    for player, rented in pairs(activeRentals) do
        activeRentals[player] = nil
        if rented then
            rentalOwners[rented] = nil
            if isElement(rented) then
                destroyElement(rented)
            end
        end
    end
    for _, player in ipairs(getElementsByType("player")) do
        setCarryWeaponLock(player, false)
        setElementData(player, "scooter:rented", false)
        setElementData(player, "player:animation", false)
    end

    activeRentals = {}
    storedRentals = {}
    rentalOwners = {}
    actionCooldowns = { rent = {}, fold = {} }
    warnedAboutFunds = {}
    rentalItemIssued = {}
    weaponControlSnapshots = {}
    weaponLockActive = {}
    weaponLockNotice = {}
    for property, value in pairs(originalVehicleHandling) do
        setModelHandling(ScooterConfig.models.vehicle, property, value)
    end
end)
