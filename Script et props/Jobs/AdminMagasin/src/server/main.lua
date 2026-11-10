-- ============================================================
-- server/main.lua - Base de données + CRUD Magasins
-- Version optimisée : cooldown random NPC + profils NPC
-- Option B : 100% custom, IDs commencent à 1
-- ============================================================

local db = nil
local employerPed = nil

_G.stores = _G.stores or {}
_G.storePaths = _G.storePaths or {}

-- ═══════════════════════════════════════════════════════════════
-- UTILITAIRES INTERNES
-- ═══════════════════════════════════════════════════════════════

function log(message, level)
    if AMConfig.debug.logToConsole then
        outputServerLog("[AdminMagasin] " .. (level or "") .. " " .. tostring(message))
    end
end

function logDebug(message)
    if AMConfig.debug.enabled and AMConfig.debug.verbose then
        outputServerLog("[AdminMagasin DEBUG] " .. tostring(message))
    end
end

function notify(player, message, nType)
    if not player or not isElement(player) then return end
    nType = nType or "info"

    local fuNotifyAvailable = false
    if AMConfig.notifications.useFUNotify then
        local res = getResourceFromName("[FU]Notify")
        if res and getResourceState(res) == "running" then
            fuNotifyAvailable = true
        end
    end

    if fuNotifyAvailable then
        exports["[FU]Notify"]:notify(player, message, nType)
    elseif AMConfig.notifications.fallbackToChatBox then
        local colors = {
            success = {87, 242, 135},
            error   = {237, 66, 69},
            info    = {88, 165, 255},
            warning = {254, 231, 92},
            aviso   = {254, 231, 92},
            infos   = {88, 165, 255},
        }
        local c = colors[nType] or colors.info
        outputChatBox("[AdminMagasin] " .. tostring(message), player, c[1], c[2], c[3])
    end
end

function hasAdminPermission(player)
    if not player or not isElement(player) or getElementType(player) ~= "player" then return false end

    -- AdminMagasin est réservé au niveau 6+, ET uniquement pendant /aduty.
    -- Refus fermé si core_staff ou l'un de ses exports est indisponible :
    -- aucun fallback de rang ne doit contourner la règle du service.
    local coreRes = getResourceFromName("core_staff")
    if not coreRes or getResourceState(coreRes) ~= "running" then return false end

    local okLevel, niveau = pcall(function()
        return exports.core_staff:hasStaffLevel(player, 6)
    end)
    if not (okLevel and niveau == true) then return false end

    local okDuty, enService = pcall(function()
        return exports.core_staff:isOnDuty(player)
    end)
    return okDuty and enService == true
end

local function safeFromJSON(value, fallback)
    if not value or value == "" then return fallback end
    local decoded = fromJSON(value)
    if decoded == nil then return fallback end
    return decoded
end

local function clampCooldownMs(value, fallback)
    value = tonumber(value) or fallback
    value = math.floor(value)
    if value < 0 then value = fallback end
    -- Sécurité : max 24h pour éviter erreurs admin
    if value > 86400000 then value = 86400000 end
    return value
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
-- BASE DE DONNÉES — MIGRATION + INIT
-- ═══════════════════════════════════════════════════════════════

local function backupOldDatabase()
    local dbFile = AMConfig.database.file
    if not fileExists(dbFile) then
        log("Aucune ancienne base de donnees a migrer.")
        return
    end

    local tempDb = dbConnect("sqlite", dbFile)
    if not tempDb then return end

    local q = dbQuery(tempDb, "SELECT name FROM sqlite_master WHERE type='table' AND name='stores'")
    local res = dbPoll(q, -1)

    if not res or #res == 0 then
        if isElement(tempDb) then destroyElement(tempDb) end
        return
    end

    local qCol = dbQuery(tempDb, "PRAGMA table_info(stores)")
    local cols = dbPoll(qCol, -1)
    local hasNewSchema = false

    if cols then
        for _, col in ipairs(cols) do
            if col.name == "basket_permanent_x" then
                hasNewSchema = true
                break
            end
        end
    end

    if isElement(tempDb) then destroyElement(tempDb) end

    if hasNewSchema then
        log("Nouvelle base de donnees deja en place, migration destructive inutile.")
        return
    end

    local time = getRealTime()
    local timestamp = string.format("%04d%02d%02d_%02d%02d%02d",
        time.year + 1900, time.month + 1, time.monthday,
        time.hour, time.minute, time.second)
    local backupPath = dbFile .. ".backup_" .. timestamp

    if fileCopy(dbFile, backupPath) then
        log("============================================")
        log("MIGRATION DETECTEE : Ancienne base sauvegardee dans " .. backupPath)
        log("============================================")

        if fileDelete(dbFile) then
            log("Ancienne base supprimee. Nouvelle base en cours de creation...")
        else
            log("ERREUR : Impossible de supprimer l'ancienne base !", "ERROR")
        end
    else
        log("ERREUR : Impossible de sauvegarder l'ancienne base !", "ERROR")
    end
