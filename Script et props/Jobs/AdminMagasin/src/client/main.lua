-- ============================================================
-- client/main.lua - Client principal AdminMagasin
-- Version clean : sans panel graphique, sans marker admin, conserve :
-- - hook caméra/position caissier
-- - /magasinedit éditeur visuel
-- - copy clipboard
-- - force exit caissier
-- ============================================================

local storesDataCache = {}

local function notify(message, nType)
    nType = nType or "info"
    local fuNotify = getResourceFromName("[FU]Notify")
    if fuNotify and getResourceState(fuNotify) == "running" then
        exports["[FU]Notify"]:notify(message, nType)
    else
        local colors = {
            success = {87, 242, 135},
            error = {237, 66, 69},
            info = {88, 165, 255},
            infos = {88, 165, 255},
            warning = {254, 231, 92},
            aviso = {254, 231, 92},
        }
        local c = colors[nType] or colors.info
        outputChatBox("[AdminMagasin] " .. tostring(message), c[1], c[2], c[3])
    end
end

-- ═══════════════════════════════════════════════════════════════
-- CACHE DES DONNÉES MAGASINS POUR HOOK CAISSIER
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:receiveAllStoresData", true)
addEventHandler("AdminMagasin:receiveAllStoresData", localPlayer, function(stores)
    storesDataCache = stores or {}
end)

local function requestAllStoresData()
    triggerServerEvent("AdminMagasin:requestAllStoresData", localPlayer)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(requestAllStoresData, 2000, 1)
end)

addEvent("AdminMagasin:notifyStoresChanged", true)
addEventHandler("AdminMagasin:notifyStoresChanged", root, requestAllStoresData)

-- ═══════════════════════════════════════════════════════════════
-- HOOK MODE CAISSIER : POSITION + CAMERA
-- S'exécute après SystemTrabajos client.
-- ═══════════════════════════════════════════════════════════════

addEvent("v1:enterCashierMode", true)
addEventHandler("v1:enterCashierMode", root, function(storeID)
    local store = storesDataCache[storeID]
    if not store then
        requestAllStoresData()
        outputDebugString("[AdminMagasin] Magasin #" .. tostring(storeID) .. " absent du cache, sync demandee.")
        return
    end

    setTimer(function()
        if not isElement(localPlayer) then return end

        if store.cashier and store.cashier.isSet then
            setElementPosition(localPlayer, store.cashier.x, store.cashier.y, store.cashier.z)
            setElementRotation(localPlayer, 0, 0, store.cashier.rot or 0)
        end

        if store.camera and store.camera.isSet and store.camera.x then
            setCameraMatrix(
                store.camera.x, store.camera.y, store.camera.z,
                store.camera.tx, store.camera.ty, store.camera.tz
            )
        end
    end, 100, 1)
end, true, "low+1")

-- ═══════════════════════════════════════════════════════════════
-- FORCE EXIT CAISSIER
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:forceExitCashier", true)
addEventHandler("AdminMagasin:forceExitCashier", localPlayer, function()
    setCameraTarget(localPlayer)
    setElementFrozen(localPlayer, false)
    setElementAlpha(localPlayer, 255)
    showCursor(false)
    notify("Mode caissier force a s'arreter par un admin.", "success")
end)

-- ═══════════════════════════════════════════════════════════════
-- CLIPBOARD
-- ═══════════════════════════════════════════════════════════════

