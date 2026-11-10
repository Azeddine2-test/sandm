-- ============================================================
-- shared/data.lua - Structure de données partagée
-- Version optimisée : paths enter/exit + cooldown random + profils NPC
-- ============================================================

AMData = {}

-- ═══════════════════════════════════════════════════════════════
-- TYPES DE PATHS
-- Système optimisé : on utilise seulement enter + exit.
-- ═══════════════════════════════════════════════════════════════

AMData.pathTypes = {
    ["enter"] = "Entree client",
    ["exit"]  = "Sortie client",
}

AMData.pathTypesOrder = {
    "enter",
    "exit",
}

-- ═══════════════════════════════════════════════════════════════
-- SKINS DES NPC CLIENTS
-- ═══════════════════════════════════════════════════════════════

AMData.customerSkins = {
    10, 11, 12, 14, 15, 16, 17, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 47, 48, 49, 50, 51, 52
}

-- ═══════════════════════════════════════════════════════════════
-- PRODUITS DISPONIBLES
-- ═══════════════════════════════════════════════════════════════

AMData.availableProducts = {
    {model = 1544, name = "Biere Corona", scale = 1.0, category = "boisson"},
    {model = 1484, name = "Biere",         scale = 0.7, category = "boisson"},
    {model = 1517, name = "Vodka",         scale = 1.0, category = "boisson"},
    {model = 1580, name = "Sprite",        scale = 0.4, category = "boisson"},
    {model = 1545, name = "Starbucks",     scale = 1.0, category = "boisson"},
    {model = 2647, name = "Canette",       scale = 0.7, category = "boisson"},
    {model = 1549, name = "Bouteille",     scale = 0.7, category = "boisson"},
    {model = 1487, name = "Cheetos",       scale = 1.0, category = "snack"},
    {model = 1520, name = "Doritos",       scale = 1.0, category = "snack"},
    {model = 1212, name = "Argent",        scale = 0.6, category = "autre"},
}

-- ═══════════════════════════════════════════════════════════════
-- COULEURS
-- ═══════════════════════════════════════════════════════════════

AMData.colors = {
    primary = {121, 80, 242},
    success = {87, 242, 135},
    error   = {237, 66, 69},
    warning = {254, 231, 92},
    info    = {88, 165, 255},
    white   = {255, 255, 255},
    black   = {0, 0, 0},
    gray    = {200, 200, 200},
    darkGray = {100, 100, 100},
    moveStand  = {100, 100, 255},
    moveWalk   = {87, 242, 135},
    moveRun    = {255, 165, 0},
    moveSprint = {255, 50, 50},
    custom  = {0, 255, 100},
    editing = {255, 200, 0},
}

-- ═══════════════════════════════════════════════════════════════
-- TYPES DE MAGASINS
-- ═══════════════════════════════════════════════════════════════

AMData.storeTypes = {
    CUSTOM = "custom",
}

-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION REQUISE
-- ═══════════════════════════════════════════════════════════════

AMData.requiredForBasicCashier = {
    "pos",
    "cashier",
    "camera",
}

AMData.requiredForNPC = {
    "pathEnter",
    "pathExit",
    "basketPermanent",
    "basketClient",
    "productPositions",
}

-- ═══════════════════════════════════════════════════════════════
-- HELPERS PARTAGÉS
-- ═══════════════════════════════════════════════════════════════

function AMData.getPathTypeName(pathType)
    return AMData.pathTypes[pathType] or pathType or "Inconnu"
end

function AMData.isValidPathType(pathType)
    return AMData.pathTypes[pathType] ~= nil
end

function AMData.getPathTypesList()
    local list = {}
    for _, pt in ipairs(AMData.pathTypesOrder) do
        table.insert(list, pt)
    end
    return list
end

