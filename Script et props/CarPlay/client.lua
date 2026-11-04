-- ============================================================================
-- CarPlay — écran du véhicule (demande 69, 20/10/2026)
-- ----------------------------------------------------------------------------
-- Ouverture : clic droit sur la voiture → « CarPlay » (menu i9_interaction,
-- juste à côté de « Radio »), place avant, iPhone dans l'inventaire.
-- Apps : Musique (liens YouTube / audio, file d'attente, favoris), Téléphone
-- (favoris, récents, contacts, clavier ; appels de l'iPhone), Messages
-- (iMessage de l'iPhone : lire, réponses rapides, écrire), Plans (carte, GPS,
-- destinations), Radio (ouvre la radio du véhicule).
-- Téléphone et Messages passent par les VRAIS événements de PhoneIOS (même
-- base, mêmes règles : SIM, blocage, mode Avion…).
-- BACKSPACE / Échap reculent d'un niveau (retour.lua, demande 21).
-- ============================================================================

local C = CARPLAY_CONFIG
local LI = CARPLAY_LIENS
local D = CARPLAY_DESSIN
local A = CARPLAY_AUDIO
if type(CARPLAY_UI) ~= "table" then CARPLAY_UI = {} end
local U = CARPLAY_UI

U.ouvert = false
U.page = "accueil"
U.sous = { musique = "lecture", telephone = "recents" }
U.zones = {}
U.defil = {}
U.textes = { lien = "", message = "" }
U.clavier = ""
U.contacts, U.journal, U.convs, U.msgs, U.favoris = {}, {}, {}, {}, {}
U.conv = nil
U.zoom = 2
U.zooms = { 0.6, 1, 2, 4, 7 }
U.plansCx, U.plansCy, U.plansDrag = nil, nil, nil
U.statutLien = nil

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
function U.racineIPhone()
    local r = getResourceFromName("PhoneIOS")
    if r and getResourceState(r) == "running" then return getResourceRootElement(r) end
    return nil
end

function U.vehicule()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return nil end
    if not C.places[getPedOccupiedVehicleSeat(localPlayer) or -1] then return nil end
    return v
end

function U.etat()
    local v = getPedOccupiedVehicle(localPlayer)
    local e = v and getElementData(v, "carplay:etat")
    return type(e) == "table" and e or nil, v
end

function U.numero() return getElementData(localPlayer, "ios.phone.number") or "" end

function U.nomDe(numero)
    numero = tostring(numero or "")
    for _, c in ipairs(U.contacts) do if c.number == numero then return c.name end end
    for _, c in ipairs(U.convs) do if c.peer == numero and c.pseudo and c.pseudo ~= "" then return c.pseudo end end
    return numero ~= "" and numero or "Inconnu"
end

function U.notifier(titre, texte, action)
    U.banniere = { titre = titre, texte = texte, fin = getTickCount() + 4500, action = action }
end

function U.zone(id, x, y, w, h, donnee)
    U.zones[#U.zones + 1] = { id = id, x = x, y = y, w = w, h = h, d = donnee }
    return D.dans(x, y, w, h)
end

function U.ilya(ts)
    local d = getRealTime().timestamp - (tonumber(ts) or 0)
    if d < 60 then return "à l'instant" end
    if d < 3600 then return math.floor(d / 60) .. " min" end
    if d < 86400 then return math.floor(d / 3600) .. " h" end
    return math.floor(d / 86400) .. " j"
end

-- ---------------------------------------------------------------------------
-- Saisie de texte (champ CEGUI invisible : Ctrl+V fonctionne)
-- ---------------------------------------------------------------------------
function U.saisir(id, max)
    if not isElement(U.edit) then
        U.edit = guiCreateEdit(0, 0, 1, 1, "", false)
        guiSetAlpha(U.edit, 0)
    end
    guiEditSetMaxLength(U.edit, max or 300)
    guiSetText(U.edit, U.textes[id] or "")
    guiBringToFront(U.edit)
    guiFocus(U.edit)
    guiEditSetCaretIndex(U.edit, #(U.textes[id] or ""))
    guiSetInputMode("no_binds_when_editing")
    U.champ = id
end

function U.finSaisie()
    if isElement(U.edit) then guiBlur(U.edit) end
    if U.champ then guiSetInputMode("allow_binds") end
    U.champ = nil
end

addEventHandler("onClientGUIChanged", root, function()
    if source == U.edit and U.champ then U.textes[U.champ] = guiGetText(source) end
end)

addEventHandler("onClientGUIAccepted", root, function()
    if source ~= U.edit then return end
    if U.champ == "lien" then U.envoyerLien(true)
    elseif U.champ == "message" then U.envoyerMessage(U.textes.message) end
end)

-- ---------------------------------------------------------------------------
-- Ouverture / fermeture
-- ---------------------------------------------------------------------------
function U.chargerPrefs()
    if fileExists("@carplay_prefs.json") then
        local f = fileOpen("@carplay_prefs.json", true)
        if f then
            local txt = fileRead(f, fileGetSize(f))
            fileClose(f)
            local data = fromJSON(txt)
            if type(data) == "table" then
                if tonumber(data.echelle) then D.echelle = tonumber(data.echelle) end
                if tonumber(data.facteurPolice) then D.facteurPolice = tonumber(data.facteurPolice) end
                if tonumber(data.customX) and tonumber(data.customY) then
                    D.customX = tonumber(data.customX)
                    D.customY = tonumber(data.customY)
                end
            end
        end
    end
end

function U.sauvegarderPrefs()
    local data = {
        echelle = D.echelle or 1.0,
        facteurPolice = D.facteurPolice or 1.0,
        customX = D.customX,
        customY = D.customY,
    }
    if fileExists("@carplay_prefs.json") then fileDelete("@carplay_prefs.json") end
    local f = fileCreate("@carplay_prefs.json")
    if f then
        fileWrite(f, toJSON(data))
        fileClose(f)
    end
end

function U.ouvrir(vehicule)
    if U.ouvert then return end
    if not U.vehicule() then return outputChatBox("CarPlay : installe-toi à l'avant du véhicule.", 255, 120, 120) end
    if getElementData(localPlayer, "ios.phone:hasPhone") ~= true then return outputChatBox("CarPlay : il te faut un iPhone.", 255, 120, 120) end
    if getElementData(localPlayer, "ecran:noir") then return end
    local v = vehicule or U.vehicule()
    if getElementData(v, "carplay:installe") ~= true then
        return outputChatBox("[CarPlay] Ce véhicule n'est pas équipé du système CarPlay (mécanicien ou admin 3+ requis).", 255, 120, 120)
    end
    U.chargerPrefs()
    U.ouvert = true
    U.page = "accueil"
    showCursor(true)
    U.chargerTelephone()
    triggerServerEvent("carplay:favoris:demander", resourceRoot)
end

function U.fermer()
    if not U.ouvert then return end
    U.glisse = nil
    U.plansDrag = nil
    U.finSaisie()
    U.ouvert = false
    showCursor(false)
end

addEvent("carplay:ouvrir", true)
addEventHandler("carplay:ouvrir", root, function(vehicule)
    if vehicule and isElement(vehicule) and getPedOccupiedVehicle(localPlayer) ~= vehicule then return end
    U.ouvrir(vehicule)
end)

addEvent("carplay:non_installe", true)
addEventHandler("carplay:non_installe", root, function()
    outputChatBox("[CarPlay] Ce véhicule n'est pas équipé du système CarPlay. Demandez à un mécanicien ou un administrateur.", 255, 120, 120)
end)

function U.allerA(page)
    U.finSaisie()
    U.page = page
    if page == "plans" then U.plansRecentrer() end
    if page == "telephone" or page == "messages" then U.chargerTelephone() end
    if page == "musique" and U.sous.musique == "favoris" then triggerServerEvent("carplay:favoris:demander", resourceRoot) end
end

function U.reculer()
    if U.champ then return U.finSaisie() end
    if U.page == "messages" and U.conv then U.conv = nil return end
    if U.page == "plans" and U.panneauDest then U.panneauDest = false return end
    if U.page ~= "accueil" then U.page = "accueil" return end
    U.fermer()
end

if RETOUR then
    RETOUR.brancher({ nom = "carplay", ouvert = function() return U.ouvert end, retour = function() U.reculer() end })
end

-- ---------------------------------------------------------------------------
-- Données iPhone (vrais événements PhoneIOS)
-- ---------------------------------------------------------------------------
function U.chargerTelephone()
    local r = U.racineIPhone()
    if not r or U.numero() == "" then return end
    triggerServerEvent("ios:phone:reqContacts", r)
    triggerServerEvent("ios:phone:reqCallLog", r)
    triggerServerEvent("ios:wa:loadConvs", r)
end

addEvent("ios:phone:contacts", true)
addEventHandler("ios:phone:contacts", root, function(liste) if type(liste) == "table" then U.contacts = liste end end)
addEvent("ios:phone:callLog", true)
addEventHandler("ios:phone:callLog", root, function(liste) if type(liste) == "table" then U.journal = liste end end)
addEvent("ios:wa:convs", true)
addEventHandler("ios:wa:convs", root, function(liste, msgs)
    if type(liste) == "table" then U.convs = liste end
    if type(msgs) == "table" then U.msgs = msgs end
end)
addEvent("ios:wa:msg", true)
addEventHandler("ios:wa:msg", root, function(m)
    if type(m) ~= "table" or not m.peer then return end
    U.msgs[m.peer] = U.msgs[m.peer] or {}
    table.insert(U.msgs[m.peer], m)
    local trouve = false
    for _, c in ipairs(U.convs) do
        if c.peer == m.peer then
            c.last, c.ts = m.text, m.ts
            if m.dir == "in" and not (U.page == "messages" and U.conv == m.peer and U.ouvert) then c.unread = (c.unread or 0) + 1 end
            trouve = true
        end
    end
    if not trouve then table.insert(U.convs, 1, { peer = m.peer, pseudo = "", last = m.text, ts = m.ts, unread = m.dir == "in" and 1 or 0 }) end
    table.sort(U.convs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    if m.dir == "in" and U.ouvert and not (U.page == "messages" and U.conv == m.peer) then
        local texte = (m.text and m.text ~= "") and m.text or "[Photo]"
        U.notifier(U.nomDe(m.peer), texte, function() U.page = "messages" U.ouvrirConv(m.peer) end)
    end
end)

function U.appeler(numero)
    local r = U.racineIPhone()
    if not r then return U.notifier("Téléphone", "L'iPhone est indisponible.") end
    if U.numero() == "" then return U.notifier("Téléphone", "Insère une carte SIM dans ton iPhone.") end
    numero = tostring(numero or ""):gsub("%s", "")
    if numero == "" then return end
    triggerServerEvent("ios:onPlayerCallToNumber", r, localPlayer, numero)
end

function U.ouvrirConv(peer)
    U.conv = peer
    U.defil.conv = 0
    local r = U.racineIPhone()
    if r then triggerServerEvent("ios:wa:read", r, peer) end
    for _, c in ipairs(U.convs) do if c.peer == peer then c.unread = 0 end end
end

function U.envoyerMessage(texte)
    texte = tostring(texte or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if texte == "" or not U.conv then return end
    local r = U.racineIPhone()
    if not r then return end
    triggerServerEvent("ios:wa:send", r, U.conv, texte)
    if U.champ == "message" or texte == U.textes.message then
        U.textes.message = ""
        if isElement(U.edit) then guiSetText(U.edit, "") end
    end
end

-- ---------------------------------------------------------------------------
-- Musique
-- ---------------------------------------------------------------------------
function U.envoyerLien(maintenant)
    local texte = U.textes.lien or ""
    local lien, err = LI.analyser(texte)
    if not lien then U.statutLien = { ok = false, texte = err } return end
    U.statutLien = { ok = true, texte = lien.type == "youtube" and "Recherche de la vidéo…" or "Ajout du lien…" }
    triggerServerEvent("carplay:ajouter", resourceRoot, texte, maintenant == true)
end

addEvent("carplay:lienAccepte", true)
addEventHandler("carplay:lienAccepte", resourceRoot, function(titre)
    U.statutLien = { ok = true, texte = "Ajouté : " .. LI.couper(titre, 70) }
    U.textes.lien = ""
    if isElement(U.edit) and U.champ == "lien" then guiSetText(U.edit, "") end
    if U.page == "musique" and U.sous.musique == "lien" then U.sous.musique = "lecture" U.finSaisie() end
end)
addEvent("carplay:lienRefuse", true)
addEventHandler("carplay:lienRefuse", resourceRoot, function(texte) U.statutLien = { ok = false, texte = tostring(texte) } end)
addEvent("carplay:favoris", true)
addEventHandler("carplay:favoris", resourceRoot, function(liste) if type(liste) == "table" then U.favoris = liste end end)

function U.estFavori(piste)
    if not piste then return false end
    for _, f in ipairs(U.favoris) do if f.ref == piste.ref then return true end end
    return false
end

function U.action(a, v) triggerServerEvent("carplay:action", resourceRoot, a, v) end

-- ---------------------------------------------------------------------------
-- Dessin : cadre, barre latérale
-- ---------------------------------------------------------------------------
U.APPS = {
    { id = "plans", nom = "Plans", image = "assets/images/carte.png" },
    { id = "musique", nom = "Musique", image = "assets/images/musique.png" },
    { id = "telephone", nom = "Téléphone", image = "assets/images/telephone.png" },
    { id = "messages", nom = "Messages", image = "assets/images/messages.png" },
    { id = "reglages", nom = "Paramètres", image = "assets/images/reglages.png" },
}

function U.dessinerCadre()
    D.rect(-14, -14, 1028, 528, 34, D.c("cadre", 250))
    D.rect(0, 0, 1000, 500, 22, D.c("fond"))
    -- barre latérale
    D.rect(8, 8, 84, 484, 18, D.c("barre"))
    local t = getRealTime()
    D.texte(string.format("%02d:%02d", t.hour, t.minute), 8, 20, 84, 24, D.c("texte"), 17, "s", "center")
    -- barres de réseau + 4G (comme CarPlay)
    for i = 1, 4 do
        local h = 3 + i * 2.5
        D.rect(30 + (i - 1) * 6, 58 - h, 4, h, 1, U.numero() ~= "" and D.c("texte") or D.c("dim", 120))
    end
    D.texte("4G", 56, 46, 24, 14, D.c("texte"), 11, "s", "left")
    -- Poignée de déplacement (drag & move) sur le haut du cadre
    local survolDrag = U.zone("deplacer", 420, -14, 160, 24)
    D.rect(460, -8, 80, 5, 2.5, survolDrag and D.c("dim", 220) or D.c("dim", 140))

    for i, app in ipairs(U.APPS) do
        local y = 72 + (i - 1) * 68
        local survol = U.zone("app", 23, y, 54, 54, app.id)
        if U.page == app.id then D.rect(16, y - 5, 68, 64, 16, D.c("carte2")) end
        D.image(app.image, 23, y, 54, 54, survol and tocolor(255, 255, 255, 220) or nil)
    end
    -- bouton accueil (grille)
    local survol = U.zone("accueil", 26, 420, 48, 48)
    D.rect(26, 420, 48, 48, 14, survol and D.c("carte2") or D.c("carte"))
    D.icone("grille", 36, 430, 28, D.c("texte"))
    -- fermer CarPlay (hors de l'écran, en haut à droite du cadre)
    local sf = U.zone("fermer", 1000, -30, 34, 34)
    D.cercle(1017, -13, 17, sf and D.c("rouge") or D.c("carte2"))
    D.icone("fermer", 1005, -25, 24, D.c("texte"))
end

-- ---------------------------------------------------------------------------
-- Accueil
-- ---------------------------------------------------------------------------
function U.dessinerAccueil()
    local apps = U.APPS
    for i, app in ipairs(apps) do
        local col = (i - 1) % 5
        local x, y = 140 + col * 165, 70
        local survol = U.zone("app", x, y, 112, 140, app.id)
        if app.image then
            D.image(app.image, x + 6, y, 100, 100, survol and tocolor(255, 255, 255, 215) or nil)
        else
            D.rect(x + 6, y, 100, 100, 24, D.c(app.fond, survol and 215 or 255))
            D.icone(app.icone, x + 28, y + 22, 56, D.c("texte"))
        end
        D.texte(app.nom, x - 10, y + 106, 132, 26, D.c("texte"), 17, "s", "center")
    end
    -- Widget « À l'écoute »
    local e = U.etat()
    local x, y, w, h = 140, 270, 810, 190
    D.rect(x, y, w, h, 22, D.c("barre"))
    if e and e.piste then
        U.zone("app", x, y, 420, h, "musique")
        U.dessinerPochette(x + 20, y + 20, 266, 150, e)
        D.texte(e.lecture and "À L'ÉCOUTE" or (e.fin and "LECTURE TERMINÉE" or "EN PAUSE"), x + 306, y + 26, 300, 20, D.c("rose"), 13, "b")
        D.texte(e.piste.titre, x + 306, y + 50, 480, 30, D.c("texte"), 21, "b")
        D.texte(e.piste.auteur, x + 306, y + 82, 480, 24, D.c("dim"), 16)
        U.dessinerControles(x + 306, y + 116, 0.8, e)
    else
        D.icone("note", x + 30, y + 55, 80, D.c("dim"))
        D.texte("Rien en cours de lecture", x + 130, y + 50, 600, 34, D.c("texte"), 22, "b")
        D.texte("Ouvre Musique et colle un lien YouTube ou un lien audio.", x + 130, y + 88, 650, 26, D.c("dim"), 16)
        local s = U.zone("lienDirect", x + 130, y + 124, 220, 42)
        D.rect(x + 130, y + 124, 220, 42, 21, D.c("rose", s and 210 or 255))
        D.texte("Ajouter un lien", x + 130, y + 124, 220, 42, D.c("texte"), 16, "s", "center")
    end
end

-- ---------------------------------------------------------------------------
-- Musique
-- ---------------------------------------------------------------------------
function U.dessinerPochette(x, y, w, h, e)
    local nav = A.navigateurDe(select(2, U.etat()))
    if e and e.piste and e.piste.type == "youtube" and nav then
        D.rect(x, y, w, h, 14, D.c("fond"))
        dxDrawImage(D.X(x), D.Y(y), D.L(w), D.L(h), nav, 0, 0, 0, tocolor(255, 255, 255), true)
        return
    end
    D.rect(x, y, w, h, 14, D.c(e and e.piste and e.piste.type == "youtube" and "rouge" or "rose"))
    local s = math.min(w, h) * 0.5
    D.icone(e and e.piste and e.piste.type == "youtube" and "play" or "note", x + (w - s) / 2, y + (h - s) / 2, s, D.c("texte", 230))
end

-- Contrôles précédent / lecture / suivant à l'échelle f.
function U.dessinerControles(x, y, f, e)
    local s = 44 * f
    local sp = U.zone("ctl", x, y + 10 * f, s, s, "precedent")
    D.icone("precedent", x, y + 10 * f, s, D.c("texte", sp and 180 or 255))
    local cx = x + s + 24 * f
    local sl = U.zone("ctl", cx, y, 64 * f, 64 * f, "lecture")
    D.cercle(cx + 32 * f, y + 32 * f, 32 * f, D.c("texte", sl and 210 or 255))
    D.icone(e and e.lecture and "pause" or "play", cx + 14 * f, y + 14 * f, 36 * f, D.c("fond"))
    local nx = cx + 64 * f + 24 * f
    local sn = U.zone("ctl", nx, y + 10 * f, s, s, "suivant")
    D.icone("suivant", nx, y + 10 * f, s, D.c("texte", sn and 180 or 255))
end

function U.onglets(liste, actif, cle)
    local x, y, total = 120, 18, 860
    local w = total / #liste
    D.rect(x, y, total, 40, 12, D.c("carte"))
    for i, o in ipairs(liste) do
        local ox = x + (i - 1) * w
        local survol = U.zone("onglet", ox, y, w, 40, { cle = cle, val = o[1] })
        if actif == o[1] then D.rect(ox + 3, y + 3, w - 6, 34, 10, D.c("carte2"))
        elseif survol then D.rect(ox + 3, y + 3, w - 6, 34, 10, D.c("carte2", 90)) end
        D.texte(o[2], ox, y, w, 40, D.c("texte"), 15, "s", "center")
    end
end

function U.dessinerMusique()
    U.onglets({ { "lecture", "À l'écoute" }, { "file", "File d'attente" }, { "favoris", "Favoris" }, { "lien", "Ajouter un lien" } }, U.sous.musique, "musique")
    local s = U.sous.musique
    if s == "lecture" then U.dessinerLecture()
    elseif s == "file" then U.dessinerFile()
    elseif s == "favoris" then U.dessinerFavoris()
    else U.dessinerLien() end
end

function U.dessinerLecture()
    local e = U.etat()
    if not e or not e.piste then
        D.icone("note", 490, 120, 100, D.c("dim"))
        D.texte("Rien en cours de lecture", 120, 240, 860, 34, D.c("texte"), 24, "b", "center")
        D.texte("Colle un lien YouTube ou un lien audio direct (.mp3, flux radio).", 120, 278, 860, 26, D.c("dim"), 16, "r", "center")
        local sv = U.zone("onglet", 430, 330, 220, 46, { cle = "musique", val = "lien" })
        D.rect(430, 330, 220, 46, 23, D.c("rose", sv and 210 or 255))
        D.texte("Ajouter un lien", 430, 330, 220, 46, D.c("texte"), 17, "s", "center")
        return
    end
    local p = e.piste
    U.dessinerPochette(130, 88, 340, 192, e)
    if p.type == "youtube" and A.navigateurRefuse then
        D.texte("Active le navigateur dans Réglages MTA > Navigateur pour entendre YouTube.", 130, 284, 340, 40, D.c("orange"), 13, "s", "center", true, true)
    end
    local x = 500
    D.texte(e.lecture and "À L'ÉCOUTE" or (e.fin and "LECTURE TERMINÉE" or "EN PAUSE"), x, 92, 460, 20, D.c("rose"), 13, "b")
    D.texte(p.titre, x, 114, 460, 60, D.c("texte"), 22, "b", "left", "top", true, true)
    D.texte(p.auteur, x, 176, 460, 24, D.c("dim"), 17)
    local source = p.type == "youtube" and "YouTube" or "Lien audio"
    local lw = D.largeur(source, 12, "s") + 22
    D.rect(x, 206, lw, 24, 12, D.c(p.type == "youtube" and "rouge" or "carte2"))
    D.texte(source, x, 206, lw, 24, D.c("texte"), 12, "s", "center")
    local fav = U.estFavori(p)
    local sfv = U.zone("favori", x + lw + 14, 202, 32, 32, p.id)
    D.icone(fav and "coeurplein" or "coeur", x + lw + 14, 202, 32, fav and D.c("rose") or D.c("texte", sfv and 180 or 255))
    -- progression
    local ec = A.ecoule(e)
    local du = tonumber(p.duree)
    local by = 300
    D.rect(130, by, 830, 6, 3, D.c("carte2"))
    if du and du > 0 then
        D.rect(130, by, math.max(6, 830 * math.min(1, ec / du)), 6, 3, D.c("texte"))
        D.texte(LI.duree(math.min(ec, du)), 130, by + 10, 120, 20, D.c("dim"), 13)
        D.texte("-" .. LI.duree(math.max(0, du - ec)), 840, by + 10, 120, 20, D.c("dim"), 13, "r", "right")
    else
        D.texte(LI.duree(ec), 130, by + 10, 120, 20, D.c("dim"), 13)
        D.texte(p.type == "audio" and "Flux" or "Durée inconnue", 760, by + 10, 200, 20, D.c("dim"), 13, "r", "right")
    end
    U.dessinerControles(445, 345, 1.15, e)
    -- volume
    local vol = tonumber(e.volume) or C.volumeDefaut
    local vy = 452
    local sm = U.zone("ctl", 300, vy - 14, 30, 30, "volmoins")
    D.icone("volmoins", 300, vy - 14, 28, D.c("texte", sm and 170 or 230))
    U.zone("volume", 340, vy - 12, 400, 24)
    D.rect(340, vy - 3, 400, 6, 3, D.c("carte2"))
    D.rect(340, vy - 3, math.max(6, 400 * vol), 6, 3, D.c("texte"))
    D.cercle(340 + 400 * vol, vy, 9, D.c("texte"))
    local sp = U.zone("ctl", 752, vy - 14, 30, 30, "volplus")
    D.icone("volplus", 752, vy - 14, 28, D.c("texte", sp and 170 or 230))
    D.texte(math.floor(vol * 100 + 0.5) .. " %", 790, vy - 12, 80, 24, D.c("dim"), 14)
end

-- Liste défilante générique : renvoie la première ligne visible.
function U.liste(cle, x, y, w, h, hl, n)
    U.listes = U.listes or {}
    U.listes[cle] = { x = x, y = y, w = w, h = h, hl = hl, n = n }
    local visibles = math.floor(h / hl)
    local maxDef = math.max(0, n - visibles)
    U.defil[cle] = math.max(0, math.min(U.defil[cle] or 0, maxDef))
    return U.defil[cle] + 1, math.min(n, U.defil[cle] + visibles)
end

function U.dessinerFile()
    local e = U.etat()
    local file = e and e.file or {}
    D.texte(#file .. " morceau" .. (#file > 1 and "x" or "") .. " dans la file", 130, 70, 500, 30, D.c("dim"), 15)
    if #file > 0 then
        local sv = U.zone("ctl", 820, 68, 140, 34, "vider")
        D.rect(820, 68, 140, 34, 17, D.c(sv and "rouge" or "carte"))
        D.texte("Tout effacer", 820, 68, 140, 34, D.c("texte"), 14, "s", "center")
    else
        D.texte("La file est vide. Ajoute un lien ou un favori.", 120, 220, 860, 30, D.c("dim"), 18, "r", "center")
        return
    end
    local i1, i2 = U.liste("file", 120, 110, 860, 380, 54, #file)
    for i = i1, i2 do
        local t = file[i]
        local y = 110 + (i - i1) * 54
        local courant = (i == e.index)
        local survol = U.zone("jouerIndex", 120, y, 780, 50, i)
        D.rect(120, y, 860, 50, 12, courant and D.c("carte2") or (survol and D.c("carte", 160) or D.c("carte", 90)))
        if courant then D.icone(e.lecture and "volplus" or "pause", 134, y + 13, 24, D.c("rose"))
        else D.texte(tostring(i), 124, y, 40, 50, D.c("dim"), 15, "s", "center") end
        D.texte(t.titre, 176, y + 4, 600, 24, D.c(courant and "rose" or "texte"), 16, "s")
        D.texte((t.auteur or "") .. (t.duree and ("  ·  " .. LI.duree(t.duree)) or ""), 176, y + 26, 600, 20, D.c("dim"), 13)
        local sr = U.zone("retirer", 920, y + 9, 32, 32, i)
        D.icone("poubelle", 924, y + 13, 24, sr and D.c("rouge") or D.c("dim"))
    end
end

function U.dessinerFavoris()
    D.texte("Tes favoris (enregistrés sur ton personnage)", 130, 70, 700, 30, D.c("dim"), 15)
    if #U.favoris == 0 then
        D.icone("coeur", 510, 160, 60, D.c("dim"))
        D.texte("Aucun favori. Pendant la lecture, touche le cœur pour en ajouter.", 120, 240, 860, 30, D.c("dim"), 17, "r", "center")
        return
    end
    local i1, i2 = U.liste("favoris", 120, 110, 860, 380, 54, #U.favoris)
    for i = i1, i2 do
        local f = U.favoris[i]
        local y = 110 + (i - i1) * 54
        local survol = U.zone("favJouer", 120, y, 700, 50, f.id)
        D.rect(120, y, 860, 50, 12, survol and D.c("carte", 160) or D.c("carte", 90))
        D.icone(f.type == "youtube" and "play" or "note", 134, y + 13, 24, D.c(f.type == "youtube" and "rouge" or "rose"))
        D.texte(f.titre, 176, y + 4, 600, 24, D.c("texte"), 16, "s")
        D.texte((f.auteur or "") .. (tonumber(f.duree) and ("  ·  " .. LI.duree(f.duree)) or ""), 176, y + 26, 600, 20, D.c("dim"), 13)
        local sa = U.zone("favFile", 840, y + 9, 32, 32, f.id)
        D.icone("plus", 842, y + 11, 28, sa and D.c("bleu") or D.c("texte"))
        local sr = U.zone("favRetirer", 900, y + 9, 32, 32, f.id)
        D.icone("coeurplein", 902, y + 11, 28, sr and D.c("dim") or D.c("rose"))
    end
end

function U.dessinerLien()
    D.texte("Colle un lien puis choisis « Lire maintenant » ou « Ajouter à la file ».", 130, 74, 830, 26, D.c("dim"), 15)
    local actif = U.champ == "lien"
    U.zone("champ", 130, 110, 830, 58, "lien")
    D.rect(130, 110, 830, 58, 16, D.c("carte"))
    if actif then D.rect(130, 166, 830, 2, 1, D.c("bleu")) end
    D.icone("lien", 146, 125, 28, D.c("dim"))
    local t = U.textes.lien or ""
    if t == "" and not actif then
        D.texte("https://www.youtube.com/watch?v=…  (Ctrl+V pour coller)", 186, 110, 760, 58, D.c("dim"), 17)
    else
        local aff = t
        while D.largeur(aff, 17) > 740 and #aff > 1 do aff = aff:sub(2) end
        D.texte(aff .. (actif and (getTickCount() % 1000 < 500 and "|" or " ") or ""), 186, 110, 760, 58, D.c("texte"), 17, "r", "left", "center", true)
    end
    local s1 = U.zone("lienLire", 130, 190, 300, 50)
    D.rect(130, 190, 300, 50, 25, D.c("rose", s1 and 210 or 255))
    D.icone("play", 162, 201, 28, D.c("texte"))
    D.texte("Lire maintenant", 196, 190, 220, 50, D.c("texte"), 17, "s")
    local s2 = U.zone("lienFile", 450, 190, 300, 50)
    D.rect(450, 190, 300, 50, 25, s2 and D.c("carte2") or D.c("carte"))
    D.icone("file", 482, 201, 28, D.c("texte"))
    D.texte("Ajouter à la file", 516, 190, 220, 50, D.c("texte"), 17, "s")
    if U.statutLien then
        D.texte(U.statutLien.texte, 130, 252, 830, 44, U.statutLien.ok and D.c("vert") or D.c("rouge"), 15, "s", "left", "top", true, true)
    end
    D.rect(130, 306, 830, 170, 16, D.c("barre"))
    D.texte("Liens acceptés", 150, 316, 400, 26, D.c("texte"), 16, "b")
    local aide = {
        "YouTube : youtube.com/watch?v=…, youtu.be/…, Shorts, YouTube Music.",
        "Audio direct : .mp3, .ogg, .wav, .aac, .m4a, .flac, ou un flux radio en ligne.",
        "Tout le monde dans la voiture l'entend, et dehors aussi (plus fort vitres ouvertes).",
        "Certaines vidéos interdisent la lecture hors de YouTube : un message te le dira.",
    }
    for i, l in ipairs(aide) do D.texte("•  " .. l, 150, 342 + (i - 1) * 31, 800, 28, D.c("dim"), 14) end
end

-- ---------------------------------------------------------------------------
-- Téléphone
-- ---------------------------------------------------------------------------
function U.pastille(nom, cx, cy, r)
    D.cercle(cx, cy, r, D.c("carte2"))
    D.texte(D.initiales(nom), cx - r, cy - r, r * 2, r * 2, D.c("texte"), r * 0.8, "s", "center")
end

function U.dessinerTelephone()
    U.onglets({ { "favoris", "Favoris" }, { "recents", "Récents" }, { "contacts", "Contacts" }, { "clavier", "Clavier" } }, U.sous.telephone, "telephone")
    if U.numero() == "" then
        D.icone("appel", 500, 150, 70, D.c("dim"))
        D.texte("Insère une carte SIM dans ton iPhone pour appeler.", 120, 240, 860, 30, D.c("dim"), 18, "r", "center")
        return
    end
    local s = U.sous.telephone
    if s == "favoris" then
        local favs = {}
        for _, c in ipairs(U.contacts) do if tonumber(c.favorite) == 1 then favs[#favs + 1] = c end end
        if #favs == 0 then return D.texte("Aucun favori. Ajoute-les dans l'app Téléphone de l'iPhone.", 120, 220, 860, 30, D.c("dim"), 17, "r", "center") end
        for i = 1, math.min(10, #favs) do
            local c = favs[i]
            local col, lig = (i - 1) % 5, math.floor((i - 1) / 5)
            local x, y = 150 + col * 165, 90 + lig * 190
            local sv = U.zone("appeler", x, y, 120, 170, c.number)
            U.pastille(c.name, x + 60, y + 55, 52)
            if sv then D.cercle(x + 60, y + 55, 52, D.c("texte", 40)) end
            D.texte(c.name, x - 15, y + 116, 150, 26, D.c("texte"), 16, "s", "center")
            D.texte(c.number, x - 15, y + 140, 150, 20, D.c("dim"), 13, "r", "center")
        end
    elseif s == "recents" then
        if #U.journal == 0 then return D.texte("Aucun appel récent.", 120, 220, 860, 30, D.c("dim"), 17, "r", "center") end
        local i1, i2 = U.liste("recents", 120, 72, 860, 416, 52, #U.journal)
        for i = i1, i2 do
            local l = U.journal[i]
            local y = 72 + (i - i1) * 52
            local manque = (l.status == "missed" or l.status == "noanswer") and l.dir == "in"
            local sv = U.zone("appeler", 120, y, 860, 48, l.other)
            D.rect(120, y, 860, 48, 12, sv and D.c("carte", 160) or D.c("carte", 80))
            D.icone(l.dir == "out" and "appel" or "horloge", 136, y + 12, 24, D.c(manque and "rouge" or "dim"))
            D.texte(U.nomDe(l.other), 176, y, 560, 48, D.c(manque and "rouge" or "texte"), 17, "s")
            D.texte((l.dir == "out" and "Sortant" or (manque and "Manqué" or "Entrant")) .. "  ·  " .. U.ilya(l.ts), 700, y, 260, 48, D.c("dim"), 14, "r", "right")
        end
    elseif s == "contacts" then
        if #U.contacts == 0 then return D.texte("Aucun contact.", 120, 220, 860, 30, D.c("dim"), 17, "r", "center") end
        local i1, i2 = U.liste("contacts", 120, 72, 860, 416, 52, #U.contacts)
        for i = i1, i2 do
            local c = U.contacts[i]
            local y = 72 + (i - i1) * 52
            local sv = U.zone("appeler", 120, y, 860, 48, c.number)
            D.rect(120, y, 860, 48, 12, sv and D.c("carte", 160) or D.c("carte", 80))
            U.pastille(c.name, 148, y + 24, 17)
            D.texte(c.name, 180, y, 500, 48, D.c("texte"), 17, "s")
            D.texte(c.number, 700, y, 220, 48, D.c("dim"), 14, "r", "right")
            D.icone("appel", 932, y + 12, 24, D.c("vert"))
        end
    else
        D.texte(U.clavier ~= "" and U.clavier or "Numéro", 120, 66, 860, 50, D.c(U.clavier ~= "" and "texte" or "dim"), 30, "s", "center")
        local touches = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
        for i, t in ipairs(touches) do
            local col, lig = (i - 1) % 3, math.floor((i - 1) / 3)
            local cx, cy = 430 + col * 110, 152 + lig * 74
            local sv = U.zone("touche", cx - 33, cy - 33, 66, 66, t)
            D.cercle(cx, cy, 33, sv and D.c("carte2") or D.c("carte"))
            D.texte(t, cx - 33, cy - 33, 66, 66, D.c("texte"), 26, "s", "center")
        end
        local sa = U.zone("appeler", 770, 300, 76, 76, "clavier")
        D.cercle(808, 338, 38, D.c("vert", sa and 210 or 255))
        D.icone("appel", 788, 318, 40, D.c("texte"))
        local se = U.zone("toucheEffacer", 780, 200, 56, 44)
        D.icone("effacer", 790, 206, 34, D.c("texte", se and 170 or 255))
    end
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
function U.dessinerMessages()
    if U.numero() == "" then
        D.icone("bulle", 500, 150, 70, D.c("dim"))
        D.texte("Insère une carte SIM dans ton iPhone pour les messages.", 120, 240, 860, 30, D.c("dim"), 18, "r", "center")
        return
    end
    if U.conv then return U.dessinerConv() end
    D.texte("Messages", 120, 16, 600, 44, D.c("texte"), 28, "b")
    if #U.convs == 0 then return D.texte("Aucune conversation.", 120, 220, 860, 30, D.c("dim"), 17, "r", "center") end
    local i1, i2 = U.liste("convs", 120, 70, 860, 418, 66, #U.convs)
    for i = i1, i2 do
        local c = U.convs[i]
        local y = 70 + (i - i1) * 66
        local sv = U.zone("conv", 120, y, 860, 60, c.peer)
        D.rect(120, y, 860, 60, 14, sv and D.c("carte", 160) or D.c("carte", 80))
        local nom = U.nomDe(c.peer)
        U.pastille(nom, 156, y + 30, 22)
        D.texte(nom, 192, y + 6, 560, 26, D.c("texte"), 17, "s")
        D.texte((c.last and c.last ~= "") and c.last or "[Photo]", 192, y + 32, 640, 22, D.c("dim"), 14)
        D.texte(U.ilya(c.ts), 800, y + 6, 160, 26, D.c("dim"), 13, "r", "right")
        if (tonumber(c.unread) or 0) > 0 then D.cercle(948, y + 42, 7, D.c("bleu")) end
    end
end

function U.dessinerConv()
    local nom = U.nomDe(U.conv)
    local sb = U.zone("convRetour", 112, 14, 120, 40)
    D.icone("retour", 112, 18, 32, D.c("bleu", sb and 170 or 255))
    D.texte("Messages", 142, 14, 120, 40, D.c("bleu", sb and 170 or 255), 16, "s")
    D.texte(nom, 300, 14, 400, 40, D.c("texte"), 19, "b", "center")
    local sa = U.zone("appeler", 920, 16, 40, 36, U.conv)
    D.icone("appel", 926, 20, 28, D.c("vert", sa and 170 or 255))
    -- bulles (les plus récentes en bas)
    local liste = U.msgs[U.conv] or {}
    local bas, haut, wmax = 340, 64, 560
    local y = bas
    for i = #liste, 1, -1 do
        local m = liste[i]
        local texte = (m.text and m.text ~= "") and m.text or (m.location and "Position partagée" or "[Photo]")
        local lignes = D.lignes(texte, wmax - 28, 16)
        local w = math.min(wmax, D.largeur(texte, 16) + 30)
        local h = lignes * 22 + 16
        y = y - h - 8
        if y < haut then break end
        local moi = m.dir == "out"
        local x = moi and (970 - w) or 130
        D.rect(x, y, w, h, 18, moi and D.c("bleu") or D.c("carte2"))
        D.texte(texte, x + 14, y + 8, w - 28, h - 16, D.c("texte"), 16, "r", "left", "top", true, true)
    end
    -- réponses rapides
    local rx = 120
    for _, r in ipairs(C.reponsesRapides) do
        local w = D.largeur(r, 14, "s") + 30
        if rx + w > 980 then break end
        local sv = U.zone("rapide", rx, 356, w, 36, r)
        D.rect(rx, 356, w, 36, 18, sv and D.c("carte2") or D.c("carte"))
        D.texte(r, rx, 356, w, 36, D.c("texte"), 14, "s", "center")
        rx = rx + w + 10
    end
    -- champ « iMessage »
    local actif = U.champ == "message"
    U.zone("champ", 120, 408, 780, 50, "message")
    D.rect(120, 408, 780, 50, 25, D.c("carte"))
    local t = U.textes.message or ""
    if t == "" and not actif then
        D.texte("iMessage", 142, 408, 740, 50, D.c("dim"), 16)
    else
        local aff = t
        while D.largeur(aff, 16) > 730 and #aff > 1 do aff = aff:sub(2) end
        D.texte(aff .. (actif and (getTickCount() % 1000 < 500 and "|" or " ") or ""), 142, 408, 740, 50, D.c("texte"), 16)
    end
    local se = U.zone("envoyer", 912, 408, 50, 50)
    D.cercle(937, 433, 25, D.c("bleu", se and 200 or 255))
    D.icone("envoyer", 924, 420, 26, D.c("texte"))
end

-- ---------------------------------------------------------------------------
-- Plans
-- ---------------------------------------------------------------------------
U.MAP = { x = 100, y = 0, w = 900, h = 500 }

function U.versCarte(wx, wy, cx, cy, z)
    local M = U.MAP
    return M.x + M.w / 2 + (wx - cx) / z, M.y + M.h / 2 - (wy - cy) / z
end

function U.versMonde(mx, my, cx, cy, z)
    local M = U.MAP
    return cx + (mx - M.x - M.w / 2) * z, cy - (my - M.y - M.h / 2) * z
end

local function drawGPSLine(x1, y1, x2, y2, color, width)
    local xmin, ymin = U.MAP.x, U.MAP.y
    local xmax, ymax = xmin + U.MAP.w, ymin + U.MAP.h
    local dx, dy = x2 - x1, y2 - y1
    local u1, u2 = 0, 1
    local p, q = { -dx, dx, -dy, dy }, { x1 - xmin, xmax - x1, y1 - ymin, ymax - y1 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return end
        else
            local r = q[i] / p[i]
            if p[i] < 0 then u1 = math.max(u1, r) else u2 = math.min(u2, r) end
            if u1 > u2 then return end
        end
    end
    dxDrawLine(D.X(x1 + u1 * dx), D.Y(y1 + u1 * dy), D.X(x1 + u2 * dx), D.Y(y1 + u2 * dy), color, width, true)
end

function U.plansRecentrer()
    local x,y=getElementPosition(localPlayer)
    U.plansCx, U.plansCy=x,y
end

function U.plansCentre()
    if not U.plansCx or not U.plansCy then U.plansRecentrer() end
    return U.plansCx,U.plansCy
end

function U.plansBorner()
    U.plansCx=math.max(-3000,math.min(3000,U.plansCx or 0))
    U.plansCy=math.max(-3000,math.min(3000,U.plansCy or 0))
end

function U.plansZoomer(sens,mx,my)
    local ancien=U.zooms[U.zoom] or 2
    local prochain=math.max(1,math.min(#U.zooms,(U.zoom or 1)+sens))
    if prochain==U.zoom then return end
    local cx,cy=U.plansCentre()
    local wx,wy=U.versMonde(mx,my,cx,cy,ancien)
    U.zoom=prochain
    local nouveau=U.zooms[U.zoom] or ancien
    local M=U.MAP
    U.plansCx=wx-(mx-M.x-M.w/2)*nouveau
    U.plansCy=wy+(my-M.y-M.h/2)*nouveau
    U.plansBorner()
end

function U.zoneSousCurseur(cx,cy)
    for i=#(U.zones or {}),1,-1 do
        local z=U.zones[i]
        if cx>=z.x and cx<=z.x+z.w and cy>=z.y and cy<=z.y+z.h then return z end
    end
end

function U.cap(dx, dy)
    local a = (math.deg(math.atan2(dx, dy)) + 360) % 360
    local noms = { "le nord", "le nord-est", "l'est", "le sud-est", "le sud", "le sud-ouest", "l'ouest", "le nord-ouest" }
    return noms[math.floor((a + 22.5) / 45) % 8 + 1]
end

function U.distance(m)
    if m >= 1000 then return (string.format("%.1f km", m / 1000):gsub("%.", ",")) end
    return math.floor(m / 10 + 0.5) * 10 .. " m"
end

-- Graphe routier GTA III extrait des PATH/IDE et transformé avec les IPL
-- originaux (translation de la map Liberty City du serveur appliquée).
U.gpsNodes, U.gpsComponents, U.route = nil, nil, nil
local function chargerGrapheGPS()
    if U.gpsNodes then return true end
    local path = "assets/data/lc_gta3_gps.csv"
    if not fileExists(path) then return false end
    local f = fileOpen(path, true)
    if not f then return false end
    local raw = fileRead(f, fileGetSize(f))
    fileClose(f)
    if type(raw) ~= "string" then return false end
    local nodes = {}
    for line in raw:gmatch("[^\r\n]+") do
        local id, x, y, z, links = line:match("^(%d+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        id, x, y, z = tonumber(id), tonumber(x), tonumber(y), tonumber(z)
        if id and x and y and z then
            local edges = {}
            for n in links:gmatch("%d+") do edges[#edges + 1] = tonumber(n) + 1 end
            nodes[id + 1] = { x = x, y = y, z = z, links = edges }
        end
    end
    if #nodes == 0 then return false end
    local components, component = {}, 0
    for i = 1, #nodes do
        if nodes[i] and not components[i] then
            component = component + 1
            local stack = { i }
            components[i] = component
            while #stack > 0 do
                local cur = table.remove(stack)
                for _, nextId in ipairs(nodes[cur].links) do
                    if nodes[nextId] and not components[nextId] then
                        components[nextId] = component
                        stack[#stack + 1] = nextId
                    end
                end
            end
        end
    end
    U.gpsNodes, U.gpsComponents = nodes, components
    return true
end

local function distance3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function gpsHeapPush(heap, item)
    local i = #heap + 1
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p].f <= item.f then break end
        heap[i] = heap[p]; i = p
    end
    heap[i] = item
end

local function gpsHeapPop(heap)
    local first, last = heap[1], table.remove(heap)
    if #heap > 0 then
        local i = 1
        while true do
            local left, right = i * 2, i * 2 + 1
            if left > #heap then break end
            local child = right <= #heap and heap[right].f < heap[left].f and right or left
            if heap[child].f >= last.f then break end
            heap[i] = heap[child]; i = child
        end
        heap[i] = last
    end
    return first
end

local function nearestGPSNodes(x, y, z)
    local perComponent = {}
    for i, n in ipairs(U.gpsNodes or {}) do
        if n then
            local d = distance3({ x = x, y = y, z = z }, n)
            local c = U.gpsComponents[i]
            local entry = perComponent[c]
            if not entry then entry = {}; perComponent[c] = entry end
            if not entry.node or d < entry.distance then entry.node, entry.distance = i, d end
        end
    end
    return perComponent
end

local function calculerRouteGPS(x, y)
    U.route = nil
    U.routeRefreshTick = getTickCount() + 5000
    if not chargerGrapheGPS() then return false end
    local px, py, pz = getElementPosition(localPlayer)
    local starts = nearestGPSNodes(px, py, pz)
    local goals = nearestGPSNodes(x, y, pz)
    local startId, goalId, bestScore
    for comp, s in pairs(starts) do
        local g = goals[comp]
        if g then
            local score = s.distance + g.distance
            if not bestScore or score < bestScore then startId, goalId, bestScore = s.node, g.node, score end
        end
    end
    if not startId or not goalId then return false end
    local nodes, open = U.gpsNodes, {}
    local came, scores, closed = {}, { [startId] = 0 }, {}
    gpsHeapPush(open, { id = startId, f = distance3(nodes[startId], nodes[goalId]) })
    local expanded = 0
    while #open > 0 and expanded < 12000 do
        local item = gpsHeapPop(open)
        local cur = item.id
        if not closed[cur] then
            if cur == goalId then break end
            closed[cur] = true; expanded = expanded + 1
            for _, nextId in ipairs(nodes[cur].links) do
                if nodes[nextId] and not closed[nextId] then
                    local tentative = scores[cur] + distance3(nodes[cur], nodes[nextId])
                    if not scores[nextId] or tentative < scores[nextId] then
                        came[nextId], scores[nextId] = cur, tentative
                        gpsHeapPush(open, { id = nextId, f = tentative + distance3(nodes[nextId], nodes[goalId]) })
                    end
                end
            end
        end
    end
    if startId ~= goalId and not came[goalId] then return false end
    local ids, current = { goalId }, goalId
    while current ~= startId do current = came[current]; if not current then return false end; ids[#ids + 1] = current end
    local route = {}
    for i = #ids, 1, -1 do route[#route + 1] = nodes[ids[i]] end
    local px, py, pz2 = getElementPosition(localPlayer)
    local meters = distance3({ x = px, y = py, z = pz2 }, route[1]) + (scores[goalId] or 0)
    meters = meters + distance3(route[#route], { x = x, y = y, z = pz })
    -- Fusionne les nœuds d'une même ligne droite pour éviter des centaines
    -- d'appels de dessin par image sur les longues avenues.
    local displayRoute = { route[1] }
    local lastKept = route[1]
    for i = 2, #route - 1 do
        local prev, cur, nextNode = route[i - 1], route[i], route[i + 1]
        local ax, ay = cur.x - prev.x, cur.y - prev.y
        local bx, by = nextNode.x - cur.x, nextNode.y - cur.y
        local al, bl = math.sqrt(ax*ax + ay*ay), math.sqrt(bx*bx + by*by)
        local straight = al > 0 and bl > 0 and (ax*bx + ay*by) / (al*bl) > .985
        if not straight or distance3(lastKept, cur) >= 45 then
            displayRoute[#displayRoute + 1] = cur
            lastKept = cur
        end
    end
    if #route > 1 then displayRoute[#displayRoute + 1] = route[#route] end
    U.route = { points = displayRoute, distance = meters }
    U.routeRefreshTick = getTickCount() + 5000
    return true
end

function U.definirDestination(x, y, nom)
    if isElement(U.blipDest) then destroyElement(U.blipDest) end
    U.dest = { x = x, y = y, nom = nom or "Point sur la carte" }
    U.blipDest = createBlip(x, y, 0, 41, 2)
    calculerRouteGPS(x, y)
end

function U.effacerDestination()
    if isElement(U.blipDest) then destroyElement(U.blipDest) end
    U.blipDest = nil
    U.dest = nil
    U.route = nil
end

function U.destinations()
    local px, py = getElementPosition(localPlayer)
    local t = {}
    for _, b in ipairs(getElementsByType("blip")) do
        local nom = getElementData(b, "blipName")
        if type(nom) == "string" and nom ~= "" and b ~= U.blipDest then
            local x, y = getElementPosition(b)
            t[#t + 1] = { nom = nom, x = x, y = y, d = getDistanceBetweenPoints2D(px, py, x, y) }
        end
    end
    table.sort(t, function(a, b) return a.d < b.d end)
    return t
end

function U.dessinerPlans()
    local M = U.MAP
    local px, py = getElementPosition(localPlayer)
    local v = getPedOccupiedVehicle(localPlayer)
    local z = U.zooms[U.zoom] or 2
    local cx, cy = U.plansCentre()
    local tex = D.texture("assets/images/carte_lc.jpg") or D.texture("assets/images/carte_sa.jpg")
    D.rect(M.x, M.y, M.w, M.h, 0, tocolor(27, 61, 89))
    if tex then
        local tw, th = dxGetMaterialSize(tex)
        local x0, y0 = cx - M.w / 2 * z, cy + M.h / 2 * z
        local u, vv = (x0 + 3000) / 6000 * tw, (3000 - y0) / 6000 * th
        local us, vs = M.w * z / 6000 * tw, M.h * z / 6000 * th
        dxDrawImageSection(D.X(M.x), D.Y(M.y), D.L(M.w), D.L(M.h), u, vv, us, vs, tex, 0, 0, 0, tocolor(255, 255, 255), true)
    end
    U.zone("carte", M.x, M.y, M.w, M.h)
    -- points de la carte (blips)
    for _, b in ipairs(getElementsByType("blip")) do
        if b ~= U.blipDest and getElementDimension(b) == getElementDimension(localPlayer) then
            local bx, by = getElementPosition(b)
            local mx, my = U.versCarte(bx, by, cx, cy, z)
            if mx > M.x + 8 and mx < M.x + M.w - 8 and my > 8 and my < M.h - 8 then
                local icone = tonumber(getBlipIcon(b)) or 0
                local chemin = ":Radar_Core/images/" .. icone .. ".png"
                if icone > 0 and icone <= 63 and getResourceFromName("Radar_Core") and getResourceState(getResourceFromName("Radar_Core")) == "running" then
                    dxDrawImage(D.X(mx - 10), D.Y(my - 10), D.L(20), D.L(20), chemin, 0, 0, 0, tocolor(255, 255, 255), true)
                else
                    local r, g, bl = getBlipColor(b)
                    D.cercle(mx, my, 5, tocolor(r, g, bl, 230))
                end
            end
        end
    end
    -- GPS : traits construits sur le réseau des nodes GTA III.
    if U.dest then
        if U.route and U.route.points then
            local prevX, prevY = px, py
            for _, node in ipairs(U.route.points) do
                local ax, ay = U.versCarte(prevX, prevY, cx, cy, z)
                local bx, by = U.versCarte(node.x, node.y, cx, cy, z)
                drawGPSLine(ax, ay, bx, by, D.c("bleu", 220), math.max(2, D.L(5)))
                prevX, prevY = node.x, node.y
            end
            local ax, ay = U.versCarte(prevX, prevY, cx, cy, z)
            local bx, by = U.versCarte(U.dest.x, U.dest.y, cx, cy, z)
            drawGPSLine(ax, ay, bx, by, D.c("bleu", 220), math.max(2, D.L(5)))
        else
            local dx, dy = U.versCarte(U.dest.x, U.dest.y, cx, cy, z)
            local ox, oy = U.versCarte(px, py, cx, cy, z)
            dxDrawLine(D.X(ox), D.Y(oy), D.X(math.max(M.x, math.min(M.x + M.w, dx))), D.Y(math.max(0, math.min(M.h, dy))), D.c("rouge", 200), math.max(2, D.L(3)), true)
        end
        local dx, dy = U.versCarte(U.dest.x, U.dest.y, cx, cy, z)
        if dx > M.x and dx < M.x + M.w and dy > 0 and dy < M.h then D.icone("repere", dx - 18, dy - 34, 36, D.c("rouge")) end
    end
    -- véhicule (flèche orientée)
    local rz = 0
    if v then local _, _, r = getElementRotation(v) rz = r end
    local vx, vy = U.versCarte(px, py, cx, cy, z)
    D.cercle(vx, vy, 20, D.c("bleu", 70))
    D.icone("fleche", vx - 15, vy - 15, 30, D.c("bleu"), -rz)
    -- carte d'itinéraire
    if U.dest then
        if getTickCount() >= (U.routeRefreshTick or 0) then calculerRouteGPS(U.dest.x, U.dest.y) end
        local d = U.route and U.route.distance or getDistanceBetweenPoints2D(px, py, U.dest.x, U.dest.y)
        if d < 25 then
            U.notifier("Plans", "Vous êtes arrivé : " .. U.dest.nom .. ".")
            U.effacerDestination()
        else
            local vit = 0
            if v then local a, b, c2 = getElementVelocity(v) vit = math.sqrt(a * a + b * b + c2 * c2) * 50 end
            local eta = math.ceil(d / math.max(vit, 13.9) / 60)
            D.rect(116, 16, 380, 104, 18, D.c("barre", 240))
            local nextPoint = U.route and U.route.points[1]
            local targetX, targetY = nextPoint and nextPoint.x or U.dest.x, nextPoint and nextPoint.y or U.dest.y
            D.icone("fleche", 132, 32, 40, D.c("texte"), (math.deg(math.atan2(targetX - px, targetY - py)) - (360 - rz)) % 360)
            D.texte(U.distance(d), 186, 24, 300, 34, D.c("texte"), 26, "b")
            local direction = U.route and "itinéraire GTA III" or "route introuvable"
            D.texte("vers " .. U.cap(U.dest.x - px, U.dest.y - py) .. " · " .. eta .. " min · " .. direction, 186, 58, 300, 24, D.c("dim"), 15)
            D.texte(U.dest.nom, 132, 84, 350, 26, D.c("texte"), 15, "s")
            local se = U.zone("finItineraire", 420, 26, 60, 36)
            D.rect(420, 26, 64, 36, 18, D.c(se and "rouge" or "carte2"))
            D.texte("Fin", 420, 26, 64, 36, D.c("texte"), 14, "s", "center")
        end
    else
        D.rect(116, 16, 420, 50, 18, D.c("barre", 230))
        D.texte("Glisse la carte · clic droit : GPS · molette : zoom", 116, 16, 420, 50, D.c("dim"), 14, "s", "center")
    end
    -- boutons
    local function bouton(id, icone, x, y)
        local s = U.zone(id, x, y, 50, 50)
        D.rect(x, y, 50, 50, 14, D.c(s and "carte2" or "barre", 240))
        D.icone(icone, x + 11, y + 11, 28, D.c("texte"))
    end
    bouton("plansRecentrer", "centrer", 934, 244)
    bouton("zoomPlus", "plus", 934, 300)
    bouton("zoomMoins", "moins", 934, 356)
    bouton("panneauDest", "etoile", 934, 412)
    if U.panneauDest then
        local liste = U.destinations()
        D.rect(560, 16, 360, 468, 18, D.c("barre", 245))
        D.texte("Destinations", 580, 24, 300, 36, D.c("texte"), 20, "b")
        if #liste == 0 then D.texte("Aucun lieu nommé sur la carte.", 580, 70, 320, 30, D.c("dim"), 15) end
        for i = 1, math.min(7, #liste) do
            local l = liste[i]
            local y = 66 + (i - 1) * 58
            local s = U.zone("destination", 572, y, 336, 52, l)
            D.rect(572, y, 336, 52, 12, s and D.c("carte2") or D.c("carte"))
            D.icone("repere", 584, y + 12, 28, D.c("rouge"))
            D.texte(l.nom, 622, y + 4, 280, 26, D.c("texte"), 15, "s")
            D.texte(U.distance(l.d), 622, y + 28, 280, 20, D.c("dim"), 13)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Paramètres (demande 71)
-- ---------------------------------------------------------------------------
function U.dessinerReglages()
    local veh = U.vehicule()
    local vx = veh and getVehicleName(veh) or "Véhicule"
    local vpl = veh and getVehiclePlateText(veh) or "---"

    D.texte("Paramètres", 120, 16, 400, 36, D.c("texte"), 24, "b")

    -- Carte 1 : Échelle de CarPlay
    D.rect(120, 58, 410, 160, 16, D.c("barre", 240))
    D.texte("Taille de CarPlay", 140, 70, 370, 24, D.c("texte"), 16, "b")
    D.texte("Ajuste la dimension globale de l'interface.", 140, 94, 370, 18, D.c("dim"), 12)

    local echelles = {
        { id = 0.75, nom = "75%" },
        { id = 0.90, nom = "90%" },
        { id = 1.00, nom = "100%" },
        { id = 1.10, nom = "110%" },
        { id = 1.25, nom = "125%" },
    }
    local curEch = math.floor((D.echelle or 1.0) * 100 + 0.5) / 100
    for i, opt in ipairs(echelles) do
        local bx = 135 + (i - 1) * 76
        local actif = math.abs(curEch - opt.id) < 0.03
        local s = U.zone("reglages:echelle", bx, 130, 68, 38, opt.id)
        D.rect(bx, 130, 68, 38, 10, actif and D.c("bleu") or (s and D.c("carte2") or D.c("carte")))
        D.texte(opt.nom, bx, 130, 68, 38, D.c("texte"), 14, actif and "b" or "s", "center")
    end
    D.texte("Taille actuelle : " .. math.floor(curEch * 100) .. "%", 140, 180, 370, 22, D.c("dim"), 13)

    -- Carte 2 : Taille de la police
    D.rect(550, 58, 410, 160, 16, D.c("barre", 240))
    D.texte("Taille de la police", 570, 70, 370, 24, D.c("texte"), 16, "b")
    D.texte("Modifie la lisibilité et l'échelle des textes.", 570, 94, 370, 18, D.c("dim"), 12)

    local polices = {
        { id = 0.85, nom = "Petite" },
        { id = 1.00, nom = "Standard" },
        { id = 1.15, nom = "Grande" },
        { id = 1.30, nom = "T. Grande" },
    }
    local curPol = math.floor((D.facteurPolice or 1.0) * 100 + 0.5) / 100
    for i, opt in ipairs(polices) do
        local bx = 565 + (i - 1) * 94
        local actif = math.abs(curPol - opt.id) < 0.03
        local s = U.zone("reglages:police", bx, 130, 86, 38, opt.id)
        D.rect(bx, 130, 86, 38, 10, actif and D.c("bleu") or (s and D.c("carte2") or D.c("carte")))
        D.texte(opt.nom, bx, 130, 86, 38, D.c("texte"), 13, actif and "b" or "s", "center")
    end
    D.texte("Échelle de police : " .. math.floor(curPol * 100) .. "%", 570, 180, 370, 22, D.c("dim"), 13)

    -- Carte 3 : Position de la fenêtre & Drag and Move
    D.rect(120, 235, 410, 140, 16, D.c("barre", 240))
    D.texte("Position de la fenêtre", 140, 247, 370, 24, D.c("texte"), 16, "b")
    D.texte("Glisse le bandeau supérieur pour déplacer la fenêtre.", 140, 271, 370, 36, D.c("dim"), 12, "r", "left", "top", true, true)
    local sRec = U.zone("reglages:recentrer", 140, 318, 180, 38)
    D.rect(140, 318, 180, 38, 10, sRec and D.c("carte2") or D.c("carte"))
    D.icone("centrer", 152, 326, 22, D.c("texte"))
    D.texte("Recentrer l'écran", 182, 318, 130, 38, D.c("texte"), 13, "s", "left")

    -- Carte 4 : Informations Véhicule & CarPlay
    D.rect(550, 235, 410, 140, 16, D.c("barre", 240))
    D.texte("Véhicule & CarPlay", 570, 247, 370, 24, D.c("texte"), 16, "b")
    D.texte("Modèle : " .. tostring(vx), 570, 277, 370, 20, D.c("texte"), 14)
    D.texte("Immatriculation : " .. tostring(vpl), 570, 301, 370, 20, D.c("dim"), 13)
    D.rect(570, 332, 10, 10, 5, D.c("vert"))
    D.texte("CarPlay installé (validé mécanicien / admin)", 590, 327, 340, 20, D.c("vert"), 13, "s")
end

-- ---------------------------------------------------------------------------
-- Bandeau d'appel (au-dessus de tout) et notifications
-- ---------------------------------------------------------------------------
function U.etatAppel()
    local entrant = getElementData(localPlayer, "ios.callProposal")
    if isElement(entrant) then return "entrant", entrant end
    local enCours = getElementData(localPlayer, "ios.callRunning")
    if isElement(enCours) then return "enCours", enCours end
    if getElementData(localPlayer, "ios.callGroup") then return "groupe" end
    local sortant = getElementData(localPlayer, "ios.callingToPlayer")
    if isElement(sortant) then return "sortant", sortant end
    return nil
end

function U.dessinerAppel()
    local genre, autre = U.etatAppel()
    if not genre then return end
    local num = isElement(autre) and (getElementData(autre, "ios.phone.number") or "") or ""
    local nom = genre == "groupe" and "Conférence" or U.nomDe(num)
    local x, y, w, h = 250, 12, 640, 76
    D.rect(x, y, w, h, 20, D.c("carte2", 250))
    U.pastille(nom, x + 40, y + 38, 26)
    D.texte(nom, x + 78, y + 10, 330, 30, D.c("texte"), 19, "b")
    local sous = ({ entrant = "Appel entrant…", sortant = "Appel en cours…", groupe = "En conférence" })[genre]
    if genre == "enCours" then
        local debut = tonumber(getElementData(localPlayer, "ios.callStart")) or getRealTime().timestamp
        sous = "En ligne · " .. LI.duree(getRealTime().timestamp - debut)
    end
    D.texte(sous, x + 78, y + 40, 330, 24, D.c("dim"), 15)
    if genre == "entrant" then
        local sr = U.zone("refuser", x + w - 150, y + 12, 52, 52)
        D.cercle(x + w - 124, y + 38, 26, D.c("rouge", sr and 200 or 255))
        D.icone("raccrocher", x + w - 140, y + 22, 32, D.c("texte"))
        local sa = U.zone("accepter", x + w - 80, y + 12, 52, 52)
        D.cercle(x + w - 54, y + 38, 26, D.c("vert", sa and 200 or 255))
        D.icone("appel", x + w - 70, y + 22, 32, D.c("texte"))
    else
        local sr = U.zone("raccrocher", x + w - 80, y + 12, 52, 52)
        D.cercle(x + w - 54, y + 38, 26, D.c("rouge", sr and 200 or 255))
        D.icone("raccrocher", x + w - 70, y + 22, 32, D.c("texte"))
    end
end

function U.dessinerBanniere()
    local b = U.banniere
    if not b then return end
    if getTickCount() > b.fin then U.banniere = nil return end
    local x, y, w, h = 300, 96, 540, 64
    U.zone("banniere", x, y, w, h)
    D.rect(x, y, w, h, 18, D.c("carte2", 245))
    D.texte(b.titre, x + 20, y + 6, w - 40, 26, D.c("texte"), 16, "b")
    D.texte(b.texte, x + 20, y + 32, w - 40, 24, D.c("dim"), 14)
end

-- ---------------------------------------------------------------------------
-- Rendu
-- ---------------------------------------------------------------------------
function U.doitFermer()
    if not U.vehicule() then return true end
    if getElementData(localPlayer, "ios.phone:hasPhone") ~= true then return true end
    if getElementData(localPlayer, "ecran:noir") then return true end
    return false
end

addEventHandler("onClientRender", root, function()
    if not U.ouvert then return end
    if U.doitFermer() then return U.fermer() end
    local sx, sy = guiGetScreenSize()
    if U.glisse then
        if getKeyState("mouse1") and isCursorShowing() then
            local mx, my = getCursorPosition()
            if mx and my then
                local curX = mx * sx
                local curY = my * sy
                D.customX = U.glisse.initOx + (curX - U.glisse.startX)
                D.customY = U.glisse.initOy + (curY - U.glisse.startY)
            end
        else
            U.glisse = nil
            U.sauvegarderPrefs()
        end
    end
    D.cadrer(sx, sy)
    if U.plansDrag then
        if U.page == "plans" and getKeyState("mouse1") then
            local cx,cy=D.curseur()
            local g=U.plansDrag
            if cx and cy then
                U.plansCx=g.cx-(cx-g.x)*g.u
                U.plansCy=g.cy+(cy-g.y)*g.u
                U.plansBorner()
            end
        else
            U.plansDrag=nil
        end
    end
    U.zones = {}
    U.listes = {}
    U.dessinerCadre()
    local p = U.page
    if p == "accueil" then U.dessinerAccueil()
    elseif p == "musique" then U.dessinerMusique()
    elseif p == "telephone" then U.dessinerTelephone()
    elseif p == "messages" then U.dessinerMessages()
    elseif p == "plans" then U.dessinerPlans()
    elseif p == "reglages" then U.dessinerReglages() end
    U.dessinerAppel()
    U.dessinerBanniere()
end)

-- ---------------------------------------------------------------------------
-- Clics
-- ---------------------------------------------------------------------------
function U.cliquer(z, cx, cy)
    local id, d = z.id, z.d
    if id ~= "champ" and U.champ then U.finSaisie() end
    if id == "fermer" then return U.fermer()
    elseif id == "accueil" then return U.allerA("accueil")
    elseif id == "app" then
        if d == "radio" then
            local v = U.vehicule()
            U.fermer()
            if v then triggerEvent("vehicleRadio:openPanel", localPlayer, v) end
            return
        end
        return U.allerA(d)
    elseif id == "lienDirect" then U.sous.musique = "lien" return U.allerA("musique")
    elseif id == "onglet" then
        U.sous[d.cle] = d.val
        if d.cle == "musique" and d.val == "favoris" then triggerServerEvent("carplay:favoris:demander", resourceRoot) end
        if d.cle == "musique" and d.val == "lien" then U.statutLien = nil U.saisir("lien", C.lienMax) end
        if d.cle == "telephone" then U.chargerTelephone() end
        return
    elseif id == "ctl" then return U.action(d)
    elseif id == "volume" then return U.action("volume", math.max(0, math.min(1, (cx - 340) / 400)))
    elseif id == "favori" then return triggerServerEvent("carplay:favori:basculer", resourceRoot, d)
    elseif id == "jouerIndex" then return U.action("jouerIndex", d)
    elseif id == "retirer" then return U.action("retirer", d)
    elseif id == "favJouer" then return triggerServerEvent("carplay:favori:jouer", resourceRoot, d, true)
    elseif id == "favFile" then return triggerServerEvent("carplay:favori:jouer", resourceRoot, d, false)
    elseif id == "favRetirer" then return triggerServerEvent("carplay:favori:retirer", resourceRoot, d)
    elseif id == "champ" then
        if U.champ ~= d then U.saisir(d, d == "lien" and C.lienMax or 1000) end
        return
    elseif id == "lienLire" then return U.envoyerLien(true)
    elseif id == "lienFile" then return U.envoyerLien(false)
    elseif id == "appeler" then
        if d == "clavier" then return U.appeler(U.clavier) end
        return U.appeler(d)
    elseif id == "touche" then
        if #U.clavier < 12 then
            if #U.clavier == 3 and d:match("%d") and not U.clavier:find("-", 1, true) and U.clavier:match("^%d%d%d$") then U.clavier = U.clavier .. "-" end
            U.clavier = U.clavier .. d
        end
        return
    elseif id == "toucheEffacer" then
        U.clavier = (U.clavier:sub(1, -2):gsub("%-$", ""))
        return
    elseif id == "conv" then return U.ouvrirConv(d)
    elseif id == "convRetour" then U.conv = nil return
    elseif id == "rapide" then return U.envoyerMessage(d)
    elseif id == "envoyer" then return U.envoyerMessage(U.textes.message)
    elseif id == "accepter" or id == "refuser" or id == "raccrocher" then
        local r = U.racineIPhone()
        if not r then return end
        if id == "accepter" then triggerServerEvent("ios:onPlayerAcceptCall", r, localPlayer)
        else triggerServerEvent("ios:onPlayerCancelCall", r, localPlayer) end
        return
    elseif id == "banniere" then
        local b = U.banniere
        U.banniere = nil
        if b and b.action then b.action() end
        return
    elseif id == "reglages:echelle" then
        D.echelle = tonumber(d) or 1.0
        D.liberer()
        U.sauvegarderPrefs()
        return
    elseif id == "reglages:police" then
        D.facteurPolice = tonumber(d) or 1.0
        D.liberer()
        U.sauvegarderPrefs()
        return
    elseif id == "reglages:recentrer" then
        D.customX = nil
        D.customY = nil
        U.sauvegarderPrefs()
        return
    elseif id == "plansRecentrer" then U.plansRecentrer() return
    elseif id == "zoomPlus" then U.plansZoomer(-1, U.MAP.x+U.MAP.w/2, U.MAP.y+U.MAP.h/2) return
    elseif id == "zoomMoins" then U.plansZoomer(1, U.MAP.x+U.MAP.w/2, U.MAP.y+U.MAP.h/2) return
    elseif id == "panneauDest" then U.panneauDest = not U.panneauDest return
    elseif id == "destination" then
        U.definirDestination(d.x, d.y, d.nom)
        U.panneauDest = false
        return
    elseif id == "finItineraire" then return U.effacerDestination()
    end
end

addEventHandler("onClientClick", root, function(bouton, etat)
    if not U.ouvert then return end
    local cx, cy = D.curseur()
    if not cx then return end

    -- Plans: GPS only with the right mouse button. A left drag pans the map.
    if bouton == "right" then
        if etat == "down" and U.page == "plans" then
            local z=U.zoneSousCurseur(cx,cy)
            if z and z.id == "carte" then
                local plansCx,plansCy=U.plansCentre()
                local wx,wy=U.versMonde(cx,cy,plansCx,plansCy,U.zooms[U.zoom] or 2)
                if wx>-3000 and wx<3000 and wy>-3000 and wy<3000 then
                    U.definirDestination(wx,wy,"Point GPS sur la carte")
                    U.notifier("Plans","Repère GPS défini par clic droit.")
                end
                cancelEvent()
            end
        end
        return
    end
    if bouton ~= "left" then return end

    if etat == "down" then
        local z=U.zoneSousCurseur(cx,cy)
        if z then
            if z.id == "deplacer" then
                local sx, sy = guiGetScreenSize()
                local mx, my = getCursorPosition()
                if mx and my then U.glisse={startX=mx*sx,startY=my*sy,initOx=D.ox,initOy=D.oy} end
                return
            elseif z.id == "carte" and U.page == "plans" then
                local mx,my=U.plansCentre()
                U.plansDrag={x=cx,y=cy,cx=mx,cy=my,u=U.zooms[U.zoom] or 2}
                return
            end
            return U.cliquer(z,cx,cy)
        end
        if U.champ then U.finSaisie() end
    elseif etat == "up" then
        U.plansDrag=nil
        if U.glisse then U.glisse=nil; U.sauvegarderPrefs() end
    end
end)

-- Molette : zoom sur Plans, défilement pour les listes.
addEventHandler("onClientKey", root, function(touche, appui)
    if not U.ouvert or not appui or (touche ~= "mouse_wheel_up" and touche ~= "mouse_wheel_down") then return end
    local cx, cy = D.curseur()
    if not cx then return end
    local z=U.zoneSousCurseur(cx,cy)
    if U.page=="plans" and z and z.id=="carte" then
        U.plansZoomer(touche=="mouse_wheel_down" and 1 or -1,cx,cy)
        cancelEvent()
        return
    end
    for cle, l in pairs(U.listes or {}) do
        if cx >= l.x and cx <= l.x + l.w and cy >= l.y and cy <= l.y + l.h then
            U.defil[cle] = (U.defil[cle] or 0) + (touche == "mouse_wheel_down" and 1 or -1)
            cancelEvent()
            return
        end
    end
    if cx >= 0 and cx <= 1000 and cy >= 0 and cy <= 500 then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if U.ouvert then U.fermer() end
    U.effacerDestination()
    D.liberer()
end)
