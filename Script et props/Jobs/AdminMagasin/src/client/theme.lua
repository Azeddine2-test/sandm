-- ============================================================================
-- THÈME NEON — habillage commun des interfaces (demande 17, 16/10/2026)
-- ============================================================================
-- Référence : le menu d'animations (scriptWalkpanel/src/client/
-- catalogue_animations.lua) — fonds anthracite, BLEU de l'inventaire
-- (74,163,224), coins arrondis, police Poppins, boutons gris qui
-- s'éclaircissent au survol, bouton fermer rond qui rougit.
--
-- ⚠ FICHIER VOLONTAIREMENT COPIÉ À L'IDENTIQUE dans chaque ressource
--   thématisée (sa copie canonique est [Lib]/neon_theme/theme.lua).
--   Un appel `exports.neon_theme:...` à chaque image coûterait un aller-retour
--   entre machines Lua par rectangle : on copie donc le code, et seules les
--   POLICES sont partagées (fichiers de la ressource neon_theme, démarrée
--   tôt par [ST]-StartAll). Pas de <include> dans les meta.xml : si
--   neon_theme manquait, MTA refuserait de démarrer la ressource (le panel
--   admin compris) ; ici on retombe simplement sur une autre police.
--   Si tu modifies ce fichier, recopie-le partout : tools/test_demande17.lua
--   échoue dès qu'une copie diverge de la canonique.
--
-- N'utilise QUE des fonctions MTA de dessin de base : chaque ressource garde
-- ses propres enveloppes (échelle, contour du texte) par-dessus.
-- ============================================================================
if type(THEME) ~= "table" then THEME = {} end
local T = THEME
T.VERSION = 1

-- Palette (r, g, b, alpha par défaut) — valeurs relevées sur le menu
-- d'animations.
T.P = {
    -- 02/11/2026 : palette relevee sur le panel admin, valeur pour valeur,
    -- pour que les interfaces qui passent par le theme partage soient
    -- exactement de la meme famille que lui. Les anciennes valeurs (18,18,22 /
    -- 32,32,39 / bordures 60,60,70) tiraient vers le gris neutre : le panel
    -- admin, lui, est sur un bleu nuit.
    fond         = { 14, 16, 19, 242 },   -- panneau principal  (admin : bg)
    entete       = { 26, 28, 34, 250 },   -- bandeaux, surfaces (admin : surface)
    surface      = { 21, 23, 28, 245 },   -- champs, saisies    (admin : input)
    carte        = { 21, 23, 28, 245 },   -- encadre            (admin : rowAlt)
    case         = { 26, 28, 34, 240 },   -- ligne de liste     (admin : row)
    caseSurvol   = { 38, 42, 50, 245 },
    bouton       = { 26, 28, 34, 235 },
    boutonSurvol = { 38, 43, 52, 245 },
    accent       = { 74, 163, 224, 255 }, -- bleu du serveur
    accentSurvol = { 98, 180, 235, 255 },
    choisi       = { 33, 57, 76, 250 },   -- selection (admin : rowSel)
    danger       = { 226, 76, 76, 250 },  -- rouge du panel admin
    dangerSurvol = { 240, 96, 96, 250 },
    fermer       = { 26, 28, 34, 235 },
    succes       = { 88, 196, 136, 250 }, -- vert du panel admin
    alerte       = { 226, 168, 76, 255 }, -- ambre du panel admin
    favori       = { 255, 202, 40, 255 },
    bordure      = { 96, 102, 113, 70 },  -- liseres discrets du panel admin
    separateur   = { 96, 102, 113, 70 },
    lisere       = { 255, 255, 255, 14 },
    poignee      = { 255, 255, 255, 40 },
    voile        = { 0, 0, 0, 140 },      -- admin : shade
    texte        = { 240, 242, 246, 255 }, -- admin : text
    texte2       = { 203, 208, 218, 255 },
    texteDim     = { 132, 138, 150, 255 }, -- admin : textDim
    texteFaible  = { 108, 114, 126, 255 },
    texteInactif = { 132, 138, 150, 255 },
    texteRouge   = { 226, 76, 76, 255 },
    texteVert    = { 88, 196, 136, 255 },
}

