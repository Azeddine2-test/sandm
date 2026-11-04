-- ============================================================================
-- CarPlay — moteur audio client (demande 69, 20/10/2026 ; rendu réaliste
-- demande 112, 04/11/2026)
-- ----------------------------------------------------------------------------
-- Pour CHAQUE joueur, tous les quarts de seconde :
--   * on regarde les véhicules proches (diffusés) qui jouent de la musique
--     CarPlay (donnée d'élément « carplay:etat », posée par le serveur) ;
--   * dedans : son plein (stéréo) ; dehors : son 3D attaché au véhicule ;
--   * YouTube : un petit navigateur CEF (non affiché, sauf comme pochette sur
--     l'écran CarPlay) charge le lecteur intégré au bon moment du morceau
--     (paramètre start) ; lien audio direct : playSound / playSound3D ;
--   * l'horloge serveur (« carplay:horloge ») garde tout le monde synchronisé.
--
-- Demande 112 — rendu « réaliste », réglable PAR VÉHICULE et EN DIRECT
-- (panneau Staff → Qualité audio, CARPLAY_ACOUSTIQUE_DEF dans config.lua) ;
-- D112 quater : un seul flux dedans / dehors, plus de coupure en descendant :
--   * ouverture du véhicule = portes (getVehicleDoorOpenRatio, portes
--     arrachées), vitres (par place), coffre ; « portes directionnelles » :
--     une ouverture du côté de l'écouteur (la caméra) compte plus ;
--   * voiture fermée vue de dehors : perte de volume (dB) + étouffement des
--     médiums-aigus (effet BASS « parameq », MTA n'a pas de passe-bas) ;
--   * réflexions (« echo »), réverbération habitacle / extérieur (« reverb »),
--     compresseur, égaliseur une bande ;
--   * fondu d'arrivée, passage dedans / dehors sans recréer le flux, volumes
--     lissés à chaque image (une porte qui s'ouvre se ENTEND s'ouvrir) ;
--   * plusieurs radios proches : équilibrage 1/√n.
-- YouTube (CEF) : MTA n'autorise aucun effet sur un navigateur, seulement
-- setBrowserVolume. Il suit donc les mêmes pertes de volume, sans timbre.
-- ============================================================================

local C = CARPLAY_CONFIG
local LI = CARPLAY_LIENS
if type(CARPLAY_AUDIO) ~= "table" then CARPLAY_AUDIO = {} end
local A = CARPLAY_AUDIO

A.ecart = 0             -- horloge serveur - horloge locale (ms)
A.lecteurs = {}         -- [véhicule] = { navigateur, cle, id, pret }
A.sons = {}             -- [véhicule] = { son, cle, mode, gain, gainCible, ... }
A.sortants = {}         -- sons qui s'éteignent en fondu (passage dedans/dehors)
A.navigateurRefuse = false

-- ---------------------------------------------------------------------------
-- Horloge
-- ---------------------------------------------------------------------------
function A.maintenantServeur() return getTickCount() + A.ecart end

function A.ecoule(e)
    if type(e) ~= "table" then return 0 end
    if e.lecture then return math.max(0, (A.maintenantServeur() - (tonumber(e.debut) or 0)) / 1000) end
    return tonumber(e.position) or 0
end

addEvent("carplay:horloge", true)
addEventHandler("carplay:horloge", resourceRoot, function(tickEnvoi, tickServeur)
    local maintenant = getTickCount()
    local aller = (maintenant - (tonumber(tickEnvoi) or maintenant)) / 2
    A.ecart = (tonumber(tickServeur) or maintenant) + aller - maintenant
end)

local function demanderHorloge() triggerServerEvent("carplay:horloge", resourceRoot, getTickCount()) end

-- ---------------------------------------------------------------------------
-- Réglages acoustiques
-- ---------------------------------------------------------------------------
local function lin(db) return 10 ^ ((tonumber(db) or 0) / 20) end
local function borne(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- Réglages d'un véhicule : l'aperçu de l'admin qui règle (instantané chez
-- lui), sinon la donnée synchronisée (appliquée en direct chez tous), sinon
-- les défauts. La donnée est relue tous les quarts de seconde.
A.apercu = {}
function A.reglages(v)
    if A.apercu[v] then return A.apercu[v] end
    local d = isElement(v) and getElementData(v, "carplay:acoustique")
    if type(d) ~= "table" then return CARPLAY_ACOUSTIQUE_REGLAGES end
    return carplayAcoustiqueComplet(d)
end

-- ---------------------------------------------------------------------------
-- Ouverture du véhicule (0 = tout fermé, 1 = grand ouvert)
-- ---------------------------------------------------------------------------
local TYPES_OUVERTS = { Bike = true, BMX = true, Quad = true, Boat = true }
-- place → porte MTA, vitre MTA, côté (x : -1 gauche / 1 droite)
local OUVERTURES = {
    { place = 0, porte = 2, vitre = 4, x = -1 },
    { place = 1, porte = 3, vitre = 2, x = 1 },
    { place = 2, porte = 4, vitre = 5, x = -1 },
    { place = 3, porte = 5, vitre = 3, x = 1 },
}
A.OUVERTURES = OUVERTURES

local function porteOuverte(v, porte)
    local o = 0
    if getVehicleDoorOpenRatio then
        local ok, r = pcall(getVehicleDoorOpenRatio, v, porte)
        if ok and tonumber(r) then o = tonumber(r) end
    end
    if getVehicleDoorState then
        local ok, etat = pcall(getVehicleDoorState, v, porte)
        if ok and etat == 4 then o = 1 end -- porte arrachée
    end
    return o
end

local function vitreOuverteA(v, ouv)
    if getElementData(v, "vehicle:windows:anyOpen") == true then return true end
    if getElementData(v, "vehicle:window:" .. ouv.place) == true then return true end
    if isVehicleWindowOpen then
        local ok, ouverte = pcall(isVehicleWindowOpen, v, ouv.vitre)
        if ok and ouverte == true then return true end
    end
    return false
end

-- Une vitre ouverte au moins (règle de portée D71, inchangée).
local function vitreOuverte(v)
    for _, ouv in ipairs(OUVERTURES) do
        if vitreOuverteA(v, ouv) then return true end
    end
    return false
end
A.vitreOuverte = vitreOuverte

-- Position de l'écouteur (la caméra : c'est elle qui « entend » dans GTA)
-- dans le repère du véhicule : x > 0 = à droite du véhicule.
local function ecouteurLocal(v)
    local cx, cy, cz = getCameraMatrix()
    local m = getElementMatrix(v)
    if not cx or type(m) ~= "table" then return 0, 0 end
    local dx, dy, dz = cx - m[4][1], cy - m[4][2], cz - m[4][3]
    return dx * m[1][1] + dy * m[1][2] + dz * m[1][3], dx * m[2][1] + dy * m[2][2] + dz * m[2][3]
end

function A.ouverture(v, r)
    if not isElement(v) then return 1 end
    if TYPES_OUVERTS[getVehicleType(v)] then return 1 end
    local lx = ecouteurLocal(v)
    local meilleur = 0
    for _, ouv in ipairs(OUVERTURES) do
        local o = porteOuverte(v, ouv.porte)
        if vitreOuverteA(v, ouv) then o = math.max(o, 0.7) end
        if o > 0 then
            local poids = 1
            if r.portesDirectionnelles and math.abs(lx) > 0.4 then
                poids = (lx * ouv.x > 0) and 1 or 0.35
            end
            meilleur = math.max(meilleur, o * poids)
        end
    end
    -- coffre / capot ouverts : le son passe, moins qu'une porte
    meilleur = math.max(meilleur, porteOuverte(v, 1) * 0.6, porteOuverte(v, 0) * 0.3)
    return borne(meilleur, 0, 1)
end

-- Clarté (Hz) : interpolation logarithmique fermé → ouvert.
function A.clarte(r, o)
    local f, ou = math.log(r.clarteFerme), math.log(r.clarteOuvert)
    return math.exp(f + (ou - f) * (o ^ 0.7))
end

-- ---------------------------------------------------------------------------
-- Portée : dedans / dehors (signature historique : mode, volume, distance,
-- portée — volume = volume CarPlay × atténuation linéaire, utilisé par CEF)
-- ---------------------------------------------------------------------------
function A.ecoute(v, e)
    if not isElement(v) or type(e) ~= "table" or not e.lecture or type(e.piste) ~= "table" then return nil end
    local vol = math.max(0, math.min(1, tonumber(e.volume) or C.volumeDefaut))
    if getPedOccupiedVehicle(localPlayer) == v then return "dedans", vol, 0 end
    if getElementDimension(v) ~= getElementDimension(localPlayer) or getElementInterior(v) ~= getElementInterior(localPlayer) then return nil end
    local r = A.reglages(v)
    local portee = A.portee(v, r)
    local facteur = vitreOuverte(v) and 1 or C.volumeFerme
    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(v)
    local d = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
    if d > portee then return nil end
    return "dehors", vol * facteur * A.attenuation(r, d, portee), d, portee
end

-- Portée dehors. D71 : vitres fermées = portée −20 %.
function A.portee(v, r)
    if vitreOuverte(v) then return r.distanceEcoute end
    return r.distanceEcoute * (C.porteeFerme / C.porteeOuvert)
end

-- Atténuation linéaire avec la distance (plein volume sous distanceMin).
function A.attenuation(r, d, portee)
    local dmin = r.distanceMin
    if d <= dmin then return 1 end
    return math.max(0, 1 - (d - dmin) / math.max(1, portee - dmin))
end

-- Gain (linéaire, hors volume CarPlay) et timbre du rendu « réaliste ».
-- Renvoie : gain, ouverture, clarté (Hz).
function A.rendu(v, mode, r)
    if mode == "dedans" then return lin(r.volumeGeneral + r.volumeInterieur), 1, r.clarteOuvert end
    local o = A.ouverture(v, r)
    local perte = r.perteFerme * (1 - o)
    return lin(r.volumeGeneral + r.volumeExterieur - perte), o, A.clarte(r, o)
end

-- ---------------------------------------------------------------------------
-- Effets BASS (appliqués seulement s'ils changent)
-- ---------------------------------------------------------------------------
local function fixerEffet(s, nom, actif, params)
    if not setSoundEffectEnabled or not isElement(s.son) then return end
    s.fx = s.fx or {}
    local f = s.fx[nom]
    if not f then f = { actif = nil, p = {} } s.fx[nom] = f end
    if f.actif ~= actif then
        pcall(setSoundEffectEnabled, s.son, nom, actif)
        f.actif = actif
        f.p = {}
    end
    if not actif or not params or not setSoundEffectParameter then return end
    for cle, val in pairs(params) do
        local avant = f.p[cle]
        if type(val) == "boolean" then
            if avant ~= val then pcall(setSoundEffectParameter, s.son, nom, cle, val) f.p[cle] = val end
        elseif avant == nil or math.abs(avant - val) > math.max(0.01, math.abs(val) * 0.03) then
            pcall(setSoundEffectParameter, s.son, nom, cle, val)
            f.p[cle] = val
        end
    end
end

-- « Dehors » de 0 (dedans) à 1 (dehors) : accepte aussi "dedans" / "dehors".
local function dehorsDe(m)
    if m == "dehors" then return 1 elseif m == "dedans" then return 0 end
    return borne(tonumber(m) or 0, 0, 1)
end

-- Force de l'étouffement (dB) pour une clarté donnée : 0 grand ouvert,
-- bassesFerme quand tout est fermé (clarté 400 Hz).
function A.forceEtouffement(r, clarte)
    if clarte >= 15000 then return 0 end
    return r.bassesFerme * borne(math.log(16000 / clarte) / math.log(2) / 5.3, 0, 1)
end

-- Choix de l'unique bande paramétrique de MTA.
-- D112 quinquies : l'étouffement n'est plus une coupe des médiums (les aigus
-- passaient : cymbales audibles voiture fermée, surtout le son fort). La bande
-- MONTE les graves (jusqu'à la clarté) de G dB et le volume baisse de G dB
-- (compensation renvoyée en 3e valeur) : tout ce qui est au-dessus de la
-- clarté baisse de G dB, les basses restent — un vrai effet « passe-bas »,
-- avec les basses qui sortent de la caisse.
-- Renvoie : bande (ou nil), rôle, compensation (dB à retirer du volume).
function A.bandeParametrique(r, mode, clarte)
    local m = dehorsDe(mode)
    local g = A.forceEtouffement(r, clarte) * m
    local eq = r.eqActif and r.eqGain ~= 0
    -- D112 sexies : un renfort de GRAVES de l'égaliseur (sous la clarté)
    -- s'ajoute à l'étouffé dans la même bande au lieu d'être ignoré : la
    -- bande monte de g + renfort, le volume ne baisse que de g.
    local renfortGraves = eq and r.eqGain > 0 and r.eqFrequence <= math.max(200, clarte)
    if g > 0.3 and renfortGraves then
        local centre = borne(math.min(clarte / 2.83, r.eqFrequence), 80, 16000)
        return { center = centre, bandwidth = math.max(30, r.eqLargeur), gain = borne(g + r.eqGain, 0, 15) }, "etouffement+egaliseur", borne(g, 0, 15)
    end
    if g > 0.3 and not (eq and r.eqPrioritaire) then
        return { center = borne(clarte / 2.83, 80, 16000), bandwidth = 36, gain = borne(g, 0, 15) }, "etouffement", borne(g, 0, 15)
    end
    if eq then
        return { center = r.eqFrequence, bandwidth = r.eqLargeur, gain = r.eqGain }, "egaliseur", 0
    end
    return nil, nil, 0
end

-- mode : "dedans", "dehors" ou un mélange 0..1 (passage progressif).
function A.appliquerEffets(s, r, mode, clarte)
    local m = dehorsDe(mode)
    local bande = A.bandeParametrique(r, m, clarte)
    fixerEffet(s, "parameq", bande ~= nil, bande)
    local wet = r.reflexions and r.forceReflexions * m or 0
    fixerEffet(s, "echo", wet >= 1, wet >= 1 and {
        wetDryMix = wet, feedback = r.retourReflexions,
        leftDelay = r.delaiReflexions, rightDelay = math.floor(r.delaiReflexions * 1.37 + 0.5),
    } or nil)
    local pct = r.reverbHabitacle + (r.reverbExterieur - r.reverbHabitacle) * m
    -- voiture fermée vue de dehors : réverbération plus sourde
    local sourd = r.bassesFerme > 0 and borne(A.forceEtouffement(r, clarte) / 15, 0, 1) * m or 0
    fixerEffet(s, "reverb", pct >= 1, pct >= 1 and {
        reverbMix = 20 * math.log10(pct / 100),
        reverbTime = 350 + (1100 - 350) * m,
        highFreqRTRatio = borne(0.3 + 0.2 * m - 0.35 * sourd, 0.05, 0.9),
    } or nil)
    fixerEffet(s, "compressor", r.compresseur, r.compresseur and {
        threshold = r.seuilCompresseur, ratio = r.ratioCompresseur, attack = 10, release = 200,
    } or nil)
end

-- ---------------------------------------------------------------------------
-- YouTube (navigateur CEF) — volume seulement (limite de MTA)
-- ---------------------------------------------------------------------------
function A.arreterLecteur(v)
    local l = A.lecteurs[v]
    if l and isElement(l.navigateur) then destroyElement(l.navigateur) end
    A.lecteurs[v] = nil
end

local function assurerLecteur(v, e, volume)
    local cle = tostring(e.piste.id) .. ":" .. tostring(e.debut)
    local l = A.lecteurs[v]
    if l and l.cle == cle and isElement(l.navigateur) then
        l.gainCible = volume
        return
    end
    A.arreterLecteur(v)
    if not createBrowser then A.navigateurRefuse = true return end
    local nav = createBrowser(426, 240, false, false)
    if not nav then A.navigateurRefuse = true return end
    A.navigateurRefuse = false
    l = { navigateur = nav, cle = cle, id = e.piste.ref, pret = false, vehicule = v, gain = 0, gainCible = volume }
    A.lecteurs[v] = l
    setBrowserVolume(nav, 0)
    addEventHandler("onClientBrowserCreated", nav, function()
        if A.lecteurs[v] ~= l then return end
        -- on relit l'état au moment du chargement : le navigateur met un
        -- instant à se créer, le morceau a avancé entre-temps.
        local ee = getElementData(v, "carplay:etat")
        local debut = (type(ee) == "table" and ee.piste and ee.piste.id == e.piste.id) and A.ecoule(ee) or A.ecoule(e)
        loadBrowserURL(source, LI.urlLecteur(l.id, debut))
        l.pret = true
    end, false)
end

-- ---------------------------------------------------------------------------
-- Lien audio direct (BASS) — rendu complet
-- ---------------------------------------------------------------------------
function A.arreterSon(v)
    local s = A.sons[v]
    if s and isElement(s.son) then stopSound(s.son) end
    A.sons[v] = nil
end

-- Le son actuel s'éteint en fondu au lieu d'être coupé net.
local function fondreSortant(s, ms)
    if not s or not isElement(s.son) then return end
    if (ms or 0) <= 0 then stopSound(s.son) return end
    s.sortie = { debut = getTickCount(), duree = ms, gain = s.gain or 0 }
    A.sortants[#A.sortants + 1] = s
end

-- D112 quater : UN seul flux du début à la fin du morceau, dedans comme
-- dehors. Avant, descendre de la voiture créait un nouveau flux (stéréo
-- dedans → 3D dehors) qui devait se recharger : la musique se coupait puis
-- recommençait. Maintenant on ne change que ses réglages :
--   * dedans : panoramique coupé (stéréo pleine), distance sans effet ;
--   * dehors : panoramique 3D, plein volume sous distanceMin, portée ;
-- et le volume glisse de l'un à l'autre (transitionHabitacle).
local MIN_DEDANS = 15   -- m : la caméra reste « dans » le son quand on conduit

local function creerSon(v, e, r)
    local son
    if not r.rendu3D then
        son = playSound(e.piste.ref, false)
    else
        local x, y, z = getElementPosition(v)
        son = playSound3D(e.piste.ref, x, y, z, false)
        if son then
            attachElements(son, v)
            setElementDimension(son, getElementDimension(v))
            setElementInterior(son, getElementInterior(v))
        end
    end
    return son
end

-- D112 quinquies : passage dedans / dehors PROGRESSIF. s.m va de 0 (dedans)
-- à 1 (dehors) sur transitionHabitacle ; volume, distance, étouffement,
-- écho et réverbération suivent s.m au lieu de basculer d'un coup.
local function placerSon(s)
    if not s.en3D then return end
    local r, m = s.reglages, s.m
    local pano = m > 0.5
    if s.panoramique ~= pano and setSoundPanningEnabled then
        pcall(setSoundPanningEnabled, s.son, pano)
        s.panoramique = pano
    end
    local portee = s.portee or C.porteeOuvert
    local dmin = MIN_DEDANS + (r.distanceMin - MIN_DEDANS) * m
    local dmax = math.max(MIN_DEDANS * 2, portee) + (portee - math.max(MIN_DEDANS * 2, portee)) * m
    if not s.dmax or math.abs(s.dmax - dmax) > 0.05 then setSoundMaxDistance(s.son, dmax) s.dmax = dmax end
    if setSoundMinDistance and (not s.dmin or math.abs(s.dmin - dmin) > 0.05) then setSoundMinDistance(s.son, dmin) s.dmin = dmin end
end

-- Volume visé pour le mélange actuel, compensation de l'étouffement comprise.
local function gainMelange(s)
    local m = s.m
    local _, _, compensation = A.bandeParametrique(s.reglages, m, s.clarte)
    return (s.gainDedans * (1 - m) + s.gainDehors * m) * lin(-compensation)
end

local function appliquerMelange(s)
    placerSon(s)
    A.appliquerEffets(s, s.reglages, s.m, s.clarte)
end

-- gainDedans / gainDehors : volume CarPlay × rendu pour chaque côté (dehors :
-- sans la distance en 3D, BASS l'applique entre distanceMin et la portée).
local function assurerSon(v, e, mode, r, gainDedans, gainDehors, clarte, portee)
    local cle = tostring(e.piste.id) .. ":" .. tostring(e.debut) .. ":" .. tostring(r.rendu3D)
    local cible = mode == "dehors" and 1 or 0
    local s = A.sons[v]
    if not (s and s.cle == cle and isElement(s.son)) then
        if s then
            A.sons[v] = nil
            fondreSortant(s, 0)
        end
        local son = creerSon(v, e, r)
        if not son then return end
        setSoundVolume(son, 0)
        s = { son = son, cle = cle, vehicule = v, piste = e.piste.id, debut = e.debut,
              gain = 0, fx = {}, nait = getTickCount(), fondu = r.fonduArrivee, en3D = r.rendu3D, m = cible }
        A.sons[v] = s
    end
    -- monter / descendre : même flux, s.m glisse vers la cible (A.lisser)
    s.mode, s.mCible = mode, cible
    s.reglages, s.clarte, s.portee = r, clarte, portee
    s.gainDedans, s.gainDehors = gainDedans, gainDehors
    s.gainCible = gainMelange(s)
    appliquerMelange(s)
end

-- Flux prêt : on se cale au bon endroit, on réapplique les effets (BASS
-- crée le canal à ce moment), et un occupant donne la durée au serveur.
addEventHandler("onClientSoundStream", root, function(ok, longueur)
    for v, s in pairs(A.sons) do
        if s.son == source then
            if not ok then return end
            s.fx = {}
            if s.reglages then A.appliquerEffets(s, s.reglages, s.m or s.mode, s.clarte or 18000) end
            local e = getElementData(v, "carplay:etat")
            if type(e) ~= "table" or not e.piste or e.piste.id ~= s.piste then return end
            longueur = tonumber(longueur) or 0
            if longueur > 0 then
                local pos = A.ecoule(e)
                if pos > 1 and pos < longueur then setSoundPosition(source, pos) end
                if not e.piste.duree and getPedOccupiedVehicle(localPlayer) == v then
                    triggerServerEvent("carplay:duree", resourceRoot, v, e.piste.id, longueur)
                end
            end
            return
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Lissage des volumes à chaque image (fondus, portes qui s'ouvrent)
-- ---------------------------------------------------------------------------
local LISSAGE_MS = 120
local dernierTick = getTickCount()

function A.lisser()
    local t = getTickCount()
    local dt = math.max(1, math.min(200, t - dernierTick))
    dernierTick = t
    local k = 1 - math.exp(-dt / LISSAGE_MS)
    for _, s in pairs(A.sons) do
        if isElement(s.son) and s.gainCible then
            -- passage dedans / dehors progressif (volume, distance et effets)
            if s.mCible and s.m ~= s.mCible then
                local pas = dt / math.max(1, s.reglages.transitionHabitacle)
                if s.m < s.mCible then s.m = math.min(s.mCible, s.m + pas) else s.m = math.max(s.mCible, s.m - pas) end
                appliquerMelange(s)
                s.gainCible = gainMelange(s)
            end
            local cible = s.gainCible
            local fondu = s.fondu or 0
            if fondu > 0 and t - s.nait < fondu then cible = cible * ((t - s.nait) / fondu) end
            s.gain = (s.gain or 0) + (cible - (s.gain or 0)) * k
            setSoundVolume(s.son, math.max(0, s.gain))
        end
    end
    for _, l in pairs(A.lecteurs) do
        if isElement(l.navigateur) and l.gainCible then
            l.gain = (l.gain or 0) + (l.gainCible - (l.gain or 0)) * k
            setBrowserVolume(l.navigateur, math.max(0, math.min(1, l.gain)))
        end
    end
    for i = #A.sortants, 1, -1 do
        local s = A.sortants[i]
        local avance = (t - s.sortie.debut) / math.max(1, s.sortie.duree)
        if not isElement(s.son) or avance >= 1 then
            if isElement(s.son) then stopSound(s.son) end
            table.remove(A.sortants, i)
        else
            setSoundVolume(s.son, s.sortie.gain * (1 - avance))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Boucle
-- ---------------------------------------------------------------------------
function A.mettreAJour()
    local candidats = {}
    local dehors = 0
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local e = getElementData(v, "carplay:etat")
        if type(e) == "table" then
            local mode, volume, d, portee = A.ecoute(v, e)
            if mode then
                candidats[#candidats + 1] = { v = v, e = e, mode = mode, volume = volume, d = d, portee = portee }
                if mode == "dehors" then dehors = dehors + 1 end
            end
        end
    end
    table.sort(candidats, function(a, b) return a.d < b.d end)
    local gardes, yt = {}, 0
    for _, c in ipairs(candidats) do
        local r = A.reglages(c.v)
        local gain, _, clarte = A.rendu(c.v, c.mode, r)
        if c.mode == "dehors" and r.equilibrageRadios and dehors > 1 then gain = gain / math.sqrt(dehors) end
        local base = math.max(0, math.min(1, tonumber(c.e.volume) or C.volumeDefaut))
        local att = c.mode == "dehors" and A.attenuation(r, c.d, c.portee) or 1
        if c.e.piste.type == "youtube" then
            if yt < C.lecteursMax then
                yt = yt + 1
                gardes[c.v] = "yt"
                -- CEF : pas de timbre possible, la perte voiture fermée est
                -- renforcée de 4 dB pour suggérer l'étouffement.
                local etouffe = c.mode == "dehors" and lin(-4 * (1 - A.ouverture(c.v, r))) or 1
                assurerLecteur(c.v, c.e, math.min(1, base * gain * att * etouffe))
            end
        elseif c.e.piste.type == "audio" then
            gardes[c.v] = "son"
            -- les deux côtés sont calculés : le passage dedans / dehors glisse
            -- de l'un à l'autre sans à-coup
            local gainDedans = base * lin(r.volumeGeneral + r.volumeInterieur)
            local gainDehors, clarteDehors = gain, clarte
            if c.mode == "dedans" then
                gainDehors, _, clarteDehors = A.rendu(c.v, "dehors", r)
            end
            gainDehors = base * gainDehors * (r.rendu3D and 1 or att)
            assurerSon(c.v, c.e, c.mode, r, gainDedans, gainDehors, clarteDehors, c.portee or A.portee(c.v, r))
        end
    end
    for v in pairs(A.lecteurs) do if gardes[v] ~= "yt" then A.arreterLecteur(v) end end
    for v, s in pairs(A.sons) do
        if gardes[v] ~= "son" then
            A.sons[v] = nil
            fondreSortant(s, 250)
        end
    end
end

-- Navigateur du véhicule (pour afficher la vidéo en pochette sur l'écran).
function A.navigateurDe(v)
    local l = A.lecteurs[v]
    return l and l.pret and isElement(l.navigateur) and l.navigateur or nil
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    demanderHorloge()
    setTimer(demanderHorloge, 60000, 0)
    setTimer(A.mettreAJour, 250, 0)
    addEventHandler("onClientPreRender", root, A.lisser)
end)

addEventHandler("onClientElementDestroy", root, function()
    if A.lecteurs[source] then A.arreterLecteur(source) end
    if A.sons[source] then A.arreterSon(source) end
    A.apercu[source] = nil
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for v in pairs(A.lecteurs) do A.arreterLecteur(v) end
    for v in pairs(A.sons) do A.arreterSon(v) end
    for _, s in ipairs(A.sortants) do if isElement(s.son) then stopSound(s.son) end end
    A.sortants = {}
end)
