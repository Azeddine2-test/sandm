-- =========================================================
-- server.lua - Système de Métiers (SystemTrabajos)
-- Version optimisée : 1 NPC actif + cooldown aléatoire par magasin
-- Lit depuis AdminMagasin
-- =========================================================

math.randomseed(getTickCount())
math.random()
math.random()

-- ═══════════════════════════════════════════════════════════════
-- CONFIG LOCALE / FALLBACKS
-- ═══════════════════════════════════════════════════════════════

local DEFAULT_FIRST_NPC_COOLDOWN_MIN = 30000      -- 30s
local DEFAULT_FIRST_NPC_COOLDOWN_MAX = 120000     -- 120s
local DEFAULT_NEXT_NPC_COOLDOWN_MIN  = 60000      -- 60s
local DEFAULT_NEXT_NPC_COOLDOWN_MAX  = 300000     -- 300s

local NPC_STREAM_DISTANCE = 60

-- ═══════════════════════════════════════════════════════════════
-- VARIABLES GLOBALES
-- ═══════════════════════════════════════════════════════════════

local npcPed = nil
local cashRegisters = {}
local registeredStoreEvents = {}
local lastRegistersHash = ""

-- Registre des NPC actifs
-- activeNPCs[ped] = { storeID, owner, slotIndex, spawnTime, state, profile, counterItems, totalArticles }
local activeNPCs = {}

-- Registre par joueur caissier
-- npcsByPlayer[player] = { npc1, npc2, ... }
local npcsByPlayer = {}

-- Registre par magasin
-- npcsByStore[storeID] = { npc1, npc2, ... }
local npcsByStore = {}

-- Sessions caissier optimisées
-- cashierSessions[player] = { storeID, currentNPC, respawnTimer, active, hasSpawnedOnce }
local cashierSessions = {}

-- ═══════════════════════════════════════════════════════════════
-- HELPERS DEBUG / NOTIFY
-- ═══════════════════════════════════════════════════════════════

local function dlog(message)
    outputDebugString("[SystemTrabajos] " .. tostring(message))
end

local function notifyPlayer(player, message, nType)
    if not player or not isElement(player) then return end

    local res = getResourceFromName("[FU]Notify")
    if res and getResourceState(res) == "running" then
        exports["[FU]Notify"]:notify(player, message, nType or "infos")
    else
        outputChatBox("[SystemTrabajos] " .. tostring(message), player, 88, 165, 255)
    end
end

local function triggerNotification(player, message, nType)
    if not player or not isElement(player) then return end
    triggerClientEvent(player, "norte notifications : created", player, message, nType or "info")
end

-- ═══════════════════════════════════════════════════════════════
-- INTÉGRATION AVEC ADMINMAGASIN
-- ═══════════════════════════════════════════════════════════════

local function getAdminMagasinRes()
    local res = getResourceFromName("AdminMagasin")
    if res and getResourceState(res) == "running" then return res end
    return nil
end

local function getEmployerNPC()
    if npcPed and isElement(npcPed) then return npcPed end

    local res = getAdminMagasinRes()
    if not res then return nil end

    local ok, ped = pcall(function()
        return exports.AdminMagasin:getEmployerPed()
    end)

    if ok and ped and isElement(ped) then
        npcPed = ped
        return ped
    end

    return nil
end

local function getStoreFullData(storeID)
    local res = getAdminMagasinRes()
    if not res then return nil end

    local ok, storeData = pcall(function()
        return exports.AdminMagasin:getStoreConfig(storeID)
    end)

    if ok and storeData then return storeData end
    return nil
end

local function getStorePathsForStore(storeID)
    local res = getAdminMagasinRes()
    if not res then return {} end

    local ok, paths = pcall(function()
        return exports.AdminMagasin:getStorePaths(storeID)
    end)

    if ok and paths then return paths end
    return {}
end

local function getPathByType(storeID, pathType)
    local paths = getStorePathsForStore(storeID)
    for _, path in pairs(paths) do
        if path.pathType == pathType and type(path.data) == "table" and #path.data > 0 then
            return path.data
        end
    end
    return nil
end

