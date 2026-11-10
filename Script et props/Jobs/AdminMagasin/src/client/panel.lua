-- ============================================================
-- client/panel.lua - Panel graphique Admin Magasin
-- ============================================================

local panel = {
    visible = false,
    width = 860,
    height = 620,
    x = 0,
    y = 0,
    view = "list",
    editStore = nil,
    editPaths = nil,
    stores = {},
    paths = {},
    listScroll = 0,
    pathScroll = 0,
    productScroll = 0,
    activeInput = nil,
    inputValues = {},
    hoveredButton = nil,
    inputBounds = {},  -- Positions des inputs pour détection clic
}

-- Liste des contrôles à désactiver quand le panel est ouvert
local BLOCKED_CONTROLS = {
    "fire", "next_weapon", "previous_weapon", "forwards", "backwards",
    "left", "right", "zoom_in", "zoom_out", "change_camera", "jump",
    "sprint", "look_behind", "crouch", "action", "walk", "aim_weapon",
    "conversation_yes", "conversation_no", "group_control_forwards",
    "group_control_back", "enter_exit", "vehicle_fire", "vehicle_secondary_fire",
    "vehicle_left", "vehicle_right", "steer_forward", "steer_back",
    "accelerate", "brake_reverse", "radio_next", "radio_previous",
    "radio_user_track_skip", "horn", "sub_mission", "handbrake",
    "vehicle_look_left", "vehicle_look_right", "vehicle_look_behind",
    "vehicle_mouse_look", "special_control_left", "special_control_right",
    "special_control_down", "special_control_up",
}

-- Touches à bloquer (F1, F2, N, etc.)
local BLOCKED_KEYS = {
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "n", "b", "y", "t", "u", "i", "o", "p", "k", "l", "m",
    "tab", "space", "lshift", "rshift", "lctrl", "rctrl", "lalt", "ralt",
}

-- ═══════════════════════════════════════════════════════════════
-- 🎨 COULEURS
-- ═══════════════════════════════════════════════════════════════

local C = {
    bg          = tocolor(18, 18, 24, 245),
    bgLight     = tocolor(28, 28, 36, 255),
    bgLighter   = tocolor(38, 38, 50, 255),
    primary     = tocolor(121, 80, 242, 255),
    primaryHov  = tocolor(141, 100, 255, 255),
    success     = tocolor(87, 242, 135, 255),
    error       = tocolor(237, 66, 69, 255),
    warning     = tocolor(254, 231, 92, 255),
    info        = tocolor(88, 165, 255, 255),
    white       = tocolor(255, 255, 255, 255),
    gray        = tocolor(180, 180, 180, 255),
    darkGray    = tocolor(80, 80, 95, 255),
    border      = tocolor(55, 55, 70, 255),
    hardcoded   = tocolor(0, 200, 255, 255),
    custom      = tocolor(0, 255, 100, 255),
    inputBg     = tocolor(12, 12, 18, 255),
    inputActive = tocolor(60, 40, 120, 200),
    overlay     = tocolor(0, 0, 0, 160),
}

-- ═══════════════════════════════════════════════════════════════
-- 🔧 HELPERS
-- ═══════════════════════════════════════════════════════════════

local font = nil
local function loadFont()
    if not font then font = dxCreateFont("assets/fonts/Poppins-Regular.ttf", 11) end
    return font or "default"
end

local function drawRect(x, y, w, h, color, postGUI)
    dxDrawRectangle(x, y, w, h, color, postGUI)
end

local function drawText(text, x, y, w, h, color, scale, align, valign, postGUI)
    dxDrawText(text, x, y, x + (w or 0), y + (h or 20),
        color or C.white, scale or 1.0, loadFont(),
        align or "left", valign or "center",
        false, false, postGUI)
end

local function drawBorder(x, y, w, h, color, thickness)
    thickness = thickness or 1
    drawRect(x, y, w, thickness, color)
    drawRect(x, y + h - thickness, w, thickness, color)
    drawRect(x, y, thickness, h, color)
    drawRect(x + w - thickness, y, thickness, h, color)
end

