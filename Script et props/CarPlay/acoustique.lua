-- ============================================================================
-- CarPlay — panneau admin « Acoustique » (demande 112, 04/11/2026 ; temps
-- réel pour tous, demande 112 quater)
-- ----------------------------------------------------------------------------
-- Ouvert par : clic droit sur le véhicule (i9) → Staff → Qualité audio.
-- Le serveur (ouvrirAcoustique) vérifie admin 3+ EN SERVICE avant d'envoyer
-- « carplay:acoustique:ouvrir ». Ne concerne que les liens audio directs :
-- le son YouTube vient d'un navigateur et MTA n'y applique aucun effet.
--
-- Disposition reprise de la vidéo « Acoustic SA » : barre de titre, recherche,
-- catégories à gauche, curseurs à droite (valeur au-dessus, repère du défaut
-- sur le rail, ↻ pour revenir au défaut), courbe d'égaliseur déplaçable,
-- boutons Enregistrer / Annuler / Défauts / Recharger / Fermer.
--
-- TEMPS RÉEL : l'admin entend chaque changement tout de suite
-- (CARPLAY_AUDIO.apercu) et le panneau l'envoie au serveur (au plus toutes
-- les 120 ms), qui l'applique au véhicule pour TOUS les joueurs proches.
-- « Enregistrer » l'écrit en base ; fermer sans enregistrer remet l'état
-- enregistré chez tout le monde.
--
-- Commandes : glisser = régler ; double-clic sur un curseur = défaut ; clic
-- sur la valeur = saisir la valeur exacte (Entrée) ; molette = défiler.
-- ============================================================================

local A = CARPLAY_AUDIO
local DEF = CARPLAY_ACOUSTIQUE_DEF
local CATS = CARPLAY_ACOUSTIQUE_CATEGORIES
local IDX = CARPLAY_ACOUSTIQUE_INDEX

if type(CARPLAY_ACOUSTIQUE) ~= "table" then CARPLAY_ACOUSTIQUE = {} end
local P = CARPLAY_ACOUSTIQUE

P.ouvert = false
P.vehicule = nil
P.nom = ""
P.persistant = true
P.enregistre = nil     -- dernier état enregistré (complet)
P.edite = nil          -- état en cours (complet)
P.cat = "radio"
P.recherche = ""
P.rechercheFocus = false
P.edition = nil        -- { cle, texte } : saisie d'une valeur exacte
P.defil = 0
P.glisse = nil         -- clé du curseur tenu, ou "eq" pour le point de la courbe
P.zones = {}
P.aEnvoyer = false     -- un changement attend d'être envoyé au serveur
P.ENVOI_MS = 120

-- ---------------------------------------------------------------------------
-- Couleurs (prises sur la vidéo) et échelle
-- ---------------------------------------------------------------------------
local COUL = {
    titre   = { 132, 24, 62 },
    fond    = { 38, 38, 41 },
    panneau = { 31, 31, 34 },
    champ   = { 21, 21, 23 },
    texte   = { 228, 228, 232 },
    gris    = { 150, 150, 158 },
    rose    = { 235, 140, 172 },
    rail    = { 64, 64, 70 },
    case    = { 70, 88, 140 },
    survol  = { 52, 52, 57 },
    bouton  = { 58, 58, 63 },
}
local function c(t, a) return tocolor(t[1], t[2], t[3], a or 255) end

local K, OX, OY = 1, 0, 0
local function cadrer()
    local sx, sy = guiGetScreenSize()
    K = math.min(sx / 1280, sy / 720)
    OX, OY = (sx - 1280 * K) / 2, (sy - 720 * K) / 2
end
local function X(u) return OX + u * K end
local function Y(u) return OY + u * K end
local function L(u) return u * K end

local polices = {}
local function police(taille, gras)
    local cle = taille .. (gras and "b" or "")
    if polices[cle] == nil then
        local fichier = gras and "assets/fonts/Inter-SemiBold.ttf" or "assets/fonts/Inter-Regular.ttf"
        polices[cle] = dxCreateFont(fichier, math.max(6, math.floor(taille * K + 0.5))) or false
    end
    return polices[cle] or "default"
end
local function libererPolices()
    for _, f in pairs(polices) do if isElement(f) then destroyElement(f) end end
    polices = {}
