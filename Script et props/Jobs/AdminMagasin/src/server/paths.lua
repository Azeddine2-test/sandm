-- ============================================================
-- server/paths.lua - Gestion des chemins NPC
-- Sauvegarde, chargement, suppression des paths en SQLite
-- ============================================================

local storePaths = {}

-- ═══════════════════════════════════════════════════════════════
-- 💾 CRUD PATHS
-- ═══════════════════════════════════════════════════════════════

--- Charger tous les paths depuis la DB
function loadPaths()
    local database = getDB()
    if not database then
        log("ERREUR : DB non disponible pour charger les paths.", "ERROR")
        return
    end
    
    storePaths = {}
    local query = dbQuery(database, "SELECT * FROM store_paths")
    local results = dbPoll(query, -1)
    
    if results then
        for _, row in ipairs(results) do
            if not storePaths[row.store_id] then
                storePaths[row.store_id] = {}
            end
            
            local pathData = fromJSON(row.path_data)
            if pathData and #pathData > 0 then
                storePaths[row.store_id][row.id] = {
                    id = row.id,
                    storeId = row.store_id,
                    pathType = row.path_type,
                    data = pathData,
                    createdBy = row.created_by,
                    createdAt = row.created_at,
                }
            else
                log("ATTENTION : Path #" .. row.id .. " a des donnees invalides, ignore.", "WARNING")
            end
        end
    end
    
    local totalPaths = 0
    for _, paths in pairs(storePaths) do
        for _ in pairs(paths) do
            totalPaths = totalPaths + 1
        end
    end
    
    log(totalPaths .. " chemin(s) charge(s).")
    
    -- Mettre à jour la référence globale
    _G.storePaths = storePaths
end