local function isHovered(x, y, w, h)
    if not isCursorShowing() then return false end
    local mx, my = getCursorPosition()
    if not mx then return false end
    local sw, sh = guiGetScreenSize()
    mx, my = mx * sw, my * sh
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function drawButton(x, y, w, h, text, colorNormal, colorHover, textColor, id)
    local hovered = isHovered(x, y, w, h)
    local color = hovered and (colorHover or C.primaryHov) or (colorNormal or C.primary)

    drawRect(x, y, w, h, color)
    drawBorder(x, y, w, h, tocolor(255, 255, 255, 20))
    drawText(text, x, y, w, h, textColor or C.white, 0.9, "center", "center")

    if id and hovered then panel.hoveredButton = id end
    return hovered
end

local function drawInput(x, y, w, h, value, placeholder, inputId)
    local isActive = (panel.activeInput == inputId)
    local bg = isActive and C.inputActive or C.inputBg
    local borderColor = isActive and C.primary or C.border

    drawRect(x, y, w, h, bg)
    drawBorder(x, y, w, h, borderColor)

    local displayText = (value and value ~= "") and value or placeholder
    local textColor = (value and value ~= "") and C.white or C.darkGray

    local cursor = ""
    if isActive and (getTickCount() % 1000 < 500) then cursor = "|" end

    drawText((displayText or "") .. cursor, x + 8, y, w - 16, h, textColor, 0.85, "left", "center")

    -- Enregistrer la position pour la détection de clic
    panel.inputBounds[inputId] = {x = x, y = y, w = w, h = h}
end

-- ═══════════════════════════════════════════════════════════════
-- 🚫 BLOCAGE DES CONTRÔLES
-- ═══════════════════════════════════════════════════════════════

local function enableControls(enable)
    for _, ctrl in ipairs(BLOCKED_CONTROLS) do
        toggleControl(ctrl, enable)
    end
end

local function blockKey(key, press)
    if panel.visible then
        cancelEvent()
        return true
    end
end

