-- ============================================================================
-- CarPlay — serveur (demande 69, 20/10/2026)
-- ----------------------------------------------------------------------------
-- Le serveur est la seule source de vérité de la musique d'un véhicule :
--   * la file d'attente (25 morceaux max), le morceau en cours, lecture /
--     pause, le volume ; publiés dans la donnée d'élément « carplay:etat » du
--     véhicule, lue par TOUS les clients (passagers et joueurs dehors) ;
--   * l'heure de départ du morceau est exprimée en getTickCount() SERVEUR :
--     chaque client connaît l'écart avec sa propre horloge (« carplay:horloge »)
--     et démarre la vidéo au même endroit que les autres (synchronisé) ;
--   * la fin d'un morceau (durée connue) passe au suivant automatiquement.
-- Seuls le conducteur et le passager avant, avec un iPhone, touchent l'écran.
-- Les favoris sont enregistrés par PERSONNAGE (LoginFuturo:charKey).
-- YouTube : titre et auteur par oEmbed, durée lue dans la page de la vidéo
-- (fetchRemote serveur : l'admin doit accepter « aclrequest allow CarPlay all »).
-- ============================================================================

local C = CARPLAY_CONFIG
local LI = CARPLAY_LIENS
local CP = {}
CARPLAY_SERVEUR = CP -- pour les bancs (tools/test_demande69.lua)

CP.etats = {}       -- [véhicule] = état complet (file comprise)
CP.timers = {}      -- [véhicule] = timer de fin de morceau
CP.dernier = {}     -- [joueur] = tick de la dernière action (anti-spam)
CP.serie = 0        -- identifiant unique des morceaux

local base = dbConnect("sqlite", "carplay.db")
CP.base = base
if base then
    dbExec(base, "CREATE TABLE IF NOT EXISTS carplay_vehicules (veh_id TEXT PRIMARY KEY, installe_par TEXT NOT NULL, role TEXT NOT NULL, ts INTEGER NOT NULL)")
    dbExec(base, "CREATE TABLE IF NOT EXISTS carplay_favoris (id INTEGER PRIMARY KEY AUTOINCREMENT, perso TEXT NOT NULL, type TEXT NOT NULL, ref TEXT NOT NULL, titre TEXT NOT NULL, auteur TEXT NOT NULL DEFAULT '', duree INTEGER, ts INTEGER NOT NULL, UNIQUE(perso, ref))")
end

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
local function notifier(p, texte, genre)
    if not isElement(p) then return end
    local res = getResourceFromName("[FU]Notify")
    if res and getResourceState(res) == "running" then
        local style = ({ error = "error", warning = "aviso", success = "success" })[genre or ""] or "infos"
        if pcall(function() exports["[FU]Notify"]:notify(p, texte, style) end) then return end
    end
    outputChatBox("[CarPlay] " .. tostring(texte), p, 255, 255, 255)
end
CP.notifier = notifier

local function clePerso(p)
    if not isElement(p) then return nil end
    local c = getElementData(p, "LoginFuturo:charKey")
    if type(c) ~= "string" or c == "" or #c > 100 then return nil end
    return c
end
CP.clePerso = clePerso

-- Véhicule que le joueur peut piloter depuis CarPlay (place avant + iPhone).
function CP.vehiculeDe(p)
    if not isElement(p) or getElementType(p) ~= "player" then return nil end
    local v = getPedOccupiedVehicle(p)
    if not v then return nil, "Tu dois être dans un véhicule." end
    if not C.places[getPedOccupiedVehicleSeat(p) or -1] then return nil, "CarPlay se contrôle depuis les places avant." end
    if getElementData(p, "ios.phone:hasPhone") ~= true then return nil, "Il te faut un iPhone pour utiliser CarPlay." end
    if getElementData(v, "carplay:installe") ~= true then
        return nil, "CarPlay n'est pas installé sur ce véhicule (mécanicien ou admin requis)."
    end
    return v
end

local function antiSpam(p, ms)
    local t = getTickCount()
    if CP.dernier[p] and t - CP.dernier[p] < (ms or 250) then return false end
    CP.dernier[p] = t
    return true
end

local function etat(v)
    local e = CP.etats[v]
    if not e then
        e = { file = {}, index = 0, lecture = false, debut = 0, position = 0, volume = C.volumeDefaut, fin = false }
        CP.etats[v] = e
    end
    return e
end
CP.etat = etat

local function pisteCourante(e) return e.file[e.index] end

-- Secondes écoulées dans le morceau en cours.
function CP.ecoule(e)
    if e.lecture then return math.max(0, (getTickCount() - e.debut) / 1000) end
    return e.position or 0
end

local function copiePiste(t)
    if not t then return nil end
    return { id = t.id, type = t.type, ref = t.ref, titre = t.titre, auteur = t.auteur, duree = t.duree }
end

-- Publie l'état (donnée d'élément synchronisée) et replanifie la fin.
function CP.publier(v)
    if not isElement(v) then return end
    local e = CP.etats[v]
    if not e or #e.file == 0 then
        removeElementData(v, "carplay:etat")
        CP.planifier(v)
        return
    end
    local liste = {}
    for i, t in ipairs(e.file) do liste[i] = { id = t.id, type = t.type, titre = t.titre, auteur = t.auteur, duree = t.duree } end
    setElementData(v, "carplay:etat", {
        piste = copiePiste(pisteCourante(e)),
        lecture = e.lecture, debut = e.debut, position = e.position,
        volume = e.volume, index = e.index, file = liste, fin = e.fin,
    }, true)
    CP.planifier(v)
