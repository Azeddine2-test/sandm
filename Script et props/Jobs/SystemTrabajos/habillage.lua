-- ============================================================================
-- HABILLAGE — fenêtres CEGUI natives au thème du menu d'animations
-- (demande 22, 16/10/2026 : « toutes les interfaces du serveur doivent adopter
-- le même thème visuel que celui du menu d'animations »)
-- ============================================================================
-- CEGUI (guiCreateWindow, guiCreateButton…) ne sait dessiner ni coins arrondis
-- ni Poppins, et son habillage gris de MTA ne se recolore pas. Plutôt que de
-- réécrire chaque fenêtre en dx (et risquer d'en casser la logique), on garde
-- les éléments CEGUI tels quels — ils reçoivent toujours les clics, la frappe,
-- le glisser de la barre de titre et des curseurs, et déclenchent toujours
-- leurs onClientGUIClick / onClientGUIScroll — mais on les rend INVISIBLES
-- (alpha 0 sur la fenêtre, hérité par ses enfants) et on redessine chacun à
-- sa place exacte, à chaque image, avec les formes du thème (THEME) :
--   fenêtre  → panneau arrondi « fond », poignée, titre Poppins SemiBold ;
--   bouton   → THEME.bouton (gris, survol plus clair ; rouge / bleu si le
--              script avait coloré son texte en rouge / vert) ;
--   champ    → THEME.champ (fond « surface », soulignement bleu au focus),
--              texte, curseur clignotant, masque, lecture seule ;
--   texte    → Poppins à la taille du panel admin (13), couleur gardée si le
--              script l'avait choisie, sinon « texte2 » ;
--   case à cocher / bouton radio → case / pastille, bleu quand coché ;
--   barre de défilement → rail et poignée bleue (même géométrie que CEGUI) ;
--   onglets  → bandeau d'onglets (actif en bleu) et zone « carte ».
--
-- Usage (après guiCreateWindow et ses enfants) :
--   if HABILLAGE then HABILLAGE.appliquer(fenetre) end
-- Champ de saisie ISOLÉ (guiCreateEdit / guiCreateMemo sans fenêtre, posé sur
-- un panneau dx — tablette du MDC, object_admin) :
--   if type(HABILLAGE) == "table" then HABILLAGE.champ(edit) end
-- Le champ (alpha 0) reçoit toujours la frappe ; il est redessiné au thème
-- tant qu'il est visible, avec sa bulle « Tooltip » comme texte d'aide grisé
-- quand il est vide et inactif.
-- La fenêtre détruite est oubliée toute seule. theme.lua doit être chargé
-- AVANT ce fichier (même meta.xml).
--
-- ⚠ Fichier COPIÉ À L'IDENTIQUE dans chaque ressource qui l'emploie (copie
--   canonique : [Lib]/neon_theme/habillage.lua) ; tools/test_demande22.lua
--   échoue si une copie diverge.
-- ============================================================================
if type(HABILLAGE) ~= "table" then HABILLAGE = {} end
local H = HABILLAGE
H.liste = H.liste or {}
H.ongletDemande = H.ongletDemande or {}
H.champs = H.champs or {}

local POST = true            -- au-dessus des autres dessins dx, comme une fenêtre
local PAD = 8                -- marge intérieure des champs (px)

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
local function T() return THEME end

local function prop(el, nom)
    if not guiGetProperty then return nil end
    local ok, v = pcall(guiGetProperty, el, nom)
    if ok and v ~= false then return v end
    return nil
end

local function nombre(v)
    if v == nil then return nil end
    local n = tonumber(v)
    if n then return n end
    -- UDim CEGUI « {échelle,décalage} »
    local d = tostring(v):match("{%s*[%-%d%.]+%s*,%s*([%-%d%.]+)%s*}")
    return tonumber(d)
end

local function hexRVB(s)
    local _, r, g, b = tostring(s or ""):match("(%x%x)(%x%x)(%x%x)(%x%x)")
    if not r then return nil end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function ulen(s)
    if utf8 and utf8.len then return utf8.len(s) or #s end
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

local function usub(s, i, j)
    if utf8 and utf8.sub then return utf8.sub(s, i, j) end
    -- repli : découpe par caractères UTF-8
    local car = {}
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do car[#car + 1] = c end
    j = j or #car
    if j < 0 then j = #car + j + 1 end
    if i < 0 then i = #car + i + 1 end
    return table.concat(car, "", math.max(1, i), math.min(#car, j))
end

local function curseur()
    if not (isCursorShowing and isCursorShowing()) then return nil, nil end
    local cx, cy = getCursorPosition()
    if not cx then return nil, nil end
    local sw, sh = guiGetScreenSize()
    return cx * sw, cy * sh
end

local function dans(px, py, x, y, l, h)
    return px and py and px >= x and px <= x + l and py >= y and py <= y + h or false
end

-- Taille du texte : celle du panel admin (13) ; plancher 11 dans les cases
-- trop basses pour 13 (une ligne Poppins 13 fait ~17 px).
function H.taille(h)
    local t = T()
    if not h or h >= 20 then return t.PANEL end
    return math.max(11, math.min(t.PANEL, math.floor(h * 0.75 + 0.5)))
end

-- Police qui tient dans la largeur : on part de la taille du panel (ou de
-- celle que permet la hauteur) et on descend jusqu'au plancher 11.
function H.policeAjustee(poids, tx, l, h)
    local t = T()
    local taille = H.taille(h)
    local f = t.police(poids, taille)
    while taille > 11 and dxGetTextWidth(tx, 1, f) > l do
        taille = taille - 1
        f = t.police(poids, taille)
    end
    return f, taille
end

local function visible(el)
    return isElement(el) and (not guiGetVisible or guiGetVisible(el))
end

local function enfants(el)
    local l = getElementChildren and getElementChildren(el) or {}
    local r = {}
    for _, e in ipairs(l) do
        local ty = getElementType(e)
        if ty and ty:sub(1, 4) == "gui-" then r[#r + 1] = e end
    end
    return r
end

local function position(el)
    local x, y = guiGetPosition(el, false)
    local l, h = guiGetSize(el, false)
    return x or 0, y or 0, l or 0, h or 0
end

-- ---------------------------------------------------------------------------
-- Dessin des éléments
-- ---------------------------------------------------------------------------
local dessiner -- (récursif)

local function texte(tx, x, y, x2, y2, col, police, ax, ay, clip, wrap)
    dxDrawText(tx, x, y, x2, y2, col, 1, police, ax or "left", ay or "top", clip or false, wrap or false, POST)
end

local function dessinerLabel(el, x, y, l, h, px, py)
    local t = T()
    local tx = guiGetText(el) or ""
    if tx == "" then return end
    local r, g, b = 255, 255, 255
    if guiLabelGetColor then r, g, b = guiLabelGetColor(el) end
    local col = (r == 255 and g == 255 and b == 255 or not r) and t.c("texte2") or tocolor(r, g, b, 255)
    local gras = tostring(guiGetFont and guiGetFont(el) or ""):find("bold") ~= nil
    local hf = tostring(prop(el, "HorzFormatting") or "")
    local police = hf:find("WordWrap") and t.police(gras and "semibold" or "medium", H.taille(h))
        or H.policeAjustee(gras and "semibold" or "medium", tx, l, h)
    local vf = tostring(prop(el, "VertFormatting") or "")
    local ax = hf:find("Centred") and "center" or (hf:find("Right") and "right" or "left")
    local ay = vf:find("Centred") and "center" or (vf:find("Bottom") and "bottom" or "top")
    texte(tx, x, y, x + l, y + h, col, police, ax, ay, false, hf:find("WordWrap") ~= nil)
end

local function genreBouton(el)
    if guiGetEnabled and not guiGetEnabled(el) then return "inactif" end
    local r, g, b = hexRVB(prop(el, "NormalTextColour"))
    if r then
        if r >= 180 and g <= 120 and b <= 120 then return "danger" end    -- texte rouge : annuler
        if g >= 180 and r <= 150 and b <= 180 then return "actif" end     -- texte vert : valider
    end
    return nil
end
H.genreBouton = genreBouton

local function dessinerBouton(el, x, y, l, h, px, py)
    local t = T()
    local genre = genreBouton(el)
    local survol = genre ~= "inactif" and dans(px, py, x, y, l, h)
    local col = t.bouton(x, y, l, h, survol, genre, t.R.bouton, POST)
    local tx = guiGetText(el) or ""
    texte(tx, x + 4, y, x + l - 4, y + h, col, H.policeAjustee("medium", tx, l - 8, h), "center", "center", true)
end

local function dessinerChamp(el, x, y, l, h, px, py, memo)
    local t = T()
    local focus = H.focus == el
    local lecture = prop(el, "ReadOnly") == "True"
    t.champ(x, y, l, h, focus and not lecture, t.R.bouton, POST)
    local tx = guiGetText(el) or ""
    if not memo and prop(el, "MaskText") == "True" then tx = string.rep("•", ulen(tx)) end
    local police = t.police("medium", H.taille(memo and 20 or h))
    local col = lecture and t.c("texte2") or t.c("texte")
    if memo then
        texte(tx, x + PAD, y + 4, x + l - PAD, y + h - 4, col, police, "left", "top", true, true)
        return
    end
    -- une ligne : si le texte déborde, on montre la fin quand on écrit
    local dispo = l - 2 * PAD
    local debut, n = 1, ulen(tx)
    if focus then
        while debut < n and dxGetTextWidth(usub(tx, debut, n), 1, police) > dispo do debut = debut + 1 end
    end
    local vu = usub(tx, debut, n)
    texte(vu, x + PAD, y, x + l - PAD, y + h, col, police, "left", "center", true)
    if n == 0 and not focus then
        local aide = prop(el, "Tooltip")
        if aide and aide ~= "" then
            texte(aide, x + PAD, y, x + l - PAD, y + h, t.c("texteDim"), police, "left", "center", true)
        end
    end
    if focus and not lecture and (getTickCount() % 1000) < 550 then
        local car = guiEditGetCaretIndex and guiEditGetCaretIndex(el) or n
        car = math.max(0, math.min(n, tonumber(car) or n))
        local avant = car >= debut and usub(tx, debut, car) or ""
        local cx = math.min(x + l - PAD, x + PAD + dxGetTextWidth(avant, 1, police))
        local ch = math.min(h - 8, 18)
        dxDrawRectangle(cx, y + (h - ch) / 2, 1, ch, t.c("accent"), POST)
    end
end

local function dessinerCoche(el, x, y, l, h, px, py, radio)
    local t = T()
    local coche
    if radio then coche = guiRadioButtonGetSelected and guiRadioButtonGetSelected(el)
    else coche = guiCheckBoxGetSelected and guiCheckBoxGetSelected(el) end
    local c = math.min(16, h)
    local cx, cy = x, y + (h - c) / 2
    local survol = dans(px, py, x, y, l, h)
    if radio then
        t.rect(cx, cy, c, c, c / 2, coche and t.c("accent") or (survol and t.c("boutonSurvol") or t.c("surface")), POST)
        if coche then t.rect(cx + c * 0.3, cy + c * 0.3, c * 0.4, c * 0.4, c * 0.2, t.c("texte"), POST) end
    else
        t.rect(cx, cy, c, c, t.R.petit, coche and t.c("accent") or (survol and t.c("boutonSurvol") or t.c("surface")), POST)
        if coche and dxDrawLine then
            local blanc = t.c("texte")
            dxDrawLine(cx + c * 0.22, cy + c * 0.52, cx + c * 0.42, cy + c * 0.72, blanc, 2, POST)
            dxDrawLine(cx + c * 0.42, cy + c * 0.72, cx + c * 0.78, cy + c * 0.3, blanc, 2, POST)
        end
    end
    texte(guiGetText(el) or "", x + c + 7, y, x + l + 40, y + h, coche and t.c("texte") or t.c("texte2"),
        t.police("medium", H.taille(h)), "left", "center", false)
end

-- Géométrie de la poignée : celle de CEGUI (flèches carrées aux bouts, poignée
-- proportionnelle à PageSize / DocumentSize), pour que la poignée dessinée
-- tombe sur la vraie, qu'on attrape à la souris.
function H.geometrieBarre(x, y, l, h, pos, page, doc)
    local horiz = l >= h
    local long, epais = horiz and l or h, horiz and h or l
    local fleche = epais
    local rail = math.max(0, long - 2 * fleche)
    local ratio = (page and doc and doc > 0) and math.max(0.05, math.min(1, page / doc)) or 0.1
    local poignee = math.max(math.min(rail, epais), rail * ratio)
    local debut = fleche + (rail - poignee) * math.max(0, math.min(100, pos or 0)) / 100
    if horiz then return horiz, x + fleche, x + debut, poignee, fleche, rail end
    return horiz, y + fleche, y + debut, poignee, fleche, rail
end

local function dessinerBarre(el, x, y, l, h, px, py)
    local t = T()
    local pos = guiScrollBarGetScrollPosition and guiScrollBarGetScrollPosition(el) or 0
    local horiz, railDebut, pDebut, pLong, fleche, rail = H.geometrieBarre(x, y, l, h, pos,
        nombre(prop(el, "PageSize")), nombre(prop(el, "DocumentSize")))
    local survol = dans(px, py, x, y, l, h)
    local fin = t.c("texteDim")
    if horiz then
        local e = math.max(4, h * 0.22)
        t.rect(railDebut, y + (h - e) / 2, rail, e, e / 2, t.c("surface"), POST)
        t.rect(railDebut, y + (h - e) / 2, pDebut - railDebut, e, e / 2, t.c("accent", 150), POST)
        t.rect(pDebut, y + 3, pLong, h - 6, math.min(t.R.bouton, (h - 6) / 2), survol and t.c("accentSurvol") or t.c("accent"), POST)
        texte("‹", x, y, x + fleche, y + h, fin, t.police("semibold", H.taille(h)), "center", "center")
        texte("›", x + l - fleche, y, x + l, y + h, fin, t.police("semibold", H.taille(h)), "center", "center")
    else
        local e = math.max(4, l * 0.22)
        t.rect(x + (l - e) / 2, railDebut, e, rail, e / 2, t.c("surface"), POST)
        t.rect(x + 3, pDebut, l - 6, pLong, math.min(t.R.bouton, (l - 6) / 2), survol and t.c("accentSurvol") or t.c("accent"), POST)
    end
end

-- Onglets : bandeau dessiné par nous, largeurs selon Poppins. Les en-têtes
-- CEGUI (invisibles) n'ont pas les mêmes largeurs : un clic dans le bandeau
-- est donc relu sur NOS en-têtes et l'onglet choisi est imposé à l'image
-- suivante (quel que soit l'ordre dans lequel CEGUI a traité le clic).
function H.hauteurOnglets(tp)
    local h = nombre(prop(tp, "AbsoluteTabHeight")) or nombre(prop(tp, "TabHeight"))
    if h and h >= 12 and h <= 60 then return h end
    return 24
end

function H.entetesOnglets(tp, x, y, l)
    local t = T()
    local hT = H.hauteurOnglets(tp)
    local police = t.police("medium", 12)
    local res, cx = {}, x
    local onglets = {}
    for _, e in ipairs(enfants(tp)) do if getElementType(e) == "gui-tab" then onglets[#onglets + 1] = e end end
    -- largeur naturelle, puis réduction proportionnelle si le bandeau déborde
    local total, larg = 0, {}
    for i, o in ipairs(onglets) do
        larg[i] = dxGetTextWidth(guiGetText(o) or "", 1, police) + 20
        total = total + larg[i] + 2
    end
    local k = total > l and (l / total) or 1
    for i, o in ipairs(onglets) do
        local w = larg[i] * k
        res[#res + 1] = { onglet = o, x = cx, y = y, l = w, h = hT - 3 }
        cx = cx + w + 2 * k
    end
    return res, hT, police
end

local function dessinerOnglets(el, x, y, l, h, px, py)
    local t = T()
    local entetes, hT, police = H.entetesOnglets(el, x, y, l)
    local actif = guiGetSelectedTab and guiGetSelectedTab(el)
    t.rect(x, y + hT, l, h - hT, t.R.carte, t.c("carte"), POST)
    for _, e in ipairs(entetes) do
        local choisi = e.onglet == actif
        local survol = dans(px, py, e.x, e.y, e.l, e.h)
        t.rect(e.x, e.y, e.l, e.h, t.R.bouton, choisi and t.c("choisi") or (survol and t.c("boutonSurvol") or t.c("bouton")), POST)
        texte(guiGetText(e.onglet) or "", e.x + 2, e.y, e.x + e.l - 2, e.y + e.h,
            choisi and t.c("texte") or t.c("texte2"), police, "center", "center", true)
    end
    if actif and visible(actif) then
        for _, c in ipairs(enfants(actif)) do dessiner(c, x, y + hT, px, py) end
    end
end

function dessiner(el, ox, oy, px, py)
    if not visible(el) then return end
    local x, y, l, h = position(el)
    x, y = ox + x, oy + y
    local ty = getElementType(el)
    if ty == "gui-label" then dessinerLabel(el, x, y, l, h, px, py)
    elseif ty == "gui-button" then dessinerBouton(el, x, y, l, h, px, py)
    elseif ty == "gui-edit" then dessinerChamp(el, x, y, l, h, px, py, false)
    elseif ty == "gui-memo" then dessinerChamp(el, x, y, l, h, px, py, true)
    elseif ty == "gui-checkbox" then dessinerCoche(el, x, y, l, h, px, py, false)
    elseif ty == "gui-radiobutton" then dessinerCoche(el, x, y, l, h, px, py, true)
    elseif ty == "gui-scrollbar" then dessinerBarre(el, x, y, l, h, px, py)
    elseif ty == "gui-tabpanel" then dessinerOnglets(el, x, y, l, h, px, py); return
    end
    for _, c in ipairs(enfants(el)) do dessiner(c, x, y, px, py) end
end

-- Rectangle arrondi d'un seul côté (haut ou bas), sans recouvrement : les
-- couleurs translucides du thème restent uniformes.
local function demiRect(x, y, l, h, r, col, haut)
    if l <= 0 or h <= 0 then return end
    r = math.max(0, math.min(r, l / 2, h))
    if r < 1 or not dxDrawCircle then dxDrawRectangle(x, y, l, h, col, POST) return end
    if haut then
        dxDrawRectangle(x + r, y, l - 2 * r, r, col, POST)
        dxDrawCircle(x + r, y + r, r, 180, 270, col, col, 8, 1, POST)
        dxDrawCircle(x + l - r, y + r, r, 270, 360, col, col, 8, 1, POST)
        dxDrawRectangle(x, y + r, l, h - r, col, POST)
    else
        dxDrawRectangle(x, y, l, h - r, col, POST)
        dxDrawRectangle(x + r, y + h - r, l - 2 * r, r, col, POST)
        dxDrawCircle(x + l - r, y + h - r, r, 0, 90, col, col, 8, 1, POST)
        dxDrawCircle(x + r, y + h - r, r, 90, 180, col, col, 8, 1, POST)
    end
end

-- Hauteur du bandeau de titre : jusqu'au premier enfant (CEGUI place les
-- enfants d'une fenêtre par rapport à son coin, barre de titre comprise).
function H.hauteurTitre(fen)
    local mini = 26
    for _, c in ipairs(enfants(fen)) do
        local _, cy = guiGetPosition(c, false)
        if cy and cy < mini then mini = cy end
    end
    return math.max(18, mini)
end

function H.dessinerFenetre(fen)
    local t = T()
    if not t or not visible(fen) then return end
    local px, py = curseur()
    local x, y, l, h = position(fen)
    local hT = H.hauteurTitre(fen)
    local r = math.min(t.R.panneau, l / 2, (hT + 4) / 2, (h - hT - 4) / 2)
    demiRect(x, y, l, hT + 4, r, t.c("entete"), true)               -- bandeau : coins du haut
    demiRect(x, y + hT + 4, l, h - hT - 4, r, t.c("fond"), false)   -- corps : coins du bas
    dxDrawRectangle(x + 10, y + hT + 3, l - 20, 1, t.c("lisere"), POST)
    texte(guiGetText(fen) or "", x + 12, y, x + l - 12, y + hT + 3, t.c("texte"),
        t.police("semibold", H.taille(hT + 2)), "left", "center", true)
    for _, c in ipairs(enfants(fen)) do dessiner(c, x, y, px, py) end
end

-- ---------------------------------------------------------------------------
-- Enregistrement
-- ---------------------------------------------------------------------------
function H.appliquer(fen)
    if not isElement(fen) then return false end
    for _, f in ipairs(H.liste) do if f == fen then return true end end
    if guiSetAlpha then guiSetAlpha(fen, 0) end        -- les enfants héritent : tout l'habillage MTA disparaît
    H.liste[#H.liste + 1] = fen
    return true
end

function H.champ(el)
    if not isElement(el) then return false end
    for _, c in ipairs(H.champs) do if c == el then return true end end
    if guiSetAlpha then guiSetAlpha(el, 0) end         -- invisible mais toujours saisissable
    H.champs[#H.champs + 1] = el
    return true
end

function H.retirer(fen)
    for i = #H.liste, 1, -1 do
        if H.liste[i] == fen then table.remove(H.liste, i) end
    end
    if isElement(fen) and guiSetAlpha then guiSetAlpha(fen, 1) end
end

function H.surRendu()
    for i = #H.liste, 1, -1 do
        local f = H.liste[i]
        if not isElement(f) then table.remove(H.liste, i) end
    end
    -- onglet demandé par un clic sur NOTRE bandeau
    for tp, o in pairs(H.ongletDemande) do
        if isElement(tp) and isElement(o) and guiSetSelectedTab then guiSetSelectedTab(tp, o) end
        H.ongletDemande[tp] = nil
    end
    for _, f in ipairs(H.liste) do H.dessinerFenetre(f) end
    -- champs isolés : position écran = position propre (pas de parent GUI)
    for i = #H.champs, 1, -1 do
        if not isElement(H.champs[i]) then table.remove(H.champs, i) end
    end
    if #H.champs > 0 then
        local px, py = curseur()
        for _, c in ipairs(H.champs) do
            if visible(c) then
                local x, y, l, h = position(c)
                dessinerChamp(c, x, y, l, h, px, py, getElementType(c) == "gui-memo")
            end
        end
    end
end

-- Position à l'écran d'un élément (somme des positions jusqu'à la fenêtre,
-- bandeau d'onglets compris).
function H.positionEcran(el)
    local x, y = guiGetPosition(el, false)
    x, y = x or 0, y or 0
    local p = getElementParent(el)
    while p and isElement(p) and tostring(getElementType(p)):sub(1, 4) == "gui-" do
        local ty = getElementType(p)
        if ty == "gui-tab" then
            local tp = getElementParent(p)
            local tx, tyy = H.positionEcran(tp)
            return x + tx, y + tyy + H.hauteurOnglets(tp)
        end
        local px, py = guiGetPosition(p, false)
        x, y = x + (px or 0), y + (py or 0)
        p = getElementParent(p)
    end
    return x, y
end

function H.surClicOnglets()
    local px, py = curseur()
    if not px then return end
    for _, f in ipairs(H.liste) do
        if visible(f) then
            local pile = { f }
            while #pile > 0 do
                local e = table.remove(pile)
                for _, c in ipairs(enfants(e)) do
                    if getElementType(c) == "gui-tabpanel" and visible(c) then
                        local x, y = H.positionEcran(c)
                        local l = select(1, guiGetSize(c, false))
                        for _, en in ipairs((H.entetesOnglets(c, x, y, l or 0))) do
                            if dans(px, py, en.x, en.y, en.l, en.h) then H.ongletDemande[c] = en.onglet end
                        end
                    end
                    pile[#pile + 1] = c
                end
            end
        end
    end
end

function H.surFocus() H.focus = source end
function H.surBlur() if H.focus == source then H.focus = nil end end

if addEventHandler and not H._branche then
    H._branche = true
    addEventHandler("onClientRender", root, H.surRendu)
    addEventHandler("onClientGUIFocus", root, H.surFocus)
    addEventHandler("onClientGUIBlur", root, H.surBlur)
    addEventHandler("onClientGUIMouseDown", root, H.surClicOnglets)
    addEventHandler("onClientGUIClick", root, H.surClicOnglets)
end