addEvent("AdminMagasin:copyToClipboard", true)
addEventHandler("AdminMagasin:copyToClipboard", localPlayer, function(text)
    if text and setClipboard then
        setClipboard(text)
        notify("Copie dans le presse-papiers !", "success")
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- EDITEUR VISUEL /magasinedit
-- ═══════════════════════════════════════════════════════════════

local editingObj = nil
local editorWindow = nil
local editorCurrentPos = nil
local editorStoreID = nil
local editorEditType = nil
local editorExtraData = nil
local editorMoveSpeed = 0.1
local editorCoordsLabel = nil
local editorPreviewMode = false

local function getEditorBasketModel()
    local res = getResourceFromName("SystemTrabajos")
    if res and getResourceState(res) == "running" then
        local ok, basketID = pcall(function()
            return exports.SystemTrabajos:getCustomBasketID()
        end)
        if ok and basketID and tonumber(basketID) then
            return tonumber(basketID)
        end
    end
    return 2905
end

local function updateEditorObject()
    if not isElement(editingObj) or not editorCurrentPos then return end
    setElementPosition(editingObj, editorCurrentPos.x, editorCurrentPos.y, editorCurrentPos.z)
    setElementRotation(editingObj, editorCurrentPos.rx or 0, editorCurrentPos.ry or 0, editorCurrentPos.rz or 0)
end

local function updateCoordsLabel()
    if not isElement(editorCoordsLabel) or not editorCurrentPos then return end
    guiSetText(editorCoordsLabel, string.format(
        "X: %.2f  Y: %.2f  Z: %.2f\nRX: %.1f°  RY: %.1f°  RZ: %.1f°",
        editorCurrentPos.x, editorCurrentPos.y, editorCurrentPos.z,
        editorCurrentPos.rx or 0, editorCurrentPos.ry or 0, editorCurrentPos.rz or 0
    ))
end

local function editorMove(axis, dir)
    if not editorCurrentPos then return end

    if axis == "x" then
        editorCurrentPos.x = editorCurrentPos.x + (editorMoveSpeed * dir)
    elseif axis == "y" then
        editorCurrentPos.y = editorCurrentPos.y + (editorMoveSpeed * dir)
    elseif axis == "z" then
        editorCurrentPos.z = editorCurrentPos.z + (editorMoveSpeed * dir)
    elseif axis == "rx" then
        editorCurrentPos.rx = (editorCurrentPos.rx or 0) + (editorMoveSpeed * 10 * dir)
    elseif axis == "ry" then
        editorCurrentPos.ry = (editorCurrentPos.ry or 0) + (editorMoveSpeed * 10 * dir)
    elseif axis == "rz" then
        editorCurrentPos.rz = (editorCurrentPos.rz or 0) + (editorMoveSpeed * 10 * dir)
    end

    updateEditorObject()
    updateCoordsLabel()
end

local function closeEditor(cancelled)
    if isElement(editorWindow) then destroyElement(editorWindow) end
    if isElement(editingObj) then destroyElement(editingObj) end

    editorWindow = nil
    editingObj = nil
    editorCurrentPos = nil
    editorStoreID = nil
    editorEditType = nil
    editorExtraData = nil
    editorCoordsLabel = nil
    editorPreviewMode = false

    showCursor(false)

    if cancelled then
        notify("Edition annulee.", "warning")
    end
end

local function saveEditor()
    if not editorCurrentPos or not editorStoreID or not editorEditType then
        return notify("Erreur : donnees manquantes.", "error")
    end

    triggerServerEvent("AdminMagasin:saveEditedPosition", localPlayer, editorStoreID, editorEditType, editorCurrentPos, editorExtraData)
    closeEditor(false)
end

local function resetToPlayerPos()
    if not editorCurrentPos then return end

    local x, y, z = getElementPosition(localPlayer)
    local rx, ry, rz = getElementRotation(localPlayer)

    editorCurrentPos.x = x
    editorCurrentPos.y = y
    editorCurrentPos.z = z
    editorCurrentPos.rx = rx
    editorCurrentPos.ry = ry
    editorCurrentPos.rz = rz

    updateEditorObject()
    updateCoordsLabel()
    notify("Position reset a la position du joueur.", "info")
end

local function togglePreview()
    if editorPreviewMode then return end
    editorPreviewMode = true

    if isElement(editorWindow) then guiSetVisible(editorWindow, false) end
    showCursor(false)

    setTimer(function()
        editorPreviewMode = false
        if isElement(editorWindow) then guiSetVisible(editorWindow, true) end
        showCursor(true)
    end, 2000, 1)
end

local function createEditorPanel(typeLabel)
    if isElement(editorWindow) then destroyElement(editorWindow) end

    local sw, sh = guiGetScreenSize()
    local panelW, panelH = 340, 500
    editorWindow = guiCreateWindow(sw - panelW - 20, (sh - panelH) / 2, panelW, panelH, "Éditeur : " .. (typeLabel or "?"), false)
    guiWindowSetSizable(editorWindow, false)

    guiCreateLabel(15, 30, panelW - 30, 15, "COORDONNÉES ACTUELLES", false, editorWindow)
    editorCoordsLabel = guiCreateLabel(15, 48, panelW - 30, 40, "...", false, editorWindow)
    guiLabelSetColor(editorCoordsLabel, 87, 242, 135)

    guiCreateLabel(15, 95, panelW - 30, 15, "VITESSE DE DÉPLACEMENT : 0,01 / 0,1 / 1", false, editorWindow)
    local rSlow = guiCreateRadioButton(15, 115, 90, 20, "Lent", false, editorWindow)
    local rNormal = guiCreateRadioButton(110, 115, 90, 20, "Normal", false, editorWindow)
    local rFast = guiCreateRadioButton(210, 115, 90, 20, "Rapide", false, editorWindow)
    guiRadioButtonSetSelected(rNormal, true)

    addEventHandler("onClientGUIClick", rSlow, function() editorMoveSpeed = 0.01 end, false)
    addEventHandler("onClientGUIClick", rNormal, function() editorMoveSpeed = 0.1 end, false)
    addEventHandler("onClientGUIClick", rFast, function() editorMoveSpeed = 1.0 end, false)

    guiCreateLabel(15, 145, panelW - 30, 15, "POSITION (X, Y, Z) :", false, editorWindow)
    local btnXMinus = guiCreateButton(15, 165, 45, 30, "X-", false, editorWindow)
    local btnXPlus = guiCreateButton(65, 165, 45, 30, "X+", false, editorWindow)
    local btnYMinus = guiCreateButton(120, 165, 45, 30, "Y-", false, editorWindow)
    local btnYPlus = guiCreateButton(170, 165, 45, 30, "Y+", false, editorWindow)
    local btnZMinus = guiCreateButton(225, 165, 45, 30, "Z-", false, editorWindow)
    local btnZPlus = guiCreateButton(275, 165, 45, 30, "Z+", false, editorWindow)

    addEventHandler("onClientGUIClick", btnXMinus, function() editorMove("x", -1) end, false)
    addEventHandler("onClientGUIClick", btnXPlus, function() editorMove("x", 1) end, false)
    addEventHandler("onClientGUIClick", btnYMinus, function() editorMove("y", -1) end, false)
    addEventHandler("onClientGUIClick", btnYPlus, function() editorMove("y", 1) end, false)
    addEventHandler("onClientGUIClick", btnZMinus, function() editorMove("z", -1) end, false)
    addEventHandler("onClientGUIClick", btnZPlus, function() editorMove("z", 1) end, false)

    guiCreateLabel(15, 205, panelW - 30, 15, "ROTATION (RX, RY, RZ) :", false, editorWindow)
    local btnRXMinus = guiCreateButton(15, 225, 45, 30, "RX-", false, editorWindow)
    local btnRXPlus = guiCreateButton(65, 225, 45, 30, "RX+", false, editorWindow)
    local btnRYMinus = guiCreateButton(120, 225, 45, 30, "RY-", false, editorWindow)
    local btnRYPlus = guiCreateButton(170, 225, 45, 30, "RY+", false, editorWindow)
    local btnRZMinus = guiCreateButton(225, 225, 45, 30, "RZ-", false, editorWindow)
    local btnRZPlus = guiCreateButton(275, 225, 45, 30, "RZ+", false, editorWindow)

    addEventHandler("onClientGUIClick", btnRXMinus, function() editorMove("rx", -1) end, false)
    addEventHandler("onClientGUIClick", btnRXPlus, function() editorMove("rx", 1) end, false)
    addEventHandler("onClientGUIClick", btnRYMinus, function() editorMove("ry", -1) end, false)
    addEventHandler("onClientGUIClick", btnRYPlus, function() editorMove("ry", 1) end, false)
    addEventHandler("onClientGUIClick", btnRZMinus, function() editorMove("rz", -1) end, false)
    addEventHandler("onClientGUIClick", btnRZPlus, function() editorMove("rz", 1) end, false)

    local btnReset = guiCreateButton(15, 275, panelW - 30, 30, "Revenir à ma position", false, editorWindow)
    addEventHandler("onClientGUIClick", btnReset, resetToPlayerPos, false)

    local btnPreview = guiCreateButton(15, 315, panelW - 30, 30, "Aperçu (2 s sans le panneau)", false, editorWindow)
    addEventHandler("onClientGUIClick", btnPreview, togglePreview, false)

    local btnSave = guiCreateButton(15, 375, panelW - 30, 45, "✓ SAUVEGARDER", false, editorWindow)
    guiSetProperty(btnSave, "NormalTextColour", "FF57F287")

    local btnCancel = guiCreateButton(15, 430, panelW - 30, 45, "✗ ANNULER", false, editorWindow)
    guiSetProperty(btnCancel, "NormalTextColour", "FFED4245")

    addEventHandler("onClientGUIClick", btnSave, saveEditor, false)
    addEventHandler("onClientGUIClick", btnCancel, function() closeEditor(true) end, false)
    if type(HABILLAGE) == "table" then HABILLAGE.appliquer(editorWindow) end   -- demande 22 : thème du menu d'animations
end

addEvent("AdminMagasin:openEditPanel", true)
addEventHandler("AdminMagasin:openEditPanel", localPlayer, function(storeId, editData)
    if not storeId or not editData then return end

    if isElement(editorWindow) then closeEditor(true) end

    editorStoreID = storeId
    editorEditType = editData.type
    editorExtraData = {
        productIndex = editData.productIndex,
        cameraTarget = editData.cameraTarget,
    }

    editorCurrentPos = {
        x = editData.pos.x,
        y = editData.pos.y,
        z = editData.pos.z,
        rx = editData.pos.rx or 0,
        ry = editData.pos.ry or 0,
        rz = editData.pos.rz or 0,
    }

    local modelToUse = editData.model or 2905
    local scale = editData.scale or 1.0

    if editData.useCustomBasket then
        modelToUse = getEditorBasketModel()
    end

    editingObj = createObject(modelToUse, editorCurrentPos.x, editorCurrentPos.y, editorCurrentPos.z, editorCurrentPos.rx, editorCurrentPos.ry, editorCurrentPos.rz)
    if not isElement(editingObj) then
        notify("Erreur : impossible de creer l'objet fantome.", "error")
        return
    end

    setObjectScale(editingObj, scale)
    setElementCollisionsEnabled(editingObj, false)
    setElementAlpha(editingObj, 180)

    createEditorPanel(editData.typeLabel)
    updateCoordsLabel()
    showCursor(true)

    notify("Editeur ouvert. Ajuste puis sauvegarde.", "info")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isElement(editorWindow) then destroyElement(editorWindow) end
    if isElement(editingObj) then destroyElement(editingObj) end
    storesDataCache = {}
end)

-- Demande 21 : BACKSPACE et Échap ferment l'éditeur de position (annulation),
-- comme le bouton « Annuler ». Champs CEGUI éventuels : BACKSPACE y efface.
if RETOUR then
    RETOUR.brancher({
        nom    = "editeur de magasin",
        ouvert = function() return isElement(editorWindow) and not editorPreviewMode end,
        retour = function() closeEditor(true) end,
    })
end
