-- ============================================================
-- config.lua - Configuration du Admin Magasin
-- Version optimisée : cooldown random NPC + profils NPC
-- ============================================================

AMConfig = {}

-- ═══════════════════════════════════════════════════════════════
-- SÉCURITÉ / PERMISSIONS
-- ═══════════════════════════════════════════════════════════════

AMConfig.security = {
    minRank = "superadmin",               -- "admin" ou "superadmin"
    staffSystemResource = "staff_system", -- Nom de la ressource staff
    fallbackToACL = true,                  -- Si staff_system indisponible, utiliser ACL MTA
    aclGroups = {"Admin", "SuperAdmin"}, -- Groupes ACL autorisés en fallback
}

-- ═══════════════════════════════════════════════════════════════
-- BASE DE DONNÉES
-- ═══════════════════════════════════════════════════════════════

AMConfig.database = {
    file = "stores.db", -- Fichier SQLite dans le dossier de la ressource
    autoBackup = true,
}

-- ═══════════════════════════════════════════════════════════════
-- INTÉGRATION AVEC SYSTEMTRABAJOS
-- ═══════════════════════════════════════════════════════════════

AMConfig.integration = {
    targetResource = "SystemTrabajos",
    autoSync = true,
    syncInterval = 30000,
}

-- Option B : pas de magasins hardcodés
AMConfig.hardcodedStores = {}

-- ═══════════════════════════════════════════════════════════════
-- NPC EMPLOYEUR
-- ═══════════════════════════════════════════════════════════════

AMConfig.employer = {
    skin = 187,
    name = "Employeur de Supermarche",
    frozen = true,
    defaultPos = {x = 2417.16, y = -1741.581, z = 13.375, rot = 260.78},
}

-- ═══════════════════════════════════════════════════════════════
-- VALEURS PAR DÉFAUT POUR UN NOUVEAU MAGASIN
-- ═══════════════════════════════════════════════════════════════

AMConfig.defaults = {
    -- Optimisation : le système final utilise 1 seul NPC actif à la fois.
    -- On garde maxNPC par compatibilité, mais il n'est plus utilisé pour multi-NPC.
    maxNPC = 1,

    salary = {min = 10, max = 30},

    -- Cooldown random par défaut, sauvegardé par magasin.
    firstNpcCooldownMin = 30000,   -- 30s avant le premier client
    firstNpcCooldownMax = 120000,  -- 120s avant le premier client
    nextNpcCooldownMin = 60000,    -- 60s entre deux clients après le premier
    nextNpcCooldownMax = 300000,   -- 300s entre deux clients après le premier

    -- Profils NPC par défaut : vide = comportement automatique.
    -- Si vide : skin aléatoire + produits aléatoires parmi tous les produits positionnés.
    npcProfiles = {},

    products = {
        {model = 1544, name = "Biere Corona", scale = 1.0},
        {model = 1487, name = "Cheetos", scale = 1.0},
        {model = 1520, name = "Doritos", scale = 1.0},
        {model = 1545, name = "Starbucks", scale = 1.0},
        {model = 1517, name = "Vodka", scale = 1.0},
        {model = 1580, name = "Sprite", scale = 0.4},
    },
}

-- ═══════════════════════════════════════════════════════════════
-- SYSTÈME NPC CLIENTS
-- ═══════════════════════════════════════════════════════════════

AMConfig.npc = {
    randomSkins = {10, 11, 12, 14, 15, 16, 17, 26, 27, 28, 29},

    basketModel = 2905,
    basketModelFallback = 2905,

    basketFiles = {
        txd = "assets/models/shopbasket1.txd",
        col = "assets/models/shopbasket1.col",
        dff = "assets/models/shopbasket1.dff",
    },

    -- Ces valeurs restent pour compatibilité ancienne.
    -- Les nouveaux cooldowns par magasin sont dans AMConfig.defaults et dans stores.db.
    firstSpawnDelay = 30000,
    respawnInterval = 60000,

    maxDistanceFromStore = 15.0,
    pauseDuration = 2000,

    minPayment = 10,
    maxPayment = 30,
}

-- ═══════════════════════════════════════════════════════════════
-- ENREGISTREMENT DE PATHS
-- ═══════════════════════════════════════════════════════════════

AMConfig.recorder = {
    fps = 10,
    minPoints = 5,
    maxPoints = 500,
}

-- ═══════════════════════════════════════════════════════════════
-- VISUALISATION 3D
-- ═══════════════════════════════════════════════════════════════

AMConfig.visualizer = {
    lineColor = {255, 215, 0},
    pointColor = {255, 100, 100},
    lineWidth = 2.0,
    maxDistance = 50,
    showLegend = true,
}

-- ═══════════════════════════════════════════════════════════════
-- MARQUEURS DES MAGASINS
-- ═══════════════════════════════════════════════════════════════

AMConfig.marker = {
    hardcodedColor = {0, 200, 255, 100},
    customColor = {0, 255, 100, 100},
    editingColor = {255, 200, 0, 150},
    type = "cylinder",
    size = 1.5,
    zOffset = -1.0,
    displayDistance = 20,
    adminOnly = true,

    cashierType = "cylinder",
    cashierSize = 1.2,
    cashierZOffset = -1.0,
    cashierColor = {0, 0, 0, 0},
}

-- ═══════════════════════════════════════════════════════════════
-- PANEL GRAPHIQUE
-- ═══════════════════════════════════════════════════════════════

AMConfig.panel = {
    colors = {
        background = {20, 20, 25, 240},
        primary    = {121, 80, 242},
        success    = {87, 242, 135},
        error      = {237, 66, 69},
        warning    = {254, 231, 92},
        info       = {88, 165, 255},
        text       = {255, 255, 255},
        textDim    = {180, 180, 180},
        border     = {96, 102, 113},
    },
    fontPath = "assets/fonts/Poppins-Regular.ttf",
    fontSize = 12,
    width = 800,
    height = 600,
}

-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATIONS
-- ═══════════════════════════════════════════════════════════════

AMConfig.notifications = {
    useFUNotify = true,
    fallbackToChatBox = true,
}

-- ═══════════════════════════════════════════════════════════════
-- SYSTÈME DE PRIX
-- ═══════════════════════════════════════════════════════════════

AMConfig.pricing = {
    basePrice = 5,
    tipsMin = 0,
    tipsMax = 15,
}

-- ═══════════════════════════════════════════════════════════════
-- TÉLÉPORTATION
-- ═══════════════════════════════════════════════════════════════

AMConfig.teleport = {
    dimension = 0,
    interior = 0,
    retryDelays = {100, 500, 1000},
    unfreeze = true,
    enableCollisions = true,
}

-- ═══════════════════════════════════════════════════════════════
-- ANTI-DOUBLON
-- ═══════════════════════════════════════════════════════════════

AMConfig.antiDuplicate = {
    enabled = true,
    cooldown = 1500,
    logDuplicates = true,
}

-- ═══════════════════════════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════════════════════════

AMConfig.debug = {
    enabled = false,
    logToConsole = true,
    verbose = false,
}

_G.AMConfig = AMConfig
