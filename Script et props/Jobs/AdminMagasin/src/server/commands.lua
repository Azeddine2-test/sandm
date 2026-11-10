-- ============================================================
-- server/commands.lua - Toutes les commandes admin
-- Version optimisée : cooldown random NPC + profils NPC
-- Paths utiles : enter / exit uniquement
-- ============================================================

-- Helpers pour toujours récupérer les vraies références globales
local function S() return _G.stores or {} end
local function SP() return _G.storePaths or {} end

-- ═══════════════════════════════════════════════════════════════
-- PROTECTION ANTI-DOUBLON
-- ═══════════════════════════════════════════════════════════════

local lastCommandTime = {}

local function isCommandDuplicated(player, commandName)
    if not AMConfig.antiDuplicate.enabled then return false end
    if not player or not isElement(player) then return false end

    local playerName = getPlayerName(player)
    local key = playerName .. ":" .. commandName
    local now = getTickCount()
    local cooldown = AMConfig.antiDuplicate.cooldown or 1500

    if lastCommandTime[key] and (now - lastCommandTime[key]) < cooldown then
        if AMConfig.antiDuplicate.logDuplicates then
            log("⚠️ DOUBLON BLOQUE : /" .. commandName .. " par " .. playerName)
        end
        return true
    end

    lastCommandTime[key] = now
    return false
end

