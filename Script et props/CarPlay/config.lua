-- ============================================================================
-- CarPlay — configuration partagée (demande 69, 20/10/2026)
-- ----------------------------------------------------------------------------
-- « carplay dans la voiture avec vrai liens youtube..etc pour jouer des
--   musics » ; ouverture par clic droit sur la voiture (menu i9_interaction,
--   comme la radio) ; tout le monde dans la voiture entend, et dehors aussi
--   (vitres ouvertes / fermées, comme la radio) ; liens YouTube + liens audio
--   directs ; file d'attente, favoris, Plans, Téléphone et Messages.
-- ============================================================================

CARPLAY_CONFIG = {
    -- Places qui peuvent toucher l'écran (conducteur + passager avant),
    -- comme la radio du véhicule.
    places = { [0] = true, [1] = true },

    -- Son : dehors, la portée diminue de 20 % si toutes les vitres sont
    -- fermées (D71). Demande 112 : étouffement voiture fermée, réglable par
    -- véhicule (panneau Staff → Qualité audio, CARPLAY_ACOUSTIQUE_DEF plus bas).
    porteeOuvert = 30,      -- dehors, une vitre ouverte
    porteeFerme = 24,       -- dehors, vitres fermées : 30 m - 20 %
    volumeFerme = 0.35,     -- volume relatif dehors, vitres fermées
    volumeDefaut = 0.5,
    pasVolume = 0.05,

    fileMax = 25,           -- morceaux dans la file d'un véhicule
    favorisMax = 60,        -- favoris par personnage
    titreMax = 120,
    lienMax = 500,

    -- Lecteurs YouTube ouverts en même temps chez un joueur (les véhicules
    -- les plus proches d'abord) : chaque lecteur est un petit navigateur CEF.
    lecteursMax = 3,

    -- Messages : réponses rapides proposées en conduisant.
    reponsesRapides = {
        "J'arrive.",
        "Je conduis, je te rappelle.",
        "D'accord.",
        "Je suis en route.",
    },
}

-- ============================================================================
-- Demande 112 (04/11/2026) — rendu audio 3D « réaliste » + panneau admin
-- « Acoustique » (clic droit sur le véhicule → Staff → Qualité audio).
-- ----------------------------------------------------------------------------
-- Chaque réglage est décrit UNE fois ici (client ET serveur) : le panneau
-- dessine ces lignes, le serveur borne chaque valeur reçue avec min / max et
-- refuse toute clé absente de la liste. Réglages PAR VÉHICULE (table SQLite
-- carplay_acoustique, donnée « carplay:acoustique »), appliqués EN DIRECT
-- pendant qu'un admin les règle (D112 quater).
--
-- Moteur audio de MTA (vérifié dans client.dll) : effets BASS « parameq »
-- (UNE seule bande), « echo », « reverb », « compressor ». Pas de vrai
-- passe-bas : l'étouffement voiture fermée = coupe large des médiums-aigus
-- (parameq) + perte de volume. YouTube (navigateur CEF) : MTA ne règle que
-- son volume, le panneau ne s'applique donc qu'aux liens audio directs.
-- ============================================================================
CARPLAY_ACOUSTIQUE_CATEGORIES = {
    { id = "general",  nom = "Général" },
    { id = "echo",     nom = "Écho" },
    { id = "effets",   nom = "Effets" },
    { id = "radio",    nom = "Radio véhicule" },
    { id = "eq",       nom = "Égaliseur" },
}

-- type : "curseur" (min, max, pas, unite) ou "case" (booléen).
CARPLAY_ACOUSTIQUE_DEF = {
    -- Général
    { cle = "volumeGeneral",   cat = "general", type = "curseur", nom = "Volume général", min = -24, max = 12, pas = 0.5, unite = "dB", defaut = 0,
      aide = "Gain appliqué partout (dedans et dehors). 0 dB = volume CarPlay." },
    { cle = "rendu3D",         cat = "general", type = "case", nom = "Rendu 3D (dehors)", defaut = true,
      aide = "Dehors, le son vient de la voiture (gauche / droite, distance)." },
    { cle = "distanceMin",     cat = "general", type = "curseur", nom = "Distance plein volume (m)", min = 1, max = 15, pas = 0.5, unite = "m", defaut = 4,
      aide = "En dessous de cette distance, le son dehors est à plein volume." },
    { cle = "volumeInterieur", cat = "general", type = "curseur", nom = "Volume habitacle", min = -24, max = 12, pas = 0.5, unite = "dB", defaut = 0,
      aide = "Gain pour les occupants du véhicule." },

    -- Écho
    { cle = "reflexions",      cat = "echo", type = "case", nom = "Réflexions de la radio", defaut = true,
      aide = "Dehors, le son rebondit sur le sol et les murs proches (écho court)." },
    { cle = "forceReflexions", cat = "echo", type = "curseur", nom = "Force des réflexions", min = 0, max = 60, pas = 1, unite = "%", defaut = 14 },
    { cle = "delaiReflexions", cat = "echo", type = "curseur", nom = "Délai des réflexions (ms)", min = 5, max = 120, pas = 1, unite = "ms", defaut = 32 },
    { cle = "retourReflexions", cat = "echo", type = "curseur", nom = "Retour des réflexions", min = 0, max = 60, pas = 1, unite = "%", defaut = 12 },
    { cle = "reverbHabitacle", cat = "echo", type = "curseur", nom = "Réverbération habitacle", min = 0, max = 50, pas = 1, unite = "%", defaut = 8,
      aide = "Petite pièce : réverbération courte entendue dans la voiture." },
    { cle = "reverbExterieur", cat = "echo", type = "curseur", nom = "Réverbération extérieure", min = 0, max = 50, pas = 1, unite = "%", defaut = 6 },

    -- Effets
    { cle = "compresseur",     cat = "effets", type = "case", nom = "Compresseur", defaut = false,
      aide = "Resserre la dynamique (son « autoradio » plus égal)." },
    { cle = "seuilCompresseur", cat = "effets", type = "curseur", nom = "Seuil du compresseur", min = -40, max = 0, pas = 1, unite = "dB", defaut = -18 },
    { cle = "ratioCompresseur", cat = "effets", type = "curseur", nom = "Taux du compresseur", min = 1, max = 20, pas = 0.5, unite = ":1", defaut = 3 },

    -- Radio véhicule (onglet « Car radio » de la vidéo)
    { cle = "volumeExterieur", cat = "radio", type = "curseur", nom = "Volume dehors", min = -24, max = 24, pas = 0.5, unite = "dB", defaut = 0,
      aide = "Gain du son entendu hors du véhicule. 0 dB = niveau de base." },
    { cle = "distanceEcoute",  cat = "radio", type = "curseur", nom = "Distance d'écoute (m)", min = 5, max = 120, pas = 1, unite = "m", defaut = 30 },
    { cle = "perteFerme",      cat = "radio", type = "curseur", nom = "Perte voiture fermée", min = 0, max = 30, pas = 0.5, unite = "dB", defaut = 3, perte = true,
      aide = "Volume perdu en plus quand portes et vitres sont fermées (graves compris)." },
    { cle = "bassesFerme",     cat = "radio", type = "curseur", nom = "Étouffement / basses", min = 0, max = 15, pas = 0.5, unite = "dB", defaut = 10,
      aide = "Voiture fermée : les graves passent, tout le reste baisse de cette valeur. Trop haut = basses qui saturent." },
    { cle = "clarteFerme",     cat = "radio", type = "curseur", nom = "Clarté voiture fermée (Hz)", min = 150, max = 4000, pas = 10, unite = "Hz", defaut = 400, log = true,
      aide = "Plus bas = plus étouffé quand tout est fermé." },
    { cle = "clarteOuvert",    cat = "radio", type = "curseur", nom = "Clarté voiture ouverte (Hz)", min = 2000, max = 18000, pas = 100, unite = "Hz", defaut = 18000, log = true },
    { cle = "portesDirectionnelles", cat = "radio", type = "case", nom = "Portes directionnelles", defaut = true,
      aide = "Une porte ou vitre ouverte de TON côté laisse passer plus de son." },
    { cle = "equilibrageRadios", cat = "radio", type = "case", nom = "Équilibrer les radios proches", defaut = true,
      aide = "Plusieurs voitures proches ne s'additionnent pas en un vacarme." },
    { cle = "fonduArrivee",    cat = "radio", type = "curseur", nom = "Fondu d'arrivée (ms)", min = 0, max = 2000, pas = 10, unite = "ms", defaut = 180 },
    { cle = "transitionHabitacle", cat = "radio", type = "curseur", nom = "Passage dedans / dehors (ms)", min = 0, max = 1000, pas = 10, unite = "ms", defaut = 400,
      aide = "Temps pour passer du son de l'habitacle au son de dehors (sans coupure)." },

    -- Égaliseur (UNE bande paramétrique : limite de MTA)
    { cle = "eqActif",         cat = "eq", type = "case", nom = "Activer l'égaliseur", defaut = false,
      aide = "Un renfort de graves s'entend partout (il s'ajoute à l'étouffé). Médiums / aigus : dedans et voiture ouverte." },
    { cle = "eqPrioritaire",   cat = "eq", type = "case", nom = "Égaliseur aussi dehors (fermé)", defaut = false,
      aide = "Pour une bande de médiums / aigus : elle s'applique aussi dehors voiture fermée, l'étouffé ne garde que la perte de volume." },
    { cle = "eqGain",          cat = "eq", type = "curseur", nom = "Gain de la bande", min = -15, max = 15, pas = 0.5, unite = "dB", defaut = 0 },
    { cle = "eqFrequence",     cat = "eq", type = "curseur", nom = "Fréquence de la bande", min = 80, max = 16000, pas = 10, unite = "Hz", defaut = 80, log = true,
      aide = "80 Hz = le plus bas permis par MTA ; avec une bande large, elle descend jusqu'aux sub-basses." },
    { cle = "eqLargeur",       cat = "eq", type = "curseur", nom = "Largeur de la bande", min = 1, max = 36, pas = 1, unite = "demi-tons", defaut = 30,
      aide = "12 demi-tons = 1 octave. Pour des basses qui « tapent », 24 à 36." },
}

CARPLAY_ACOUSTIQUE_INDEX = {}
for _, d in ipairs(CARPLAY_ACOUSTIQUE_DEF) do CARPLAY_ACOUSTIQUE_INDEX[d.cle] = d end

-- Ramène une valeur dans sa plage (ou nil si la clé / le type est invalide).
function carplayAcoustiqueBorner(cle, valeur)
    local d = CARPLAY_ACOUSTIQUE_INDEX[cle]
    if not d then return nil end
    if d.type == "case" then
        if type(valeur) ~= "boolean" then return nil end
        return valeur
    end
    valeur = tonumber(valeur)
    if not valeur or valeur ~= valeur or valeur == math.huge or valeur == -math.huge then return nil end
    valeur = math.max(d.min, math.min(d.max, valeur))
    local pas = d.pas or 1
    return math.floor(valeur / pas + 0.5) * pas
end

-- Réglages complets : défauts + valeurs enregistrées. ⚠ tester ~= nil :
-- `t and t[k]` vaut false sans table et ferait tomber les cases cochées.
function carplayAcoustiqueComplet(partiel)
    local out = {}
    for _, d in ipairs(CARPLAY_ACOUSTIQUE_DEF) do
        local v = nil
        if type(partiel) == "table" and partiel[d.cle] ~= nil then v = carplayAcoustiqueBorner(d.cle, partiel[d.cle]) end
        if v == nil then v = d.defaut end
        out[d.cle] = v
    end
    return out
end

-- Ne garde que ce qui diffère des défauts (donnée d'élément compacte).
function carplayAcoustiqueEcarts(complet)
    local out, n = {}, 0
    for _, d in ipairs(CARPLAY_ACOUSTIQUE_DEF) do
        local v = nil
        if type(complet) == "table" then v = carplayAcoustiqueBorner(d.cle, complet[d.cle]) end
        if v ~= nil and v ~= d.defaut then out[d.cle] = v; n = n + 1 end
    end
    return out, n
end

-- Réglages par défaut (véhicule sans réglage enregistré).
CARPLAY_ACOUSTIQUE_REGLAGES = carplayAcoustiqueComplet(nil)