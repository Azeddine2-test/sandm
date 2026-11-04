-- ============================================================================
-- CarPlay — primitives de dessin (demande 69)
-- ----------------------------------------------------------------------------
-- Tout est dessiné dans un repère de 1000 × 500 unités (l'écran CarPlay),
-- mis à l'échelle de l'écran du joueur. Rectangles arrondis anticrénelés à
-- partir d'UNE texture de cercle (coins = quarts de cercle, pas de
-- chevauchement, donc la transparence reste propre). Icônes : PNG blancs
-- teintés à la volée.
-- ============================================================================

if type(CARPLAY_DESSIN) ~= "table" then CARPLAY_DESSIN = {} end
local D = CARPLAY_DESSIN

D.ox, D.oy, D.k = 0, 0, 1
D.echelle = 1.0
D.facteurPolice = 1.0
D.customX = nil
D.customY = nil
D.polices = {}
D.textures = {}

D.COUL = {
    fond = { 0, 0, 0 }, barre = { 28, 28, 30 }, carte = { 44, 44, 46 }, carte2 = { 58, 58, 60 },
    separateur = { 56, 56, 58 }, texte = { 255, 255, 255 }, dim = { 142, 142, 147 },
    bleu = { 10, 132, 255 }, vert = { 48, 209, 88 }, rouge = { 255, 69, 58 }, rose = { 250, 45, 72 },
    orange = { 255, 159, 10 }, cadre = { 12, 12, 14 },
}

function D.c(nom, a)
    local c = D.COUL[nom] or D.COUL.texte
    return tocolor(c[1], c[2], c[3], a or 255)
end

function D.cadrer(sx, sy)
    local ech = D.echelle or 1.0
    D.k = math.min(sx * 0.64 / 1000, sy * 0.66 / 500) * ech
    local w = 1000 * D.k
    local h = 500 * D.k
    if D.customX and D.customY then
        D.ox = math.max(-w * 0.3, math.min(sx - w * 0.7, D.customX))
        D.oy = math.max(0, math.min(sy - h * 0.5, D.customY))
    else
        D.ox = math.floor((sx - w) / 2)
        D.oy = math.floor(sy - h - sy * 0.07)
    end
end

function D.X(u) return D.ox + u * D.k end
function D.Y(u) return D.oy + u * D.k end
function D.L(u) return u * D.k end

-- Curseur en unités CarPlay (nil si caché).
function D.curseur()
    if not isCursorShowing() then return nil end
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    local sx, sy = guiGetScreenSize()
    return (cx * sx - D.ox) / D.k, (cy * sy - D.oy) / D.k
end

function D.dans(x, y, w, h)
    local cx, cy = D.curseur()
    return cx and cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

function D.texture(chemin)
    local t = D.textures[chemin]
    if t == nil then
        t = (fileExists(chemin) and dxCreateTexture(chemin, "argb", true, "clamp")) or false
        D.textures[chemin] = t
    end
    return t or nil
end

function D.police(taille, poids)
    local fp = D.facteurPolice or 1.0
    local px = math.max(6, math.floor(taille * D.k * fp + 0.5))
    local cle = (poids or "r") .. px
    local f = D.polices[cle]
    if f == nil then
        local fichier = ({ b = "Inter-Bold.ttf", s = "Inter-SemiBold.ttf" })[poids or "r"] or "Inter-Regular.ttf"
        f = dxCreateFont("assets/fonts/" .. fichier, px, false, "antialiased") or "default-bold"
        D.polices[cle] = f
    end
    return f
end

function D.liberer()
    for _, f in pairs(D.polices) do if isElement(f) then destroyElement(f) end end
    D.polices = {}
end

-- Rectangle arrondi (unités CarPlay).
function D.rect(x, y, w, h, r, couleur)
    local X, Y, W, H = D.X(x), D.Y(y), D.L(w), D.L(h)
    local R = math.min(D.L(r or 0), W / 2, H / 2)
    local cercle = R >= 1 and D.texture("assets/images/cercle.png")
    if not cercle then dxDrawRectangle(X, Y, W, H, couleur, true) return end
    dxDrawRectangle(X + R, Y, W - 2 * R, H, couleur, true)
    if H - 2 * R > 0 then
        dxDrawRectangle(X, Y + R, R, H - 2 * R, couleur, true)
        dxDrawRectangle(X + W - R, Y + R, R, H - 2 * R, couleur, true)
    end
    dxDrawImageSection(X, Y, R, R, 0, 0, 128, 128, cercle, 0, 0, 0, couleur, true)
    dxDrawImageSection(X + W - R, Y, R, R, 128, 0, 128, 128, cercle, 0, 0, 0, couleur, true)
    dxDrawImageSection(X, Y + H - R, R, R, 0, 128, 128, 128, cercle, 0, 0, 0, couleur, true)
    dxDrawImageSection(X + W - R, Y + H - R, R, R, 128, 128, 128, 128, cercle, 0, 0, 0, couleur, true)
end

function D.cercle(cx, cy, rayon, couleur)
    local t = D.texture("assets/images/cercle.png")
    if not t then return D.rect(cx - rayon, cy - rayon, rayon * 2, rayon * 2, 0, couleur) end
    dxDrawImage(D.X(cx - rayon), D.Y(cy - rayon), D.L(rayon * 2), D.L(rayon * 2), t, 0, 0, 0, couleur, true)
end

function D.icone(nom, x, y, s, couleur, rotation)
    local t = D.texture("assets/icones/" .. nom .. ".png")
    if t then dxDrawImage(D.X(x), D.Y(y), D.L(s), D.L(s), t, rotation or 0, 0, 0, couleur or D.c("texte"), true) end
end

function D.image(chemin, x, y, w, h, couleur)
    local t = D.texture(chemin)
    if t then dxDrawImage(D.X(x), D.Y(y), D.L(w), D.L(h), t, 0, 0, 0, couleur or tocolor(255, 255, 255), true) end
end

function D.texte(t, x, y, w, h, couleur, taille, poids, ax, ay, couper, retour)
    dxDrawText(tostring(t or ""), D.X(x), D.Y(y), D.X(x + w), D.Y(y + h), couleur or D.c("texte"), 1,
        D.police(taille or 16, poids), ax or "left", ay or "center", couper ~= false, retour == true, true)
end

function D.largeur(t, taille, poids)
    return dxGetTextWidth(tostring(t or ""), 1, D.police(taille or 16, poids)) / D.k
end

-- Nombre de lignes d'un texte coupé à la largeur w (unités).
function D.lignes(t, w, taille, poids)
    local n, ligne = 1, ""
    for mot in tostring(t or ""):gmatch("%S+") do
        local essai = (ligne == "") and mot or (ligne .. " " .. mot)
        if D.largeur(essai, taille, poids) > w and ligne ~= "" then
            n = n + 1
            ligne = mot
        else
            ligne = essai
        end
    end
    return n
end

-- Initiales pour les pastilles de contact.
function D.initiales(nom)
    nom = tostring(nom or "?")
    local U8 = "[%z\1-\127\194-\244][\128-\191]*"
    local a, b = nom:match("^(" .. U8 .. ")%S*%s+(" .. U8 .. ")")
    if a then return (a .. b):upper() end
    return (nom:match("^" .. U8) or "#"):upper()
end