addEventHandler("onPlayerQuit", root, function()
    local playerName = getPlayerName(source)
    for key in pairs(lastCommandTime) do
        if string.find(key, "^" .. playerName .. ":") then
            lastCommandTime[key] = nil
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- HELPERS COMMANDES
-- ═══════════════════════════════════════════════════════════════

local function requireAdmin(player)
    if not hasAdminPermission(player) then
        notify(player, "Permission refusee.", "error")
        return false
    end
    return true
end

local function getStoreOrNotify(player, id)
    id = tonumber(id)
    if not id then
        notify(player, "ID magasin invalide.", "warning")
        return nil, nil
    end

    local store = S()[id]
    if not store then
        notify(player, "Magasin #" .. id .. " introuvable.", "error")
        return nil, id
    end

    return store, id
end

local function secondsToMs(sec)
    sec = tonumber(sec)
    if not sec then return nil end
    sec = math.floor(sec)
    if sec < 0 then sec = 0 end
    return sec * 1000
end

local function msToSeconds(ms)
    return math.floor((tonumber(ms) or 0) / 1000)
end

local function parseProductList(str)
    if not str or str == "" then return nil end

    local products = {}
    for token in string.gmatch(str, "[^,]+") do
        local n = tonumber(token)
        if n and n > 0 then
            table.insert(products, math.floor(n))
        end
    end

    if #products == 0 then return nil end
    return products
end

local function productsToString(products)
    if type(products) ~= "table" or #products == 0 then return "tous" end
    local out = {}
    for _, id in ipairs(products) do table.insert(out, tostring(id)) end
    return table.concat(out, ",")
end

local function validateProductIndexes(store, products)
    if type(products) ~= "table" or #products == 0 then return false, "Liste de produits vide." end
    local max = #(store.products or {})
    if max == 0 then return false, "Ce magasin n'a aucun produit." end

    for _, idx in ipairs(products) do
        if idx < 1 or idx > max then
            return false, "Produit #" .. idx .. " invalide. Produits disponibles : 1 a " .. max .. "."
        end
    end

    return true
end

local function getDefaultCooldowns()
    return {
        firstMin = AMConfig.defaults.firstNpcCooldownMin or 30000,
        firstMax = AMConfig.defaults.firstNpcCooldownMax or 120000,
        nextMin  = AMConfig.defaults.nextNpcCooldownMin or 60000,
        nextMax  = AMConfig.defaults.nextNpcCooldownMax or 300000,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- MAGASINS - GESTION DE BASE
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinpanel", function(player)
    if not requireAdmin(player) then return end
    triggerClientEvent(player, "AdminMagasin:openPanel", player, S(), SP())
end)

addCommandHandler("magasinlist", function(player)
    if not requireAdmin(player) then return end

    local stores = S()
    outputChatBox(" ", player)
    outputChatBox("=== LISTE DES MAGASINS ===", player, 121, 80, 242)

    local sortedIds = {}
    for id in pairs(stores) do table.insert(sortedIds, id) end
    table.sort(sortedIds)

    for _, id in ipairs(sortedIds) do
        local store = stores[id]
        local status = AMData.getStoreStatus(store, getStorePaths(id))
        local statusIcon = status.npcReady and "✓ NPC" or (status.basicCashierReady and "~ Caissier" or "✗ Vide")
        outputChatBox(string.format("  #%d | %s | Clients: %ds-%ds puis %ds-%ds | Etat: %s",
            id,
            store.name,
            msToSeconds(store.firstNpcCooldownMin),
            msToSeconds(store.firstNpcCooldownMax),
            msToSeconds(store.nextNpcCooldownMin),
            msToSeconds(store.nextNpcCooldownMax),
            statusIcon
        ), player, 255, 255, 255)
    end

    if #sortedIds == 0 then
        outputChatBox("  Aucun magasin. Utilisez /magasincreate [nom] pour commencer.", player, 200, 200, 200)
    end

    outputChatBox("Total : " .. #sortedIds .. " magasin(s)", player, 255, 255, 100)
    outputChatBox("Legende : ✓ NPC pret | ~ Caissier basique | ✗ Non fonctionnel", player, 200, 200, 200)
    outputChatBox(" ", player)
end)

addCommandHandler("magasincreate", function(player, cmd, ...)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasincreate") then return end

    local name = table.concat({...}, " ")
    if name == "" then
        return notify(player, "Usage : /magasincreate [nom du magasin]", "warning")
    end

    local x, y, z = getElementPosition(player)
    -- PHASE 6: custom account key via core_account (log/DB column).
    local okAcc, caKey = pcall(function() return exports.core_account:getAccountID(player) end)
    if not (okAcc and caKey and caKey ~= '') then
        caKey = getElementData(player, 'core_account:id') or getElementData(player, 'LoginFuturo:accountKey')
    end
    local adminName = (caKey and caKey ~= '' and caKey ~= false) and tostring(caKey) or "unknown"

    local newId = createStore(name, x, y, z, adminName)
    if not newId then return notify(player, "Erreur lors de la creation.", "error") end

    notify(player, "Magasin #" .. newId .. " '" .. name .. "' cree a votre position !", "success")
    notify(player, "Prochaine etape : /magasinstatus " .. newId, "info")
end)

addCommandHandler("magasindelete", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasindelete") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return end

    local name = store.name
    local pathCount = countPathsForStore(storeId)
    deleteStore(storeId)

    notify(player, "Magasin #" .. storeId .. " '" .. name .. "' SUPPRIME (" .. pathCount .. " path(s) supprimes).", "success")
end)

addCommandHandler("magasintp", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return end

    teleportPlayerSafe(player, store.pos.x, store.pos.y, store.pos.z + 1)
    notify(player, "Teleporte au magasin #" .. storeId .. " : " .. store.name, "success")
end)

addCommandHandler("magasingoto", function(player, cmd, id, target)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then
        notify(player, "Usage : /magasingoto [id] [magasin|caissier|camera|panier|panierclient]", "warning")
        return
    end

    target = target and string.lower(target) or "magasin"

    if target == "caissier" then
        if not store.cashier.isSet then return notify(player, "Le caissier n'est pas defini.", "error") end
        teleportPlayerSafe(player, store.cashier.x, store.cashier.y, store.cashier.z + 1)
        notify(player, "Teleporte au caissier du magasin #" .. storeId, "success")
    elseif target == "camera" then
        if not store.camera.isSet then return notify(player, "La camera n'est pas definie.", "error") end
        teleportPlayerSafe(player, store.camera.x, store.camera.y, store.camera.z + 1)
        notify(player, "Teleporte a la camera du magasin #" .. storeId, "success")
    elseif target == "panier" then
        if not store.basketPermanent.isSet then return notify(player, "Le panier permanent n'est pas defini.", "error") end
        teleportPlayerSafe(player, store.basketPermanent.x, store.basketPermanent.y, store.basketPermanent.z + 1)
        notify(player, "Teleporte au panier permanent du magasin #" .. storeId, "success")
    elseif target == "panierclient" then
        if not store.basketClient.isSet then return notify(player, "Le panier client n'est pas defini.", "error") end
        teleportPlayerSafe(player, store.basketClient.x, store.basketClient.y, store.basketClient.z + 1)
        notify(player, "Teleporte au panier client du magasin #" .. storeId, "success")
    else
        teleportPlayerSafe(player, store.pos.x, store.pos.y, store.pos.z + 1)
        notify(player, "Teleporte au magasin #" .. storeId .. " : " .. store.name, "success")
    end
end)

addCommandHandler("magasininfo", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasininfo [id]", "warning") end

    local pathCount = countPathsForStore(storeId)
    local profilesCount = store.npcProfiles and #store.npcProfiles or 0

    outputChatBox(" ", player)
    outputChatBox("=== MAGASIN #" .. storeId .. " : " .. store.name .. " ===", player, 121, 80, 242)
    outputChatBox("  Position : " .. AMData.formatPosition(store.pos.x, store.pos.y, store.pos.z), player, 255, 255, 255)
    outputChatBox("  NPC actif max : 1 (systeme optimise)", player, 255, 255, 255)
    outputChatBox("  Premier client : " .. msToSeconds(store.firstNpcCooldownMin) .. "s - " .. msToSeconds(store.firstNpcCooldownMax) .. "s", player, 255, 255, 255)
    outputChatBox("  Clients suivants : " .. msToSeconds(store.nextNpcCooldownMin) .. "s - " .. msToSeconds(store.nextNpcCooldownMax) .. "s", player, 255, 255, 255)
    outputChatBox("  Profils NPC : " .. profilesCount .. " configure(s)", player, 255, 255, 255)
    outputChatBox("  Salaire : " .. store.salary.min .. " - " .. store.salary.max .. " $", player, 255, 255, 255)
    outputChatBox("  Produits : " .. #store.products .. " configure(s)", player, 255, 255, 255)
    outputChatBox("  Paths : " .. pathCount .. " chemin(s)", player, 255, 255, 255)
    outputChatBox("  Points de pause : " .. (#(store.pausePoints or {})), player, 255, 255, 255)
    outputChatBox("  Cree par : " .. (store.createdBy or "?"), player, 200, 200, 200)
    outputChatBox("Commandes : /magasinstatus " .. storeId .. " | /magasincooldown " .. storeId .. " | /magasinnpcprofiles " .. storeId, player, 200, 200, 200)
    outputChatBox(" ", player)
end)

addCommandHandler("magasinrename", function(player, cmd, id, ...)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinrename") then return end

    local store, storeId = getStoreOrNotify(player, id)
    local newName = table.concat({...}, " ")
    if not store or newName == "" then return notify(player, "Usage : /magasinrename [id] [nouveau nom]", "warning") end

    local oldName = store.name
    updateStore(storeId, "name", newName)
    if S()[storeId].marker and isElement(S()[storeId].marker) then
        setElementData(S()[storeId].marker, "adminMagasin:name", newName)
    end
    notify(player, "Magasin #" .. storeId .. " renomme : '" .. oldName .. "' -> '" .. newName .. "'", "success")
end)

addCommandHandler("magasinclone", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinclone") then return end

    local sourceStore, sourceId = getStoreOrNotify(player, id)
    if not sourceStore then return end

    local x, y, z = getElementPosition(player)
    -- PHASE 6: custom account key via core_account (log/DB column).
    local okAcc, caKey = pcall(function() return exports.core_account:getAccountID(player) end)
    if not (okAcc and caKey and caKey ~= '') then
        caKey = getElementData(player, 'core_account:id') or getElementData(player, 'LoginFuturo:accountKey')
    end
    local adminName = (caKey and caKey ~= '' and caKey ~= false) and tostring(caKey) or "unknown"

    local newId = createStore(sourceStore.name .. " (copie)", x, y, z, adminName)
    if not newId then return notify(player, "Erreur lors du clonage.", "error") end

    updateStore(newId, "products", AMData.deepCopy(sourceStore.products))
    updateStore(newId, "cooldowns", {
        firstMin = sourceStore.firstNpcCooldownMin,
        firstMax = sourceStore.firstNpcCooldownMax,
        nextMin = sourceStore.nextNpcCooldownMin,
        nextMax = sourceStore.nextNpcCooldownMax,
    })
    updateStore(newId, "npcProfiles", AMData.deepCopy(sourceStore.npcProfiles or {}))

    notify(player, "Magasin #" .. sourceId .. " clone en #" .. newId .. " a votre position !", "success")
    notify(player, "N'oubliez pas de definir caissier, camera et paniers pour le nouveau magasin.", "info")
end)

addCommandHandler("magasinpos", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinpos") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinpos [id]", "warning") end

    local x, y, z = getElementPosition(player)
    updateStore(storeId, "pos", {x = x, y = y, z = z})
    notify(player, "Position du magasin #" .. storeId .. " changee a votre position.", "success")
end)

addCommandHandler("magasincaissier", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasincaissier") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasincaissier [id]", "warning") end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    updateStore(storeId, "cashier", {x = x, y = y, z = z, rot = rot})
    notify(player, "Position du caissier definie pour le magasin #" .. storeId .. " !", "success")
end)

addCommandHandler("magasincamera", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasincamera") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasincamera [id]", "warning") end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local camX, camY, camZ = x, y, z + 0.6
    local rad = math.rad(rot)
    local dist = 5.0
    local tx = camX - math.sin(rad) * dist
    local ty = camY - math.cos(rad) * dist
    local tz = camZ

    updateStore(storeId, "camera", {x = camX, y = camY, z = camZ, tx = tx, ty = ty, tz = tz})
    notify(player, "Camera POV caissier definie pour le magasin #" .. storeId .. " !", "success")
end)

addCommandHandler("magasinnpc", function(player, cmd, id, maxNPC)
    if not requireAdmin(player) then return end
    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinnpc [id]", "warning") end

    updateStore(storeId, "maxNPC", 1)
    notify(player, "Systeme optimise : le magasin #" .. storeId .. " utilise 1 NPC actif maximum.", "info")
end)

addCommandHandler("magasinsalaire", function(player, cmd, id, minS, maxS)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinsalaire") then return end

    local store, storeId = getStoreOrNotify(player, id)
    minS = tonumber(minS)
    maxS = tonumber(maxS)
    if not store or not minS or not maxS then return notify(player, "Usage : /magasinsalaire [id] [min] [max]", "warning") end

    if minS > maxS then minS, maxS = maxS, minS end
    minS = math.max(1, minS)
    maxS = math.max(1, maxS)

    updateStore(storeId, "salaryMin", minS)
    updateStore(storeId, "salaryMax", maxS)
    notify(player, "Magasin #" .. storeId .. " : Salaire = " .. minS .. " - " .. maxS .. " $", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- COOLDOWN NPC PAR MAGASIN
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasincooldown", function(player, cmd, id, firstMin, firstMax, nextMin, nextMax)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasincooldown") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then
        notify(player, "Usage : /magasincooldown [id] [firstMin] [firstMax] [nextMin] [nextMax]", "warning")
        notify(player, "Exemple : /magasincooldown 1 30 120 60 300", "info")
        return
    end

    if not firstMin then
        outputChatBox(" ", player)
        outputChatBox("=== COOLDOWN NPC MAGASIN #" .. storeId .. " : " .. store.name .. " ===", player, 121, 80, 242)
        outputChatBox("  Premier NPC : " .. msToSeconds(store.firstNpcCooldownMin) .. "s - " .. msToSeconds(store.firstNpcCooldownMax) .. "s", player, 255, 255, 255)
        outputChatBox("  NPC suivants : " .. msToSeconds(store.nextNpcCooldownMin) .. "s - " .. msToSeconds(store.nextNpcCooldownMax) .. "s", player, 255, 255, 255)
        outputChatBox("Modifier : /magasincooldown " .. storeId .. " 30 120 60 300", player, 200, 200, 200)
        outputChatBox("Reset : /magasincooldownreset " .. storeId, player, 200, 200, 200)
        outputChatBox(" ", player)
        return
    end

    local fMin = secondsToMs(firstMin)
    local fMax = secondsToMs(firstMax)
    local nMin = secondsToMs(nextMin)
    local nMax = secondsToMs(nextMax)

    if not fMin or not fMax or not nMin or not nMax then
        notify(player, "Usage : /magasincooldown [id] [firstMin] [firstMax] [nextMin] [nextMax]", "warning")
        notify(player, "Exemple : /magasincooldown 1 30 120 60 300", "info")
        return
    end

    if fMin > fMax then fMin, fMax = fMax, fMin end
    if nMin > nMax then nMin, nMax = nMax, nMin end

    updateStore(storeId, "cooldowns", {firstMin = fMin, firstMax = fMax, nextMin = nMin, nextMax = nMax})
    notify(player, "Cooldown magasin #" .. storeId .. " mis a jour : premier " .. firstMin .. "-" .. firstMax .. "s, suivants " .. nextMin .. "-" .. nextMax .. "s.", "success")
end)

addCommandHandler("magasincooldownreset", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasincooldownreset") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasincooldownreset [id]", "warning") end

    local d = getDefaultCooldowns()
    updateStore(storeId, "cooldowns", {firstMin = d.firstMin, firstMax = d.firstMax, nextMin = d.nextMin, nextMax = d.nextMax})
    notify(player, "Cooldown du magasin #" .. storeId .. " reinitialise par defaut.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- PROFILS NPC PAR MAGASIN
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinnpcprofiles", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinnpcprofiles [id]", "warning") end

    local profiles = store.npcProfiles or {}

    outputChatBox(" ", player)
    outputChatBox("=== PROFILS NPC MAGASIN #" .. storeId .. " : " .. store.name .. " ===", player, 121, 80, 242)

    if #profiles == 0 then
        outputChatBox("  Aucun profil. Mode auto : skin aleatoire + produits aleatoires.", player, 200, 200, 200)
    else
        for i, profile in ipairs(profiles) do
            outputChatBox(string.format("  #%d | %s | Skin %s | Produits: %s",
                i,
                profile.name or "Profil sans nom",
                tostring(profile.skin or "?"),
                productsToString(profile.products)
            ), player, 255, 255, 255)
        end
    end

    outputChatBox("Ajouter : /magasinnpcprofileadd " .. storeId .. " [skin] [produits] [nom]", player, 200, 200, 200)
    outputChatBox("Exemple : /magasinnpcprofileadd " .. storeId .. " 34 2,3,6 Client snacks", player, 200, 200, 200)
    outputChatBox(" ", player)
end)

addCommandHandler("magasinnpcprofileadd", function(player, cmd, id, skin, productsStr, ...)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinnpcprofileadd") then return end

    local store, storeId = getStoreOrNotify(player, id)
    skin = tonumber(skin)
    local products = parseProductList(productsStr)
    local name = table.concat({...}, " ")

    if not store or not skin or not products or name == "" then
        notify(player, "Usage : /magasinnpcprofileadd [id] [skin] [produits] [nom]", "warning")
        notify(player, "Exemple : /magasinnpcprofileadd 1 34 2,3,6 Client snacks", "info")
        return
    end

    local ok, err = validateProductIndexes(store, products)
    if not ok then return notify(player, err, "error") end

    local profiles = AMData.deepCopy(store.npcProfiles or {})
    table.insert(profiles, {name = name, skin = skin, products = products})
    updateStore(storeId, "npcProfiles", profiles)

    notify(player, "Profil NPC ajoute au magasin #" .. storeId .. " : " .. name .. " (skin " .. skin .. ").", "success")
end)

addCommandHandler("magasinnpcprofiledel", function(player, cmd, id, profileId)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinnpcprofiledel") then return end

    local store, storeId = getStoreOrNotify(player, id)
    profileId = tonumber(profileId)
    if not store or not profileId then return notify(player, "Usage : /magasinnpcprofiledel [id] [profileId]", "warning") end

    local profiles = AMData.deepCopy(store.npcProfiles or {})
    if profileId < 1 or profileId > #profiles then
        return notify(player, "Profil #" .. profileId .. " introuvable.", "error")
    end

    local removed = table.remove(profiles, profileId)
    updateStore(storeId, "npcProfiles", profiles)
    notify(player, "Profil NPC supprime : " .. (removed.name or "?"), "success")
end)

addCommandHandler("magasinnpcprofileskin", function(player, cmd, id, profileId, skin)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinnpcprofileskin") then return end

    local store, storeId = getStoreOrNotify(player, id)
    profileId = tonumber(profileId)
    skin = tonumber(skin)
    if not store or not profileId or not skin then return notify(player, "Usage : /magasinnpcprofileskin [id] [profileId] [skin]", "warning") end

    local profiles = AMData.deepCopy(store.npcProfiles or {})
    if profileId < 1 or profileId > #profiles then return notify(player, "Profil introuvable.", "error") end

    profiles[profileId].skin = skin
    updateStore(storeId, "npcProfiles", profiles)
    notify(player, "Skin du profil #" .. profileId .. " mis a jour : " .. skin, "success")
end)

addCommandHandler("magasinnpcprofileproducts", function(player, cmd, id, profileId, productsStr)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinnpcprofileproducts") then return end

    local store, storeId = getStoreOrNotify(player, id)
    profileId = tonumber(profileId)
    local products = parseProductList(productsStr)
    if not store or not profileId or not products then return notify(player, "Usage : /magasinnpcprofileproducts [id] [profileId] [produits]", "warning") end

    local ok, err = validateProductIndexes(store, products)
    if not ok then return notify(player, err, "error") end

    local profiles = AMData.deepCopy(store.npcProfiles or {})
    if profileId < 1 or profileId > #profiles then return notify(player, "Profil introuvable.", "error") end

    profiles[profileId].products = products
    updateStore(storeId, "npcProfiles", profiles)
    notify(player, "Produits du profil #" .. profileId .. " mis a jour : " .. productsToString(products), "success")
end)

addCommandHandler("magasinnpcprofilereset", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinnpcprofilereset") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinnpcprofilereset [id]", "warning") end

    updateStore(storeId, "npcProfiles", {})
    notify(player, "Profils NPC du magasin #" .. storeId .. " reinitialises. Mode automatique actif.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- PANIERS
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinpanier", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinpanier") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinpanier [id]", "warning") end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    updateStore(storeId, "basketPermanent", {x = x, y = y, z = z, rot = rot})
    notify(player, "Panier permanent defini pour le magasin #" .. storeId .. " a votre position !", "success")
end)