-- Rayons des coins (px de conception, à multiplier par l'échelle locale).
T.R = { panneau = 16, carte = 13, bouton = 9, petit = 6 }

-- Tailles Poppins du menu d'animations (px de conception).
T.TAILLES = { titre = 18, nom = 15, texte = 12, petit = 11 }

function T.rgb(nom)
    local p = T.P[nom] or T.P.texte
    return p[1], p[2], p[3], p[4] or 255
end

function T.c(nom, alpha)
    local p = T.P[nom] or T.P.texte
    return tocolor(p[1], p[2], p[3], alpha or p[4] or 255)
end

-- ---------------------------------------------------------------------------
-- Polices : Poppins de neon_theme, puis la copie locale éventuelle de la
-- ressource (assets/fonts ou src/assets/fonts), puis la police MTA.
-- ---------------------------------------------------------------------------
-- 02/11/2026 : SF Pro Display D'ABORD, Poppins en repli. Le panel admin,
-- l'inventaire, la banque et la location de trottinettes utilisent SF Pro
-- Display ; tout le reste passait encore par Poppins, d'ou deux identites
-- visuelles sur le serveur. Chaque poids liste ses fichiers par ordre de
-- preference : si neon_theme est absent, la copie locale Poppins de la
-- ressource prend le relais, puis la police MTA.
T.FICHIERS = {
    regular  = { "SFProDisplay-Regular.ttf", "Poppins-Regular.ttf" },
    medium   = { "SFProDisplay-Medium.ttf",  "Poppins-Medium.ttf" },
    semibold = { "SFProDisplay-Bold.ttf",    "Poppins-SemiBold.ttf" },
    bold     = { "SFProDisplay-Bold.ttf",    "Poppins-Bold.ttf" },
}
T.CHEMINS = { ":neon_theme/fonts/", "assets/fonts/", "src/assets/fonts/" }
local cache = {}
local echecs = {}       -- cle -> getTickCount() du dernier échec
T.REESSAI = 5000        -- ms : neon_theme a pu démarrer après nous

function T.police(poids, taille)
    poids = T.FICHIERS[poids] and poids or "medium"
    taille = math.max(5, math.min(150, math.floor((tonumber(taille) or 12) + 0.5)))
    local cle = poids .. ":" .. taille
    local maintenant = getTickCount and getTickCount() or 0
    if cache[cle] == false and maintenant - (echecs[cle] or 0) >= T.REESSAI then cache[cle] = nil end
    if cache[cle] == nil then
        local f = false
        if dxCreateFont then
            -- Deux boucles : le FICHIER d'abord (SF Pro avant Poppins), le
            -- dossier ensuite. L'ordre inverse aurait pris la copie Poppins
            -- locale avant le SF Pro de neon_theme.
            -- admin_panel remplace T.FICHIERS par une simple chaine apres le
            -- chargement de ce fichier : on accepte les deux formes.
            local liste = T.FICHIERS[poids]
            if type(liste) == "string" then liste = { liste } end
            for _, nomFichier in ipairs(liste) do
                for _, dossier in ipairs(T.CHEMINS) do
                    local chemin = dossier .. nomFichier
                    if not fileExists or dossier:sub(1, 1) == ":" or fileExists(chemin) then
                        f = dxCreateFont(chemin, taille) or false
                        if f then break end
                    end
                end
                if f then break end
            end
        end
        cache[cle] = f
        if not f then echecs[cle] = maintenant end
    end
    if cache[cle] then return cache[cle] end
    return (poids == "regular") and "default" or "default-bold"
end

-- Taille de référence = texte normal du PANEL ADMIN (demande 19 : « mets la
-- même taille de police, comme le panel admin »). admin_panel : BASE_POLICE 9
-- × facteur ×1,3 × FONT_SCALE 1,10 ≈ 12,9 → Poppins Medium 13 ; à partir de
-- ×1,05 il passe en SemiBold. Taille absolue (le panel admin ne la réduit pas
-- selon la résolution) : 13 = taille lisible minimale du texte courant.
T.PANEL = 13
function T.policePanel(facteur, poids)
    facteur = tonumber(facteur) or 1
    return T.police(poids or (facteur >= 1.05 and "semibold" or "medium"), T.PANEL * facteur)
end
-- Remonte une taille codée en dur au niveau du panel admin : le texte courant
-- (10 à 12) passe à 13, les petits textes (8-9) à 11-12, les titres (13 et
-- plus) gardent leur taille. Pour les ressources qui écrivent leurs tailles
-- en clair (laptop, appartements, aides d'AdminMagasin, object_admin…).
function T.versPanel(taille)
    taille = tonumber(taille) or T.PANEL
    if taille >= T.PANEL then return taille end
    return math.min(T.PANEL, taille + 3)
end

function T.viderPolices()
    for cle, f in pairs(cache) do
        if f and isElement and isElement(f) then destroyElement(f) end
        cache[cle] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Formes
-- ---------------------------------------------------------------------------
-- Rectangle aux coins arrondis : 3 bandes qui ne se recouvrent pas + 4 quarts
-- de disque (une couleur translucide reste donc uniforme).
function T.rect(x, y, l, h, r, col, postGUI)
    if l <= 0 or h <= 0 then return end
    r = math.min(r or 0, l / 2, h / 2)
    if r < 1 or not dxDrawCircle then
        dxDrawRectangle(x, y, l, h, col, postGUI)
        return
    end
    dxDrawRectangle(x + r, y, l - 2 * r, h, col, postGUI)
    dxDrawRectangle(x, y + r, r, h - 2 * r, col, postGUI)
    dxDrawRectangle(x + l - r, y + r, r, h - 2 * r, col, postGUI)
    dxDrawCircle(x + r, y + r, r, 180, 270, col, col, 8, 1, postGUI)
    dxDrawCircle(x + l - r, y + r, r, 270, 360, col, col, 8, 1, postGUI)
    dxDrawCircle(x + l - r, y + h - r, r, 0, 90, col, col, 8, 1, postGUI)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, col, col, 8, 1, postGUI)
end

-- Fond d'un bouton selon son état ; renvoie la couleur du texte à employer.
--   genre : nil/"normal", "actif" (bleu), "danger" (rouge), "succes" (vert)
function T.bouton(x, y, l, h, survol, genre, r, postGUI)
    local fond, texte
    if genre == "actif" then
        fond, texte = survol and T.c("accentSurvol") or T.c("accent"), T.c("texte")
    elseif genre == "danger" then
        fond, texte = survol and T.c("dangerSurvol") or T.c("danger"), T.c("texte")
    elseif genre == "succes" then
        fond, texte = T.c("succes", survol and 255 or 235), T.c("texte")
    elseif genre == "inactif" then
        fond, texte = T.c("bouton", 160), T.c("texteInactif")
    else
        fond, texte = survol and T.c("boutonSurvol") or T.c("bouton"), T.c("texte")
    end
    T.rect(x, y, l, h, r or T.R.bouton, fond, postGUI)
    return texte
end

-- Bouton fermer rond (gris, rouge au survol) avec sa croix.
function T.fermer(x, y, t, survol, postGUI)
    T.rect(x, y, t, t, t / 2, survol and T.c("dangerSurvol", 235) or T.c("fermer"), postGUI)
    if dxDrawLine then
        local m, e = t * 0.32, math.max(1, t / 14)
        local col = T.c("texte")
        dxDrawLine(x + m, y + m, x + t - m, y + t - m, col, e, postGUI)
        dxDrawLine(x + t - m, y + m, x + m, y + t - m, col, e, postGUI)
    end
end

-- Champ de saisie : fond « surface » et soulignement bleu (plein au focus).
function T.champ(x, y, l, h, focus, r, postGUI)
    T.rect(x, y, l, h, r or T.R.bouton, T.c("surface"), postGUI)
    local e = math.max(1, h / 18)
    dxDrawRectangle(x + (r or 6), y + h - e, l - 2 * (r or 6), e, T.c("accent", focus and 255 or 170), postGUI)
end

-- Panneau principal : fond arrondi + poignée centrale du menu d'animations.
function T.panneau(x, y, l, h, s, postGUI)
    s = s or 1
    T.rect(x, y, l, h, T.R.panneau * s, T.c("fond"), postGUI)
    T.rect(x + l / 2 - 22 * s, y + 8 * s, 44 * s, 4 * s, 2 * s, T.c("poignee"), postGUI)
end

function T.dans(px, py, x, y, l, h)
    return px and py and px >= x and px <= x + l and py >= y and py <= y + h or false
end