-- Bind toutes les touches problématiques
for _, key in ipairs(BLOCKED_KEYS) do
    bindKey(key, "down", function()
        if panel.visible then
            -- Ne fait rien = bloque
            return
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- 📋 VUE LISTE
-- ═══════════════════════════════════════════════════════════════

local function drawListView()
    local px, py = panel.x, panel.y
    local pw, ph = panel.width, panel.height

    -- Titre
    drawRect(px, py, pw, 50, C.bgLight)
    drawBorder(px, py, pw, 50, C.border)
    drawRect(px, py, 4, 50, C.primary)
    drawText("🏪  ADMIN MAGASIN — Gestion des magasins", px + 20, py, pw - 40, 50, C.white, 1.1, "left", "center")

    drawButton(px + pw - 45, py + 10, 32, 30, "✕", C.error, tocolor(200, 50, 50, 255), C.white, "close")

    -- Zone liste
    local listX, listY = px + 20, py + 70
    local listW, listH = pw - 40, ph - 140

    drawRect(listX - 5, listY - 5, listW + 10, listH + 10, C.bgLight)
    drawBorder(listX - 5, listY - 5, listW + 10, listH + 10, C.border)
    drawRect(listX - 5, listY - 5, listW + 10, 30, C.bgLighter)
    drawText("📋  LISTE DES MAGASINS", listX + 5, listY - 5, listW, 30, C.gray, 0.85, "left", "center")

    local itemHeight = 42
    local visibleCount = math.floor(listH / itemHeight)

    local storeList = {}
    for id, store in pairs(panel.stores) do table.insert(storeList, store) end
    table.sort(storeList, function(a, b)
        if a.type == b.type then return a.id < b.id end
        return a.type == "hardcoded"
    end)
    local totalStores = #storeList

    panel.listScroll = math.max(0, math.min(panel.listScroll, math.max(0, totalStores - visibleCount)))
    local startIdx = panel.listScroll + 1
    local endIdx = math.min(totalStores, startIdx + visibleCount - 1)

    for i = startIdx, endIdx do
        local store = storeList[i]
        if not store then break end

        local itemY = listY + (i - startIdx) * itemHeight + 25
        local isEven = (i % 2 == 0)
        local itemBg = isEven and tocolor(22, 22, 30, 255) or tocolor(26, 26, 35, 255)
        local hovItem = isHovered(listX - 5, itemY, listW + 10, itemHeight - 2)

        drawRect(listX - 5, itemY, listW + 10, itemHeight - 2, hovItem and tocolor(35, 35, 48, 255) or itemBg)

        local typeColor = (store.type == "hardcoded") and C.hardcoded or C.custom
        drawRect(listX - 5, itemY, 3, itemHeight - 2, typeColor)

        drawText("#" .. store.id, listX + 5, itemY, 35, itemHeight - 2, typeColor, 0.9, "left", "center")
        drawText(store.name or "?", listX + 42, itemY, listW - 220, itemHeight - 2, C.white, 0.95, "left", "center")

        local pathCount = 0
        if panel.paths[store.id] then
            for _ in pairs(panel.paths[store.id]) do pathCount = pathCount + 1 end
        end
        local statusOk = store.cashier and store.cashier.isSet and store.camera and store.camera.isSet and pathCount > 0
        local statusColor = statusOk and C.success or C.warning
        drawText(statusOk and "✓" or "⚠", listX + listW - 215, itemY, 20, itemHeight - 2, statusColor, 1.0, "center", "center")

        local btnY = itemY + 8
        local btnH = itemHeight - 18

        local modX = listX + listW - 195
        drawButton(modX, btnY, 75, btnH, "Modifier", C.primary, C.primaryHov, C.white, "edit_" .. store.id)

        local tpX = modX + 80
        drawButton(tpX, btnY, 40, btnH, "TP", tocolor(50, 100, 180, 255), tocolor(70, 130, 220, 255), C.white, "tp_" .. store.id)

        if store.type == "custom" then
            local delX = tpX + 45
            drawButton(delX, btnY, 30, btnH, "✕", tocolor(180, 50, 50, 255), C.error, C.white, "delstore_" .. store.id)
        end
    end

    if totalStores > visibleCount then
        local scrollH = listH - 25
        local scrollY = listY + 25
        local thumbH = math.max(20, scrollH * visibleCount / totalStores)
        local thumbY = scrollY + (panel.listScroll / math.max(1, totalStores - visibleCount)) * (scrollH - thumbH)
        drawRect(listX + listW + 2, scrollY, 6, scrollH, C.bgLighter)
        drawRect(listX + listW + 2, thumbY, 6, thumbH, C.primary)
    end

    local btnAreaY = py + ph - 60
    drawRect(px, btnAreaY, pw, 60, C.bgLight)
    drawBorder(px, btnAreaY, pw, 60, C.border)

    drawButton(px + 20, btnAreaY + 12, 160, 36, "+ Creer un magasin", C.success, tocolor(60, 200, 100, 255), tocolor(10, 30, 15, 255), "create")
    drawButton(px + 190, btnAreaY + 12, 120, 36, "🔄 Rafraichir", C.bgLighter, tocolor(50, 50, 65, 255), C.gray, "refresh")

    local hardCount, custCount = 0, 0
    for _, s in pairs(panel.stores) do
        if s.type == "hardcoded" then hardCount = hardCount + 1 else custCount = custCount + 1 end
    end
    drawText(hardCount .. " hardcode(s) + " .. custCount .. " custom(s) = " .. totalStores .. " magasin(s)",
        px + pw - 320, btnAreaY, 300, 60, C.gray, 0.85, "right", "center")
end

-- ═══════════════════════════════════════════════════════════════
-- ✏️ VUE ÉDITION
-- ═══════════════════════════════════════════════════════════════

local function drawEditView()
    local px, py = panel.x, panel.y
    local pw, ph = panel.width, panel.height
    local store = panel.editStore
    if not store then return end

    drawRect(px, py, pw, 50, C.bgLight)
    drawBorder(px, py, pw, 50, C.border)
    drawRect(px, py, 4, 50, (store.type == "hardcoded") and C.hardcoded or C.custom)

    local typeLabel = (store.type == "hardcoded") and "[HARDCODE]" or "[CUSTOM]"
    drawText("✏️  Modifier : #" .. store.id .. " " .. (store.name or "?") .. "  " .. typeLabel,
        px + 20, py, pw - 100, 50, C.white, 1.05, "left", "center")

    drawButton(px + pw - 160, py + 10, 60, 30, "← Retour", C.bgLighter, tocolor(50, 50, 65, 255), C.gray, "back")
    drawButton(px + pw - 45, py + 10, 32, 30, "✕", C.error, tocolor(200, 50, 50, 255), C.white, "close")

    local contentX, contentY = px + 20, py + 60
    local contentW = pw - 40
    local cy = contentY + 10

    -- GÉNÉRAL
    drawRect(contentX, cy, contentW, 25, C.bgLighter)
    drawRect(contentX, cy, 3, 25, C.primary)
    drawText("  GENERAL", contentX, cy, contentW, 25, C.gray, 0.85, "left", "center")
    cy = cy + 30

    drawText("Nom :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    local nameVal = panel.inputValues["name"] or store.name or ""
    drawInput(contentX + 85, cy, contentW - 250, 28, nameVal, "Nom du magasin...", "name")
    drawButton(contentX + contentW - 155, cy, 75, 28, "✔ Appliquer", C.success, tocolor(60, 200, 100, 255), tocolor(10, 30, 15, 255), "apply_name")
    cy = cy + 36

    local posText = store.pos and AMData.formatPosition(store.pos.x, store.pos.y, store.pos.z) or "N/A"
    drawText("Position :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    drawText(posText, contentX + 85, cy, contentW - 250, 28, C.white, 0.85, "left", "center")
    drawButton(contentX + contentW - 155, cy, 150, 28, "📍 Changer (ta pos)", tocolor(50, 80, 160, 255), tocolor(70, 110, 200, 255), C.white, "change_pos")
    cy = cy + 36

    local cashierStatus = store.cashier and store.cashier.isSet
    local cashierText = cashierStatus and AMData.formatPosition(store.cashier.x, store.cashier.y, store.cashier.z) or "Non defini"
    local cashierColor = cashierStatus and C.success or C.error
    drawText("Caissier :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    drawText(cashierText, contentX + 85, cy, contentW - 250, 28, cashierColor, 0.85, "left", "center")
    drawButton(contentX + contentW - 155, cy, 150, 28, "📍 Changer (ta pos)", tocolor(50, 80, 160, 255), tocolor(70, 110, 200, 255), C.white, "change_cashier")
    cy = cy + 36

    local camStatus = store.camera and store.camera.isSet
    local camText = camStatus and "Definie ✓" or "Non definie"
    local camColor = camStatus and C.success or C.error
    drawText("Camera :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    drawText(camText, contentX + 85, cy, contentW - 250, 28, camColor, 0.85, "left", "center")
    drawButton(contentX + contentW - 155, cy, 150, 28, "📷 Changer (ta vue)", tocolor(50, 80, 160, 255), tocolor(70, 110, 200, 255), C.white, "change_camera")
    cy = cy + 36

    drawText("Salaire :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    drawText("Min :", contentX + 85, cy, 35, 28, C.gray, 0.8, "left", "center")
    local minVal = panel.inputValues["salaryMin"] or tostring(store.salary and store.salary.min or 10)
    drawInput(contentX + 120, cy, 60, 28, minVal, "10", "salaryMin")
    drawText("Max :", contentX + 190, cy, 35, 28, C.gray, 0.8, "left", "center")
    local maxVal = panel.inputValues["salaryMax"] or tostring(store.salary and store.salary.max or 30)
    drawInput(contentX + 225, cy, 60, 28, maxVal, "30", "salaryMax")
    drawButton(contentX + contentW - 155, cy, 75, 28, "✔ Appliquer", C.success, tocolor(60, 200, 100, 255), tocolor(10, 30, 15, 255), "apply_salary")
    cy = cy + 36

    drawText("NPC max :", contentX, cy, 80, 28, C.gray, 0.85, "left", "center")
    local npcVal = panel.inputValues["maxNPC"] or tostring(store.maxNPC or 2)
    drawInput(contentX + 85, cy, 60, 28, npcVal, "2", "maxNPC")
    drawText("(1-5)", contentX + 155, cy, 50, 28, C.darkGray, 0.8, "left", "center")
    drawButton(contentX + contentW - 155, cy, 75, 28, "✔ Appliquer", C.success, tocolor(60, 200, 100, 255), tocolor(10, 30, 15, 255), "apply_npc")
    cy = cy + 44

    -- PATHS
    local pathCount = 0
    if panel.paths[store.id] then for _ in pairs(panel.paths[store.id]) do pathCount = pathCount + 1 end end

    drawRect(contentX, cy, contentW, 25, C.bgLighter)
    drawRect(contentX, cy, 3, 25, C.info)
    drawText("  🛤️  PATHS (" .. pathCount .. ")", contentX, cy, contentW, 25, C.gray, 0.85, "left", "center")
    cy = cy + 30

    if panel.paths[store.id] then
        for pathId, path in pairs(panel.paths[store.id]) do
            local typeName = AMData and AMData.getPathTypeName(path.pathType) or path.pathType
            local pts = path.data and #path.data or 0

            drawRect(contentX, cy, contentW, 30, tocolor(22, 22, 32, 255))
            drawBorder(contentX, cy, contentW, 30, C.border)
            drawRect(contentX, cy, 2, 30, C.info)

            drawText("  #" .. pathId .. " | " .. typeName .. " | " .. pts .. " points",
                contentX, cy, contentW - 100, 30, C.white, 0.85, "left", "center")

            drawButton(contentX + contentW - 95, cy + 4, 40, 22, "👁", tocolor(50, 80, 160, 255), tocolor(70, 110, 200, 255), C.white, "show_path_" .. pathId)
            drawButton(contentX + contentW - 50, cy + 4, 40, 22, "🗑", tocolor(140, 40, 40, 255), C.error, C.white, "del_path_" .. pathId)
            cy = cy + 34
        end
    end

    if pathCount == 0 then
        drawText("  Aucun chemin. Utilisez /pathrecord " .. store.id .. " [type]",
            contentX, cy, contentW, 28, C.darkGray, 0.85, "left", "center")
        cy = cy + 30
    end

    drawButton(contentX, cy, 180, 28, "+ Enregistrer un path", tocolor(30, 80, 140, 255), tocolor(50, 110, 180, 255), C.white, "add_path")
    cy = cy + 40

    -- PRODUITS
    local prodCount = store.products and #store.products or 0

    drawRect(contentX, cy, contentW, 25, C.bgLighter)
    drawRect(contentX, cy, 3, 25, C.warning)
    drawText("  📦  PRODUITS (" .. prodCount .. ")", contentX, cy, contentW, 25, C.gray, 0.85, "left", "center")
    cy = cy + 30

    if store.products then
        for i, prod in ipairs(store.products) do
            drawRect(contentX, cy, contentW, 28, tocolor(22, 22, 32, 255))
            drawBorder(contentX, cy, contentW, 28, C.border)
            drawRect(contentX, cy, 2, 28, C.warning)

            drawText("  " .. i .. ". " .. (prod.name or "?") .. " (model: " .. (prod.model or "?") .. ", ×" .. (prod.scale or 1.0) .. ")",
                contentX, cy, contentW - 55, 28, C.white, 0.82, "left", "center")

            drawButton(contentX + contentW - 50, cy + 3, 40, 22, "🗑", tocolor(140, 40, 40, 255), C.error, C.white, "del_prod_" .. i)
            cy = cy + 30
        end
    end

    if prodCount == 0 then
        drawText("  Aucun produit configure.", contentX, cy, contentW, 28, C.darkGray, 0.85, "left", "center")
        cy = cy + 30
    end

    drawText("Modele :", contentX, cy, 65, 28, C.gray, 0.8, "left", "center")
    local modelVal = panel.inputValues["newModel"] or ""
    drawInput(contentX + 70, cy, 70, 28, modelVal, "1544", "newModel")
    drawText("Nom :", contentX + 150, cy, 45, 28, C.gray, 0.8, "left", "center")
    local nameNewVal = panel.inputValues["newProdName"] or ""
    drawInput(contentX + 195, cy, 160, 28, nameNewVal, "Biere Corona...", "newProdName")
    drawButton(contentX + 365, cy, 130, 28, "+ Ajouter produit", C.warning, tocolor(210, 190, 60, 255), tocolor(30, 25, 0, 255), "add_prod")
    cy = cy + 40
end

-- ═══════════════════════════════════════════════════════════════
-- 🖥️ RENDU PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local function renderPanel()
    if not panel.visible then return end

    local sw, sh = guiGetScreenSize()
    panel.x = math.floor((sw - panel.width) / 2)
    panel.y = math.floor((sh - panel.height) / 2)

    drawRect(0, 0, sw, sh, C.overlay)
    drawRect(panel.x, panel.y, panel.width, panel.height, C.bg)
    drawBorder(panel.x, panel.y, panel.width, panel.height, C.border, 2)
    drawRect(panel.x, panel.y, panel.width, 3, C.primary)

    panel.hoveredButton = nil
    panel.inputBounds = {}

    if panel.view == "list" then
        drawListView()
    elseif panel.view == "edit" then
        drawEditView()
    end
end

addEventHandler("onClientRender", root, renderPanel)

-- ═══════════════════════════════════════════════════════════════
-- 🔧 NOTIFY
-- ═══════════════════════════════════════════════════════════════

local function notify(message, nType)
    nType = nType or "info"
    local fuNotify = getResourceFromName("[FU]Notify")
    if fuNotify and getResourceState(fuNotify) == "running" then
        exports['[FU]Notify']:notify(message, nType)
    else
        local colors = { success={87,242,135}, error={237,66,69}, info={88,165,255}, warning={254,231,92} }
        local c = colors[nType] or colors.info
        outputChatBox("[AdminMagasin] " .. message, c[1], c[2], c[3])
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🖱️ GESTION DES CLICS
-- ═══════════════════════════════════════════════════════════════

local function handleClick(btn)
    if not btn then return end

    if btn == "close" then
        panel.visible = false
        showCursor(false)
        enableControls(true)
        return
    end

    if btn == "back" then
        panel.view = "list"
        panel.editStore = nil
        panel.editPaths = nil
        panel.inputValues = {}
        panel.activeInput = nil
        return
    end

    if btn == "refresh" then
        triggerServerEvent("AdminMagasin:requestStoresList", localPlayer)
        notify("Rafraichissement en cours...", "info")
        return
    end

    if btn == "create" then
        notify("Fermez le panel et utilisez /magasincreate [nom] pour creer un magasin.", "info")
        return
    end

    if string.sub(btn, 1, 5) == "edit_" then
        local storeId = tonumber(string.sub(btn, 6))
        if storeId and panel.stores[storeId] then
            panel.view = "edit"
            panel.editStore = panel.stores[storeId]
            panel.editPaths = panel.paths[storeId] or {}
            panel.inputValues = {}
            panel.activeInput = nil
        end
        return
    end

    if string.sub(btn, 1, 3) == "tp_" then
        local storeId = tonumber(string.sub(btn, 4))
        if storeId then
            triggerServerEvent("AdminMagasin:requestTP", localPlayer, storeId)
            panel.visible = false
            showCursor(false)
            enableControls(true)
            notify("Teleportation vers le magasin #" .. storeId, "info")
        end
        return
    end

    -- Suppression magasin (renommé "delstore_" pour éviter conflit avec del_path/del_prod)
    if string.sub(btn, 1, 9) == "delstore_" then
        local storeId = tonumber(string.sub(btn, 10))
        if storeId then
            triggerServerEvent("AdminMagasin:deleteStoreFromPanel", localPlayer, storeId)
        end
        return
    end

    -- ─── ACTIONS EN MODE ÉDITION ───
    local store = panel.editStore
    if not store then return end

    if btn == "apply_name" then
        local newName = panel.inputValues["name"]
        if newName and newName ~= "" then
            triggerServerEvent("AdminMagasin:renameStore", localPlayer, store.id, newName)
            panel.inputValues["name"] = nil
        else
            notify("Entrez un nom valide.", "warning")
        end
        return
    end

    if btn == "change_pos" then
        triggerServerEvent("AdminMagasin:changePosFromPanel", localPlayer, store.id)
        notify("Position du magasin mise a jour !", "success")
        return
    end

    if btn == "change_cashier" then
        triggerServerEvent("AdminMagasin:changeCashierFromPanel", localPlayer, store.id)
        notify("Position du caissier mise a jour !", "success")
        return
    end

    if btn == "change_camera" then
        triggerServerEvent("AdminMagasin:changeCameraFromPanel", localPlayer, store.id)
        notify("Camera mise a jour !", "success")
        return
    end

    if btn == "apply_salary" then
        local minS = tonumber(panel.inputValues["salaryMin"])
        local maxS = tonumber(panel.inputValues["salaryMax"])
        if minS and maxS then
            triggerServerEvent("AdminMagasin:updateSalary", localPlayer, store.id, minS, maxS)
            panel.inputValues["salaryMin"] = nil
            panel.inputValues["salaryMax"] = nil
        else
            notify("Valeurs de salaire invalides.", "warning")
        end
        return
    end

    if btn == "apply_npc" then
        local npc = tonumber(panel.inputValues["maxNPC"])
        if npc then
            triggerServerEvent("AdminMagasin:updateMaxNPC", localPlayer, store.id, npc)
            panel.inputValues["maxNPC"] = nil
        else
            notify("Valeur invalide.", "warning")
        end
        return
    end

    if string.sub(btn, 1, 10) == "show_path_" then
        local pathId = tonumber(string.sub(btn, 11))
        if pathId then triggerServerEvent("AdminMagasin:requestPathData", localPlayer, pathId) end
        return
    end

    if string.sub(btn, 1, 9) == "del_path_" then
        local pathId = tonumber(string.sub(btn, 10))
        if pathId then triggerServerEvent("AdminMagasin:deletePathFromPanel", localPlayer, pathId, store.id) end
        return
    end

    if btn == "add_path" then
        panel.visible = false
        showCursor(false)
        enableControls(true)
        notify("Utilisez : /pathrecord " .. store.id .. " [enter/exit/enter_alt/queue_to_counter]", "info")
        return
    end

    if string.sub(btn, 1, 9) == "del_prod_" then
        local prodIdx = tonumber(string.sub(btn, 10))
        if prodIdx then triggerServerEvent("AdminMagasin:removeProduct", localPlayer, store.id, prodIdx) end
        return
    end

    if btn == "add_prod" then
        local model = tonumber(panel.inputValues["newModel"])
        local name = panel.inputValues["newProdName"]
        if model and name and name ~= "" then
            triggerServerEvent("AdminMagasin:addProduct", localPlayer, store.id, model, name, 1.0)
            panel.inputValues["newModel"] = nil
            panel.inputValues["newProdName"] = nil
        else
            notify("Remplissez modele et nom du produit.", "warning")
        end
        return
    end
end

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if not panel.visible then return end
    if button ~= "left" or state ~= "down" then return end

    -- Priorité 1 : Bouton hovered
    if panel.hoveredButton then
        handleClick(panel.hoveredButton)
        return
    end

    -- Priorité 2 : Clic sur un input
    for inputId, bounds in pairs(panel.inputBounds) do
        if absX >= bounds.x and absX <= bounds.x + bounds.w
        and absY >= bounds.y and absY <= bounds.y + bounds.h then
            panel.activeInput = inputId
            -- Initialiser la valeur si vide
            if not panel.inputValues[inputId] then
                if inputId == "name" and panel.editStore then
                    panel.inputValues[inputId] = panel.editStore.name or ""
                elseif inputId == "salaryMin" and panel.editStore and panel.editStore.salary then
                    panel.inputValues[inputId] = tostring(panel.editStore.salary.min)
                elseif inputId == "salaryMax" and panel.editStore and panel.editStore.salary then
                    panel.inputValues[inputId] = tostring(panel.editStore.salary.max)
                elseif inputId == "maxNPC" and panel.editStore then
                    panel.inputValues[inputId] = tostring(panel.editStore.maxNPC or 2)
                else
                    panel.inputValues[inputId] = ""
                end
            end
            return
        end
    end

    -- Sinon, désactiver l'input actif
    panel.activeInput = nil
end)

-- ═══════════════════════════════════════════════════════════════
-- ⌨️ CLAVIER
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientKey", root, function(key, pressed)
    if not panel.visible or not pressed then return end

    if key == "escape" then
        if panel.view == "edit" then
            panel.view = "list"
            panel.editStore = nil
            panel.inputValues = {}
            panel.activeInput = nil
        else
            panel.visible = false
            showCursor(false)
            enableControls(true)
        end
        cancelEvent()
        return
    end

    if not panel.activeInput then return end

    if key == "backspace" then
        local val = panel.inputValues[panel.activeInput] or ""
        panel.inputValues[panel.activeInput] = string.sub(val, 1, -2)
        cancelEvent()
    elseif key == "enter" then
        panel.activeInput = nil
        cancelEvent()
    end
end)

addEventHandler("onClientCharacter", root, function(char)
    if not panel.visible or not panel.activeInput then return end

    local val = panel.inputValues[panel.activeInput] or ""
    local maxLen = 50
    if panel.activeInput == "salaryMin" or panel.activeInput == "salaryMax"
    or panel.activeInput == "maxNPC" or panel.activeInput == "newModel" then
        maxLen = 8
        if not tonumber(char) then return end
    end

    if #val < maxLen then
        panel.inputValues[panel.activeInput] = val .. char
    end
end)

addEventHandler("onClientMouseWheel", root, function(up)
    if not panel.visible then return end
    panel.listScroll = panel.listScroll + (up and -1 or 1)
    panel.listScroll = math.max(0, panel.listScroll)
end)

-- ═══════════════════════════════════════════════════════════════
-- 📥 RECEPTION DES DONNÉES
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:openPanel", true)
addEventHandler("AdminMagasin:openPanel", localPlayer, function(storesData, pathsData)
    panel.stores = storesData or {}
    panel.paths = pathsData or {}
    panel.view = "list"
    panel.editStore = nil
    panel.inputValues = {}
    panel.activeInput = nil
    panel.listScroll = 0
    panel.visible = true
    showCursor(true)
    enableControls(false)  -- Bloquer les contrôles
end)

addEvent("AdminMagasin:receiveStoresList", true)
addEventHandler("AdminMagasin:receiveStoresList", localPlayer, function(storesData, pathsData)
    panel.stores = storesData or {}
    panel.paths = pathsData or {}

    if panel.view == "edit" and panel.editStore then
        local storeId = panel.editStore.id
        if panel.stores[storeId] then
            panel.editStore = panel.stores[storeId]
            panel.editPaths = panel.paths[storeId] or {}
        end
    end
end)

addEvent("AdminMagasin:receiveStoreDetails", true)
addEventHandler("AdminMagasin:receiveStoreDetails", localPlayer, function(storeData, pathsData)
    if not storeData then return end

    panel.stores[storeData.id] = storeData
    panel.paths[storeData.id] = pathsData or {}

    if panel.view == "edit" and panel.editStore and panel.editStore.id == storeData.id then
        panel.editStore = storeData
        panel.editPaths = pathsData or {}
    end
end)

addEvent("AdminMagasin:receivePathData", true)
addEventHandler("AdminMagasin:receivePathData", localPlayer, function(pathData)
    if not pathData then return end
    panel.visible = false
    showCursor(false)
    enableControls(true)
    triggerEvent("AdminMagasin:showPath", localPlayer, pathData.data, pathData.id)
end)

-- ═══════════════════════════════════════════════════════════════
-- 🧹 NETTOYAGE
-- ═══════════════════════════════════════════════════════════════

addEventHandler("onClientResourceStop", resourceRoot, function()
    if panel.visible then
        panel.visible = false
        showCursor(false)
        enableControls(true)
    end
    removeEventHandler("onClientRender", root, renderPanel)
end)