function AMData.getRandomSkin()
    return AMData.customerSkins[math.random(#AMData.customerSkins)]
end

function AMData.getProductByModel(model)
    for _, product in ipairs(AMData.availableProducts) do
        if product.model == model then
            return product
        end
    end
    return nil
end

function AMData.getProductsByCategory(category)
    local result = {}
    for _, product in ipairs(AMData.availableProducts) do
        if product.category == category then
            table.insert(result, product)
        end
    end
    return result
end

function AMData.getCategories()
    local categories = {}
    local seen = {}
    for _, product in ipairs(AMData.availableProducts) do
        if product.category and not seen[product.category] then
            seen[product.category] = true
            table.insert(categories, product.category)
        end
    end
    return categories
end

function AMData.getColor(name)
    return AMData.colors[name] or AMData.colors.white
end

function AMData.getMoveStateColor(moveState)
    if moveState == "stand" then
        return AMData.colors.moveStand
    elseif moveState == "walk" then
        return AMData.colors.moveWalk
    elseif moveState == "run" then
        return AMData.colors.moveRun
    elseif moveState == "sprint" then
        return AMData.colors.moveSprint
    end
    return AMData.colors.white
end

function AMData.formatMoney(amount)
    if not amount or type(amount) ~= "number" then return "0 $" end
    return tostring(math.floor(amount)) .. " $"
end

function AMData.formatPosition(x, y, z)
    return string.format("%d, %d, %d",
        math.floor(x or 0),
        math.floor(y or 0),
        math.floor(z or 0))
end

function AMData.formatCooldown(ms)
    ms = tonumber(ms) or 0
    return tostring(math.floor(ms / 1000)) .. "s"
end

function AMData.clamp(value, min, max)
    value = tonumber(value) or min
    return math.max(min, math.min(max, value))
end

function AMData.deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            copy[k] = AMData.deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function AMData.countTable(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function AMData.productsListToString(products)
    if type(products) ~= "table" or #products == 0 then return "tous" end
    local out = {}
    for _, idx in ipairs(products) do
        table.insert(out, tostring(idx))
    end
    return table.concat(out, ",")
end

-- ═══════════════════════════════════════════════════════════════
-- VALIDATION / PROFILS NPC
-- ═══════════════════════════════════════════════════════════════

function AMData.normalizeNPCProfiles(profiles, productCount)
    if type(profiles) ~= "table" then return {} end

    local normalized = {}
    productCount = tonumber(productCount) or 0

    for _, profile in ipairs(profiles) do
        if type(profile) == "table" and tonumber(profile.skin) then
            local products = {}

            if type(profile.products) == "table" then
                for _, idx in ipairs(profile.products) do
                    idx = tonumber(idx)
                    if idx and idx >= 1 and (productCount <= 0 or idx <= productCount) then
                        table.insert(products, math.floor(idx))
                    end
                end
            end

            table.insert(normalized, {
                name = profile.name or "Profil NPC",
                skin = tonumber(profile.skin),
                products = products,
            })
        end
    end

    return normalized
end

-- ═══════════════════════════════════════════════════════════════
-- STATUS D'UN MAGASIN
-- ═══════════════════════════════════════════════════════════════

function AMData.getStoreStatus(store, paths)
    if not store then
        return {
            valid = false,
            basicCashierReady = false,
            npcReady = false,
            checks = {},
            missing = {"Magasin introuvable"},
        }
    end

    local checks = {}
    local missing = {}

    local hasPos = store.pos and store.pos.x and store.pos.y and store.pos.z
    table.insert(checks, {name = "Position magasin", ok = hasPos})
    if not hasPos then table.insert(missing, "pos") end

    local hasCashier = store.cashier and store.cashier.isSet
    table.insert(checks, {name = "Position caissier", ok = hasCashier})
    if not hasCashier then table.insert(missing, "caissier") end

    local hasCamera = store.camera and store.camera.isSet and store.camera.x
    table.insert(checks, {name = "Camera", ok = hasCamera})
    if not hasCamera then table.insert(missing, "camera") end

    local pathEnterCount = 0
    local pathExitCount = 0

    if paths then
        for _, path in pairs(paths) do
            if path.pathType == "enter" then
                pathEnterCount = pathEnterCount + 1
            elseif path.pathType == "exit" then
                pathExitCount = pathExitCount + 1
            end
        end
    end

    local hasPathEnter = pathEnterCount > 0
    local hasPathExit = pathExitCount > 0

    table.insert(checks, {name = "Path 'enter' (" .. pathEnterCount .. ")", ok = hasPathEnter})
    table.insert(checks, {name = "Path 'exit' (" .. pathExitCount .. ")", ok = hasPathExit})

    if not hasPathEnter then table.insert(missing, "path enter") end
    if not hasPathExit then table.insert(missing, "path exit") end

    local hasBasketPerm = store.basketPermanent and store.basketPermanent.isSet
    table.insert(checks, {name = "Panier permanent", ok = hasBasketPerm})
    if not hasBasketPerm then table.insert(missing, "panier permanent") end

    local hasBasketClient = store.basketClient and store.basketClient.isSet
    table.insert(checks, {name = "Panier client (spawn)", ok = hasBasketClient})
    if not hasBasketClient then table.insert(missing, "panier client") end

    local productCount = store.products and #store.products or 0
    local positionedProductCount = 0
    if store.products then
        for _, product in ipairs(store.products) do
            if product.position and product.position.isSet then
                positionedProductCount = positionedProductCount + 1
            end
        end
    end

    local hasProductPositions = positionedProductCount > 0
    table.insert(checks, {
        name = "Produits positionnes (" .. positionedProductCount .. "/" .. productCount .. ")",
        ok = hasProductPositions
    })
    if not hasProductPositions then table.insert(missing, "positions produits") end

    local pauseCount = store.pausePoints and #store.pausePoints or 0
    table.insert(checks, {
        name = "Points de pause (" .. pauseCount .. ")",
        ok = pauseCount > 0,
        optional = true,
    })

    local profileCount = store.npcProfiles and #store.npcProfiles or 0
    table.insert(checks, {
        name = "Profils NPC (" .. profileCount .. ")",
        ok = profileCount > 0,
        optional = true,
    })

    if store.firstNpcCooldownMin and store.firstNpcCooldownMax and store.nextNpcCooldownMin and store.nextNpcCooldownMax then
        table.insert(checks, {
            name = "Cooldown NPC : 1er " .. AMData.formatCooldown(store.firstNpcCooldownMin) .. "-" .. AMData.formatCooldown(store.firstNpcCooldownMax)
                .. " | suivants " .. AMData.formatCooldown(store.nextNpcCooldownMin) .. "-" .. AMData.formatCooldown(store.nextNpcCooldownMax),
            ok = true,
            optional = true,
        })
    end

    local basicCashierReady = hasPos and hasCashier and hasCamera
    local npcReady = basicCashierReady and hasPathEnter and hasPathExit
        and hasBasketPerm and hasBasketClient and hasProductPositions

    return {
        valid = true,
        basicCashierReady = basicCashierReady,
        npcReady = npcReady,
        checks = checks,
        missing = missing,
        pathCount = {
            enter = pathEnterCount,
            exit = pathExitCount,
        },
        productCount = productCount,
        positionedProductCount = positionedProductCount,
        pauseCount = pauseCount,
        profileCount = profileCount,
    }
end

_G.AMData = AMData