end

local function rect(x, y, w, h, coul) dxDrawRectangle(X(x), Y(y), L(w), L(h), coul) end
local function texte(t, x, y, w, h, coul, taille, gras, ax, ay)
    dxDrawText(t, X(x), Y(y), X(x + w), Y(y + h), coul, 1, police(taille or 9, gras), ax or "left", ay or "center", true)
end

local function souris()
    if not isCursorShowing() then return -1, -1 end
    local sx, sy = guiGetScreenSize()
    local mx, my = getCursorPosition()
    return ((mx * sx) - OX) / K, ((my * sy) - OY) / K
end
local function dans(x, y, w, h)
    local mx, my = souris()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- ---------------------------------------------------------------------------
-- Valeurs
-- ---------------------------------------------------------------------------
local function copie(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end

local function format(d, v)
    if d.type == "case" then return v and "Oui" or "Non" end
    local u = d.unite or ""
    if u == "dB" and d.perte then return string.format("%.1f dB de perte", v) end
    if u == "dB" then return string.format("%+.1f dB", v) end
    if u == "Hz" then return string.format("%d Hz", math.floor(v + 0.5)) end
    if u == "%" then return string.format("%d %%", math.floor(v + 0.5)) end
    if u == ":1" then return string.format("%.1f:1", v) end
    if (d.pas or 1) < 1 then return string.format("%.1f %s", v, u) end
    return string.format("%d %s", math.floor(v + 0.5), u)
end

-- position 0..1 sur le rail ↔ valeur (échelle logarithmique pour les Hz)
local function versPos(d, v)
    if d.log then return (math.log(v) - math.log(d.min)) / (math.log(d.max) - math.log(d.min)) end
    return (v - d.min) / (d.max - d.min)
end
local function depuisPos(d, p)
    p = math.max(0, math.min(1, p))
    local v
    if d.log then v = math.exp(math.log(d.min) + p * (math.log(d.max) - math.log(d.min)))
    else v = d.min + p * (d.max - d.min) end
    return carplayAcoustiqueBorner(d.cle, v)
end

-- L'état édité s'entend tout de suite chez l'admin, et part au serveur.
local function appliquerEdite()
    if not isElement(P.vehicule) or not P.edite then return end
    A.apercu[P.vehicule] = copie(P.edite)
    P.aEnvoyer = true
end

local function changer(cle, valeur)
    local b = carplayAcoustiqueBorner(cle, valeur)
    if b == nil or not P.edite then return end
    if P.edite[cle] == b then return end
    P.edite[cle] = b
    appliquerEdite()
end

-- Envoi en direct au serveur (au plus toutes les ENVOI_MS).
function P.envoyer()
    if not P.ouvert or not P.aEnvoyer or not isElement(P.vehicule) then return end
    P.aEnvoyer = false
    triggerServerEvent("carplay:acoustique:apercu", resourceRoot, P.vehicule, P.edite)
end

local function modifie()
    if not P.edite or not P.enregistre then return false end
    for _, d in ipairs(DEF) do if P.edite[d.cle] ~= P.enregistre[d.cle] then return true end end
    return false
end

-- ---------------------------------------------------------------------------
-- Recherche (sans accents, sans casse)
-- ---------------------------------------------------------------------------
local ACCENTS = { ["à"]="a", ["â"]="a", ["ä"]="a", ["é"]="e", ["è"]="e", ["ê"]="e", ["ë"]="e",
    ["î"]="i", ["ï"]="i", ["ô"]="o", ["ö"]="o", ["ù"]="u", ["û"]="u", ["ü"]="u", ["ç"]="c",
    ["É"]="e", ["È"]="e", ["À"]="a", ["Ç"]="c" }
local function simple(s)
    s = tostring(s or "")
    for a, b in pairs(ACCENTS) do s = s:gsub(a, b) end
    return s:lower()
end

local function lignesVisibles()
    local out = {}
    local q = simple(P.recherche)
    if q ~= "" then
        for _, d in ipairs(DEF) do
            if simple(d.nom):find(q, 1, true) or simple(d.aide or ""):find(q, 1, true) then out[#out + 1] = d end
        end
        return out
    end
    for _, d in ipairs(DEF) do if d.cat == P.cat then out[#out + 1] = d end end
    return out
end

-- ---------------------------------------------------------------------------
-- Géométrie (unités 1280 × 720)
-- ---------------------------------------------------------------------------
local W = { x = 280, y = 105, w = 720, h = 505 }
local G = { x = W.x + 8, y = W.y + 62, w = 106, h = 382 }            -- catégories
local D = { x = W.x + 120, y = W.y + 62, w = 592, h = 382 }          -- contenu
local LIGNE = 30
local RAIL = { x = D.x + 290, w = 255 }
local EQ_H = 128

-- Préréglages de l'égaliseur (une bande : limite de MTA, +15 dB au plus,
-- pas de centre sous 80 Hz).
PRESETS_EQ = {
    { nom = "Basses fortes", l = 76, valeurs = { eqActif = true, eqGain = 15, eqFrequence = 80, eqLargeur = 30 } },
    { nom = "Basses légères", l = 80, valeurs = { eqActif = true, eqGain = 7, eqFrequence = 90, eqLargeur = 24 } },
    { nom = "Plat", l = 40, valeurs = { eqActif = false, eqGain = 0, eqFrequence = 80, eqLargeur = 30 } },
}

-- Courbe : réponse de la bande paramétrique (cloche en octaves)
local FMIN, FMAX = 20, 20000
local function fx(f, gx, gw) return gx + gw * (math.log(f / FMIN) / math.log(FMAX / FMIN)) end
local function reponse(e, f)
    if not e.eqActif then return 0 end
    local oct = math.log(f / e.eqFrequence) / math.log(2)
    local sigma = math.max(0.05, (e.eqLargeur / 12) / 2.355)
    return e.eqGain * math.exp(-(oct * oct) / (2 * sigma * sigma))
end

-- ---------------------------------------------------------------------------
-- Dessin
-- ---------------------------------------------------------------------------
local function bouton(id, x, y, w, h, t, principal)
    local survol = dans(x, y, w, h)
    rect(x, y, w, h, principal and c(COUL.titre, survol and 255 or 225) or c(survol and COUL.survol or COUL.bouton))
    texte(t, x, y, w, h, c(COUL.texte), 8.5, false, "center")
    P.zones[#P.zones + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function dessinerCourbe(gx, gy, gw, gh)
    rect(gx, gy, gw, gh, c(COUL.champ))
    for _, g in ipairs({ 15, 7.5, 0, -7.5, -15 }) do
        local yy = gy + gh / 2 - (g / 15) * (gh / 2 - 8)
        dxDrawLine(X(gx + 20), Y(yy), X(gx + gw - 6), Y(yy), tocolor(255, 255, 255, g == 0 and 40 or 14), 1)
        texte(tostring(g), gx + 2, yy - 5, 16, 10, c(COUL.gris), 6.5)
    end
    for _, f in ipairs({ 100, 1000, 10000 }) do
        local xx = fx(f, gx + 20, gw - 26)
        dxDrawLine(X(xx), Y(gy + 4), X(xx), Y(gy + gh - 12), tocolor(255, 255, 255, 14), 1)
        texte(f >= 1000 and (f / 1000 .. "k") or (f .. " Hz"), xx - 20, gy + gh - 12, 40, 10, c(COUL.gris), 6.5, false, "center")
    end
    local e = P.edite
    local px, py
    for i = 0, 120 do
        local f = FMIN * (FMAX / FMIN) ^ (i / 120)
        local xx = fx(f, gx + 20, gw - 26)
        local yy = gy + gh / 2 - (reponse(e, f) / 15) * (gh / 2 - 8)
        if px then dxDrawLine(X(px), Y(py), X(xx), Y(yy), c(COUL.rose), math.max(1, L(1.6))) end
        px, py = xx, yy
    end
    local ptx = fx(e.eqFrequence, gx + 20, gw - 26)
    local pty = gy + gh / 2 - (e.eqGain / 15) * (gh / 2 - 8)
    local r = (P.glisse == "eq" or dans(ptx - 6, pty - 6, 12, 12)) and 5 or 4
    dxDrawCircle(X(ptx), Y(pty), L(r), 0, 360, c(COUL.rose, e.eqActif and 255 or 110), c(COUL.rose, e.eqActif and 255 or 110), 24)
    P.zones[#P.zones + 1] = { id = "eqpoint", x = ptx - 7, y = pty - 7, w = 14, h = 14 }
    P.courbe = { x = gx + 20, y = gy, w = gw - 26, h = gh }
end

local function dessinerLigne(d, y, survols)
    local e = P.edite
    local v = e[d.cle]
    texte(d.nom, D.x + 10, y, 270, LIGNE, c(COUL.texte), 8.5)
    if d.type == "case" then
        local bx, by = RAIL.x, y + LIGNE / 2 - 7
        rect(bx, by, 14, 14, v and c(COUL.case) or c(COUL.champ))
        if v then texte("✓", bx, by, 14, 14, c(COUL.rose), 9, true, "center") end
        P.zones[#P.zones + 1] = { id = "case", cle = d.cle, x = bx - 2, y = by - 2, w = 18, h = 18 }
    else
        local ry = y + LIGNE - 9
        local p = math.max(0, math.min(1, versPos(d, v)))
        rect(RAIL.x, ry, RAIL.w, 3, c(COUL.rail))
        rect(RAIL.x, ry, RAIL.w * p, 3, c(COUL.rose))
        local pd = math.max(0, math.min(1, versPos(d, d.defaut)))
        rect(RAIL.x + RAIL.w * pd - 0.5, ry - 3, 1, 9, tocolor(255, 255, 255, 90))
        local tenu = P.glisse == d.cle or dans(RAIL.x + RAIL.w * p - 5, ry - 5, 10, 13)
        rect(RAIL.x + RAIL.w * p - 4, ry - 4, 8, 11, tenu and c(COUL.rose) or tocolor(200, 200, 205))
        P.zones[#P.zones + 1] = { id = "rail", cle = d.cle, x = RAIL.x - 6, y = ry - 8, w = RAIL.w + 12, h = 18 }
        local edition = P.edition and P.edition.cle == d.cle
        local tv = edition and (P.edition.texte .. ((getTickCount() % 1000 < 500) and "|" or "")) or format(d, v)
        texte(tv, RAIL.x, y + 2, RAIL.w, 12, edition and c(COUL.rose) or c(COUL.gris), 7.5, false, "right")
        P.zones[#P.zones + 1] = { id = "valeur", cle = d.cle, x = RAIL.x + RAIL.w - 80, y = y + 1, w = 80, h = 13 }
    end
    if v ~= d.defaut then
        texte("↻", RAIL.x + RAIL.w + 12, y, 16, LIGNE, c(COUL.gris), 10, false, "center")
        P.zones[#P.zones + 1] = { id = "defaut", cle = d.cle, x = RAIL.x + RAIL.w + 10, y = y + 6, w = 18, h = LIGNE - 12 }
    end
    if d.aide and dans(D.x, y, D.w, LIGNE) then survols.aide = d.aide end
end

function P.dessiner()
    if not P.ouvert then return end
    if not isElement(P.vehicule) then P.fermer() return end
    cadrer()
    P.zones = {}
    local survols = {}

    rect(W.x, W.y, W.w, W.h, c(COUL.fond, 248))
    rect(W.x, W.y, W.w, 18, c(COUL.titre))
    texte("Acoustique — " .. P.nom, W.x, W.y, W.w, 18, c(COUL.texte), 8.5, true, "center")
    local fermerSurvol = dans(W.x + W.w - 20, W.y, 20, 18)
    texte("×", W.x + W.w - 20, W.y, 20, 18, fermerSurvol and tocolor(255, 255, 255) or c(COUL.gris), 9, false, "center")
    P.zones[#P.zones + 1] = { id = "fermer", x = W.x + W.w - 20, y = W.y, w = 20, h = 18 }
    texte("Réglages audio en direct (liens audio, pas YouTube)" .. (modifie() and "  ·  non enregistré" or ""),
        W.x + 9, W.y + 22, 380, 14, c(COUL.gris), 7.5)

    rect(W.x + 8, W.y + 40, W.w - 16, 15, c(COUL.champ))
    local rt = P.recherche
    if rt == "" and not P.rechercheFocus then rt = "Rechercher…" end
    if P.rechercheFocus and getTickCount() % 1000 < 500 then rt = rt .. "|" end
    texte(rt, W.x + 14, W.y + 40, W.w - 30, 15, P.recherche == "" and c(COUL.gris) or c(COUL.texte), 7.5)
    P.zones[#P.zones + 1] = { id = "recherche", x = W.x + 8, y = W.y + 40, w = W.w - 16, h = 15 }

    rect(G.x, G.y, G.w, G.h, c(COUL.panneau))
    texte("CATÉGORIES", G.x + 10, G.y + 4, G.w, 14, c(COUL.gris), 7)
    for i, cat in ipairs(CATS) do
        local yy = G.y + 20 + (i - 1) * 25
        local actif = P.recherche == "" and P.cat == cat.id
        if actif then rect(G.x + 2, yy, G.w - 4, 22, c(COUL.titre))
        elseif dans(G.x + 2, yy, G.w - 4, 22) then rect(G.x + 2, yy, G.w - 4, 22, c(COUL.survol)) end
        texte(cat.nom, G.x + 10, yy, G.w - 12, 22, c(COUL.texte), 8.5)
        P.zones[#P.zones + 1] = { id = "cat", cat = cat.id, x = G.x + 2, y = yy, w = G.w - 4, h = 22 }
    end
    local yAide = G.y + 20 + #CATS * 25 + 12
    rect(G.x + 8, yAide - 6, G.w - 16, 1, c(COUL.rail))
    dxDrawText("Glisser : régler.\nDouble-clic : défaut.\nClic valeur : saisir.",
        X(G.x + 9), Y(yAide), X(G.x + G.w - 6), Y(yAide + 60), c(COUL.gris), 1, police(7), "left", "top", true, true)
    if P.idTemporaire then
        dxDrawText("Véhicule de faction : son ID change à chaque sortie. Enregistre pour le modèle.",
            X(G.x + 9), Y(yAide + 64), X(G.x + G.w - 6), Y(G.y + G.h - 4), tocolor(235, 170, 90), 1, police(7), "left", "top", true, true)
    elseif not P.persistant then
        dxDrawText("Ce véhicule n'a ni ID ni plaque : réglages non sauvegardés en base.",
            X(G.x + 9), Y(yAide + 64), X(G.x + G.w - 6), Y(G.y + G.h - 4), tocolor(235, 170, 90), 1, police(7), "left", "top", true, true)
    end

    rect(D.x, D.y, D.w, D.h, c(COUL.panneau))
    local lignes = lignesVisibles()
    local haut = D.y + 22
    if P.recherche == "" then
        local nomCat = ""
        for _, cat in ipairs(CATS) do if cat.id == P.cat then nomCat = cat.nom end end
        texte(nomCat, D.x + 10, D.y + 4, 300, 14, c(COUL.texte), 8)
    else
        texte(#lignes .. " résultat(s)", D.x + 10, D.y + 4, 300, 14, c(COUL.gris), 8)
    end

    local extra = (P.recherche == "" and P.cat == "eq") and (EQ_H + 26) or 0
    local totalH = extra + #lignes * LIGNE
    local visibleH = D.y + D.h - 6 - haut
    P.defilMax = math.max(0, totalH - visibleH)
    P.defil = math.max(0, math.min(P.defil, P.defilMax))

    local y = haut - P.defil
    if extra > 0 then
        if y + 18 >= haut then
            rect(D.x + 6, y, D.w - 12, 16, c(COUL.titre, 200))
            texte("▼  Égaliseur de la radio", D.x + 14, y, 200, 16, c(COUL.texte), 8)
            -- préréglages (D112 sexies)
            local px = D.x + D.w - 12
            for i = #PRESETS_EQ, 1, -1 do
                local pr = PRESETS_EQ[i]
                px = px - pr.l - 4
                local survol = dans(px, y + 1, pr.l, 14)
                rect(px, y + 1, pr.l, 14, survol and c(COUL.survol) or c(COUL.bouton))
                texte(pr.nom, px, y + 1, pr.l, 14, c(COUL.texte), 7.5, false, "center")
                P.zones[#P.zones + 1] = { id = "preset", preset = i, x = px, y = y + 1, w = pr.l, h = 14 }
            end
        end
        if y + 20 >= haut and y + 20 + EQ_H <= D.y + D.h then
            dxDrawText("Glisser le point pour façonner la bande (+15 dB max, 80 Hz min : limites de MTA). Double-clic : à plat.",
                X(D.x + 10), Y(y + 18), X(D.x + D.w - 10), Y(y + 28), c(COUL.gris), 1, police(7), "left", "top", true)
            dessinerCourbe(D.x + 8, y + 30, D.w - 16, EQ_H - 32)
        end
        y = y + extra
    end
    for _, d in ipairs(lignes) do
        if y >= haut - 2 and y + LIGNE <= D.y + D.h - 2 then dessinerLigne(d, y, survols) end
        y = y + LIGNE
    end
    if P.defilMax > 0 then
        local hh = visibleH * visibleH / totalH
        local yy = haut + (visibleH - hh) * (P.defil / P.defilMax)
        rect(D.x + D.w - 5, yy, 3, hh, c(COUL.rail))
    end

    local by = W.y + W.h - 46
    bouton("sauver", W.x + 8, by, 64, 15, "Enregistrer", true)
    bouton("annuler", W.x + 76, by, 52, 15, "Annuler")
    bouton("defauts", W.x + 132, by, 52, 15, "Défauts")
    bouton("recharger", W.x + 188, by, 62, 15, "Recharger")
    bouton("fermerb", W.x + 254, by, 48, 15, "Fermer")
    -- portée de l'enregistrement : ce véhicule (son ID) ou tout le modèle
    texte("Enregistrer pour :", W.x + 316, by, 90, 15, c(COUL.gris), 7.5)
    local surVeh, surMod = P.porteeEnregistrement == "vehicule", P.porteeEnregistrement == "modele"
    rect(W.x + 404, by, 72, 15, surVeh and c(COUL.case) or c(COUL.bouton))
    texte("Ce véhicule", W.x + 404, by, 72, 15, c(COUL.texte), 7.5, surVeh, "center")
    P.zones[#P.zones + 1] = { id = "portee", portee = "vehicule", x = W.x + 404, y = by, w = 72, h = 15 }
    rect(W.x + 480, by, 110, 15, surMod and c(COUL.case) or c(COUL.bouton))
    texte("Tous les « " .. P.nom .. " »", W.x + 480, by, 110, 15, c(COUL.texte), 7.5, surMod, "center")
    P.zones[#P.zones + 1] = { id = "portee", portee = "modele", x = W.x + 480, y = by, w = 110, h = 15 }
    local origine = P.source == "vehicule" and "Réglages actuels : propres à ce véhicule"
        or P.source == "modele" and ("Réglages actuels : ceux de tous les « " .. P.nom .. " »")
        or "Réglages actuels : par défaut"
    texte(origine, W.x + 300, W.y + 22, W.w - 309, 14, c(COUL.gris), 7, false, "right")
    texte("Glisser : régler  |  Clic sur la valeur : valeur exacte  |  0 dB = volume de base",
        W.x + 9, by + 19, 600, 12, c(COUL.gris), 7)
    texte("Les changements s'entendent tout de suite, pour tout le monde. « Enregistrer » les garde pour ce véhicule.",
        W.x + 9, by + 31, 700, 12, c(COUL.texte, 200), 7)

    if survols.aide and not P.glisse then
        local mx, my = souris()
        local largeur = math.min(300, 12 + #survols.aide * 4.2)
        rect(mx + 12, my + 10, largeur, 30, tocolor(16, 16, 18, 240))
        dxDrawText(survols.aide, X(mx + 17), Y(my + 13), X(mx + 8 + largeur), Y(my + 38), c(COUL.texte), 1, police(7), "left", "top", true, true)
    end
end

-- ---------------------------------------------------------------------------
-- Souris et clavier
-- ---------------------------------------------------------------------------
local function zoneSous(mx, my)
    for i = #P.zones, 1, -1 do
        local z = P.zones[i]
        if mx >= z.x and mx <= z.x + z.w and my >= z.y and my <= z.y + z.h then return z end
    end
end

local function glisser()
    if not P.glisse then return end
    local mx, my = souris()
    if P.glisse == "eq" and P.courbe then
        local cb = P.courbe
        local f = FMIN * (FMAX / FMIN) ^ math.max(0, math.min(1, (mx - cb.x) / cb.w))
        local g = -((my - (cb.y + cb.h / 2)) / (cb.h / 2 - 8)) * 15
        if not P.edite.eqActif then changer("eqActif", true) end
        changer("eqFrequence", f)
        changer("eqGain", g)
        return
    end
    local d = IDX[P.glisse]
    if d then changer(d.cle, depuisPos(d, (mx - RAIL.x) / RAIL.w)) end
end

local function validerEdition()
    local ed = P.edition
    P.edition = nil
    if not ed then return end
    local n = tonumber((ed.texte:gsub(",", ".")))
    if n then changer(ed.cle, n) end
end

local function remplacerTout(etat)
    P.edite = copie(etat)
    appliquerEdite()
end

function P.clic(boutonSouris, etat)
    if not P.ouvert then return end
    if boutonSouris ~= "left" then return end
    if etat == "up" then P.glisse = nil return end
    local mx, my = souris()
    local z = zoneSous(mx, my)
    if P.edition and not (z and z.id == "valeur" and z.cle == P.edition.cle) then validerEdition() end
    P.rechercheFocus = z and z.id == "recherche" or false
    if not z then return end
    if z.id == "fermer" or z.id == "fermerb" then P.fermer()
    elseif z.id == "cat" then P.cat = z.cat P.recherche = "" P.defil = 0
    elseif z.id == "case" then changer(z.cle, not P.edite[z.cle])
    elseif z.id == "rail" then P.glisse = z.cle glisser()
    elseif z.id == "eqpoint" then P.glisse = "eq"
    elseif z.id == "valeur" then
        local d = IDX[z.cle]
        P.edition = { cle = z.cle, texte = "" }
        if d and d.type ~= "case" then P.edition.texte = tostring(P.edite[z.cle]) end
    elseif z.id == "defaut" then changer(z.cle, IDX[z.cle].defaut)
    elseif z.id == "portee" then P.porteeEnregistrement = z.portee
    elseif z.id == "preset" then
        for cle, valeur in pairs(PRESETS_EQ[z.preset].valeurs) do changer(cle, valeur) end
    elseif z.id == "sauver" then
        P.aEnvoyer = false
        triggerServerEvent("carplay:acoustique:sauver", resourceRoot, P.vehicule, P.edite, P.porteeEnregistrement)
    elseif z.id == "annuler" then remplacerTout(P.enregistre)
    elseif z.id == "defauts" then remplacerTout(carplayAcoustiqueComplet(nil))
    elseif z.id == "recharger" then
        triggerServerEvent("carplay:acoustique:recharger", resourceRoot, P.vehicule)
    end
end

function P.doubleClic(boutonSouris)
    if not P.ouvert or boutonSouris ~= "left" then return end
    local mx, my = souris()
    local z = zoneSous(mx, my)
    if not z then return end
    if z.id == "rail" then P.glisse = nil changer(z.cle, IDX[z.cle].defaut)
    elseif z.id == "eqpoint" then P.glisse = nil changer("eqGain", 0) changer("eqFrequence", IDX.eqFrequence.defaut) end
end

function P.touche(touche, appui)
    if not P.ouvert or not appui then return end
    if touche == "mouse_wheel_down" then P.defil = P.defil + LIGNE
    elseif touche == "mouse_wheel_up" then P.defil = math.max(0, P.defil - LIGNE)
    elseif touche == "backspace" then
        if P.edition then P.edition.texte = P.edition.texte:sub(1, -2)
        elseif P.rechercheFocus then P.recherche = P.recherche:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") P.defil = 0 end
    elseif touche == "enter" or touche == "num_enter" then
        if P.edition then validerEdition() else P.rechercheFocus = false end
    end
end

function P.caractere(ch)
    if not P.ouvert then return end
    if P.edition then
        if ch:match("^[%d%.,%-%+]$") and #P.edition.texte < 10 then P.edition.texte = P.edition.texte .. ch end
    elseif P.rechercheFocus and #P.recherche < 40 then
        P.recherche = P.recherche .. ch
        P.defil = 0
    end
end

-- ---------------------------------------------------------------------------
-- Ouverture / fermeture
-- ---------------------------------------------------------------------------
function P.ouvrir(v, enregistre, nom, persistant, infos)
    if not isElement(v) then return end
    if P.ouvert then P.fermer() end
    P.ouvert, P.vehicule, P.nom, P.persistant = true, v, tostring(nom or "Véhicule"), persistant ~= false
    infos = type(infos) == "table" and infos or {}
    P.source, P.idTemporaire = infos.source, infos.idTemporaire == true
    -- par défaut : là où sont déjà les réglages ; véhicule de faction ou sans
    -- ID = le modèle (seul enregistrement qui tient dans le temps)
    P.porteeEnregistrement = (infos.source == "modele" or P.idTemporaire or not P.persistant) and "modele" or "vehicule"
    P.enregistre = carplayAcoustiqueComplet(enregistre)
    P.edite = copie(P.enregistre)
    P.recherche, P.rechercheFocus, P.edition, P.defil, P.glisse, P.aEnvoyer = "", false, nil, 0, nil, false
    A.apercu[v] = copie(P.edite)
    showCursor(true)
    guiSetInputMode("no_binds")
    addEventHandler("onClientRender", root, P.dessiner)
    addEventHandler("onClientCursorMove", root, glisser)
    addEventHandler("onClientClick", root, P.clic)
    addEventHandler("onClientDoubleClick", root, P.doubleClic)
    addEventHandler("onClientKey", root, P.touche)
    addEventHandler("onClientCharacter", root, P.caractere)
    P.minuterie = setTimer(P.envoyer, P.ENVOI_MS, 0)
end

function P.fermer()
    if not P.ouvert then return end
    P.ouvert = false
    local v = P.vehicule
    -- le serveur remet l'état enregistré chez tout le monde (rien si
    -- « Enregistrer » vient d'être cliqué : c'est déjà cet état)
    if isElement(v) then
        A.apercu[v] = nil
        triggerServerEvent("carplay:acoustique:fermer", resourceRoot, v)
    end
    if P.minuterie and isTimer(P.minuterie) then killTimer(P.minuterie) end
    P.minuterie = nil
    P.vehicule, P.edite, P.enregistre, P.edition, P.glisse, P.aEnvoyer = nil, nil, nil, nil, nil, false
    removeEventHandler("onClientRender", root, P.dessiner)
    removeEventHandler("onClientCursorMove", root, glisser)
    removeEventHandler("onClientClick", root, P.clic)
    removeEventHandler("onClientDoubleClick", root, P.doubleClic)
    removeEventHandler("onClientKey", root, P.touche)
    removeEventHandler("onClientCharacter", root, P.caractere)
    showCursor(false)
    guiSetInputMode("allow_binds")
    libererPolices()
end

addEvent("carplay:acoustique:ouvrir", true)
addEventHandler("carplay:acoustique:ouvrir", resourceRoot, function(v, enregistre, nom, persistant, infos)
    P.ouvrir(v, enregistre, nom, persistant, infos)
end)

-- Réponse à « Enregistrer » / « Recharger » : nouvel état de référence.
addEvent("carplay:acoustique:enregistre", true)
addEventHandler("carplay:acoustique:enregistre", resourceRoot, function(v, complet, source)
    if not P.ouvert or v ~= P.vehicule then return end
    P.source = source
    P.enregistre = carplayAcoustiqueComplet(complet)
    P.edite = copie(P.enregistre)
    A.apercu[v] = copie(P.edite)
end)

-- Le panneau suit l'admin : véhicule disparu ou trop loin = fermeture.
setTimer(function()
    if not P.ouvert then return end
    local v = P.vehicule
    if not isElement(v) then return P.fermer() end
    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(v)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > 60 then P.fermer() end
end, 1000, 0)

-- BACKSPACE / Échap : saisie → recherche → fermeture.
if RETOUR and RETOUR.brancher then
    RETOUR.brancher({
        nom = "carplay_acoustique",
        ouvert = function() return P.ouvert end,
        saisie = function() return P.edition ~= nil or P.rechercheFocus end,
        cegui = false,
        retour = function()
            if P.edition then P.edition = nil
            elseif P.rechercheFocus then P.rechercheFocus = false
            elseif P.recherche ~= "" then P.recherche = ""
            else P.fermer() end
        end,
    })
end

addEventHandler("onClientResourceStop", resourceRoot, function() if P.ouvert then P.fermer() end end)