addCommandHandler("magasinpanierclient", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinpanierclient") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinpanierclient [id]", "warning") end

    local x, y, z = getElementPosition(player)
    updateStore(storeId, "basketClient", {x = x, y = y, z = z})
    notify(player, "Position du panier client definie pour le magasin #" .. storeId .. " !", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- POINTS DE PAUSE
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinpausepoint", function(player, cmd, id, duration)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinpausepoint") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinpausepoint [id] [duree(ms) optionnelle]", "warning") end

    duration = tonumber(duration) or 2000
    duration = AMData.clamp(duration, 500, 10000)

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)

    local points = AMData.deepCopy(store.pausePoints or {})
    table.insert(points, {x = x, y = y, z = z, rot = rot, duration = duration})
    updateStore(storeId, "pausePoints", points)

    notify(player, "Point de pause #" .. #points .. " ajoute au magasin #" .. storeId .. " (" .. duration .. "ms).", "success")
end)

addCommandHandler("magasinpausepointlist", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinpausepointlist [id]", "warning") end

    local points = store.pausePoints or {}
    outputChatBox(" ", player)
    outputChatBox("=== POINTS DE PAUSE DU MAGASIN #" .. storeId .. " ===", player, 121, 80, 242)

    if #points == 0 then
        outputChatBox("  Aucun point de pause. Utilisez /magasinpausepoint " .. storeId, player, 200, 200, 200)
    else
        for i, pt in ipairs(points) do
            outputChatBox(string.format("  #%d | Pos: %s | Rot: %d | Duree: %dms",
                i, AMData.formatPosition(pt.x, pt.y, pt.z), math.floor(pt.rot or 0), pt.duration or 2000), player, 255, 255, 255)
        end
    end

    outputChatBox("Total : " .. #points .. " point(s)", player, 255, 255, 100)
    outputChatBox("Supprimer : /magasinpausepointdel " .. storeId .. " [numero]", player, 200, 200, 200)
    outputChatBox(" ", player)
end)

addCommandHandler("magasinpausepointdel", function(player, cmd, id, num)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinpausepointdel") then return end

    local store, storeId = getStoreOrNotify(player, id)
    num = tonumber(num)
    if not store or not num then return notify(player, "Usage : /magasinpausepointdel [id] [numero]", "warning") end

    local points = AMData.deepCopy(store.pausePoints or {})
    if num < 1 or num > #points then return notify(player, "Numero de point invalide.", "error") end

    table.remove(points, num)
    updateStore(storeId, "pausePoints", points)
    notify(player, "Point de pause #" .. num .. " supprime du magasin #" .. storeId .. ".", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- STATUS
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinstatus", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinstatus [id]", "warning") end

    local paths = getStorePaths(storeId)
    local status = AMData.getStoreStatus(store, paths)

    outputChatBox(" ", player)
    outputChatBox("=== ETAT DU MAGASIN #" .. storeId .. " : " .. store.name .. " ===", player, 121, 80, 242)

    for _, check in ipairs(status.checks) do
        local icon = check.ok and "✓" or "✗"
        local r, g, b = 87, 242, 135
        if not check.ok then
            if check.optional then
                r, g, b = 254, 231, 92
                icon = "○"
            else
                r, g, b = 237, 66, 69
            end
        end
        outputChatBox("  " .. icon .. " " .. check.name, player, r, g, b)
    end

    outputChatBox(" ", player)
    if status.npcReady then
        outputChatBox("  STATUS : ✓ COMPLET (NPC clients fonctionnels)", player, 87, 242, 135)
    elseif status.basicCashierReady then
        outputChatBox("  STATUS : ~ PARTIEL (mode caissier basique uniquement)", player, 254, 231, 92)
        outputChatBox("  Il manque : " .. table.concat(status.missing, ", "), player, 254, 231, 92)
    else
        outputChatBox("  STATUS : ✗ INCOMPLET", player, 237, 66, 69)
        outputChatBox("  Il manque : " .. table.concat(status.missing, ", "), player, 237, 66, 69)
    end

    outputChatBox(" ", player)
end)

-- ═══════════════════════════════════════════════════════════════
-- RESET GLOBAL
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinreset", function(player)
    if not requireAdmin(player) then return end

    local playerName = getPlayerName(player)
    local key = playerName .. ":magasinreset_confirm"
    local now = getTickCount()

    if not lastCommandTime[key] or (now - lastCommandTime[key]) > 10000 then
        lastCommandTime[key] = now
        notify(player, "⚠️ ATTENTION : Cela va SUPPRIMER TOUS les magasins !", "warning")
        notify(player, "Retape /magasinreset dans les 10 secondes pour CONFIRMER.", "warning")
        return
    end

    lastCommandTime[key] = nil

    local storeCount = 0
    local pathCount = 0
    for _, paths in pairs(SP()) do for _ in pairs(paths) do pathCount = pathCount + 1 end end
    for _ in pairs(S()) do storeCount = storeCount + 1 end

    local toDelete = {}
    for storeId in pairs(S()) do table.insert(toDelete, storeId) end
    for _, storeId in ipairs(toDelete) do deleteStore(storeId) end

    notify(player, "RESET TERMINE : " .. storeCount .. " magasin(s) et " .. pathCount .. " path(s) supprimes.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- PATHS - VERSION OPTIMISÉE ENTER/EXIT UNIQUEMENT
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("pathrecord", function(player, cmd, storeId, pathType)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "pathrecord") then return end

    storeId = tonumber(storeId)
    if not storeId or not pathType then
        notify(player, "Usage : /pathrecord [magasinId] [type]", "warning")
        notify(player, "Types utiles : enter, exit", "info")
        notify(player, "Aide visuelle : /pathaide", "info")
        return
    end
    if not S()[storeId] then return notify(player, "Magasin #" .. storeId .. " introuvable.", "error") end

    pathType = string.lower(pathType)
    if not AMData.isValidPathType(pathType) then
        notify(player, "Type invalide : '" .. pathType .. "'", "error")
        notify(player, "Types valides : enter, exit", "info")
        return
    end

    triggerClientEvent(player, "AdminMagasin:startRecording", player, storeId, pathType)
end)

addCommandHandler("pathstop", function(player)
    if not requireAdmin(player) then return end
    triggerClientEvent(player, "AdminMagasin:stopRecording", player)
end)

addCommandHandler("pathlist", function(player, cmd, storeId)
    if not requireAdmin(player) then return end

    outputChatBox(" ", player)

    if storeId then
        storeId = tonumber(storeId)
        if not storeId then return notify(player, "Usage : /pathlist [magasinId]", "warning") end
        if not S()[storeId] then return notify(player, "Magasin #" .. storeId .. " introuvable.", "error") end

        outputChatBox("=== PATHS DU MAGASIN #" .. storeId .. " : " .. S()[storeId].name .. " ===", player, 121, 80, 242)

        local paths = getStorePaths(storeId)
        local count = 0
        for pathId, path in pairs(paths) do
            count = count + 1
            local typeName = AMData.getPathTypeName(path.pathType)
            outputChatBox(string.format("  #%d | %s | %d points | par %s",
                pathId, typeName, #path.data, path.createdBy or "?"), player, 255, 255, 255)
        end
        if count == 0 then outputChatBox("  Aucun path. Utilisez /pathrecord " .. storeId .. " [enter|exit]", player, 200, 200, 200) end
        outputChatBox("Total : " .. count .. " chemin(s)", player, 255, 255, 100)
    else
        outputChatBox("=== TOUS LES PATHS ===", player, 121, 80, 242)
        local totalPaths = 0
        for sId, paths in pairs(SP()) do
            local storeName = S()[sId] and S()[sId].name or "Magasin supprime"
            for pathId, path in pairs(paths) do
                totalPaths = totalPaths + 1
                local typeName = AMData.getPathTypeName(path.pathType)
                outputChatBox(string.format("  #%d | Magasin #%d (%s) | %s | %d pts",
                    pathId, sId, storeName, typeName, #path.data), player, 255, 255, 255)
            end
        end
        if totalPaths == 0 then outputChatBox("  Aucun path enregistre.", player, 200, 200, 200) end
        outputChatBox("Total : " .. totalPaths .. " chemin(s)", player, 255, 255, 100)
    end
    outputChatBox(" ", player)
end)

addCommandHandler("pathdelete", function(player, cmd, pathId)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "pathdelete") then return end

    pathId = tonumber(pathId)
    if not pathId then return notify(player, "Usage : /pathdelete [pathId]", "warning") end

    if deletePath(pathId) then notify(player, "Chemin #" .. pathId .. " supprime.", "success")
    else notify(player, "Chemin #" .. pathId .. " introuvable.", "error") end
end)

addCommandHandler("pathdeleteall", function(player, cmd, storeId)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "pathdeleteall") then return end

    storeId = tonumber(storeId)
    if not storeId then return notify(player, "Usage : /pathdeleteall [magasinId]", "warning") end
    if not S()[storeId] then return notify(player, "Magasin #" .. storeId .. " introuvable.", "error") end

    local count = countPathsForStore(storeId)
    if count == 0 then return notify(player, "Le magasin #" .. storeId .. " n'a aucun chemin.", "warning") end

    deleteAllPaths(storeId)
    notify(player, count .. " chemin(s) du magasin #" .. storeId .. " supprime(s).", "success")
end)

addCommandHandler("pathtest", function(player, cmd, pathId)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "pathtest") then return end

    pathId = tonumber(pathId)
    if not pathId then return notify(player, "Usage : /pathtest [pathId]", "warning") end

    local path = getPathById(pathId)
    if not path or not path.data or #path.data == 0 then return notify(player, "Chemin #" .. pathId .. " introuvable ou vide.", "error") end

    local startPoint = path.data[1]
    local skin = AMData.getRandomSkin()
    local ped = createPed(skin, startPoint.x, startPoint.y, startPoint.z, startPoint.rot or 0)
    if not ped then return notify(player, "Erreur : Impossible de creer le NPC de test.", "error") end

    setElementData(ped, "isJobNPC", true)
    setElementData(ped, "testNPC", true)
    setElementDimension(ped, getElementDimension(player))
    setElementInterior(ped, getElementInterior(player))

    triggerClientEvent(player, "AdminMagasin:testPath", player, ped, path.data)

    local typeName = AMData.getPathTypeName(path.pathType)
    notify(player, "NPC de test cree pour le chemin #" .. pathId .. " (" .. typeName .. ", " .. #path.data .. " points).", "success")
    setTimer(function() if isElement(ped) then destroyElement(ped) end end, 60000, 1)
end)

addCommandHandler("pathshow", function(player, cmd, pathId)
    if not requireAdmin(player) then return end

    pathId = tonumber(pathId)
    if not pathId then return notify(player, "Usage : /pathshow [pathId]", "warning") end

    local path = getPathById(pathId)
    if not path then return notify(player, "Chemin #" .. pathId .. " introuvable.", "error") end

    triggerClientEvent(player, "AdminMagasin:showPath", player, path.data, pathId)
    notify(player, "Visualisation du chemin #" .. pathId .. " activee. /pathhide pour masquer.", "success")
end)

addCommandHandler("pathhide", function(player)
    if not requireAdmin(player) then return end
    triggerClientEvent(player, "AdminMagasin:hidePath", player)
    notify(player, "Visualisation masquee.", "info")
end)

addCommandHandler("pathexport", function(player, cmd, pathId)
    if not requireAdmin(player) then return end

    pathId = tonumber(pathId)
    if not pathId then return notify(player, "Usage : /pathexport [pathId]", "warning") end

    local path = getPathById(pathId)
    if not path then return notify(player, "Chemin #" .. pathId .. " introuvable.", "error") end

    local varName = "path_" .. path.storeId .. "_" .. path.pathType
    local luaString = pathToLuaString(path.data, varName)
    triggerClientEvent(player, "AdminMagasin:copyToClipboard", player, luaString)
    notify(player, "Path #" .. pathId .. " exporte et copie dans le presse-papiers.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- EMPLOYEUR
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("employeurpos", function(player)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "employeurpos") then return end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    moveEmployer(x, y, z, rot)
    notify(player, "NPC Employeur place a votre position !", "success")
end)

addCommandHandler("employeurtp", function(player)
    if not requireAdmin(player) then return end

    local ped = getEmployerPed()
    if ped and isElement(ped) then
        local x, y, z = getElementPosition(ped)
        teleportPlayerSafe(player, x, y, z + 1)
        notify(player, "Teleporte vers le NPC Employeur.", "success")
    else
        notify(player, "L'employeur n'a pas de position definie.", "error")
    end
end)

addCommandHandler("employeurskin", function(player, cmd, skinId)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "employeurskin") then return end

    skinId = tonumber(skinId)
    if not skinId then return notify(player, "Usage : /employeurskin [id du skin]", "warning") end

    changeEmployerSkin(skinId)
    notify(player, "Skin du NPC Employeur change vers " .. skinId, "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- PRODUITS
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinproduits", function(player, cmd, id)
    if not requireAdmin(player) then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinproduits [id]", "warning") end

    local products = store.products
    outputChatBox(" ", player)
    outputChatBox("=== PRODUITS DU MAGASIN #" .. storeId .. " : " .. store.name .. " ===", player, 121, 80, 242)

    if #products == 0 then
        outputChatBox("  Aucun produit configure.", player, 200, 200, 200)
    else
        for i, prod in ipairs(products) do
            local posInfo = (prod.position and prod.position.isSet) and " [POS OK]" or " [POS ✗]"
            outputChatBox(string.format("  %d. %s (model: %d, scale: %.1f)%s", i, prod.name, prod.model, prod.scale or 1.0, posInfo), player, 255, 255, 255)
        end
    end

    outputChatBox("Total : " .. #products .. " produit(s)", player, 255, 255, 100)
    outputChatBox("Ajouter : /magasinaddproduit [id] [model] [nom]", player, 200, 200, 200)
    outputChatBox("Position : /magasinproduitpos [id] [numero]", player, 200, 200, 200)
    outputChatBox(" ", player)
end)

addCommandHandler("magasinaddproduit", function(player, cmd, id, model, ...)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinaddproduit") then return end

    local store, storeId = getStoreOrNotify(player, id)
    model = tonumber(model)
    local name = table.concat({...}, " ")
    if not store or not model or name == "" then
        notify(player, "Usage : /magasinaddproduit [id] [model] [nom]", "warning")
        return
    end

    local products = AMData.deepCopy(store.products)
    table.insert(products, {model = model, name = name, scale = 1.0})
    updateStore(storeId, "products", products)

    notify(player, "Produit '" .. name .. "' ajoute au magasin #" .. storeId .. ".", "success")
    notify(player, "Definir sa position : /magasinproduitpos " .. storeId .. " " .. #products, "info")
end)

addCommandHandler("magasindelproduit", function(player, cmd, id, num)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasindelproduit") then return end

    local store, storeId = getStoreOrNotify(player, id)
    num = tonumber(num)
    if not store or not num then return notify(player, "Usage : /magasindelproduit [id] [numero]", "warning") end

    local products = AMData.deepCopy(store.products)
    if num < 1 or num > #products then return notify(player, "Numero de produit invalide.", "error") end

    local removed = table.remove(products, num)
    updateStore(storeId, "products", products)
    notify(player, "Produit '" .. removed.name .. "' retire.", "success")
end)

addCommandHandler("magasinclearproduits", function(player, cmd, id)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinclearproduits") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store then return notify(player, "Usage : /magasinclearproduits [id]", "warning") end

    local count = #store.products
    updateStore(storeId, "products", {})
    notify(player, count .. " produit(s) supprime(s) du magasin #" .. storeId .. ".", "success")
end)

addCommandHandler("magasinproduitpos", function(player, cmd, id, num)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinproduitpos") then return end

    local store, storeId = getStoreOrNotify(player, id)
    num = tonumber(num)
    if not store or not num then return notify(player, "Usage : /magasinproduitpos [id] [numero]", "warning") end

    local products = AMData.deepCopy(store.products)
    if num < 1 or num > #products then return notify(player, "Numero de produit invalide.", "error") end

    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)

    products[num].position = {x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, isSet = true}
    updateStore(storeId, "products", products)
    notify(player, "Position du produit '" .. products[num].name .. "' definie !", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- STOP CAISSIER
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("stopcaissier", function(player)
    if not requireAdmin(player) then return end

    triggerClientEvent(player, "AdminMagasin:forceExitCashier", player)
    triggerEvent("v1:quitJobCajero", player)
    notify(player, "Mode caissier force a s'arreter.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- AIDE
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinaide", function(player)
    if not requireAdmin(player) then return end

    outputChatBox(" ", player)
    outputChatBox("═════════ ADMIN MAGASIN - AIDE ═════════", player, 121, 80, 242)
    outputChatBox(" ", player)
    outputChatBox("--- PANEL GRAPHIQUE ---", player, 254, 231, 92)
    outputChatBox("  /magasinpanel — Ouvrir le panel graphique", player, 255, 255, 255)
    outputChatBox(" ", player)
    outputChatBox("--- MAGASINS ---", player, 88, 165, 255)
    outputChatBox("  /magasinlist | /magasincreate [nom] | /magasindelete [id]", player, 255, 255, 255)
    outputChatBox("  /magasininfo [id] | /magasinstatus [id] | /magasintp [id]", player, 255, 255, 255)
    outputChatBox("  /magasingoto [id] [magasin|caissier|camera|panier|panierclient]", player, 255, 255, 255)
    outputChatBox("  /magasinrename [id] [nom] | /magasinclone [id]", player, 255, 255, 255)
    outputChatBox(" ", player)
    outputChatBox("--- CONFIGURATION ---", player, 88, 165, 255)
    outputChatBox("  /magasinpos [id] | /magasincaissier [id] | /magasincamera [id]", player, 255, 255, 255)
    outputChatBox("  /magasinpanier [id] | /magasinpanierclient [id]", player, 87, 242, 135)
    outputChatBox("  /magasincooldown [id] [firstMin] [firstMax] [nextMin] [nextMax]", player, 87, 242, 135)
    outputChatBox("  Exemple : /magasincooldown 1 30 120 60 300", player, 200, 200, 200)
    outputChatBox(" ", player)
    outputChatBox("--- PROFILS NPC ---", player, 87, 242, 135)
    outputChatBox("  /magasinnpcprofiles [id]", player, 255, 255, 255)
    outputChatBox("  /magasinnpcprofileadd [id] [skin] [produits] [nom]", player, 255, 255, 255)
    outputChatBox("  /magasinnpcprofiledel [id] [profileId]", player, 255, 255, 255)
    outputChatBox("  /magasinnpcprofileskin [id] [profileId] [skin]", player, 255, 255, 255)
    outputChatBox("  /magasinnpcprofileproducts [id] [profileId] [produits]", player, 255, 255, 255)
    outputChatBox("  /magasinnpcprofilereset [id]", player, 255, 255, 255)
    outputChatBox(" ", player)
    outputChatBox("--- PRODUITS ---", player, 254, 231, 92)
    outputChatBox("  /magasinproduits [id] | /magasinaddproduit [id] [model] [nom]", player, 255, 255, 255)
    outputChatBox("  /magasindelproduit [id] [num] | /magasinproduitpos [id] [num]", player, 255, 255, 255)
    outputChatBox(" ", player)
    outputChatBox("--- CHEMINS NPC ---", player, 87, 242, 135)
    outputChatBox("  /pathrecord [id] [enter|exit] | /pathstop | /pathlist [id?]", player, 255, 255, 255)
    outputChatBox("  /pathdelete [pathId] | /pathtest [pathId] | /pathshow [pathId] | /pathhide", player, 255, 255, 255)
    outputChatBox(" ", player)
    outputChatBox("--- EMPLOYEUR / URGENCE ---", player, 237, 66, 69)
    outputChatBox("  /employeurpos | /employeurtp | /employeurskin [id]", player, 255, 255, 255)
    outputChatBox("  /stopcaissier | /magasinreset", player, 237, 66, 69)
    outputChatBox(" ", player)
    outputChatBox("Types de chemin utiles : enter, exit", player, 200, 200, 200)
    outputChatBox("═════════════════════════════════════════", player, 121, 80, 242)
    outputChatBox(" ", player)
end)

-- ═══════════════════════════════════════════════════════════════
-- EDITEUR VISUEL /magasinedit
-- ═══════════════════════════════════════════════════════════════

addCommandHandler("magasinedit", function(player, cmd, id, targetType, param)
    if not requireAdmin(player) then return end
    if isCommandDuplicated(player, "magasinedit") then return end

    local store, storeId = getStoreOrNotify(player, id)
    if not store or not targetType then
        notify(player, "Usage : /magasinedit [id] [type] [param?]", "warning")
        notify(player, "Types : panier, panierclient, camera, caissier, produit [num]", "info")
        return
    end

    targetType = string.lower(targetType)
    local editData = nil

    if targetType == "panier" or targetType == "basketpermanent" or targetType == "basketperm" then
        if not store.basketPermanent or not store.basketPermanent.isSet then return notify(player, "Panier permanent non defini.", "warning") end
        editData = {
            type = "basketPermanent",
            typeLabel = "Panier Permanent",
            model = 2905,
            useCustomBasket = true,
            pos = {x = store.basketPermanent.x, y = store.basketPermanent.y, z = store.basketPermanent.z, rx = 0, ry = 0, rz = store.basketPermanent.rot or 0},
        }

    elseif targetType == "panierclient" or targetType == "basketclient" then
        if not store.basketClient or not store.basketClient.isSet then return notify(player, "Panier client non defini.", "warning") end
        editData = {
            type = "basketClient",
            typeLabel = "Panier Client (spawn NPC)",
            model = 2905,
            useCustomBasket = true,
            pos = {x = store.basketClient.x, y = store.basketClient.y, z = store.basketClient.z, rx = 0, ry = 0, rz = 0},
        }

    elseif targetType == "camera" then
        if not store.camera or not store.camera.isSet then return notify(player, "Camera non definie.", "warning") end
        editData = {
            type = "camera",
            typeLabel = "Camera POV",
            model = 1338,
            useCustomBasket = false,
            pos = {x = store.camera.x, y = store.camera.y, z = store.camera.z, rx = 0, ry = 0, rz = 0},
            cameraTarget = {x = store.camera.tx, y = store.camera.ty, z = store.camera.tz},
        }

    elseif targetType == "caissier" or targetType == "cashier" then
        if not store.cashier or not store.cashier.isSet then return notify(player, "Caissier non defini.", "warning") end
        editData = {
            type = "cashier",
            typeLabel = "Position Caissier",
            model = 1210,
            useCustomBasket = false,
            pos = {x = store.cashier.x, y = store.cashier.y, z = store.cashier.z, rx = 0, ry = 0, rz = store.cashier.rot or 0},
        }

    elseif targetType == "produit" or targetType == "product" then
        local prodNum = tonumber(param)
        if not prodNum then return notify(player, "Usage : /magasinedit " .. storeId .. " produit [numero]", "warning") end

        local products = store.products or {}
        if prodNum < 1 or prodNum > #products then return notify(player, "Produit #" .. prodNum .. " introuvable.", "error") end

        local product = products[prodNum]
        if not product.position or not product.position.isSet then return notify(player, "Position du produit non definie.", "warning") end

        editData = {
            type = "product",
            typeLabel = "Produit #" .. prodNum .. " : " .. product.name,
            productIndex = prodNum,
            model = product.model,
            useCustomBasket = false,
            scale = product.scale or 1.0,
            pos = {x = product.position.x, y = product.position.y, z = product.position.z, rx = product.position.rx or 0, ry = product.position.ry or 0, rz = product.position.rz or 0},
        }
    else
        notify(player, "Type invalide : '" .. targetType .. "'", "error")
        notify(player, "Types valides : panier, panierclient, camera, caissier, produit [num]", "info")
        return
    end

    triggerClientEvent(player, "AdminMagasin:openEditPanel", player, storeId, editData)
    notify(player, "Panel d'edition ouvert pour : " .. editData.typeLabel, "success")
end)