local function getCooldownConfig(store)
    local firstMin = tonumber(store and store.firstNpcCooldownMin) or DEFAULT_FIRST_NPC_COOLDOWN_MIN
    local firstMax = tonumber(store and store.firstNpcCooldownMax) or DEFAULT_FIRST_NPC_COOLDOWN_MAX
    local nextMin  = tonumber(store and store.nextNpcCooldownMin)  or DEFAULT_NEXT_NPC_COOLDOWN_MIN
    local nextMax  = tonumber(store and store.nextNpcCooldownMax)  or DEFAULT_NEXT_NPC_COOLDOWN_MAX

    if firstMin < 0 then firstMin = DEFAULT_FIRST_NPC_COOLDOWN_MIN end
    if firstMax < 0 then firstMax = DEFAULT_FIRST_NPC_COOLDOWN_MAX end
    if nextMin < 0 then nextMin = DEFAULT_NEXT_NPC_COOLDOWN_MIN end
    if nextMax < 0 then nextMax = DEFAULT_NEXT_NPC_COOLDOWN_MAX end

    if firstMin > firstMax then firstMin, firstMax = firstMax, firstMin end
    if nextMin > nextMax then nextMin, nextMax = nextMax, nextMin end

    return firstMin, firstMax, nextMin, nextMax
end

local function randomCooldownMs(store, isFirst)
    local firstMin, firstMax, nextMin, nextMax = getCooldownConfig(store)
    if isFirst then
        return math.random(firstMin, firstMax)
    end
    return math.random(nextMin, nextMax)
end

-- ═══════════════════════════════════════════════════════════════
-- CASH REGISTERS
-- ═══════════════════════════════════════════════════════════════