end

local function tableHasColumn(tableName, columnName)
    if not db then return false end

    local q = dbQuery(db, "PRAGMA table_info(" .. tableName .. ")")
    local cols = dbPoll(q, -1)
    if not cols then return false end

    for _, col in ipairs(cols) do
        if col.name == columnName then return true end
    end

    return false
end

local function ensureColumn(tableName, columnName, definition)
    if tableHasColumn(tableName, columnName) then return true end

    local sql = "ALTER TABLE " .. tableName .. " ADD COLUMN " .. columnName .. " " .. definition
    local ok = dbExec(db, sql)
    if ok then
        log("Migration DB : colonne ajoutee " .. tableName .. "." .. columnName)
    else
        log("ERREUR migration DB : impossible d'ajouter " .. tableName .. "." .. columnName, "ERROR")
    end
    return ok
end

local function initDatabase()
    backupOldDatabase()

    db = dbConnect("sqlite", AMConfig.database.file)
    if not db then
        log("ERREUR : Impossible de se connecter a la base de donnees !", "ERROR")
        return false
    end

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS stores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            pos_z REAL NOT NULL,
            cashier_x REAL,
            cashier_y REAL,
            cashier_z REAL,
            cashier_rot REAL DEFAULT 0,
            cashier_set INTEGER DEFAULT 0,
            cam_x REAL,
            cam_y REAL,
            cam_z REAL,
            cam_tx REAL,
            cam_ty REAL,
            cam_tz REAL,
            cam_set INTEGER DEFAULT 0,
            basket_permanent_x REAL,
            basket_permanent_y REAL,
            basket_permanent_z REAL,
            basket_permanent_rot REAL DEFAULT 0,
            basket_permanent_set INTEGER DEFAULT 0,
            basket_client_x REAL,
            basket_client_y REAL,
            basket_client_z REAL,
            basket_client_set INTEGER DEFAULT 0,
            max_npc INTEGER DEFAULT 1,
            salary_min INTEGER DEFAULT 10,
            salary_max INTEGER DEFAULT 30,
            products TEXT,
            pause_points TEXT,
            first_npc_cooldown_min INTEGER DEFAULT 30000,
            first_npc_cooldown_max INTEGER DEFAULT 120000,
            next_npc_cooldown_min INTEGER DEFAULT 60000,
            next_npc_cooldown_max INTEGER DEFAULT 300000,
            npc_profiles TEXT,
            created_by TEXT,
            created_at INTEGER,
            modified_at INTEGER
        )
    ]])

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS store_paths (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER NOT NULL,
            path_type TEXT NOT NULL,
            path_data TEXT NOT NULL,
            created_by TEXT,
            created_at INTEGER
        )
    ]])

    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS employer_position (
            id INTEGER PRIMARY KEY DEFAULT 1,
            pos_x REAL NOT NULL DEFAULT 0,
            pos_y REAL NOT NULL DEFAULT 0,
            pos_z REAL NOT NULL DEFAULT 0,
            rot REAL DEFAULT 0,
            skin INTEGER DEFAULT 187
        )
    ]])

    -- Migrations non destructives pour les anciennes DB déjà au nouveau schéma.
    ensureColumn("stores", "first_npc_cooldown_min", "INTEGER DEFAULT 30000")
    ensureColumn("stores", "first_npc_cooldown_max", "INTEGER DEFAULT 120000")
    ensureColumn("stores", "next_npc_cooldown_min", "INTEGER DEFAULT 60000")
    ensureColumn("stores", "next_npc_cooldown_max", "INTEGER DEFAULT 300000")
    ensureColumn("stores", "npc_profiles", "TEXT")

    log("Base de donnees initialisee avec succes.")
    return true