end

function CP.planifier(v)
    if CP.timers[v] and isTimer(CP.timers[v]) then killTimer(CP.timers[v]) end
    CP.timers[v] = nil
    local e = CP.etats[v]
    if not e or not e.lecture then return end
    local t = pisteCourante(e)
    if not t or not t.duree then return end
    local reste = t.duree - CP.ecoule(e) + 1.5
    CP.timers[v] = setTimer(function(veh, id)
        CP.timers[veh] = nil
        local ee = CP.etats[veh]
        local tt = ee and pisteCourante(ee)
        if tt and tt.id == id and ee.lecture then CP.suivant(veh, true) end
    end, math.max(50, math.floor(reste * 1000)), 1, v, t.id)
end

-- Démarre le morceau n° i à la position pos (secondes).
function CP.jouer(v, i, pos)
    local e = etat(v)
    if not e.file[i] then return false end
    e.index = i
    e.lecture = true
    e.fin = false
    e.position = 0
    e.debut = getTickCount() - math.floor((pos or 0) * 1000)
    -- La radio du véhicule se tait : une seule source de son à la fois.
    triggerEvent("vehicleRadio:couper", v)
    CP.publier(v)
    return true
end

function CP.pause(v)
    local e = CP.etats[v]
    if not e or not e.lecture then return false end
    e.position = CP.ecoule(e)
    e.lecture = false
    CP.publier(v)
    return true
end

function CP.reprendre(v)
    local e = CP.etats[v]
    if not e or e.lecture or not pisteCourante(e) then return false end
    if e.fin then return CP.jouer(v, e.index, 0) end
    return CP.jouer(v, e.index, e.position)
end

function CP.suivant(v, auto)
    local e = CP.etats[v]
    if not e or #e.file == 0 then return false end
    if e.index < #e.file then return CP.jouer(v, e.index + 1, 0) end
    -- Fin de la file : on s'arrête sur le dernier morceau (« Lecture terminée »).
    e.lecture = false
    e.position = 0
    e.fin = true
    CP.publier(v)
    return auto and true or false
end

function CP.precedent(v)
    local e = CP.etats[v]
    if not e or #e.file == 0 then return false end
    if CP.ecoule(e) > 5 or e.index <= 1 then return CP.jouer(v, math.max(1, e.index), 0) end
    return CP.jouer(v, e.index - 1, 0)
end

function CP.arreter(v)
    local e = CP.etats[v]
    if CP.timers[v] and isTimer(CP.timers[v]) then killTimer(CP.timers[v]) end
    CP.timers[v] = nil
    CP.etats[v] = nil
    if isElement(v) then removeElementData(v, "carplay:etat") end
    return e ~= nil
end