local function rebuildCashRegisters()
    local newRegisters = {}
    local res = getAdminMagasinRes()

    if res then
        local ok, allStores = pcall(function()
            return exports.AdminMagasin:getAllStoresSimple()
        end)

        if ok and allStores then
            for storeID, storeData in pairs(allStores) do
                if storeData and storeData.pos then
                    table.insert(newRegisters, {
                        storeID = storeID,
                        x = storeData.pos.x,
                        y = storeData.pos.y,
                        z = storeData.pos.z,
                        occupiedBy = nil,
                    })
                end
            end
        end
    end

    local hash = ""
    for _, reg in ipairs(newRegisters) do
        hash = hash .. tostring(reg.storeID) .. ":" .. math.floor(reg.x) .. "," .. math.floor(reg.y) .. "," .. math.floor(reg.z) .. ";"
    end

    if hash == lastRegistersHash then return end
    lastRegistersHash = hash

    -- Préserver les occupations en cours
    for _, oldReg in ipairs(cashRegisters) do
        if isElement(oldReg.occupiedBy) then
            for _, newReg in ipairs(newRegisters) do
                if newReg.storeID == oldReg.storeID then
                    newReg.occupiedBy = oldReg.occupiedBy
                    break
                end
            end
        end
    end

    cashRegisters = newRegisters
    dlog("cashRegisters reconstruit : " .. #cashRegisters .. " magasin(s).")
end

local function getRegisterByStoreID(storeID)
    for _, reg in ipairs(cashRegisters) do
        if reg.storeID == storeID then return reg end
    end
    return nil
end

local function updateStoreOccupancy()
    local ped = getEmployerNPC()
    if not ped or not isElement(ped) then return end

    for _, reg in ipairs(cashRegisters) do
        setElementData(ped, "store_" .. tostring(reg.storeID) .. "_occ", 0)
    end

    for _, reg in ipairs(cashRegisters) do
        if isElement(reg.occupiedBy) then
            setElementData(ped, "store_" .. tostring(reg.storeID) .. "_occ", 1)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- GUIDAGE VERS MAGASIN / EVENTS I9
-- ═══════════════════════════════════════════════════════════════

local function guideToStore(storeID, targetPlayer)
    local player = targetPlayer or client
    if not isElement(player) then return end

    if getElementData(player, "Job") ~= "Cajero" then
        triggerNotification(player, "Vous devez d'abord accepter l'emploi de caissier dans le menu.", "error")
        return
    end

    local targetRegister = getRegisterByStoreID(storeID)
    if not targetRegister then
        triggerNotification(player, "Ce magasin n'existe pas ou plus.", "error")
        return
    end

    if isElement(targetRegister.occupiedBy) and targetRegister.occupiedBy ~= player then
        triggerNotification(player, "Cette succursale est deja occupee par un autre travailleur.", "error")
        return
    end

    triggerClientEvent(player, "v1:showJobRoute", player, targetRegister.x, targetRegister.y, targetRegister.z, targetRegister.storeID)
end

local function registerStoreEvents()
    local res = getAdminMagasinRes()
    if not res then return end

    local ok, allStores = pcall(function()
        return exports.AdminMagasin:getAllStoresSimple()
    end)
    if not ok or not allStores then return end

    for storeID, _ in pairs(allStores) do
        local eventName = "v1:guideToStore_" .. tostring(storeID)
        if not registeredStoreEvents[eventName] then
            registeredStoreEvents[eventName] = true
            addEvent(eventName, true)
            addEventHandler(eventName, root, function()
                guideToStore(storeID, client)
            end)
        end
    end

    -- Compatibilité anciens events
    for i = 1, 4 do
        local oldEventName = "v1:guideToStore" .. i
        if not registeredStoreEvents[oldEventName] then
            registeredStoreEvents[oldEventName] = true
            addEvent(oldEventName, true)
            addEventHandler(oldEventName, root, function()
                guideToStore(i, client)
            end)
        end
    end
end

addEvent("v1:guideToStoreGeneric", true)
addEventHandler("v1:guideToStoreGeneric", root, function(storeID)
    storeID = tonumber(storeID)
    if not storeID then return end
    guideToStore(storeID, client)
end)

-- ═══════════════════════════════════════════════════════════════
-- ENVOI MAGASINS CLIENT
-- ═══════════════════════════════════════════════════════════════

addEvent("SystemTrabajos:requestStores", true)
addEventHandler("SystemTrabajos:requestStores", root, function()
    if not client or not isElement(client) then return end

    local res = getAdminMagasinRes()
    if not res then
        triggerClientEvent(client, "SystemTrabajos:receiveStores", client, {})
        return
    end

    local ok, allStores = pcall(function()
        return exports.AdminMagasin:getAllStoresSimple()
    end)

    if ok and allStores then
        triggerClientEvent(client, "SystemTrabajos:receiveStores", client, allStores)
    else
        triggerClientEvent(client, "SystemTrabajos:receiveStores", client, {})
    end
end)

local function broadcastStoresToAllClients()
    local res = getAdminMagasinRes()
    if not res then return end

    local ok, allStores = pcall(function()
        return exports.AdminMagasin:getAllStoresSimple()
    end)

    if ok and allStores then
        triggerClientEvent(root, "SystemTrabajos:receiveStores", root, allStores)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EMPLOI
-- ═══════════════════════════════════════════════════════════════

addEvent("v1:setJob", true)
addEventHandler("v1:setJob", root, function(jobName, p, routeX, routeY, routeZ, storeID)
    local target = p or client
    if not isElement(target) then return end

    if jobName ~= "Cajero" then
        for _, reg in ipairs(cashRegisters) do
            if reg.occupiedBy == target then
                reg.occupiedBy = nil
            end
        end
        updateStoreOccupancy()
    end

    setElementData(target, "Job", jobName)
    triggerNotification(target, "Vous avez accepte l'emploi de : " .. tostring(jobName), "success")

    if routeX and routeY and routeZ then
        triggerClientEvent(target, "v1:showJobRoute", target, routeX, routeY, routeZ, storeID)
    end
end)

addEvent("v1:setJobCajero", true)
addEventHandler("v1:setJobCajero", root, function(plr)
    local target = plr or client
    if not isElement(target) then return end

    if getElementData(target, "Job") == "Cajero" then
        triggerNotification(target, "Vous avez deja le travail de caissier. Selectionnez une succursale pour vous guider.", "aviso")
        return
    end

    setElementData(target, "Job", "Cajero")
    triggerNotification(target, "Vous avez accepte l'emploi de Caissier. Selectionnez une succursale dans le menu.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- SESSIONS CAISSIER / TIMERS OPTIMISÉS
-- ═══════════════════════════════════════════════════════════════

local function killSessionTimer(session)
    if session and isTimer(session.respawnTimer) then
        killTimer(session.respawnTimer)
    end
    if session then session.respawnTimer = nil end
end

local function despawnNPC(ped)
    if not isElement(ped) then return end

    local info = activeNPCs[ped]
    if info then
        if info.counterItems then
            for _, item in ipairs(info.counterItems) do
                if isElement(item) then destroyElement(item) end
            end
            info.counterItems = nil
        end

        if info.owner and npcsByPlayer[info.owner] then
            for i, p in ipairs(npcsByPlayer[info.owner]) do
                if p == ped then
                    table.remove(npcsByPlayer[info.owner], i)
                    break
                end
            end
        end

        if info.storeID and npcsByStore[info.storeID] then
            for i, p in ipairs(npcsByStore[info.storeID]) do
                if p == ped then
                    table.remove(npcsByStore[info.storeID], i)
                    break
                end
            end
        end

        activeNPCs[ped] = nil
    end

    triggerClientEvent(root, "SystemTrabajos:npcDespawned", root, ped)
    destroyElement(ped)
end

local function cleanupCashierSession(player, despawnCurrentNPC)
    local session = cashierSessions[player]
    if not session then return end

    session.active = false
    killSessionTimer(session)

    if despawnCurrentNPC and session.currentNPC and isElement(session.currentNPC) then
        despawnNPC(session.currentNPC)
    end

    cashierSessions[player] = nil
end

local function despawnAllNPCsForPlayer(player)
    if not player or not npcsByPlayer[player] then return end

    local toDespawn = {}
    for _, npc in ipairs(npcsByPlayer[player]) do
        table.insert(toDespawn, npc)
    end

    for _, npc in ipairs(toDespawn) do
        despawnNPC(npc)
    end

    npcsByPlayer[player] = nil
    dlog("Tous les NPC du joueur " .. tostring(getPlayerName(player)) .. " despawn.")
end

local function isPlayerAssignedToStore(player, storeID)
    local reg = getRegisterByStoreID(storeID)
    return reg and reg.occupiedBy == player
end

local function countActiveNPCsForStore(storeID)
    if not npcsByStore[storeID] then return 0 end
    local count = 0
    for _, npc in ipairs(npcsByStore[storeID]) do
        if isElement(npc) then count = count + 1 end
    end
    return count
end

local function pickRandomNPCProfile(store)
    local profiles = store and store.npcProfiles
    if type(profiles) ~= "table" or #profiles == 0 then return nil end

    local valid = {}
    for _, profile in ipairs(profiles) do
        if type(profile) == "table" and tonumber(profile.skin) then
            table.insert(valid, profile)
        end
    end

    if #valid == 0 then return nil end
    return valid[math.random(#valid)]
end

local function getRandomNPCSkin(store, profile)
    if profile and tonumber(profile.skin) then
        return tonumber(profile.skin)
    end

    -- Si AdminMagasin exporte des profils plus tard, fallback skins classiques
    local skins = {
        10, 11, 12, 14, 15, 16, 17, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 47, 48, 49, 50, 51, 52
    }
    return skins[math.random(#skins)]
end

local function getPlayersNearPosition(x, y, z, maxDistance, exceptPlayer)
    local players = {}
    for _, player in ipairs(getElementsByType("player")) do
        if player ~= exceptPlayer and isElement(player) then
            local px, py, pz = getElementPosition(player)
            if px and getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= maxDistance then
                table.insert(players, player)
            end
        end
    end
    return players
end

local function scheduleNextNPC(player, isFirst)
    if not player or not isElement(player) then return end

    local session = cashierSessions[player]
    if not session or not session.active then return end
    if session.currentNPC and isElement(session.currentNPC) then return end

    killSessionTimer(session)

    local store = getStoreFullData(session.storeID)
    if not store then return end

    local delay = randomCooldownMs(store, isFirst)
    session.respawnTimer = setTimer(function()
        if not isElement(player) then return end
        local s = cashierSessions[player]
        if not s or not s.active then return end
        if s.currentNPC and isElement(s.currentNPC) then return end
        if getElementData(player, "Job") ~= "Cajero" then return end
        if not isPlayerAssignedToStore(player, s.storeID) then return end

        -- spawnNPCForStore est défini plus bas, mais disponible au moment d'exécution du timer.
        local ped = spawnNPCForStore(s.storeID, player)
        if ped and isElement(ped) then
            s.currentNPC = ped
            s.hasSpawnedOnce = true
        else
            -- Si le spawn échoue, on retente plus tard avec le cooldown suivant.
            scheduleNextNPC(player, false)
        end
    end, delay, 1)

    dlog("Prochain NPC magasin #" .. tostring(session.storeID) .. " dans " .. math.floor(delay / 1000) .. "s.")
end

-- ═══════════════════════════════════════════════════════════════
-- SPAWN NPC
-- ═══════════════════════════════════════════════════════════════

function spawnNPCForStore(storeID, owner)
    if not owner or not isElement(owner) then return nil end

    local session = cashierSessions[owner]
    if not session or not session.active or session.storeID ~= storeID then return nil end
    if session.currentNPC and isElement(session.currentNPC) then return nil end

    local store = getStoreFullData(storeID)
    if not store then
        dlog("spawnNPCForStore: Magasin #" .. tostring(storeID) .. " introuvable.")
        return nil
    end

    if not store.basketClient or not store.basketClient.isSet then
        dlog("spawnNPCForStore: Panier client non defini pour magasin #" .. tostring(storeID))
        return nil
    end

    -- Optimisation : 1 NPC actif max dans cette nouvelle version.
    if countActiveNPCsForStore(storeID) >= 1 then
        return nil
    end

    local enterPath = getPathByType(storeID, "enter")
    if not enterPath then
        dlog("spawnNPCForStore: path enter introuvable pour magasin #" .. tostring(storeID))
        return nil
    end

    local profile = pickRandomNPCProfile(store)
    local skin = getRandomNPCSkin(store, profile)

    local spawnX = store.basketClient.x
    local spawnY = store.basketClient.y
    local spawnZ = store.basketClient.z
    local spawnRot = 0

    local ped = createPed(skin, spawnX, spawnY, spawnZ, spawnRot)
    if not ped then
        dlog("spawnNPCForStore: Echec creation NPC.")
        return nil
    end

    setElementData(ped, "isJobNPC", true)
    setElementData(ped, "systemTrabajos:storeID", storeID)
    setElementData(ped, "systemTrabajos:ownerName", getPlayerName(owner))
    setElementFrozen(ped, false)

    activeNPCs[ped] = {
        storeID = storeID,
        owner = owner,
        slotIndex = 1,
        spawnTime = getTickCount(),
        state = "entering",
        profile = profile,
    }

    if not npcsByPlayer[owner] then npcsByPlayer[owner] = {} end
    table.insert(npcsByPlayer[owner], ped)

    if not npcsByStore[storeID] then npcsByStore[storeID] = {} end
    table.insert(npcsByStore[storeID], ped)

    local pausePoints = store.pausePoints or {}
    setElementSyncer(ped, owner)

    triggerClientEvent(owner, "SystemTrabajos:npcSpawned", owner, ped, storeID, 1, enterPath, pausePoints)

    for _, player in ipairs(getPlayersNearPosition(spawnX, spawnY, spawnZ, NPC_STREAM_DISTANCE, owner)) do
        triggerClientEvent(player, "SystemTrabajos:npcSpawned", player, ped, storeID, 1, nil, nil)
    end

    dlog("NPC spawn magasin #" .. tostring(storeID) .. " owner " .. getPlayerName(owner) .. " skin " .. tostring(skin) .. " path " .. tostring(#enterPath) .. " pts.")
    return ped
end

-- ═══════════════════════════════════════════════════════════════
-- MODE CAISSIER START / STOP
-- ═══════════════════════════════════════════════════════════════

addEvent("v1:tryEnterCashier", true)
addEventHandler("v1:tryEnterCashier", root, function(storeID)
    local target = client
    if not isElement(target) then return end
    if getElementData(target, "Job") ~= "Cajero" then return end

    local assignedReg = nil
    for _, reg in ipairs(cashRegisters) do
        if reg.storeID == storeID then
            if reg.occupiedBy == target or not isElement(reg.occupiedBy) then
                reg.occupiedBy = target
                assignedReg = reg
            end
            break
        end
    end

    if assignedReg then
        triggerClientEvent(target, "v1:enterCashierMode", target, storeID)
        updateStoreOccupancy()
    else
        triggerNotification(target, "Cette caisse est deja occupee. Essayez dans une autre succursale.", "error")
    end
end)

addEvent("SystemTrabajos:startNPCSystem", true)
addEventHandler("SystemTrabajos:startNPCSystem", root, function(storeID)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "Job") ~= "Cajero" then return end

    if not isPlayerAssignedToStore(player, storeID) then
        dlog("startNPCSystem refuse : " .. getPlayerName(player) .. " n'est pas caissier du magasin #" .. tostring(storeID))
        return
    end

    local store = getStoreFullData(storeID)
    local paths = getStorePathsForStore(storeID)

    if not store then
        triggerNotification(player, "⚠️ Impossible de charger les donnees du magasin.", "error")
        return
    end

    local missing = {}
    if not store.basketClient or not store.basketClient.isSet then table.insert(missing, "panier client") end
    if not store.basketPermanent or not store.basketPermanent.isSet then table.insert(missing, "panier permanent") end

    local hasPathEnter = false
    local hasPathExit = false
    for _, p in pairs(paths) do
        if p.pathType == "enter" then hasPathEnter = true end
        if p.pathType == "exit" then hasPathExit = true end
    end

    if not hasPathEnter then table.insert(missing, "path enter") end
    if not hasPathExit then table.insert(missing, "path exit") end

    if #missing > 0 then
        triggerNotification(player, "⚠️ Magasin incomplet - Il manque : " .. table.concat(missing, ", ") .. ". Aucun NPC ne peut spawn.", "aviso")
        dlog("Magasin #" .. tostring(storeID) .. " incomplet. Manque : " .. table.concat(missing, ", "))
        return
    end

    -- Stop session précédente éventuelle pour éviter doublons.
    cleanupCashierSession(player, true)

    cashierSessions[player] = {
        storeID = storeID,
        currentNPC = nil,
        respawnTimer = nil,
        active = true,
        hasSpawnedOnce = false,
    }

    -- Option B : le premier NPC arrive après un délai aléatoire.
    scheduleNextNPC(player, true)

    local firstMin, firstMax, nextMin, nextMax = getCooldownConfig(store)
    notifyPlayer(player,
        "Service lance, votre premier client arrive dans peu de temps.",
        "infos"
    )

    dlog("Systeme NPC demarre magasin #" .. tostring(storeID) .. " joueur " .. getPlayerName(player) .. ".")
end)

addEvent("SystemTrabajos:stopNPCSystem", true)
addEventHandler("SystemTrabajos:stopNPCSystem", root, function()
    local player = client
    if not isElement(player) then return end
    cleanupCashierSession(player, true)
    despawnAllNPCsForPlayer(player)
end)

addEvent("v1:quitJobCajero", true)
addEventHandler("v1:quitJobCajero", root, function()
    local target = client or source
    if not isElement(target) then return end

    cleanupCashierSession(target, true)
    despawnAllNPCsForPlayer(target)

    for _, reg in ipairs(cashRegisters) do
        if reg.occupiedBy == target then
            reg.occupiedBy = nil
        end
    end

    removeElementData(target, "Job")
    updateStoreOccupancy()
end)

-- ═══════════════════════════════════════════════════════════════
-- ARTICLES / ARRIVÉE COMPTOIR
-- ═══════════════════════════════════════════════════════════════

local function buildAllowedProductSet(profile)
    if not profile or type(profile.products) ~= "table" then return nil end

    local set = {}
    for _, idx in ipairs(profile.products) do
        idx = tonumber(idx)
        if idx and idx > 0 then set[idx] = true end
    end

    local hasAny = false
    for _ in pairs(set) do hasAny = true break end
    if not hasAny then return nil end

    return set
end

local function collectPositionedProducts(store, allowedSet)
    local positioned = {}

    for i, product in ipairs(store.products or {}) do
        if product.position and product.position.isSet then
            if not allowedSet or allowedSet[i] then
                table.insert(positioned, {
                    index = i,
                    model = product.model,
                    name = product.name,
                    scale = product.scale or 1.0,
                    pos = product.position,
                })
            end
        end
    end

    return positioned
end

local function pickRandomArticles(store, profile)
    local allowedSet = buildAllowedProductSet(profile)
    local positioned = collectPositionedProducts(store, allowedSet)

    -- Fallback robuste : si le profil n'a aucun produit valide, on prend tous les produits positionnés.
    if #positioned == 0 and allowedSet then
        positioned = collectPositionedProducts(store, nil)
    end

    if #positioned == 0 then return {} end

    local maxArticles = math.min(6, #positioned)
    local nbArticles = math.random(1, maxArticles)

    local shuffled = {}
    for _, p in ipairs(positioned) do table.insert(shuffled, p) end

    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local picked = {}
    for i = 1, nbArticles do
        table.insert(picked, shuffled[i])
    end

    return picked
end

addEvent("SystemTrabajos:npcReachedCounter", true)
addEventHandler("SystemTrabajos:npcReachedCounter", root, function(ped, storeID)
    if not isElement(ped) then return end
    if not activeNPCs[ped] then return end

    local npcInfo = activeNPCs[ped]

    if npcInfo.owner ~= client then
        dlog("npcReachedCounter refuse : mauvais owner")
        return
    end

    if npcInfo.state == "waiting" or npcInfo.state == "paid" then return end

    npcInfo.state = "waiting"
    npcInfo.reachedCounterTime = getTickCount()

    local store = getStoreFullData(storeID)
    if not store then
        dlog("npcReachedCounter : magasin introuvable")
        return
    end

    local articles = pickRandomArticles(store, npcInfo.profile)
    local spawnedItems = {}

    for _, article in ipairs(articles) do
        local obj = createObject(
            article.model,
            article.pos.x, article.pos.y, article.pos.z,
            article.pos.rx or 0, article.pos.ry or 0, article.pos.rz or 0
        )

        if isElement(obj) then
            setElementDimension(obj, getElementDimension(ped))
            setElementInterior(obj, getElementInterior(ped))
            setObjectScale(obj, article.scale)
            setElementCollisionsEnabled(obj, false)
            setElementData(obj, "systemTrabajos:counterItem", true)
            setElementData(obj, "systemTrabajos:storeID", storeID)
            setElementData(obj, "systemTrabajos:ownerNPC", ped)
            setElementData(obj, "systemTrabajos:articleName", article.name)
            table.insert(spawnedItems, obj)
        end
    end

    npcInfo.counterItems = spawnedItems
    npcInfo.totalArticles = #spawnedItems

    triggerClientEvent(client, "SystemTrabajos:npcArrivedAtCounter", client, ped, storeID, spawnedItems, store.basketPermanent)

    local nx, ny, nz = getElementPosition(ped)
    for _, player in ipairs(getPlayersNearPosition(nx, ny, nz, NPC_STREAM_DISTANCE, client)) do
        triggerClientEvent(player, "SystemTrabajos:npcArrivedAtCounter", player, ped, storeID, spawnedItems, store.basketPermanent)
    end

    if #articles == 0 then
        triggerNotification(client, "⚠️ Ce magasin n'a aucun produit positionne. Utilise /magasinproduitpos.", "aviso")
    else
        triggerNotification(client, "Un client attend d'etre servi (" .. #articles .. " article(s) au comptoir).", "infos")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- PAIEMENT SÉCURISÉ
-- ═══════════════════════════════════════════════════════════════

local function getPricingConfig()
    return { basePrice = 5, tipsMin = 0, tipsMax = 15 }
end

function triggerNPCExit(ped, npcInfo)
    if not isElement(ped) or not npcInfo then return end

    local storeID = npcInfo.storeID
    local owner = npcInfo.owner

    local exitPath = getPathByType(storeID, "exit")
    if not exitPath or #exitPath == 0 then
        dlog("Pas de path exit pour magasin #" .. tostring(storeID) .. ", despawn direct")
        setTimer(function()
            if isElement(ped) then
                local session = owner and cashierSessions[owner]
                if session and session.currentNPC == ped then session.currentNPC = nil end
                despawnNPC(ped)
                if session and session.active then scheduleNextNPC(owner, false) end
            end
        end, 2000, 1)
        return
    end

    setElementFrozen(ped, false)
    setElementSyncer(ped, owner)

    if isElement(owner) then
        triggerClientEvent(owner, "SystemTrabajos:npcStartExit", owner, ped, exitPath)
    end

    local nx, ny, nz = getElementPosition(ped)
    for _, player in ipairs(getPlayersNearPosition(nx, ny, nz, NPC_STREAM_DISTANCE, owner)) do
        triggerClientEvent(player, "SystemTrabajos:npcStartExit", player, ped, nil)
    end

    dlog("NPC magasin #" .. tostring(storeID) .. " demarre path exit (" .. tostring(#exitPath) .. " points).")
end

function completePurchase(player, ped, npcInfo)
    if not isElement(player) or not isElement(ped) then return end

    local pricing = getPricingConfig()
    local nbArticles = npcInfo.totalArticles or 1

    local baseAmount = nbArticles * pricing.basePrice
    local tips = math.random(pricing.tipsMin, pricing.tipsMax)
    local totalAmount = baseAmount + tips

    local maxPayment = 6 * 20 + 30
    if totalAmount > maxPayment then totalAmount = maxPayment end

    givePlayerMoney(player, totalAmount)
    triggerEvent("updateItems", player, player)

    triggerClientEvent(player, "SystemTrabajos:paymentReceived", player, totalAmount, baseAmount, tips, nbArticles)

    npcInfo.state = "paid"
    triggerNPCExit(ped, npcInfo)
end

addEvent("SystemTrabajos:depositArticle", true)
addEventHandler("SystemTrabajos:depositArticle", root, function(article, ped)
    local player = client
    if not isElement(player) then return end
    if not isElement(article) then return end
    if not isElement(ped) then return end

    local npcInfo = activeNPCs[ped]
    if not npcInfo then return end
    if npcInfo.owner ~= player then return end
    if npcInfo.state ~= "waiting" then return end

    local isValidArticle = false
    local articleIndex = nil

    for i, item in ipairs(npcInfo.counterItems or {}) do
        if item == article then
            isValidArticle = true
            articleIndex = i
            break
        end
    end

    if not isValidArticle then return end

    table.remove(npcInfo.counterItems, articleIndex)
    destroyElement(article)

    triggerClientEvent(player, "SystemTrabajos:articleDeposited", player, ped, articleIndex)

    if #npcInfo.counterItems == 0 then
        completePurchase(player, ped, npcInfo)
    end
end)

addEvent("v1:payCashier", true)
addEventHandler("v1:payCashier", root, function(amount)
    if client and type(amount) == "number" and amount > 0 and amount <= 300 then
        givePlayerMoney(client, amount)
        triggerEvent("updateItems", client, client)
    end
end)

addEvent("SystemTrabajos:npcFinishedExit", true)
addEventHandler("SystemTrabajos:npcFinishedExit", root, function(ped)
    if not isElement(ped) then return end

    local npcInfo = activeNPCs[ped]
    if not npcInfo then return end

    if npcInfo.owner ~= client then
        dlog("npcFinishedExit refuse : mauvais owner")
        return
    end

    local owner = npcInfo.owner
    local session = owner and cashierSessions[owner]

    if session and session.currentNPC == ped then
        session.currentNPC = nil
    end

    despawnNPC(ped)

    if session and session.active and isElement(owner) and getElementData(owner, "Job") == "Cajero" and isPlayerAssignedToStore(owner, session.storeID) then
        scheduleNextNPC(owner, false)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onPlayerQuit", root, function()
    local player = source
    cleanupCashierSession(player, true)
    despawnAllNPCsForPlayer(player)

    for _, reg in ipairs(cashRegisters) do
        if reg.occupiedBy == player then
            reg.occupiedBy = nil
        end
    end

    updateStoreOccupancy()
end, true, "high")

addEventHandler("onElementDestroy", root, function()
    if activeNPCs[source] then
        local info = activeNPCs[source]

        if info.owner and npcsByPlayer[info.owner] then
            for i, p in ipairs(npcsByPlayer[info.owner]) do
                if p == source then
                    table.remove(npcsByPlayer[info.owner], i)
                    break
                end
            end
        end

        if info.storeID and npcsByStore[info.storeID] then
            for i, p in ipairs(npcsByStore[info.storeID]) do
                if p == source then
                    table.remove(npcsByStore[info.storeID], i)
                    break
                end
            end
        end

        activeNPCs[source] = nil
    end
end)

-- Demande 34 : « JOB NETTOYEUR AUTRE GAMEMODE » (v1:setJobCleaner) retiré
-- avec [ScriptJobCleaner] : plus personne ne déclenchait cet événement.

-- ═══════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        rebuildCashRegisters()
        registerStoreEvents()
        updateStoreOccupancy()
    end, 3500, 1)
end)

addEvent("AdminMagasin:notifyStoresChanged", true)
addEventHandler("AdminMagasin:notifyStoresChanged", root, function()
    rebuildCashRegisters()
    registerStoreEvents()
    updateStoreOccupancy()
    broadcastStoresToAllClients()
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, session in pairs(cashierSessions) do
        cleanupCashierSession(player, true)
    end

    for ped in pairs(activeNPCs) do
        if isElement(ped) then destroyElement(ped) end
    end

    activeNPCs = {}
    npcsByPlayer = {}
    npcsByStore = {}
end)