end

function getDB()
    return db
end

-- ═══════════════════════════════════════════════════════════════
-- CHARGEMENT DES MAGASINS
-- ═══════════════════════════════════════════════════════════════

local function loadStoreFromRow(row)
    local defaults = getDefaultCooldowns()

    local firstMin = clampCooldownMs(row.first_npc_cooldown_min, defaults.firstMin)
    local firstMax = clampCooldownMs(row.first_npc_cooldown_max, defaults.firstMax)
    local nextMin  = clampCooldownMs(row.next_npc_cooldown_min, defaults.nextMin)
    local nextMax  = clampCooldownMs(row.next_npc_cooldown_max, defaults.nextMax)

    if firstMin > firstMax then firstMin, firstMax = firstMax, firstMin end
    if nextMin > nextMax then nextMin, nextMax = nextMax, nextMin end

    return {
        id = row.id,
        dbId = row.id,
        type = AMData.storeTypes.CUSTOM,
        name = row.name,
        pos = {x = row.pos_x, y = row.pos_y, z = row.pos_z},

        cashier = {
            x = row.cashier_x or row.pos_x,
            y = row.cashier_y or row.pos_y,
            z = row.cashier_z or row.pos_z,
            rot = row.cashier_rot or 0,
            isSet = (row.cashier_set == 1),
        },

        camera = {
            x = row.cam_x,
            y = row.cam_y,
            z = row.cam_z,
            tx = row.cam_tx,
            ty = row.cam_ty,
            tz = row.cam_tz,
            isSet = (row.cam_set == 1),
        },

        basketPermanent = {
            x = row.basket_permanent_x,
            y = row.basket_permanent_y,
            z = row.basket_permanent_z,
            rot = row.basket_permanent_rot or 0,
            isSet = (row.basket_permanent_set == 1),
        },

        basketClient = {
            x = row.basket_client_x,
            y = row.basket_client_y,
            z = row.basket_client_z,
            isSet = (row.basket_client_set == 1),
        },

        -- Compatibilité : conservé, mais le nouveau SystemTrabajos utilise 1 NPC actif max.
        maxNPC = row.max_npc or AMConfig.defaults.maxNPC or 1,

        salary = {
            min = row.salary_min or 10,
            max = row.salary_max or 30,
        },

        products = safeFromJSON(row.products, AMData.deepCopy(AMConfig.defaults.products)),
        pausePoints = safeFromJSON(row.pause_points, {}),

        firstNpcCooldownMin = firstMin,
        firstNpcCooldownMax = firstMax,
        nextNpcCooldownMin = nextMin,
        nextNpcCooldownMax = nextMax,
        npcProfiles = safeFromJSON(row.npc_profiles, AMData.deepCopy(AMConfig.defaults.npcProfiles or {})),

        createdBy = row.created_by or "unknown",
        modifiedAt = row.modified_at,
        marker = nil,
        blip = nil,
    }
end

function loadAllStores()
    for k in pairs(_G.stores) do _G.stores[k] = nil end

    local query = dbQuery(db, "SELECT * FROM stores ORDER BY id ASC")
    local results = dbPoll(query, -1)

    if results then
        for _, row in ipairs(results) do
            local store = loadStoreFromRow(row)
            _G.stores[store.id] = store
        end
    end

    local total = AMData.countTable(_G.stores)
    log(total .. " magasin(s) charge(s).")
    return _G.stores
end

-- ═══════════════════════════════════════════════════════════════
-- CRUD MAGASINS
-- ═══════════════════════════════════════════════════════════════