-- Ajoute un morceau prêt (métadonnées connues). maintenant = lire tout de suite.
function CP.ajouterPiste(v, piste, maintenant)
    local e = etat(v)
    if #e.file >= C.fileMax then return false, "La file d'attente est pleine (" .. C.fileMax .. " morceaux)." end
    CP.serie = CP.serie + 1
    piste.id = CP.serie
    piste.titre = LI.couper(piste.titre or "Sans titre", C.titreMax)
    piste.auteur = LI.couper(piste.auteur or "", 80)
    if maintenant and pisteCourante(e) then
        -- « Lire maintenant » : juste après le morceau en cours, et on y passe.
        table.insert(e.file, e.index + 1, piste)
        CP.jouer(v, e.index + 1, 0)
        return true
    end
    -- Rien en cours (file vide ou lecture terminée) : le nouveau morceau part.
    local demarrer = maintenant or not pisteCourante(e) or (e.fin and not e.lecture)
    e.file[#e.file + 1] = piste
    if demarrer then CP.jouer(v, #e.file, 0) else CP.publier(v) end
    return true
end

-- ---------------------------------------------------------------------------
-- Métadonnées YouTube (oEmbed + durée dans la page)
-- ---------------------------------------------------------------------------
local OEMBED = "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v="
local PAGE = "https://www.youtube.com/watch?hl=fr&v="
local ENTETES = {
    ["Accept-Language"] = "fr-FR,fr;q=0.9,en;q=0.8",
    ["Cookie"] = "CONSENT=YES+cb; SOCS=CAI",
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
}

local function telecharger(url, entetes, rappel)
    if type(fetchRemote) ~= "function" then return false end
    local ok, lance = pcall(fetchRemote, url, { queueName = "carplay", connectionAttempts = 2, connectTimeout = 6000, headers = entetes }, rappel)
    return ok and lance and true or false
end

function CP.infosYoutube(id, rappel)
    local res = { titre = nil, auteur = nil, duree = nil, refus = nil }
    local restant = 2
    local function fini()
        restant = restant - 1
        if restant == 0 then rappel(res) end
    end
    local lanceA = telecharger(OEMBED .. id, nil, function(data, info)
        local code = type(info) == "table" and tonumber(info.statusCode) or 0
        if type(info) == "table" and info.success and type(data) == "string" then
            local j = type(fromJSON) == "function" and select(2, pcall(fromJSON, data)) or nil
            if type(j) == "table" then
                res.titre, res.auteur = j.title, j.author_name
            else
                res.titre = LI.deJSON(data:match('"title"%s*:%s*"(.-)"%s*,'))
                res.auteur = LI.deJSON(data:match('"author_name"%s*:%s*"(.-)"%s*,'))
            end
        elseif code == 401 or code == 403 then
            res.refus = "Le propriétaire de cette vidéo interdit sa lecture hors de YouTube."
        elseif code == 400 or code == 404 then
            res.refus = "Vidéo YouTube introuvable (supprimée ou privée)."
        end
        fini()
    end)
    if not lanceA then fini() end
    local lanceB = telecharger(PAGE .. id, ENTETES, function(data, info)
        if type(info) == "table" and info.success then res.duree = LI.dureeDansPage(data) end
        fini()
    end)
    if not lanceB then fini() end
end

-- ---------------------------------------------------------------------------
-- Ajout d'un lien
-- ---------------------------------------------------------------------------
function CP.ajouterLien(p, texte, maintenant)
    local v, err = CP.vehiculeDe(p)
    if not v then return notifier(p, err, "error") end
    local lien, pourquoi = LI.analyser(texte)
    if not lien then
        triggerClientEvent(p, "carplay:lienRefuse", resourceRoot, pourquoi)
        return notifier(p, pourquoi, "error")
    end
    if #etat(v).file >= C.fileMax then return notifier(p, "La file d'attente est pleine (" .. C.fileMax .. " morceaux).", "error") end
    local par = getPlayerName(p)
    if lien.type == "youtube" then
        CP.infosYoutube(lien.ref, function(info)
            if not isElement(v) then return end
            if info.refus then
                if isElement(p) then triggerClientEvent(p, "carplay:lienRefuse", resourceRoot, info.refus) end
                return notifier(p, info.refus, "error")
            end
            local ok, e2 = CP.ajouterPiste(v, { type = "youtube", ref = lien.ref, titre = info.titre or ("Vidéo YouTube " .. lien.ref), auteur = info.auteur or "YouTube", duree = info.duree, par = par }, maintenant)
            if not ok then return notifier(p, e2, "error") end
            if isElement(p) then triggerClientEvent(p, "carplay:lienAccepte", resourceRoot, info.titre or lien.ref) end
        end)
    else
        local chemin = lien.ref:match("^[^%?#]*")
        local nom = chemin:match("([^/]+)%.%w+$") or lien.ref:match("^https?://([^/%?#]+)") or "Lien audio"
        local ok, e2 = CP.ajouterPiste(v, { type = "audio", ref = lien.ref, titre = (nom:gsub("[_%+]", " ")), auteur = lien.flux and "Flux audio" or "Lien audio", duree = nil, par = par }, maintenant)
        if not ok then return notifier(p, e2, "error") end
        triggerClientEvent(p, "carplay:lienAccepte", resourceRoot, nom)
    end
end

-- ---------------------------------------------------------------------------
-- Favoris (par personnage)
-- ---------------------------------------------------------------------------
function CP.listeFavoris(p)
    local cle = clePerso(p)
    if not base or not cle then return {} end
    local q = dbQuery(base, "SELECT id, type, ref, titre, auteur, duree FROM carplay_favoris WHERE perso = ? ORDER BY ts DESC LIMIT ?", cle, C.favorisMax)
    return (q and dbPoll(q, -1)) or {}
end

function CP.envoyerFavoris(p)
    triggerClientEvent(p, "carplay:favoris", resourceRoot, CP.listeFavoris(p))
end

function CP.basculerFavori(p, piste)
    local cle = clePerso(p)
    if not base or not cle then return notifier(p, "Favoris indisponibles : personnage introuvable.", "error") end
    if type(piste) ~= "table" or (piste.type ~= "youtube" and piste.type ~= "audio") or type(piste.ref) ~= "string" then return end
    local q = dbQuery(base, "SELECT id FROM carplay_favoris WHERE perso = ? AND ref = ?", cle, piste.ref)
    local r = q and dbPoll(q, -1)
    if r and r[1] then
        dbExec(base, "DELETE FROM carplay_favoris WHERE id = ?", r[1].id)
        notifier(p, "Retiré des favoris.", "success")
    else
        local n = dbQuery(base, "SELECT COUNT(*) AS n FROM carplay_favoris WHERE perso = ?", cle)
        local nr = n and dbPoll(n, -1)
        if nr and nr[1] and (tonumber(nr[1].n) or 0) >= C.favorisMax then return notifier(p, "Tu as déjà " .. C.favorisMax .. " favoris.", "error") end
        dbExec(base, "INSERT OR IGNORE INTO carplay_favoris (perso, type, ref, titre, auteur, duree, ts) VALUES (?, ?, ?, ?, ?, ?, ?)",
            cle, piste.type, piste.ref, LI.couper(piste.titre or "Sans titre", C.titreMax), LI.couper(piste.auteur or "", 80), tonumber(piste.duree), getRealTime().timestamp)
        notifier(p, "Ajouté aux favoris.", "success")
    end
    CP.envoyerFavoris(p)
end

-- ---------------------------------------------------------------------------
-- Événements des clients
-- ---------------------------------------------------------------------------
addEvent("carplay:horloge", true)
addEventHandler("carplay:horloge", resourceRoot, function(tickClient)
    if not isElement(client) then return end
    triggerClientEvent(client, "carplay:horloge", resourceRoot, tickClient, getTickCount())
end)

addEvent("carplay:ajouter", true)
addEventHandler("carplay:ajouter", resourceRoot, function(texte, maintenant)
    local p = client
    if not isElement(p) or not antiSpam(p, 800) then return end
    CP.ajouterLien(p, texte, maintenant == true)
end)

function CP.action(p, action, valeur)
    local v, err = CP.vehiculeDe(p)
    if not v then return notifier(p, err, "error") end
    local e = CP.etats[v]
    if action == "lecture" then
        if e and e.lecture then CP.pause(v) elseif e then CP.reprendre(v) end
    elseif action == "pause" then CP.pause(v)
    elseif action == "reprendre" then CP.reprendre(v)
    elseif action == "suivant" then CP.suivant(v)
    elseif action == "precedent" then CP.precedent(v)
    elseif action == "stop" then CP.arreter(v)
    elseif action == "vider" then CP.arreter(v)
    elseif action == "volume" or action == "volplus" or action == "volmoins" then
        e = etat(v)
        local nv = tonumber(valeur)
        if action == "volplus" then nv = e.volume + C.pasVolume elseif action == "volmoins" then nv = e.volume - C.pasVolume end
        if not nv then return end
        e.volume = math.max(0, math.min(1, math.floor(nv * 100 + 0.5) / 100))
        if #e.file > 0 then CP.publier(v) end
    elseif action == "jouerIndex" then
        local i = math.floor(tonumber(valeur) or 0)
        if e and e.file[i] then CP.jouer(v, i, 0) end
    elseif action == "retirer" then
        local i = math.floor(tonumber(valeur) or 0)
        if not (e and e.file[i]) then return end
        local courant = (i == e.index)
        table.remove(e.file, i)
        if #e.file == 0 then return CP.arreter(v) end
        if i < e.index then e.index = e.index - 1
        elseif courant then
            if e.index > #e.file then e.index = #e.file; e.lecture = false; e.fin = true; e.position = 0
            elseif e.lecture then return CP.jouer(v, e.index, 0)
            else e.position = 0 end
        end
        CP.publier(v)
    end
end

addEvent("carplay:action", true)
addEventHandler("carplay:action", resourceRoot, function(action, valeur)
    local p = client
    if not isElement(p) or type(action) ~= "string" or not antiSpam(p, 150) then return end
    CP.action(p, action, valeur)
end)

-- Durée d'un lien audio direct, mesurée par un OCCUPANT du véhicule.
addEvent("carplay:duree", true)
addEventHandler("carplay:duree", resourceRoot, function(v, id, secondes)
    local p = client
    if not isElement(p) or not isElement(v) or getPedOccupiedVehicle(p) ~= v then return end
    local e = CP.etats[v]
    local t = e and pisteCourante(e)
    secondes = tonumber(secondes)
    if not t or t.id ~= id or t.type ~= "audio" or t.duree or not secondes or secondes < 1 or secondes > 6 * 3600 then return end
    t.duree = math.floor(secondes)
    CP.publier(v)
end)

addEvent("carplay:favoris:demander", true)
addEventHandler("carplay:favoris:demander", resourceRoot, function()
    if isElement(client) and antiSpam(client, 300) then CP.envoyerFavoris(client) end
end)

addEvent("carplay:favori:basculer", true)
addEventHandler("carplay:favori:basculer", resourceRoot, function(id)
    local p = client
    if not isElement(p) or not antiSpam(p, 300) then return end
    local v = getPedOccupiedVehicle(p)
    local e = v and CP.etats[v]
    if not e then return end
    for _, t in ipairs(e.file) do
        if t.id == id then return CP.basculerFavori(p, t) end
    end
end)

addEvent("carplay:favori:retirer", true)
addEventHandler("carplay:favori:retirer", resourceRoot, function(fid)
    local p = client
    local cle = clePerso(p)
    if not isElement(p) or not cle or not base or not antiSpam(p, 300) then return end
    dbExec(base, "DELETE FROM carplay_favoris WHERE id = ? AND perso = ?", tonumber(fid) or -1, cle)
    CP.envoyerFavoris(p)
end)

addEvent("carplay:favori:jouer", true)
addEventHandler("carplay:favori:jouer", resourceRoot, function(fid, maintenant)
    local p = client
    local cle = clePerso(p)
    if not isElement(p) or not cle or not base or not antiSpam(p, 400) then return end
    local v, err = CP.vehiculeDe(p)
    if not v then return notifier(p, err, "error") end
    local q = dbQuery(base, "SELECT type, ref, titre, auteur, duree FROM carplay_favoris WHERE id = ? AND perso = ?", tonumber(fid) or -1, cle)
    local r = q and dbPoll(q, -1)
    if not (r and r[1]) then return end
    local f = r[1]
    local ok, e2 = CP.ajouterPiste(v, { type = f.type, ref = f.ref, titre = f.titre, auteur = f.auteur, duree = tonumber(f.duree), par = getPlayerName(p) }, maintenant ~= false)
    if not ok then notifier(p, e2, "error") end
end)

-- La radio du véhicule s'allume : CarPlay se met en pause.
addEvent("vehicleRadio:allumee", false)
addEventHandler("vehicleRadio:allumee", root, function()
    if CP.etats[source] then CP.pause(source) end
end)

addEventHandler("onElementDestroy", root, function()
    if CP.etats[source] or CP.timers[source] then CP.arreter(source) end
end)

addEventHandler("onPlayerQuit", root, function() CP.dernier[source] = nil end)

-- ---------------------------------------------------------------------------
-- Demande 71 : Installation / désinstallation de CarPlay
-- Seuls un mécanicien ou un administrateur 3+ peuvent équiper un véhicule.
-- L'équipement est persisté dans SQLite (carplay_vehicules).
-- ---------------------------------------------------------------------------
local function idVehicule(v)
    if not isElement(v) or getElementType(v) ~= "vehicle" then return nil end
    local id = getElementData(v, "Vehicle > ID") or getElementData(v, "vehicle:id") or getElementData(v, "vehicle:dbID") or getElementData(v, "dbid")
    if id and tonumber(id) then return "id:" .. tostring(id) end
    local plaque = getVehiclePlateText(v)
    if plaque and plaque ~= "" then return "plaque:" .. tostring(plaque) end
    return nil
end
CP.idVehicule = idVehicule

local function verifierInstallationVehicule(v)
    if not isElement(v) or getElementType(v) ~= "vehicle" then return end
    if getElementData(v, "carplay:installe") == true then return end
    local vid = idVehicule(v)
    if not vid or not base then return end
    local q = dbQuery(base, "SELECT veh_id FROM carplay_vehicules WHERE veh_id = ?", vid)
    local res = q and dbPoll(q, -1)
    if res and #res > 0 then
        setElementData(v, "carplay:installe", true, true)
    end
end
CP.verifierInstallationVehicule = verifierInstallationVehicule

-- Demande 91 : quand un véhicule est racheté, sa clé d'identification (id ou
-- plaque) peut coïncider avec celle de l'ancien exemplaire... qui avait un
-- CarPlay installé. verifierInstallationVehicule ressortait alors la ligne
-- SQLite et « réinstallait » le boîtier sur le véhicule neuf. Le
-- concessionnaire purge donc l'équipement persistant à la sortie d'un
-- véhicule NEUF (carplayInstalled = false écrit à l'achat, demande 82).
function carplaySupprimerInstallation(v)
    local vid = isElement(v) and idVehicule(v) or (v and tostring(v) or nil)
    if not vid or not base then return false end
    dbExec(base, "DELETE FROM carplay_vehicules WHERE veh_id = ?", vid)
    if isElement(v) and getElementData(v, "carplay:installe") == true then
        setElementData(v, "carplay:installe", false, true)
    end
    return true
end

local function peutInstallerCarPlay(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    -- 1. Staff niveau 3+ (Admin 1 et +)
    local staffRes = getResourceFromName("core_staff")
    if staffRes and getResourceState(staffRes) == "running" then
        local ok, allowed = pcall(function() return exports.core_staff:hasStaffLevel(player, 3) end)
        if ok and allowed then return true, "admin" end
    end
    local stRes = getResourceFromName("staff_system")
    if stRes and getResourceState(stRes) == "running" then
        local ok, res = pcall(function() return exports.staff_system:isAdmin(player) end)
        if ok and res then return true, "admin" end
    end
    -- 2. Mécanicien (faction_system)
    local facRes = getResourceFromName("faction_system")
    if facRes and getResourceState(facRes) == "running" then
        local ok, onDuty = pcall(function() return exports.faction_system:isPlayerOnFactionDuty(player, "mecanicien") end)
        if ok and onDuty then return true, "mecanicien" end
    end
    -- Repli ancien métier indépendant : lui aussi doit être de service.
    if getElementData(player, "mecanicien >> duty") == true or getElementData(player, "mechanic >> duty") == true then
        return true, "mecanicien"
    end
    return false
end
CP.peutInstallerCarPlay = peutInstallerCarPlay

function CP.trouverVehiculeCible(joueur, veh)
    if isElement(veh) and getElementType(veh) == "vehicle" then return veh end
    local vOcc = getPedOccupiedVehicle(joueur)
    if isElement(vOcc) then return vOcc end
    local jx, jy, jz = getElementPosition(joueur)
    local proche, distMin = nil, 6
    for _, v in ipairs(getElementsByType("vehicle")) do
        if getElementDimension(v) == getElementDimension(joueur) and getElementInterior(v) == getElementInterior(joueur) then
            local vx, vy, vz = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(jx, jy, jz, vx, vy, vz)
            if d < distMin then
                distMin = d
                proche = v
            end
        end
    end
    return proche
end

function CP.installerCarPlay(joueur, veh)
    if not isElement(joueur) or getElementType(joueur) ~= "player" then return false end
    local ok, role = peutInstallerCarPlay(joueur)
    if not ok then
        notifier(joueur, "Seul un mécanicien ou un administrateur (3+) peut installer CarPlay.", "error")
        return false
    end
    local targetVeh = CP.trouverVehiculeCible(joueur, veh)
    if not isElement(targetVeh) then
        notifier(joueur, "Aucun véhicule ciblé ou à proximité immédiate (6 m).", "error")
        return false
    end

    if getElementData(targetVeh, "carplay:installe") == true then
        notifier(joueur, "CarPlay est déjà installé sur ce véhicule.", "warning")
        return false
    end

    setElementData(targetVeh, "carplay:installe", true, true)
    local vid = idVehicule(targetVeh)
    if vid and base then
        dbExec(base, "INSERT OR REPLACE INTO carplay_vehicules (veh_id, installe_par, role, ts) VALUES (?, ?, ?, ?)",
            vid, getPlayerName(joueur), role or "mecanicien", getRealTime().timestamp)
    end

    notifier(joueur, "CarPlay a été installé avec succès sur ce véhicule !", "success")
    outputChatBox("[CarPlay] Le système CarPlay a été installé sur ce véhicule.", targetVeh, 48, 209, 88)
    return true
end

function CP.desinstallerCarPlay(joueur, veh)
    if not isElement(joueur) or getElementType(joueur) ~= "player" then return false end
    local ok, role = peutInstallerCarPlay(joueur)
    if not ok then
        notifier(joueur, "Seul un mécanicien ou un administrateur (3+) peut désinstaller CarPlay.", "error")
        return false
    end
    local targetVeh = CP.trouverVehiculeCible(joueur, veh)
    if not isElement(targetVeh) then
        notifier(joueur, "Aucun véhicule ciblé ou à proximité immédiate.", "error")
        return false
    end

    if getElementData(targetVeh, "carplay:installe") ~= true then
        notifier(joueur, "CarPlay n'est pas installé sur ce véhicule.", "warning")
        return false
    end

    setElementData(targetVeh, "carplay:installe", false, true)
    local vid = idVehicule(targetVeh)
    if vid and base then
        dbExec(base, "DELETE FROM carplay_vehicules WHERE veh_id = ?", vid)
    end
    CP.arreter(targetVeh)

    notifier(joueur, "CarPlay a été désinstallé de ce véhicule.", "infos")
    outputChatBox("[CarPlay] Le système CarPlay a été retiré de ce véhicule.", targetVeh, 255, 69, 58)
    return true
end

-- API appelée par le service mécano autoritaire après validation de la zone et
-- de l'accord propriétaire ; elle conserve les mêmes contrôles de rôle.
function installCarPlayFromMechanic(player, vehicle)
    return CP.installerCarPlay(player, vehicle)
end

function uninstallCarPlayFromMechanic(player, vehicle)
    return CP.desinstallerCarPlay(player, vehicle)
end

addEvent("carplay:installer", true)
addEventHandler("carplay:installer", root, function()
    local p = client or source
    if isElement(p) and getElementType(p) == "player" then
        CP.installerCarPlay(p, source ~= p and source or nil)
    end
end)

addEvent("carplay:desinstaller", true)
addEventHandler("carplay:desinstaller", root, function()
    local p = client or source
    if isElement(p) and getElementType(p) == "player" then
        CP.desinstallerCarPlay(p, source ~= p and source or nil)
    end
end)



-- ---------------------------------------------------------------------------
-- Demande 112 : réglages acoustiques par véhicule (panneau « Acoustique »)
-- Ouvert depuis i9 → Staff → Qualité audio (admin_panel appelle
-- ouvrirAcoustique). Admin 3+ EN SERVICE. Le serveur borne chaque valeur
-- (carplayAcoustiqueBorner, config.lua) et ne garde que les écarts aux défauts.
-- D112 quater : pendant le réglage, chaque changement est appliqué EN DIRECT
-- (donnée synchronisée → tous les joueurs proches l'entendent) ; « Enregistrer »
-- l'écrit en base ; fermer sans enregistrer remet l'état enregistré.
-- ---------------------------------------------------------------------------
local DONNEE_ACOUSTIQUE = "carplay:acoustique"
if base then
    dbExec(base, "CREATE TABLE IF NOT EXISTS carplay_acoustique (veh_id TEXT PRIMARY KEY, reglages TEXT NOT NULL, par TEXT, ts INTEGER NOT NULL)")
end
CP.reglageEnCours = {}   -- [véhicule] = admin qui règle (aperçu en direct)
CP.dernierApercu = {}    -- [joueur] = tick du dernier aperçu reçu

local function peutReglerAcoustique(p)
    if not isElement(p) or getElementType(p) ~= "player" then return false, "joueur invalide" end
    local res = getResourceFromName("core_staff")
    if not res or getResourceState(res) ~= "running" then return false, "core_staff est arrêtée." end
    local okN, niveau = pcall(function() return exports.core_staff:hasStaffLevel(p, 3) end)
    if not okN or not niveau then return false, "Réservé aux administrateurs niveau 3+." end
    local okS, service = pcall(function() return exports.core_staff:isOnDuty(p) end)
    if not okS or service ~= true then return false, "Passe en service (/aduty) pour régler l'audio." end
    return true
end
CP.peutReglerAcoustique = peutReglerAcoustique

-- D112 quinquies : deux portées d'enregistrement.
--   « vehicule » : l'ID du véhicule (véhicules de joueurs du concessionnaire :
--                  ID stable en base) — passe devant le modèle ;
--   « modele »   : tous les véhicules de ce modèle (clé « modele:<id GTA> »).
-- ⚠ police_system et system_ems donnent un ID ALÉATOIRE (7 000 000 à
-- 8 999 999) à chaque sortie : pour eux, seul le modèle tient dans le temps.
local function cleModele(v) return "modele:" .. tostring(getElementModel(v)) end
CP.cleModele = cleModele

local function idTemporaire(v)
    local id = tonumber(getElementData(v, "Vehicle > ID") or getElementData(v, "vehicle:id") or getElementData(v, "vehicle:dbID"))
    return id ~= nil and id >= 7000000 and id <= 8999999
end

local function lireCle(cle)
    if not cle or not base then return nil end
    local q = dbQuery(base, "SELECT reglages FROM carplay_acoustique WHERE veh_id = ?", cle)
    local res = q and dbPoll(q, -1)
    if res and res[1] then return carplayAcoustiqueEcarts(carplayAcoustiqueComplet(fromJSON(res[1].reglages))) end
    return nil
end

-- Réglages en base d'un véhicule : les siens, sinon ceux de son modèle.
-- Renvoie : écarts (ou nil), source ("vehicule", "modele" ou nil).
local function lireAcoustiqueEnBase(v)
    local propres = lireCle(idVehicule(v))
    if propres then return propres, "vehicule" end
    local modele = lireCle(cleModele(v))
    if modele then return modele, "modele" end
    return nil, nil
end

-- Pose (ou retire) la donnée synchronisée d'un véhicule.
local function poserAcoustique(v, ecarts)
    if type(ecarts) == "table" and next(ecarts) ~= nil then
        setElementData(v, DONNEE_ACOUSTIQUE, ecarts, true)
    elseif getElementData(v, DONNEE_ACOUSTIQUE) then
        removeElementData(v, DONNEE_ACOUSTIQUE)
    end
end

local function chargerAcoustique(v)
    if not isElement(v) or getElementType(v) ~= "vehicle" then return end
    if CP.reglageEnCours[v] then return end -- un admin règle : on ne l'écrase pas
    poserAcoustique(v, lireAcoustiqueEnBase(v))
end
CP.chargerAcoustique = chargerAcoustique

local function vehiculeReglable(p, v)
    if not isElement(v) or getElementType(v) ~= "vehicle" then return false, "Véhicule introuvable." end
    if getElementDimension(v) ~= getElementDimension(p) or getElementInterior(v) ~= getElementInterior(p) then
        return false, "Le véhicule n'est pas dans ton monde."
    end
    local px, py, pz = getElementPosition(p)
    local vx, vy, vz = getElementPosition(v)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > 60 then return false, "Approche-toi du véhicule (60 m)." end
    return true
end

local function nettoyer(reglages)
    local propre = {}
    if type(reglages) ~= "table" then return propre end
    for cle, valeur in pairs(reglages) do
        if type(cle) == "string" then
            local b = carplayAcoustiqueBorner(cle, valeur)
            if b ~= nil then propre[cle] = b end
        end
    end
    return propre
end

-- Fin du réglage sans enregistrer : on remet ce qui est en base.
local function finReglage(v)
    if not isElement(v) then return end
    CP.reglageEnCours[v] = nil
    chargerAcoustique(v)
end

-- Export appelé par admin_panel (entrée Staff → Qualité audio).
function ouvrirAcoustique(p, v)
    local ok, raison = peutReglerAcoustique(p)
    if not ok then notifier(p, raison, "error") return false end
    local okV, raisonV = vehiculeReglable(p, v)
    if not okV then notifier(p, raisonV, "error") return false end
    local autre = CP.reglageEnCours[v]
    if isElement(autre) and autre ~= p then
        notifier(p, getPlayerName(autre) .. " règle déjà l'audio de ce véhicule.", "warning")
        return false
    end
    CP.reglageEnCours[v] = p
    local ecarts, source = lireAcoustiqueEnBase(v)
    local nom = getVehicleName(v) or "Véhicule"
    triggerClientEvent(p, "carplay:acoustique:ouvrir", resourceRoot, v, carplayAcoustiqueComplet(ecarts), nom, idVehicule(v) ~= nil, {
        source = source,                 -- d'où viennent les réglages actuels
        idTemporaire = idTemporaire(v),  -- véhicule de faction : ID aléatoire
    })
    return true
end

-- Aperçu en direct (le panneau envoie au plus ~8 changements par seconde).
addEvent("carplay:acoustique:apercu", true)
addEventHandler("carplay:acoustique:apercu", resourceRoot, function(v, reglages)
    local p = client
    if not p or CP.reglageEnCours[v] ~= p then return end
    local t = getTickCount()
    if CP.dernierApercu[p] and t - CP.dernierApercu[p] < 80 then return end
    CP.dernierApercu[p] = t
    if not peutReglerAcoustique(p) or not vehiculeReglable(p, v) then return end
    poserAcoustique(v, (carplayAcoustiqueEcarts(carplayAcoustiqueComplet(nettoyer(reglages)))))
end)

addEvent("carplay:acoustique:sauver", true)
addEventHandler("carplay:acoustique:sauver", resourceRoot, function(v, reglages, portee)
    local p = client
    if not p then return end
    if not antiSpam(p, 800) then return end
    local ok, raison = peutReglerAcoustique(p)
    if not ok then return notifier(p, raison, "error") end
    local okV, raisonV = vehiculeReglable(p, v)
    if not okV then return notifier(p, raisonV, "error") end
    if type(reglages) ~= "table" then return end
    portee = portee == "modele" and "modele" or "vehicule"
    local ecarts, n = carplayAcoustiqueEcarts(carplayAcoustiqueComplet(nettoyer(reglages)))
    local vid = idVehicule(v)
    local cle = portee == "modele" and cleModele(v) or vid
    if not cle or not base then
        poserAcoustique(v, ecarts)
        notifier(p, "Réglages appliqués, mais ce véhicule n'a ni ID ni plaque : ils seront perdus à sa disparition.", "warning")
        return triggerClientEvent(p, "carplay:acoustique:enregistre", resourceRoot, v, carplayAcoustiqueComplet(ecarts), "vehicule")
    end
    if n > 0 then
        dbExec(base, "INSERT OR REPLACE INTO carplay_acoustique (veh_id, reglages, par, ts) VALUES (?, ?, ?, ?)",
            cle, toJSON(ecarts, true), getPlayerName(p), getRealTime().timestamp)
    else
        dbExec(base, "DELETE FROM carplay_acoustique WHERE veh_id = ?", cle)
    end
    local nomModele = getVehicleName(v) or "ce modèle"
    if portee == "modele" then
        -- ce véhicule suit désormais son modèle : ses réglages propres partent
        if vid then dbExec(base, "DELETE FROM carplay_acoustique WHERE veh_id = ?", vid) end
        poserAcoustique(v, ecarts)
        -- les autres véhicules de ce modèle en jeu suivent tout de suite
        local modele = getElementModel(v)
        for _, autre in ipairs(getElementsByType("vehicle")) do
            if autre ~= v and getElementModel(autre) == modele then chargerAcoustique(autre) end
        end
        notifier(p, "Réglages audio enregistrés pour tous les véhicules « " .. nomModele .. " ».", "success")
    else
        poserAcoustique(v, ecarts)
        notifier(p, idTemporaire(v)
            and "Enregistré sur l'ID de ce véhicule, mais c'est un ID temporaire (faction) : enregistre plutôt pour le modèle."
            or "Réglages audio enregistrés pour ce véhicule.", idTemporaire(v) and "warning" or "success")
    end
    local _, source = lireAcoustiqueEnBase(v)
    triggerClientEvent(p, "carplay:acoustique:enregistre", resourceRoot, v, carplayAcoustiqueComplet(ecarts), source or portee)
end)

addEvent("carplay:acoustique:recharger", true)
addEventHandler("carplay:acoustique:recharger", resourceRoot, function(v)
    local p = client
    if not p or not antiSpam(p, 500) then return end
    if not peutReglerAcoustique(p) or not vehiculeReglable(p, v) then return end
    local enBase, source = lireAcoustiqueEnBase(v)
    poserAcoustique(v, enBase)
    triggerClientEvent(p, "carplay:acoustique:enregistre", resourceRoot, v, carplayAcoustiqueComplet(enBase), source)
end)

addEvent("carplay:acoustique:fermer", true)
addEventHandler("carplay:acoustique:fermer", resourceRoot, function(v)
    if client and CP.reglageEnCours[v] == client then finReglage(v) end
end)

addEventHandler("onPlayerQuit", root, function()
    CP.dernierApercu[source] = nil
    for v, p in pairs(CP.reglageEnCours) do if p == source then finReglage(v) end end
end)

addEventHandler("onElementDestroy", root, function()
    if CP.reglageEnCours[source] then CP.reglageEnCours[source] = nil end
end)

addEventHandler("onElementDataChange", root, function(nom, ancien)
    if getElementType(source) == "vehicle" and (nom == "Vehicle > ID" or nom == "vehicle:id" or nom == "vehicle:dbID" or nom == "dbid") then
        verifierInstallationVehicule(source)
        chargerAcoustique(source)
    end
    -- Personne d'autre que ce fichier n'écrit les réglages acoustiques
    -- (un client qui écrirait la donnée est annulé).
    if nom == DONNEE_ACOUSTIQUE and client then
        if ancien == nil then removeElementData(source, nom) else setElementData(source, nom, ancien, true) end
    end
end)

-- Démarrage / arrêt : pas de musique fantôme sur les véhicules.
local function demarrerRessource()
    for _, v in ipairs(getElementsByType("vehicle")) do
        if getElementData(v, "carplay:etat") ~= nil then removeElementData(v, "carplay:etat") end
        verifierInstallationVehicule(v)
        chargerAcoustique(v)
    end
    pcall(function()
        exports["core_staff"]:registerResourceCommands("CarPlay", {
            {
                command = "installcarplay",
                description = "Installer le boîtier CarPlay sur le véhicule (Admin 3+ ou mécanicien)",
                level = 0,
                category = "Véhicule",
            },
            {
                command = "uninstallcarplay",
                description = "Désinstaller le boîtier CarPlay du véhicule",
                level = 3,
                category = "Staff",
            },
        })
    end)
end

local function arreterRessource()
    for _, v in ipairs(getElementsByType("vehicle")) do
        if getElementData(v, "carplay:etat") ~= nil then removeElementData(v, "carplay:etat") end
    end
    pcall(function() exports["core_staff"]:unregisterResourceCommands("CarPlay") end)
end

addEventHandler("onResourceStart", resourceRoot, demarrerRessource)
addEventHandler("onResourceStop", resourceRoot, arreterRessource)