--- Sauvegarder un nouveau path
function savePath(storeId, pathType, pathData, adminName)
    local database = getDB()
    if not database then return nil end
    if not storeId or not pathType or not pathData then return nil end
    
    local minPoints = AMConfig.recorder.minPoints or 5
    if #pathData < minPoints then
        log("Path trop court (" .. #pathData .. " points, min " .. minPoints .. ")", "WARNING")
        return nil
    end
    
    local maxPoints = AMConfig.recorder.maxPoints or 500
    if #pathData > maxPoints then
        log("Path trop long (" .. #pathData .. " points, max " .. maxPoints .. "), tronque.", "WARNING")
        -- Tronquer
        local truncated = {}
        for i = 1, maxPoints do
            table.insert(truncated, pathData[i])
        end
        pathData = truncated
    end
    
    local timestamp = getRealTime().timestamp
    local jsonData = toJSON(pathData)
    
    if not jsonData or jsonData == "" then
        log("ERREUR : Impossible de convertir les donnees du path en JSON.", "ERROR")
        return nil
    end
    
    dbExec(database, [[
        INSERT INTO store_paths (store_id, path_type, path_data, created_by, created_at)
        VALUES (?, ?, ?, ?, ?)
    ]], storeId, pathType, jsonData, adminName, timestamp)
    
    local qid = dbQuery(database, "SELECT last_insert_rowid() as id")
    local res = dbPoll(qid, -1)
    local newId = res and res[1] and res[1].id or 0
    
    if newId == 0 then
        log("ERREUR : Impossible de recuperer l'ID du nouveau path.", "ERROR")
        return nil
    end
    
    if not storePaths[storeId] then
        storePaths[storeId] = {}
    end
    
    storePaths[storeId][newId] = {
        id = newId,
        storeId = storeId,
        pathType = pathType,
        data = pathData,
        createdBy = adminName,
        createdAt = timestamp,
    }
    
    _G.storePaths = storePaths
    
    log("Path #" .. newId .. " cree pour magasin #" .. storeId .. " (type: " .. pathType .. ", " .. #pathData .. " points)")
    
    -- 🔥 Injecter le path dans SystemTrabajos
    if _G.syncPathToSystemTrabajos then
        _G.syncPathToSystemTrabajos(storeId, pathType, pathData)
    end
    
    return newId
end

--- Supprimer un path
function deletePath(pathId)
    local database = getDB()
    if not database then return false end
    
    for storeId, paths in pairs(storePaths) do
        if paths[pathId] then
            local pathType = paths[pathId].pathType
            dbExec(database, "DELETE FROM store_paths WHERE id = ?", pathId)
            paths[pathId] = nil
            
            -- Si plus de paths pour ce magasin, nettoyer
            if AMData.countTable(paths) == 0 then
                storePaths[storeId] = nil
            end
            
            _G.storePaths = storePaths
            log("Path #" .. pathId .. " (type: " .. pathType .. ") supprime du magasin #" .. storeId)
            
            -- 🔥 Restaurer le path d'origine dans SystemTrabajos (si hardcodé)
            if _G.restoreOriginalPath then
                _G.restoreOriginalPath(storeId, pathType)
            end
            
            return true
        end
    end
    return false
end

--- Supprimer tous les paths d'un magasin
function deleteAllPaths(storeId)
    local database = getDB()
    if not database then return false end
    
    local count = countPathsForStore(storeId)
    dbExec(database, "DELETE FROM store_paths WHERE store_id = ?", storeId)
    
    -- Récupérer les types avant de supprimer
    local types = {}
    if storePaths[storeId] then
        for _, path in pairs(storePaths[storeId]) do
            table.insert(types, path.pathType)
        end
    end
    
    storePaths[storeId] = nil
    _G.storePaths = storePaths
    
    -- Restaurer tous les paths d'origine
    if _G.restoreOriginalPath then
        for _, pType in ipairs(types) do
            _G.restoreOriginalPath(storeId, pType)
        end
    end
    
    log(count .. " path(s) du magasin #" .. storeId .. " supprimes.")
    return true
end

--- Obtenir tous les paths d'un magasin
function getStorePaths(storeId)
    return storePaths[storeId] or {}
end

--- Obtenir TOUS les paths
function getAllPaths()
    return storePaths
end

--- Obtenir un path par son ID
function getPathById(pathId)
    pathId = tonumber(pathId)
    if not pathId then return nil end
    
    for _, paths in pairs(storePaths) do
        if paths[pathId] then
            return paths[pathId]
        end
    end
    return nil
end

--- Compter les paths d'un magasin
function countPathsForStore(storeId)
    local count = 0
    if storePaths[storeId] then
        for _ in pairs(storePaths[storeId]) do
            count = count + 1
        end
    end
    return count
end

--- Obtenir les paths d'un type spécifique pour un magasin
function getStorePathsByType(storeId, pathType)
    local result = {}
    if storePaths[storeId] then
        for pathId, path in pairs(storePaths[storeId]) do
            if path.pathType == pathType then
                result[pathId] = path
            end
        end
    end
    return result
end

--- Obtenir un path aléatoire d'un type spécifique pour un magasin
function getRandomPathByType(storeId, pathType)
    local paths = getStorePathsByType(storeId, pathType)
    local pathList = {}
    for _, path in pairs(paths) do
        table.insert(pathList, path)
    end
    if #pathList == 0 then return nil end
    return pathList[math.random(#pathList)]
end

--- Convertir un path au format Lua (pour export/copie)
function pathToLuaString(pathData, varName)
    if not pathData or type(pathData) ~= "table" or #pathData == 0 then
        return "-- Path vide"
    end
    
    varName = varName or "myPath"
    local output = "local " .. varName .. " = {\n"
    
    for _, point in ipairs(pathData) do
        output = output .. string.format(
            "    {x=%.3f, y=%.3f, z=%.3f, rot=%.3f, time=%d, moveState=\"%s\"},\n",
            point.x or 0, point.y or 0, point.z or 0, 
            point.rot or 0, point.time or 0, 
            point.moveState or "walk"
        )
    end
    
    output = output .. "}\n"
    return output
end

-- ═══════════════════════════════════════════════════════════════
-- 📤 EXPOSER GLOBALEMENT
-- ═══════════════════════════════════════════════════════════════

_G.storePaths = storePaths
_G.savePath = savePath
_G.deletePath = deletePath
_G.deleteAllPaths = deleteAllPaths
_G.getStorePaths = getStorePaths
_G.getAllPaths = getAllPaths
_G.getPathById = getPathById
_G.countPathsForStore = countPathsForStore
_G.getStorePathsByType = getStorePathsByType
_G.getRandomPathByType = getRandomPathByType
_G.pathToLuaString = pathToLuaString
_G.loadPaths = loadPaths