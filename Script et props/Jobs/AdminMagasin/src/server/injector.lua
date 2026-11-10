-- ============================================================
-- server/injector.lua - Liaison légère avec SystemTrabajos
-- Version clean : sans sync périodique, sans logs spam, sans ancien hardcoded
-- ============================================================

local function S() return _G.stores or {} end

-- ═══════════════════════════════════════════════════════════════
-- VÉRIFICATION DE SYSTEMTRABAJOS
-- ═══════════════════════════════════════════════════════════════

local function isSystemTrabajosRunning()
    local target = AMConfig and AMConfig.integration and AMConfig.integration.targetResource or "SystemTrabajos"
    local res = getResourceFromName(target)
    return res and getResourceState(res) == "running"
end

-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATION DE CHANGEMENT
-- SystemTrabajos lit les magasins via exports AdminMagasin.
-- On n'injecte plus de magasins hardcodés, on notifie seulement qu'il faut rebuild.
-- ═══════════════════════════════════════════════════════════════

function notifyStoresChanged()
    if not isSystemTrabajosRunning() then return end
    triggerEvent("AdminMagasin:notifyStoresChanged", root)
    logDebug("SystemTrabajos notifie du changement de magasins.")
end

-- ═══════════════════════════════════════════════════════════════
-- EXPORT SIMPLE POUR SYSTEMTRABAJOS / i9_interaction
-- ═══════════════════════════════════════════════════════════════

function getAllStoresSimple()
    local result = {}

    for id, store in pairs(S()) do
        if store and store.pos then
            result[id] = {
                id = id,
                name = store.name,
                pos = {
                    x = store.pos.x,
                    y = store.pos.y,
                    z = store.pos.z,
                },
                type = store.type,
                maxNPC = store.maxNPC,
                firstNpcCooldownMin = store.firstNpcCooldownMin,
                firstNpcCooldownMax = store.firstNpcCooldownMax,
                nextNpcCooldownMin = store.nextNpcCooldownMin,
                nextNpcCooldownMax = store.nextNpcCooldownMax,
            }
        end
    end

    return result
end

-- ═══════════════════════════════════════════════════════════════
-- COMPATIBILITÉ ANCIENS APPELS
-- Ces fonctions restent exposées pour éviter de casser d'anciens appels,
-- mais elles ne font plus d'injection hardcodée.
-- ═══════════════════════════════════════════════════════════════

function syncStoreToSystemTrabajos(storeId)
    notifyStoresChanged()
    logDebug("syncStoreToSystemTrabajos appele pour magasin #" .. tostring(storeId) .. " (mode clean : notify uniquement).")
end

function syncAllStoresToSystemTrabajos()
    notifyStoresChanged()
    logDebug("syncAllStoresToSystemTrabajos appele (mode clean : notify uniquement).")
end

function syncPathToSystemTrabajos(storeId, pathType, pathData)
    notifyStoresChanged()
    logDebug("syncPathToSystemTrabajos appele pour magasin #" .. tostring(storeId) .. " type " .. tostring(pathType) .. " (mode clean : notify uniquement).")
end

function syncAllPathsToSystemTrabajos()
    notifyStoresChanged()
    logDebug("syncAllPathsToSystemTrabajos appele (mode clean : notify uniquement).")
end

function restoreOriginalPath(storeId, pathType)
    logDebug("restoreOriginalPath ignore en mode clean pour magasin #" .. tostring(storeId) .. " type " .. tostring(pathType) .. ".")
end

-- ═══════════════════════════════════════════════════════════════
-- DEMANDE MANUELLE DE SYNC CLIENT/SERVEUR
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:requestSync", true)
addEventHandler("AdminMagasin:requestSync", root, function()
    if not client or not isElement(client) then return end
    notifyStoresChanged()
end)

-- Pas de timer périodique ici.
-- Les mises à jour passent par notifyStoresChanged() après create/update/delete/path save.

-- ═══════════════════════════════════════════════════════════════
-- EXPOSITION GLOBALE
-- ═══════════════════════════════════════════════════════════════

_G.syncStoreToSystemTrabajos = syncStoreToSystemTrabajos
_G.syncAllStoresToSystemTrabajos = syncAllStoresToSystemTrabajos
_G.syncPathToSystemTrabajos = syncPathToSystemTrabajos
_G.syncAllPathsToSystemTrabajos = syncAllPathsToSystemTrabajos
_G.restoreOriginalPath = restoreOriginalPath
_G.isSystemTrabajosRunning = isSystemTrabajosRunning
_G.notifyStoresChanged = notifyStoresChanged
_G.getAllStoresSimple = getAllStoresSimple
