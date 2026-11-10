-- ============================================================
-- server/events.lua - Événements serveur AdminMagasin
-- Version clean : sans panel graphique, conserve recorder / visualizer / magasinedit
-- ============================================================

local function S() return _G.stores or {} end

local function checkPermission(player)
    if not player or not isElement(player) then return false end
    if not hasAdminPermission(player) then
        notify(player, "Permission refusee.", "error")
        return false
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- PATHS : recorder / visualizer / export
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:savePath", true)
addEventHandler("AdminMagasin:savePath", root, function(storeId, pathType, pathData)
    if not checkPermission(client) then return end

    storeId = tonumber(storeId)
    if not storeId or not S()[storeId] then
        return notify(client, "Magasin #" .. tostring(storeId) .. " introuvable.", "error")
    end

    if not AMData.isValidPathType(pathType) then
        return notify(client, "Type de path invalide. Types valides : enter, exit.", "error")
    end

    if type(pathData) ~= "table" or #pathData == 0 then
        return notify(client, "Donnees de path invalides.", "error")
    end

    -- PHASE 6: custom account key via core_account (log/DB column).
    local okAcc, caKey = pcall(function() return exports.core_account:getAccountID(client) end)
    if not (okAcc and caKey and caKey ~= '') then
        caKey = getElementData(client, 'core_account:id') or getElementData(client, 'LoginFuturo:accountKey')
    end
    local adminName = (caKey and caKey ~= '' and caKey ~= false) and tostring(caKey) or "unknown"

    local newId = savePath(storeId, pathType, pathData, adminName)
    if newId then
        local typeName = AMData.getPathTypeName(pathType)
        notify(client, "Chemin #" .. newId .. " sauvegarde (" .. typeName .. ", " .. #pathData .. " points).", "success")
    else
        notify(client, "Erreur : chemin trop court (min " .. (AMConfig.recorder.minPoints or 5) .. " points).", "error")
    end
end)

addEvent("AdminMagasin:requestPathData", true)
addEventHandler("AdminMagasin:requestPathData", root, function(pathId)
    if not checkPermission(client) then return end

    pathId = tonumber(pathId)
    local path = pathId and getPathById(pathId)
    if path then
        triggerClientEvent(client, "AdminMagasin:receivePathData", client, path)
    else
        notify(client, "Chemin #" .. tostring(pathId) .. " introuvable.", "error")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- MAGASINEDIT : sauvegarde des positions éditées visuellement
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:saveEditedPosition", true)
addEventHandler("AdminMagasin:saveEditedPosition", root, function(storeId, editType, newPos, extraData)
    if not checkPermission(client) then return end

    storeId = tonumber(storeId)
    if not storeId or not S()[storeId] then
        return notify(client, "Magasin introuvable.", "error")
    end

    if not editType or type(newPos) ~= "table" then
        return notify(client, "Donnees d'edition invalides.", "error")
    end

    local store = S()[storeId]

    if editType == "basketPermanent" then
        updateStore(storeId, "basketPermanent", {
            x = newPos.x,
            y = newPos.y,
            z = newPos.z,
            rot = newPos.rz or 0,
        })
        notify(client, "Panier permanent mis a jour !", "success")

    elseif editType == "basketClient" then
        updateStore(storeId, "basketClient", {
            x = newPos.x,
            y = newPos.y,
            z = newPos.z,
        })
        notify(client, "Panier client mis a jour !", "success")

    elseif editType == "camera" then
        local targetX, targetY, targetZ

        if extraData and extraData.cameraTarget then
            targetX = extraData.cameraTarget.x
            targetY = extraData.cameraTarget.y
            targetZ = extraData.cameraTarget.z
        else
            local rad = math.rad(newPos.rz or 0)
            local dist = 5.0
            targetX = newPos.x - math.sin(rad) * dist
            targetY = newPos.y - math.cos(rad) * dist
            targetZ = newPos.z
        end

        updateStore(storeId, "camera", {
            x = newPos.x,
            y = newPos.y,
            z = newPos.z,
            tx = targetX,
            ty = targetY,
            tz = targetZ,
        })
        notify(client, "Camera mise a jour !", "success")

    elseif editType == "cashier" then
        updateStore(storeId, "cashier", {
            x = newPos.x,
            y = newPos.y,
            z = newPos.z,
            rot = newPos.rz or 0,
        })
        notify(client, "Position caissier mise a jour !", "success")

    elseif editType == "product" then
        local prodIndex = extraData and tonumber(extraData.productIndex)
        if not prodIndex then return notify(client, "Index produit manquant.", "error") end

        local products = AMData.deepCopy(store.products or {})
        if prodIndex < 1 or prodIndex > #products then
            return notify(client, "Produit introuvable.", "error")
        end

        products[prodIndex].position = {
            x = newPos.x,
            y = newPos.y,
            z = newPos.z,
            rx = newPos.rx or 0,
            ry = newPos.ry or 0,
            rz = newPos.rz or 0,
            isSet = true,
        }

        updateStore(storeId, "products", products)
        notify(client, "Position du produit '" .. tostring(products[prodIndex].name) .. "' mise a jour !", "success")
    else
        notify(client, "Type d'edition inconnu : " .. tostring(editType), "error")
        return
    end

    logDebug("Edition sauvegardee : magasin #" .. storeId .. " type " .. tostring(editType))
end)

-- ═══════════════════════════════════════════════════════════════
-- DATA POUR HOOK CAISSIER CLIENT
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:requestAllStoresData", true)
addEventHandler("AdminMagasin:requestAllStoresData", root, function()
    if not client or not isElement(client) then return end

    local storesData = {}
    for id, store in pairs(S()) do
        storesData[id] = {
            id = id,
            name = store.name,
            pos = store.pos,
            cashier = store.cashier,
            camera = store.camera,
            basketPermanent = store.basketPermanent,
            basketClient = store.basketClient,
            products = store.products,
            pausePoints = store.pausePoints,
            maxNPC = store.maxNPC,
            salary = store.salary,
            firstNpcCooldownMin = store.firstNpcCooldownMin,
            firstNpcCooldownMax = store.firstNpcCooldownMax,
            nextNpcCooldownMin = store.nextNpcCooldownMin,
            nextNpcCooldownMax = store.nextNpcCooldownMax,
            npcProfiles = store.npcProfiles,
        }
    end

    triggerClientEvent(client, "AdminMagasin:receiveAllStoresData", client, storesData)
end)