function createStore(name, x, y, z, adminName)
    local timestamp = getRealTime().timestamp
    local defaults = getDefaultCooldowns()

    local productsJSON = toJSON(AMConfig.defaults.products)
    local pausePointsJSON = toJSON({})
    local npcProfilesJSON = toJSON(AMConfig.defaults.npcProfiles or {})

    dbExec(db, [[
        INSERT INTO stores (
            name, pos_x, pos_y, pos_z,
            cashier_x, cashier_y, cashier_z, cashier_set, cam_set,
            basket_permanent_set, basket_client_set,
            max_npc, salary_min, salary_max,
            products, pause_points,
            first_npc_cooldown_min, first_npc_cooldown_max,
            next_npc_cooldown_min, next_npc_cooldown_max,
            npc_profiles,
            created_by, created_at, modified_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
        name, x, y, z,
        x, y, z,
        AMConfig.defaults.maxNPC or 1,
        AMConfig.defaults.salary.min, AMConfig.defaults.salary.max,
        productsJSON, pausePointsJSON,
        defaults.firstMin, defaults.firstMax,
        defaults.nextMin, defaults.nextMax,
        npcProfilesJSON,
        adminName, timestamp, timestamp
    )

    local qid = dbQuery(db, "SELECT last_insert_rowid() as id")
    local res = dbPoll(qid, -1)
    local storeId = res and res[1] and res[1].id or 0

    if storeId == 0 then
        log("ERREUR : Impossible de creer le magasin en DB", "ERROR")
        return nil
    end

    _G.stores[storeId] = {
        id = storeId,
        dbId = storeId,
        type = AMData.storeTypes.CUSTOM,
        name = name,
        pos = {x = x, y = y, z = z},
        cashier = {x = x, y = y, z = z, rot = 0, isSet = false},
        camera = {x = nil, y = nil, z = nil, tx = nil, ty = nil, tz = nil, isSet = false},
        basketPermanent = {x = nil, y = nil, z = nil, rot = 0, isSet = false},
        basketClient = {x = nil, y = nil, z = nil, isSet = false},
        maxNPC = AMConfig.defaults.maxNPC or 1,
        salary = {min = AMConfig.defaults.salary.min, max = AMConfig.defaults.salary.max},
        products = AMData.deepCopy(AMConfig.defaults.products),
        pausePoints = {},
        firstNpcCooldownMin = defaults.firstMin,
        firstNpcCooldownMax = defaults.firstMax,
        nextNpcCooldownMin = defaults.nextMin,
        nextNpcCooldownMax = defaults.nextMax,
        npcProfiles = AMData.deepCopy(AMConfig.defaults.npcProfiles or {}),
        createdBy = adminName,
        modifiedAt = timestamp,
        marker = nil,
        blip = nil,
    }

    createStoreMarker(storeId)
    log("Magasin #" .. storeId .. " '" .. name .. "' cree par " .. adminName)

    if _G.notifyStoresChanged then _G.notifyStoresChanged() end

    return storeId
end

function deleteStore(storeId)
    if not _G.stores[storeId] then return false end

    local store = _G.stores[storeId]

    if store.marker and isElement(store.marker) then destroyElement(store.marker) end
    if store.blip and isElement(store.blip) then destroyElement(store.blip) end

    if store.dbId then
        dbExec(db, "DELETE FROM stores WHERE id = ?", store.dbId)
        dbExec(db, "DELETE FROM store_paths WHERE store_id = ?", storeId)
    end

    local name = store.name
    _G.stores[storeId] = nil

    if _G.storePaths[storeId] then _G.storePaths[storeId] = nil end

    log("Magasin #" .. storeId .. " '" .. name .. "' supprime.")

    if _G.notifyStoresChanged then _G.notifyStoresChanged() end

    return true
end

function updateStore(storeId, field, value)
    if not _G.stores[storeId] then return false end

    local store = _G.stores[storeId]
    local timestamp = getRealTime().timestamp

    if not store.dbId then
        log("ERREUR : Magasin #" .. storeId .. " n'a pas de dbId", "ERROR")
        return false
    end

    if field == "name" then
        dbExec(db, "UPDATE stores SET name = ?, modified_at = ? WHERE id = ?", value, timestamp, store.dbId)
        store.name = value

    elseif field == "pos" then
        dbExec(db, "UPDATE stores SET pos_x = ?, pos_y = ?, pos_z = ?, modified_at = ? WHERE id = ?",
            value.x, value.y, value.z, timestamp, store.dbId)
        store.pos = value
        createStoreMarker(storeId)

    elseif field == "maxNPC" then
        -- Compatibilité ancienne commande. Le système optimisé utilise 1 NPC actif max.
        local v = AMData.clamp(tonumber(value) or 1, 1, 1)
        dbExec(db, "UPDATE stores SET max_npc = ?, modified_at = ? WHERE id = ?", v, timestamp, store.dbId)
        store.maxNPC = v

    elseif field == "salaryMin" then
        local v = math.max(1, tonumber(value) or 10)
        dbExec(db, "UPDATE stores SET salary_min = ?, modified_at = ? WHERE id = ?", v, timestamp, store.dbId)
        store.salary.min = v

    elseif field == "salaryMax" then
        local v = math.max(1, tonumber(value) or 30)
        dbExec(db, "UPDATE stores SET salary_max = ?, modified_at = ? WHERE id = ?", v, timestamp, store.dbId)
        store.salary.max = v

    elseif field == "cashier" then
        dbExec(db, [[UPDATE stores SET cashier_x = ?, cashier_y = ?, cashier_z = ?,
            cashier_rot = ?, cashier_set = 1, modified_at = ? WHERE id = ?]],
            value.x, value.y, value.z, value.rot or 0, timestamp, store.dbId)
        value.isSet = true
        store.cashier = value

    elseif field == "camera" then
        dbExec(db, [[UPDATE stores SET cam_x = ?, cam_y = ?, cam_z = ?,
            cam_tx = ?, cam_ty = ?, cam_tz = ?, cam_set = 1, modified_at = ? WHERE id = ?]],
            value.x, value.y, value.z, value.tx, value.ty, value.tz, timestamp, store.dbId)
        value.isSet = true
        store.camera = value

    elseif field == "basketPermanent" then
        dbExec(db, [[UPDATE stores SET basket_permanent_x = ?, basket_permanent_y = ?,
            basket_permanent_z = ?, basket_permanent_rot = ?, basket_permanent_set = 1,
            modified_at = ? WHERE id = ?]],
            value.x, value.y, value.z, value.rot or 0, timestamp, store.dbId)
        value.isSet = true
        store.basketPermanent = value

    elseif field == "basketClient" then
        dbExec(db, [[UPDATE stores SET basket_client_x = ?, basket_client_y = ?,
            basket_client_z = ?, basket_client_set = 1,
            modified_at = ? WHERE id = ?]],
            value.x, value.y, value.z, timestamp, store.dbId)
        value.isSet = true
        store.basketClient = value

    elseif field == "products" then
        dbExec(db, "UPDATE stores SET products = ?, modified_at = ? WHERE id = ?",
            toJSON(value), timestamp, store.dbId)
        store.products = value

    elseif field == "pausePoints" then
        dbExec(db, "UPDATE stores SET pause_points = ?, modified_at = ? WHERE id = ?",
            toJSON(value), timestamp, store.dbId)
        store.pausePoints = value

    elseif field == "cooldowns" then
        local defaults = getDefaultCooldowns()
        local firstMin = clampCooldownMs(value.firstMin, defaults.firstMin)
        local firstMax = clampCooldownMs(value.firstMax, defaults.firstMax)
        local nextMin  = clampCooldownMs(value.nextMin, defaults.nextMin)
        local nextMax  = clampCooldownMs(value.nextMax, defaults.nextMax)

        if firstMin > firstMax then firstMin, firstMax = firstMax, firstMin end
        if nextMin > nextMax then nextMin, nextMax = nextMax, nextMin end

        dbExec(db, [[UPDATE stores SET first_npc_cooldown_min = ?, first_npc_cooldown_max = ?,
            next_npc_cooldown_min = ?, next_npc_cooldown_max = ?, modified_at = ? WHERE id = ?]],
            firstMin, firstMax, nextMin, nextMax, timestamp, store.dbId)

        store.firstNpcCooldownMin = firstMin
        store.firstNpcCooldownMax = firstMax
        store.nextNpcCooldownMin = nextMin
        store.nextNpcCooldownMax = nextMax

    elseif field == "npcProfiles" then
        local profiles = type(value) == "table" and value or {}
        dbExec(db, "UPDATE stores SET npc_profiles = ?, modified_at = ? WHERE id = ?",
            toJSON(profiles), timestamp, store.dbId)
        store.npcProfiles = profiles

    else
        log("Champ updateStore inconnu : " .. tostring(field), "WARNING")
        return false
    end

    store.modifiedAt = timestamp
    logDebug("Magasin #" .. storeId .. " mis a jour : " .. tostring(field))

    if _G.notifyStoresChanged then _G.notifyStoresChanged() end

    return true
end

-- ═══════════════════════════════════════════════════════════════
-- MARQUEURS ADMIN
-- ═══════════════════════════════════════════════════════════════

function createStoreMarker(storeId)
    local store = _G.stores[storeId]
    if not store then return end

    -- Version optimisée : on ne crée plus de marker admin visible.
    -- Le marker vert + texte [CUSTOM] #ID était uniquement un repère admin.
    -- Le vrai marker de service caissier est créé côté SystemTrabajos, donc ça ne casse pas le job.
    if store.marker and isElement(store.marker) then destroyElement(store.marker) end
    if store.blip and isElement(store.blip) then destroyElement(store.blip) end

    store.marker = nil
    store.blip = nil
end

function createAllStoreMarkers()
    for storeId, _ in pairs(_G.stores) do
        createStoreMarker(storeId)
    end
end

function destroyAllStoreMarkers()
    for _, store in pairs(_G.stores) do
        if store.marker and isElement(store.marker) then destroyElement(store.marker) end
        if store.blip and isElement(store.blip) then destroyElement(store.blip) end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- NPC EMPLOYEUR
-- ═══════════════════════════════════════════════════════════════

function loadEmployer()
    if not db then return end

    local query = dbQuery(db, "SELECT * FROM employer_position WHERE id = 1")
    local results = dbPoll(query, -1)

    local posX, posY, posZ, rot, skin

    if results and #results > 0 then
        posX = results[1].pos_x
        posY = results[1].pos_y
        posZ = results[1].pos_z
        rot = results[1].rot or 0
        skin = results[1].skin or AMConfig.employer.skin
    else
        posX = AMConfig.employer.defaultPos.x
        posY = AMConfig.employer.defaultPos.y
        posZ = AMConfig.employer.defaultPos.z
        rot = AMConfig.employer.defaultPos.rot
        skin = AMConfig.employer.skin

        dbExec(db, "INSERT INTO employer_position (id, pos_x, pos_y, pos_z, rot, skin) VALUES (1, ?, ?, ?, ?, ?)",
            posX, posY, posZ, rot, skin)
        log("Position d'employeur par defaut chargee depuis config.")
    end

    if employerPed and isElement(employerPed) then destroyElement(employerPed) end

    employerPed = createPed(skin, posX, posY, posZ, rot)
    if employerPed then
        setElementFrozen(employerPed, AMConfig.employer.frozen)
        setElementData(employerPed, "i9.interaction.bot", true)
        setElementData(employerPed, "[i9.interaction.bot]", true)
        setElementData(employerPed, "isJobNPC", true)
        setElementData(employerPed, "adminMagasin:employer", true)
        setElementData(employerPed, "name", AMConfig.employer.name)
        log("NPC Employeur place a " .. math.floor(posX) .. ", " .. math.floor(posY) .. ", " .. math.floor(posZ))
    else
        log("ERREUR : Impossible de creer le NPC Employeur !", "ERROR")
    end
end

function moveEmployer(x, y, z, rot)
    if not db then return end

    local query = dbQuery(db, "SELECT COUNT(*) as cnt FROM employer_position WHERE id = 1")
    local res = dbPoll(query, -1)

    if res and res[1] and res[1].cnt > 0 then
        dbExec(db, "UPDATE employer_position SET pos_x = ?, pos_y = ?, pos_z = ?, rot = ? WHERE id = 1",
            x, y, z, rot or 0)
    else
        dbExec(db, "INSERT INTO employer_position (id, pos_x, pos_y, pos_z, rot, skin) VALUES (1, ?, ?, ?, ?, ?)",
            x, y, z, rot or 0, AMConfig.employer.skin)
    end

    if employerPed and isElement(employerPed) then
        setElementPosition(employerPed, x, y, z)
        setElementRotation(employerPed, 0, 0, rot or 0)
    else
        loadEmployer()
    end

    log("NPC Employeur deplace a " .. math.floor(x) .. ", " .. math.floor(y) .. ", " .. math.floor(z))
end

function changeEmployerSkin(newSkin)
    if not db or not newSkin then return end

    newSkin = tonumber(newSkin) or AMConfig.employer.skin
    dbExec(db, "UPDATE employer_position SET skin = ? WHERE id = 1", newSkin)

    if employerPed and isElement(employerPed) then
        setElementModel(employerPed, newSkin)
    end

    log("Skin du NPC Employeur change vers " .. newSkin)
end

function getEmployerPed()
    return employerPed
end

-- ═══════════════════════════════════════════════════════════════
-- TÉLÉPORTATION SÉCURISÉE
-- ═══════════════════════════════════════════════════════════════

function teleportPlayerSafe(player, x, y, z)
    if not player or not isElement(player) then return false end

    if isElementAttached(player) then detachElements(player) end

    local vehicle = getPedOccupiedVehicle(player)
    if vehicle then removePedFromVehicle(player) end

    if AMConfig.teleport.unfreeze then setElementFrozen(player, false) end
    if AMConfig.teleport.enableCollisions then setElementCollisionsEnabled(player, true) end

    setElementDimension(player, AMConfig.teleport.dimension)
    setElementInterior(player, AMConfig.teleport.interior)
    setElementPosition(player, x, y, z)

    for _, delay in ipairs(AMConfig.teleport.retryDelays) do
        setTimer(function()
            if isElement(player) then
                setElementPosition(player, x, y, z)
                if AMConfig.teleport.unfreeze then setElementFrozen(player, false) end
            end
        end, delay, 1)
    end

    return true
end

-- ═══════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════

function getStore(storeId)
    return _G.stores[storeId]
end

function getAllStores()
    return _G.stores
end

function getAllStoresSimple()
    local simple = {}
    for id, store in pairs(_G.stores) do
        simple[id] = {
            id = id,
            name = store.name,
            pos = store.pos,
            maxNPC = store.maxNPC,
            firstNpcCooldownMin = store.firstNpcCooldownMin,
            firstNpcCooldownMax = store.firstNpcCooldownMax,
            nextNpcCooldownMin = store.nextNpcCooldownMin,
            nextNpcCooldownMax = store.nextNpcCooldownMax,
        }
    end
    return simple
end

function getStoreConfig(storeId)
    local store = _G.stores[storeId]
    if not store then return nil end

    return {
        id = store.id,
        type = store.type,
        name = store.name,
        pos = store.pos,
        cashier = store.cashier,
        camera = store.camera,
        basketPermanent = store.basketPermanent,
        basketClient = store.basketClient,
        maxNPC = store.maxNPC,
        salary = store.salary,
        products = store.products,
        pausePoints = store.pausePoints,
        firstNpcCooldownMin = store.firstNpcCooldownMin,
        firstNpcCooldownMax = store.firstNpcCooldownMax,
        nextNpcCooldownMin = store.nextNpcCooldownMin,
        nextNpcCooldownMax = store.nextNpcCooldownMax,
        npcProfiles = store.npcProfiles,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- INITIALISATION
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onResourceStart", resourceRoot, function()
    log("============================================")
    log("Admin Magasin v2.1 optimise - Demarrage...")
    log("============================================")

    if not initDatabase() then
        log("ERREUR CRITIQUE : Echec d'initialisation de la BDD.", "ERROR")
        return
    end

    loadAllStores()
    createAllStoreMarkers()
    loadEmployer()

    setTimer(function()
        if _G.loadPaths then _G.loadPaths() end

        setTimer(function()
            if _G.notifyStoresChanged then _G.notifyStoresChanged() end
        end, 500, 1)
    end, 500, 1)

    log("Initialisation terminee !")
    log("Magasins charges : " .. AMData.countTable(_G.stores))
    log("Tapez /magasinaide pour voir les commandes.")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    destroyAllStoreMarkers()
    if employerPed and isElement(employerPed) then destroyElement(employerPed) end
    log("Admin Magasin arrete. Donnees sauvegardees.")
end)
